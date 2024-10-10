mod config;
mod types;

use anyhow::{bail, Context};
use approval::{
    self,
    iam::ApprovalManager,
    ticket::{ApprovalTicket, HumanIdentity},
};
use aws_arn::ResourceName;
use aws_config::BehaviorVersion;
use aws_sdk_iam::config::SharedCredentialsProvider;

use clap::{Args, Parser, Subcommand};
use config::Configuration;

use serde_json;
use std::{path::PathBuf, sync::Arc};
use tokio;

#[derive(Parser)]
#[command()]
struct Cli {
    /// Sets a custom config file
    #[arg(short, long, value_name = "FILE")]
    config: Option<PathBuf>,

    #[command(subcommand)]
    command: Option<RootCommand>,
}

#[derive(Subcommand)]
enum RootCommand {
    Ticket(TicketArgs),
    Mirror(MirrorArgs),
}

#[derive(Args)]
#[command(about)]
struct TicketArgs {
    #[arg(long, global = true)]
    profile: Option<String>,

    /// The name of the role to manage. Default to the calling principal's role.
    #[arg(long, global = true)]
    role_name: Option<String>,

    #[command(subcommand)]
    command: TicketCommand,
}

#[derive(Subcommand)]
enum TicketCommand {
    List {},
    Set { receiver: String },
    Unset {},
}

#[derive(Args)]
#[command(about)]
struct MirrorArgs {
    #[arg(long, global = true)]
    profile: Option<String>,

    #[command(subcommand)]
    command: MirrorCommand,
}

#[derive(Subcommand)]
enum MirrorCommand {
    Assume {},
}

#[tokio::main]
async fn main() {
    let program = Cli::parse();

    let Some(command) = program.command else {
        eprintln!("No command provided");
        return;
    };

    let config = Configuration::load(program.config);

    match command {
        RootCommand::Ticket(args) => match handle_ticket_commands(&config, args).await {
            Ok(_) => {}
            Err(e) => eprintln!("Error: {:#}", e),
        },
        RootCommand::Mirror(args) => match handle_mirror_commands(&config, args).await {
            Ok(_) => {}
            Err(e) => eprintln!("Error: {:#}", e),
        },
    };
}

async fn handle_ticket_commands(_app_config: &Configuration, args: TicketArgs) -> anyhow::Result<()> {
    let mut sdk_config = aws_config::load_defaults(BehaviorVersion::latest()).await;

    if let Some(profile) = args.profile {
        let provider = aws_config::profile::credentials::Builder::default()
            .profile_name(profile)
            .build();
        sdk_config = sdk_config
            .into_builder()
            .credentials_provider(SharedCredentialsProvider::new(provider))
            .build();
    }

    let iam_client = Arc::new(aws_sdk_iam::Client::new(&sdk_config));
    let manager = approval::iam::RoleApprovalManager::new(iam_client.clone());

    let sts_client = aws_sdk_sts::Client::new(&sdk_config);

    let (role_name, session_name) = match args.role_name {
        Some(name) => (CallerRoleName(name), None),
        None => {
            let (role_name, session) = get_caller(&sts_client).await?;
            (role_name, Some(session))
        }
    };

    match args.command {
        TicketCommand::List {} => match manager.get_ticket(&role_name.0).await {
            Ok(ticket) => {
                println!("Ticket: {:#?}", ticket);
            }
            Err(e) => {
                eprintln!("Error: {:#}", e);
            }
        },
        TicketCommand::Set { receiver } => {
            let expiry = chrono::Utc::now() + chrono::Duration::hours(1);
            let giver = match session_name {
                Some(session) => session,
                None => get_caller(&sts_client).await?.1,
            };

            let ticket =
                ApprovalTicket::new(HumanIdentity::new(giver.0), HumanIdentity::new(receiver)).set_expiry(expiry);

            if let Err(e) = manager.set_ticket(&role_name.0, ticket).await {
                eprintln!("Error: {:#}", e);
            }
        }
        TicketCommand::Unset {} => {
            if let Err(e) = manager.unset_ticket(&role_name.0).await {
                eprintln!("Error: {:#}", e);
            }
        }
    }
    Ok(())
}

const SSO_ROLE_PATH_PREFIX: &str = "/aws-reserved/sso.amazonaws.com/";
const MIRROR_ROLE_NAME_PREFIX: &str = "tagctl-mirror-";

async fn handle_mirror_commands(_app_config: &Configuration, args: MirrorArgs) -> anyhow::Result<()> {
    let mut sdk_config = aws_config::load_defaults(BehaviorVersion::latest()).await;

    if let Some(profile) = args.profile {
        let provider = aws_config::profile::credentials::Builder::default()
            .profile_name(profile)
            .build();
        sdk_config = sdk_config
            .into_builder()
            .credentials_provider(SharedCredentialsProvider::new(provider))
            .build();
    }

    match args.command {
        MirrorCommand::Assume {} => {
            let sts_client = aws_sdk_sts::Client::new(&sdk_config);
            let (role_name, session_name) = get_caller(&sts_client).await?;

            let iam_client = aws_sdk_iam::Client::new(&sdk_config);
            let current_role = iam_client
                .get_role()
                .role_name(role_name.0)
                .send()
                .await?
                .role
                .context("missing role")?;

            if !current_role.path().starts_with(SSO_ROLE_PATH_PREFIX) {
                bail!("current role is not an SSO role, cannot assume mirror role");
            };

            let sso_role_name_crumbs: Vec<_> = current_role.role_name.split("_").collect();
            let ["AWSReservedSSO", permissionset_name, _] = sso_role_name_crumbs[..] else {
                bail!("role name does not match expected format for SSO role: AWSReservedSSO_<PERMSET>_<UID>");
            };

            let mirror_role = iam_client
                .get_role()
                .role_name(format!("{}{}", MIRROR_ROLE_NAME_PREFIX, permissionset_name))
                .send()
                .await?
                .role
                .with_context(|| format!("no mirror role found for {}", current_role.role_name))?;

            let assume_output = sts_client
                .assume_role()
                .role_arn(mirror_role.arn)
                .role_session_name(&session_name.0)
                //.duration_seconds(role.max_session_duration.unwrap_or(900))
                .source_identity(&session_name.0)
                .send()
                .await?;

            let serde_assume_output: types::AssumeRoleOutput = assume_output.try_into()?;
            let json_output = serde_json::to_string_pretty(&serde_assume_output)?;
            print!("{}", json_output);

            Ok(())
        }
    }
}

struct CallerRoleName(String);
struct CallerSessionName(String);

async fn get_caller(sts: &aws_sdk_sts::Client) -> anyhow::Result<(CallerRoleName, CallerSessionName)> {
    let arn = sts
        .get_caller_identity()
        .send()
        .await?
        .arn
        .context("no arn returned by sts:GetCallerIdentity")?;
    let arn: ResourceName = arn.parse()?;
    let resource_name_parts: Vec<_> = arn.resource.split("/").collect();
    match resource_name_parts[..] {
        ["assumed-role", role, _session] => Some((
            CallerRoleName(role.to_string()),
            CallerSessionName(_session.to_string()),
        )),
        _ => None,
    }
    .context("unsupported caller identity")
}
