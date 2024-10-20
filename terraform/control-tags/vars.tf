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


variable "sso_mirror_spec" {
  default     = {}
  description = <<-EOT
    A map from permission set arn to a mirror role spec.
    Each specified permission set will have a mirror role created in every all accounts of each target specified by `deployment_targets`.
    Each spec is a map with the following keys:
     - grant_area_suffix: the grant area to be set on the mirror role. the value will be concatenated after with the control prefix to form the grant area control tag value.
  EOT
  # tag a permissionsset with this tag key, specifying grant area suffix to set up a mirror role with control tags attached
  type = map(object({
    grant_area_suffix = string
  }))
}

variable "emit_scp_sids" {
  default     = "short"
  description = <<-EOT
    The SID format to use for the control tags. The default is "short" which uses the short form of the SID.
    The second option is "long" which uses the long form of the SID, and the third option is "none" which does not emit SIDs.
  EOT
  type        = string

  validation {
    condition     = contains(["short", "long", "none"], var.emit_scp_sids)
    error_message = "The emit_scp_sids must be one of 'short', 'long', or 'none'."
  }
}
