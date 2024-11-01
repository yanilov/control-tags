use anyhow::{Context, Result};
use approval::{self, iam::ApprovalManager, ticket::ApprovalTicket};
use async_stream::try_stream;
use aws_config::{sts::AssumeRoleProviderBuilder, BehaviorVersion};
use aws_sdk_iam;
use aws_sdk_iam::config::SharedCredentialsProvider;
use aws_sdk_iam::primitives::Blob;
use aws_sdk_lambda::{self, types::InvocationType};
use aws_sdk_organizations::types::{ChildType, TargetType};
use aws_smithy_types_convert::stream::PaginationStreamExt;
use chrono::Duration;
use futures::{future, stream, Stream, StreamExt, TryStreamExt};
use lambda_runtime::{service_fn, tracing, Error, LambdaEvent};
use serde::{Deserialize, Serialize};
use serde_json;
use std::{env::var, sync::Arc};

#[derive(Serialize, Deserialize)]
enum Request {
    ScheduleApprovalEviction {},
    EvictStaleApprovals { account_id: String },
}

#[derive(Serialize)]
enum Response {
    DiscoveredAccounts(Vec<String>),
    EvictionSummary {
        users: Vec<(String, ApprovalTicket)>,
        roles: Vec<(String, ApprovalTicket)>,
    },
}

struct AppState {
    sdk_config: aws_config::SdkConfig,
    role_name: String,
    role_path: String,
    control_tags_scp_id: String,
    max_ticket_ttl_seconds: chrono::Duration,
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    // required to enable CloudWatch error logging by the runtime
    tracing::init_default_subscriber();

    let func = service_fn(my_handler);
    lambda_runtime::run(func).await?;
    Ok(())
}

async fn init_appstate() -> anyhow::Result<AppState> {
    let ttl = var("MAX_TICKET_TTL_SECONDS")
        .context("MAX_TICKET_TTL_SECONDS")?
        .parse()
        .ok()
        .filter(|&x| x > 0)
        .context("ttl is not possitive")?;

    Ok(AppState {
        sdk_config: aws_config::load_defaults(BehaviorVersion::latest()).await,
        role_name: var("WORKER_ROLE_NAME").context("WORKER_ROLE_NAME")?,
        role_path: var("WORKER_ROLE_PATH")
            .context("WORKER_ROLE_PATH")?
            .trim_matches('/')
            .to_owned(),
        control_tags_scp_id: var("CONTROL_TAGS_SCP_ID").context("CONTROL_TAGS_SCP_ID")?,
        max_ticket_ttl_seconds: Duration::seconds(ttl),
    })
}

pub(crate) async fn my_handler(event: LambdaEvent<Request>) -> anyhow::Result<Response, Error> {
    let appstate = init_appstate().await?;
    match event.payload {
        Request::ScheduleApprovalEviction {} => {
            tracing::info!("scheduling eviction of approval tickets");
            let orgs_client = aws_sdk_organizations::Client::new(&appstate.sdk_config);
            let mut accounts = traverse_accounts_affected_by_policy(&orgs_client, appstate.control_tags_scp_id);
            let mut affected = vec![];
            let lambda_arn = event.context.invoked_function_arn;

            let lambda_client = aws_sdk_lambda::Client::new(&appstate.sdk_config);
            while let Some(x) = accounts.next().await {
                match x {
                    Ok(account_id) => {
                        tracing::debug!(msg = "scheduling eviction", account_id = %account_id);
                        if let Err(e) = schedule_eviction(&lambda_client, &account_id, &lambda_arn).await {
                            tracing::error!(msg = "scheduling eviction", account_id = %account_id, error = %e);
                            continue;
                        }
                        affected.push(account_id);
                    }
                    Err(e) => {
                        tracing::error!(msg = "traversing accounts", error = %e);
                    }
                }
            }

            return Ok(Response::DiscoveredAccounts(affected));
        }
        Request::EvictStaleApprovals { account_id } => {
            let role_arn = format!(
                "arn:aws:iam::{account}:role/{path}/{name}",
                account = &account_id,
                path = appstate.role_path,
                name = appstate.role_name,
            );
            let provider = AssumeRoleProviderBuilder::new(role_arn).build().await;

            let config = appstate
                .sdk_config
                .into_builder()
                .credentials_provider(SharedCredentialsProvider::new(provider))
                .build();
            let iam_client = Arc::new(aws_sdk_iam::Client::new(&config));

            let user_manager = approval::iam::UserApprovalManager::new(iam_client.clone());
            let role_manager = approval::iam::RoleApprovalManager::new(iam_client.clone());

            let users_tickets_fut = evict_invalid_tickets(user_manager, appstate.max_ticket_ttl_seconds);
            let roles_tickets_fut = evict_invalid_tickets(role_manager, appstate.max_ticket_ttl_seconds);

            let (users_tickets, roles_tickets) = future::try_join(users_tickets_fut, roles_tickets_fut).await?;
            return Ok(Response::EvictionSummary {
                users: users_tickets,
                roles: roles_tickets,
            });
        }
    }
}

