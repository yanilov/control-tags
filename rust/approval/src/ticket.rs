use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    fmt::{Debug, Display},
    str::FromStr,
};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ParseError {
    #[error("cannot parse giver")]
    MissingGiver,
    #[error("cannot parse receiver")]
    MissingReceiver,
}

#[derive(Debug, Clone, PartialEq, PartialOrd, Serialize, Deserialize)]
pub struct HumanIdentity(String);

impl HumanIdentity {
    pub fn new(s: impl Into<String>) -> Self {
        HumanIdentity(s.into())
    }
}

impl Display for HumanIdentity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ApprovalTicket {
    pub giver: HumanIdentity,
    pub receiver: HumanIdentity,
    spec: HashMap<String, String>,
}

impl FromStr for ApprovalTicket {
    type Err = ParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let parts = &s.split("/").collect::<Vec<_>>()[..];

        let ["by", giver, parts @ ..] = parts else {
            return Err(ParseError::MissingGiver);
        };

        let [payload @ .., "for", receiver] = parts else {
            return Err(ParseError::MissingReceiver);
        };

        let spec = payload
            .iter()
            .filter_map(|part| {
                let crumbs = &part.splitn(2, "=").collect::<Vec<_>>()[..];
                match crumbs {
                    [key, value] => Some((key.to_string(), value.to_string())),
                    _ => None,
                }
            })
            .collect();

        Ok(ApprovalTicket {
            giver: HumanIdentity(giver.to_string()),
            receiver: HumanIdentity(receiver.to_string()),
            spec,
        })
    }
}

impl Display for ApprovalTicket {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let spec_str = self
            .spec
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect::<Vec<_>>()
            .join("/");

        write!(
            f,
            "by/{giver}/{spec}/for/{receiver}",
            giver = self.giver,
            spec = spec_str,
            receiver = self.receiver
        )
    }
}

impl ApprovalTicket {
    pub fn new(giver: HumanIdentity, receiver: HumanIdentity) -> Self {
        ApprovalTicket {
            giver,
            receiver,
            spec: HashMap::new(),
        }
    }

    pub fn insert(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.spec.insert(key.into(), value.into());
        self
    }

    pub fn set_chainable(mut self, chainable: bool) -> Self {
        self.spec.insert("chain".to_string(), chainable.to_string());
        self
    }

    pub fn is_chainable(&self) -> bool {
        self.spec
            .get_key_value("chain")
            .map_or(false, |(_, v)| v.parse::<bool>().unwrap_or(false))
    }

    pub fn set_expiry(mut self, expiry: DateTime<Utc>) -> Self {
        self.spec.insert("exp".to_string(), expiry.timestamp().to_string());
        self
    }

    pub fn expires_at(&self) -> Option<DateTime<Utc>> {
        self.spec
            .get_key_value("exp")
            .and_then(|(_, v)| v.parse::<i64>().ok())
            .and_then(|seconds| DateTime::from_timestamp(seconds, 0))
    }
}

#[cfg(test)]
mod tests {
    use super::{ApprovalTicket, HumanIdentity};
    use chrono::DateTime;

    #[test]
    fn test_parse_ticket() {
        let ticket = "by/alice/chain=true/exp=1618033988/for/bob";
        let parsed = ticket.parse::<ApprovalTicket>().unwrap();
        assert_eq!(parsed.giver.0, "alice");
        assert_eq!(parsed.receiver.0, "bob");
        assert_eq!(parsed.is_chainable(), true);
        assert_eq!(parsed.spec.get("exp"), Some(&"1618033988".to_string()));
    }

    #[test]
    fn test_display_ticket() {
        let ticket = ApprovalTicket {
            giver: HumanIdentity("alice".to_string()),
            receiver: HumanIdentity("bob".to_string()),
            spec: vec![
                ("chain".to_string(), "true".to_string()),
                ("exp".to_string(), "1618033988".to_string()),
            ]
            .into_iter()
            .collect(),
        };
        let displayed = format!("{}", ticket);
        assert!(displayed.starts_with("by/alice/"));
        assert!(displayed.ends_with("/for/bob"));
        assert!(displayed.contains("/chain=true/"));
        assert!(displayed.contains("/exp=1618033988/"));
    }

    #[test]
    fn test_chainable_ticket() {
        let ticket = ApprovalTicket {
            giver: HumanIdentity("alice".to_string()),
            receiver: HumanIdentity("bob".to_string()),
            spec: vec![
                ("chain".to_string(), "true".to_string()),
                ("exp".to_string(), "1618033988".to_string()),
            ]
            .into_iter()
            .collect(),
        };
        assert_eq!(ticket.is_chainable(), true);
    }

    #[test]
    fn test_expires_at_ticket() {
        let ticket = ApprovalTicket {
            giver: HumanIdentity("alice".to_string()),
            receiver: HumanIdentity("bob".to_string()),
            spec: vec![
                ("chain".to_string(), "true".to_string()),
                ("exp".to_string(), "1618033988".to_string()),
            ]
            .into_iter()
            .collect(),
        };
        assert_eq!(
            ticket.expires_at(),
            Some(DateTime::from_timestamp(1618033988, 0).unwrap())
        );
    }
}
