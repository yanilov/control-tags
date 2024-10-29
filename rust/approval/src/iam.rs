use crate::{
    tags,
    ticket::{ApprovalTicket, ParseError},
};
use anyhow;
use aws_sdk_iam::{self, error::BuildError, types::Tag};

use aws_smithy_types_convert::stream::PaginationStreamExt;
use futures::{Stream, TryStreamExt};
use std::{future, sync::Arc};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ListPrincipalsError {
    #[error("cannot list principals: {0:?}")]
    InternalError(#[from] anyhow::Error),
}

#[derive(Error, Debug)]
pub enum ListAllTicketsError {
    #[error("cannot list tickets: {0:?}")]
    InternalError(#[from] anyhow::Error),
}

#[derive(Error, Debug)]
pub enum ListTicketsError {
    #[error("cannot list tickets: {0:?}")]
    InternalError(#[from] anyhow::Error),
}

#[derive(Error, Debug)]
pub enum SetTicketError {
    #[error("cannot set ticket: {0:?}")]
    InternalError(#[from] anyhow::Error),
    #[error("create tag from ticket specification")]
    MalformedTag,
}

#[derive(Error, Debug)]
pub enum UnsetTicketError {
    #[error("cannot unset ticket: {0:?}")]
    InternalError(#[from] anyhow::Error),
}

pub type NamedIamPrincipal = String;

pub trait ApprovalManager {
    fn list_all_tickets(&self) -> impl Stream<Item = Result<(NamedIamPrincipal, ApprovalTicket), ListAllTicketsError>>;
    fn get_ticket(
        &self,
        principal: &NamedIamPrincipal,
    ) -> impl std::future::Future<Output = Result<Option<ApprovalTicket>, ListTicketsError>>;
    fn set_ticket(
        &self,
        principal: &NamedIamPrincipal,
        ticket: ApprovalTicket,
    ) -> impl std::future::Future<Output = Result<(), SetTicketError>>;
    fn unset_ticket(
        &self,
        principal: &NamedIamPrincipal,
    ) -> impl std::future::Future<Output = Result<(), UnsetTicketError>>;
}

pub struct RoleApprovalManager {
    iam: std::sync::Arc<aws_sdk_iam::Client>,
}

impl RoleApprovalManager {
    pub fn new(iam: Arc<aws_sdk_iam::Client>) -> Self {
        Self { iam }
    }
}

pub struct UserApprovalManager {
    iam: std::sync::Arc<aws_sdk_iam::Client>,
}

impl UserApprovalManager {
    pub fn new(iam: Arc<aws_sdk_iam::Client>) -> Self {
        Self { iam }
    }
}

impl ApprovalManager for RoleApprovalManager {
    fn list_all_tickets(&self) -> impl Stream<Item = Result<(NamedIamPrincipal, ApprovalTicket), ListAllTicketsError>> {
        self.iam
            .list_roles()
            .into_paginator()
            .items()
            .send()
            .into_stream_03x()
            .map_err(|e| ListAllTicketsError::InternalError(e.into()))
            .map_ok(|role| async {
                let ticket = self
                    .get_ticket(&role.role_name)
                    .await
                    .map_err(|e| ListAllTicketsError::InternalError(e.into()))?;
                Ok((role.role_name, ticket))
            })
            .try_buffer_unordered(4)
            .try_filter_map(|(principal, ticket)| {
                future::ready(match ticket {
                    Some(ticket) => Ok(Some((principal, ticket))),
                    None => Ok(None),
                })
            })
    }

    async fn get_ticket(&self, principal: &NamedIamPrincipal) -> Result<Option<ApprovalTicket>, ListTicketsError> {
        let tags = self
            .iam
            .list_role_tags()
            .role_name(principal)
            .send()
            .await
            .map_err(|e| ListTicketsError::InternalError(e.into()))?
            .tags;

        let ticket = tags.iter().find_map(|t| ApprovalTicket::try_from(t).ok());

        Ok(ticket)
    }

    async fn set_ticket(&self, principal: &NamedIamPrincipal, ticket: ApprovalTicket) -> Result<(), SetTicketError> {
        let tag = ticket.try_into().map_err(|_| SetTicketError::MalformedTag)?;

        self.iam
            .tag_role()
            .role_name(principal)
            .tags(tag)
            .send()
            .await
            .map_err(|e| SetTicketError::InternalError(e.into()))?;
        Ok(())
    }

    async fn unset_ticket(&self, principal: &NamedIamPrincipal) -> Result<(), UnsetTicketError> {
        self.iam
            .untag_role()
            .tag_keys(tags::KEY_ADMIN_TICKET)
            .role_name(principal)
            .send()
            .await
            .map_err(|e| UnsetTicketError::InternalError(e.into()))?;
        Ok(())
    }
}

impl ApprovalManager for UserApprovalManager {
    fn list_all_tickets(&self) -> impl Stream<Item = Result<(NamedIamPrincipal, ApprovalTicket), ListAllTicketsError>> {
        self.iam
            .list_users()
            .into_paginator()
            .items()
            .send()
            .into_stream_03x()
            .map_err(|e| ListAllTicketsError::InternalError(e.into()))
            .map_ok(|user| async {
                let ticket = self
                    .get_ticket(&user.user_name)
                    .await
                    .map_err(|e| ListAllTicketsError::InternalError(e.into()))?;
                Ok((user.user_name, ticket))
            })
            .try_buffer_unordered(4)
            .try_filter_map(|(principal, ticket)| {
                future::ready(match ticket {
                    Some(ticket) => Ok(Some((principal, ticket))),
                    None => Ok(None),
                })
            })
    }

    async fn get_ticket(&self, principal: &NamedIamPrincipal) -> Result<Option<ApprovalTicket>, ListTicketsError> {
        let tags = self
            .iam
            .list_user_tags()
            .user_name(principal)
            .send()
            .await
            .map_err(|e| ListTicketsError::InternalError(e.into()))?
            .tags;

        let ticket = tags.iter().find_map(|t| ApprovalTicket::try_from(t).ok());

        Ok(ticket)
    }

    async fn set_ticket(&self, principal: &NamedIamPrincipal, ticket: ApprovalTicket) -> Result<(), SetTicketError> {
        let tag = ticket.try_into().map_err(|_| SetTicketError::MalformedTag)?;

        self.iam
            .tag_user()
            .user_name(principal)
            .tags(tag)
            .send()
            .await
            .map_err(|e| SetTicketError::InternalError(e.into()))?;
        Ok(())
    }

    async fn unset_ticket(&self, principal: &NamedIamPrincipal) -> Result<(), UnsetTicketError> {
        self.iam
            .untag_user()
            .tag_keys(tags::KEY_ADMIN_TICKET)
            .user_name(principal)
            .send()
            .await
            .map_err(|e| UnsetTicketError::InternalError(e.into()))?;
        Ok(())
    }
}

#[derive(Error, Debug)]
pub enum TicketBuildError {
    #[error("Invalid tag key: {0}. Tag key must start with {}", tags::KEY_ADMIN_TICKET)]
    TagKeyInvalid(String),
    #[error("Failed to parse tag value: {0}")]
    TagValueParseError(#[from] ParseError),
}

impl TryFrom<&Tag> for crate::ticket::ApprovalTicket {
    type Error = TicketBuildError;

    fn try_from(tag: &Tag) -> Result<Self, Self::Error> {
        if !tag.key().starts_with(tags::KEY_ADMIN_TICKET) {
            return Err(TicketBuildError::TagKeyInvalid(tag.key().to_string()));
        }

        tag.value()
            .parse::<ApprovalTicket>()
            .map_err(|e| TicketBuildError::TagValueParseError(e))
    }
}

impl TryFrom<crate::ticket::ApprovalTicket> for Tag {
    type Error = BuildError;
    fn try_from(ticket: crate::ticket::ApprovalTicket) -> Result<Self, Self::Error> {
        Tag::builder()
            .key(tags::KEY_ADMIN_TICKET)
            .value(ticket.to_string())
            .build()
    }
}