async fn schedule_eviction(client: &aws_sdk_lambda::Client, account_id: &str, lambda_arn: &str) -> anyhow::Result<()> {
    let payload = Request::EvictStaleApprovals {
        account_id: account_id.to_string(),
    };

    let _ = client
        .invoke()
        .function_name(lambda_arn)
        .invocation_type(InvocationType::Event)
        .payload(Blob::new(serde_json::to_vec(&payload)?))
        .send()
        .await
        .expect("failed to invoke lambda");

    Ok(())
}

async fn evict_invalid_tickets<T: ApprovalManager>(
    manager: T,
    max_ttl: chrono::Duration,
) -> anyhow::Result<Vec<(String, ApprovalTicket)>> {
    let evicted = manager
        .list_all_tickets()
        .inspect_err(|e| tracing::error!(msg = "listing account tickets", error = %e))
        .filter_map(|result| async {
            match result {
                Ok((principal, ticket)) if is_evictable(&ticket, max_ttl) => Some((principal, ticket)),
                _ => None,
            }
        })
        .map(|(principal, ticket)| async {
            if let Err(e) = manager.unset_ticket(&principal).await {
                tracing::error!(msg = "unset ticket", error = %e, principal = %principal, ticket = ?ticket)
            };
            (principal, ticket)
        })
        .buffer_unordered(4)
        .collect()
        .await;

    Ok(evicted)
}

fn is_evictable(ticket: &ApprovalTicket, max_ttl: chrono::Duration) -> bool {
    let now = chrono::Utc::now();
    let ttl = ticket.expires_at().map(|ts| ts - now);
    match ttl {
        Some(ttl) => ttl <= Duration::zero() || ttl >= max_ttl,
        None => true,
    }
}

fn traverse_accounts_affected_by_policy<'a>(
    client: &'a aws_sdk_organizations::Client,
    policy_id: impl Into<String>,
) -> impl Stream<Item = anyhow::Result<String>> + 'a {
    let targets = client
        .list_targets_for_policy()
        .policy_id(policy_id)
        .into_paginator()
        .send()
        .into_stream_03x()
        .flat_map(|output| match output {
            Ok(output) => stream::iter(
                output
                    .targets
                    .unwrap_or_default()
                    .into_iter()
                    .map(Ok)
                    .collect::<Vec<_>>(),
            ),
            Err(err) => stream::iter(vec![Err(err)]),
        });

    targets
        .map_ok(|target| {
            let Some(target_id) = target.target_id else {
                return stream::empty().boxed();
            };
            match target.r#type {
                Some(TargetType::Account) => stream::iter(vec![Ok(target_id)]).boxed(),
                Some(TargetType::Root | TargetType::OrganizationalUnit) => {
                    traverse_account_tree(client, target_id).boxed()
                }
                _ => {
                    tracing::warn!(msg = "Unknown target type", target_id =% target_id);
                    stream::empty().boxed()
                }
            }
        })
        .try_flatten()
}

fn traverse_account_tree<'a>(
    client: &'a aws_sdk_organizations::Client,
    target_id: String,
) -> impl Stream<Item = Result<String, anyhow::Error>> + Send + 'a {
    try_stream! {
        let accounts = list_accounts_for_target(client, &target_id);
        for await account in accounts {
            yield account?;
        }

        let org_units = list_org_units_for_target(client, &target_id);
        for await ou in org_units {
            let nested = traverse_account_tree(client, ou?).boxed();
            for await account in nested {
                yield account?;
            }
        }
    }
}

fn list_accounts_for_target(
    client: &aws_sdk_organizations::Client,
    target_id: &str,
) -> impl Stream<Item = Result<String, anyhow::Error>> {
    let child_accounts = client
        .list_children()
        .parent_id(target_id)
        .child_type(ChildType::Account)
        .into_paginator()
        .send()
        .into_stream_03x()
        .map_ok(|output| {
            let account_ids = output
                .children
                .unwrap_or_default()
                .into_iter()
                .filter_map(|child| child.id)
                .map(Ok);
            stream::iter(account_ids)
        })
        .try_flatten();
    child_accounts
}

fn list_org_units_for_target(
    client: &aws_sdk_organizations::Client,
    target_id: &str,
) -> impl Stream<Item = Result<String, anyhow::Error>> {
    let org_units = client
        .list_children()
        .parent_id(target_id)
        .child_type(ChildType::OrganizationalUnit)
        .into_paginator()
        .send()
        .into_stream_03x()
        .map_ok(|output| {
            let ou_ids = output
                .children
                .unwrap_or_default()
                .into_iter()
                .filter_map(|child| child.id)
                .map(Ok);
            stream::iter(ou_ids)
        })
        .try_flatten();
    org_units
}
