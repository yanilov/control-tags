mod config;

use anyhow::Context;
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
    };
}

async fn handle_ticket_commands(_app_config: &Configuration, args: TicketArgs) -> anyhow::Result<()> {
    let sdk_config = aws_config::load_defaults(BehaviorVersion::latest()).await;

    let profile = match args.profile {
        Some(profile) => profile,
        None => std::env::var("AWS_PROFILE").unwrap_or("default".to_string()),
    };
    let provider = aws_config::profile::credentials::Builder::default()
        .profile_name(profile)
        .build();
    let sdk_config = sdk_config
        .into_builder()
        .credentials_provider(SharedCredentialsProvider::new(provider))
        .build();

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
