data "aws_organizations_organization" "main" {}

data "aws_caller_identity" "main" {
  lifecycle {
    postcondition {
      condition     = self.account_id == data.aws_organizations_organization.main.master_account_id || var.using_delegated_admin_account
      error_message = "This module must be called from the organization's management (AKA master) account."
    }
  }
}
