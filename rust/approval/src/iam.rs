use crate::{tags, ticket::ApprovalTicket};
use aws_sdk_iam::{self, types::Tag};
use aws_smithy_types_convert::stream::PaginationStreamExt;
use futures::{Stream, TryStreamExt};
use std::{future, sync::Arc};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ListPrincipalsError {
    #[error("cannot list principals")]
    InternalError,
}

#[derive(Error, Debug)]
pub enum ListAllTicketsError {
    #[error("cannot list tickets")]
    InternalError,
}

#[derive(Error, Debug)]
pub enum ListTicketsError {
    #[error("cannot list tickets")]
    InternalError,
    #[error("principal {0} was not included in the response")]
    MissingPrincipal(NamedIamPrincipal),
}

#[derive(Error, Debug)]
pub enum SetTicketError {
    #[error("cannot list tickets")]
    InternalError,
    #[error("create tag from ticket specification")]
    MalformedTag,
}

#[derive(Error, Debug)]
pub enum UnsetTicketError {
    #[error("cannot list tickets")]
    InternalError,
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
            .map_err(|_| ListAllTicketsError::InternalError)
            .map_ok(|role| async {
                let ticket = self
                    .get_ticket(&role.role_name)
                    .await
                    .map_err(|_| ListAllTicketsError::InternalError)?;
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
        let role = self
            .iam
            .get_role()
            .role_name(principal)
            .send()
            .await
            .map_err(|_| ListTicketsError::InternalError)?
            .role;

        let Some(role) = role else {
            return Err(ListTicketsError::MissingPrincipal(principal.into()));
        };

        let ticket = role.tags().iter().find_map(|t| ApprovalTicket::try_from(t).ok());

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
            .map_err(|_| SetTicketError::InternalError)?;
        Ok(())
    }

    async fn unset_ticket(&self, principal: &NamedIamPrincipal) -> Result<(), UnsetTicketError> {
        self.iam
            .untag_role()
            .tag_keys(tags::KEY_ADMIN_TICKET)
            .role_name(principal)
            .send()
            .await
            .map_err(|_| UnsetTicketError::InternalError)?;
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
            .map_err(|_| ListAllTicketsError::InternalError)
            .map_ok(|user| async {
                let ticket = self
                    .get_ticket(&user.user_name)
                    .await
                    .map_err(|_| ListAllTicketsError::InternalError)?;
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
        let user = self
            .iam
            .get_user()
            .user_name(principal)
            .send()
            .await
            .map_err(|_| ListTicketsError::InternalError)?
            .user;

        let Some(user) = user else {
            return Err(ListTicketsError::MissingPrincipal(principal.clone()));
        };

        let ticket = user.tags().iter().find_map(|t| ApprovalTicket::try_from(t).ok());

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
            .map_err(|_| SetTicketError::InternalError)?;
        Ok(())
    }

    async fn unset_ticket(&self, principal: &NamedIamPrincipal) -> Result<(), UnsetTicketError> {
        self.iam
            .untag_user()
            .tag_keys(tags::KEY_ADMIN_TICKET)
            .user_name(principal)
            .send()
            .await
            .map_err(|_| UnsetTicketError::InternalError)?;
        Ok(())
    }
}

impl TryFrom<&Tag> for crate::ticket::ApprovalTicket {
    type Error = ();

    fn try_from(tag: &Tag) -> Result<Self, Self::Error> {
        match tag.key() {
            key if key.starts_with(tags::KEY_ADMIN_TICKET) => tag.value().parse::<ApprovalTicket>().map_err(|_| ()),
            _ => Err(()),
        }
    }
}

impl TryFrom<crate::ticket::ApprovalTicket> for Tag {
    type Error = ();
    fn try_from(ticket: crate::ticket::ApprovalTicket) -> Result<Self, Self::Error> {
        Tag::builder()
            .key(tags::KEY_ADMIN_TICKET)
            .value(ticket.to_string())
            .build()
            .map_err(|_| ())
    }
}
