use aws_smithy_types_convert::date_time::DateTimeExt;
use chrono::Utc;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct AssumeRoleOutput {
    #[serde(rename = "Credentials")]
    credentials: Option<AssumeRoleOutputCredentials>,
    #[serde(rename = "AssumedRoleUser")]
    assumed_role_user: Option<AssumeRoleOutputAssumedRoleUser>,
    #[serde(rename = "SourceIdentity")]
    source_identity: Option<String>,
}

impl TryFrom<aws_sdk_sts::operation::assume_role::AssumeRoleOutput> for AssumeRoleOutput {
    type Error = anyhow::Error;
    fn try_from(output: aws_sdk_sts::operation::assume_role::AssumeRoleOutput) -> anyhow::Result<Self> {
        Ok(Self {
            credentials: output.credentials.map(TryInto::try_into).transpose()?,
            assumed_role_user: output.assumed_role_user.map(TryInto::try_into).transpose()?,
            source_identity: output.source_identity,
        })
    }
}

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct AssumeRoleOutputCredentials {
    #[serde(rename = "AccessKeyId")]
    access_key_id: String,
    #[serde(rename = "SecretAccessKey")]
    secret_access_key: String,
    #[serde(rename = "SessionToken")]
    session_token: String,
    #[serde(rename = "Expiration")]
    expiration: chrono::DateTime<Utc>,
}

impl TryFrom<aws_sdk_sts::types::Credentials> for AssumeRoleOutputCredentials {
    type Error = anyhow::Error;
    fn try_from(credentials: aws_sdk_sts::types::Credentials) -> anyhow::Result<Self> {
        Ok(Self {
            access_key_id: credentials.access_key_id,
            secret_access_key: credentials.secret_access_key,
            session_token: credentials.session_token,
            expiration: credentials.expiration.to_chrono_utc()?,
        })
    }
}

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct AssumeRoleOutputAssumedRoleUser {
    #[serde(rename = "AssumedRoleId")]
    assumed_role_id: String,
    #[serde(rename = "Arn")]
    arn: String,
}

impl From<aws_sdk_sts::types::AssumedRoleUser> for AssumeRoleOutputAssumedRoleUser {
    fn from(value: aws_sdk_sts::types::AssumedRoleUser) -> Self {
        Self {
            assumed_role_id: value.assumed_role_id,
            arn: value.arn,
        }
    }
}
