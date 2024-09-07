variable "well_known_tag_keys" {
  default     = ["info/*"]
  description = <<-EOT
    A list of pre-existing tag key patterns in your organization that you'd like to together with control tags.
    by default, a single-elemtn list containing only "info/*" which is a nice extensibility point.
  EOT

  type = list(string)
}

variable "using_delegated_admin_account" {
  default     = false
  description = <<-EOT
    set this to true if you'd like to apply this module from a delegated administrator account for SCPs.
    false by default which requires this module to be installed from the management (master) account.
  EOT
}

variable "deployment_targets" {
  default     = { organizational_unit_ids = [], account_ids = [] }
  description = <<-EOT
    A map of deployment targets. The keys are "organizational_unit_ids", and "account_ids".
    The values are lists of strings representing the target IDs.
  EOT
  type = object({
    organizational_unit_ids = list(string)
    account_ids             = list(string)
  })
}
