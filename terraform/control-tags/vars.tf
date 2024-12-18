variable "well_known_tag_keys" {
  default     = ["info/*"]
  description = <<-EOT
    A list of pre-existing tag key patterns in your organization that you'd like to together with control tags.
    by default, a single-elemtn list containing only "info/*" which is a nice extensibility point.
  EOT

  type = list(string)
}

variable "deployment_targets" {
  default     = { organizational_unit_ids = [], account_ids = [] }
  description = <<-EOT
    A map of deployment targets. The keys are "organizational_unit_ids", and "account_ids".
    The values are lists of strings representing the target IDs.
  EOT
  type = object({
    organizational_unit_ids = optional(list(string))
    account_ids             = optional(list(string))
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

variable "max_ticket_ttl_seconds" {
  default     = 4 * 3600
  description = "The maximum approval ticket TTL in seconds."
  type        = number

  validation {
    condition     = var.max_ticket_ttl_seconds > 0
    error_message = "The max_ticket_ttl_seconds must be greater than 0."
  }
}

variable "lambda_archive_file" {
  description = "The path to the lambda archive file."
  type        = string
  validation {
    condition     = fileexists(var.lambda_archive_file)
    error_message = "The lambda archive file must exist."
  }
}

variable "lambda_timetout_seconds" {
  default     = 5
  description = "The timeout in seconds for the lambda function."
  type        = number

  validation {
    condition     = var.lambda_timetout_seconds > 0
    error_message = "The lambda_timetout_seconds must be greater than 0."
  }
}

variable "lambda_scheduler_rate_minutes" {
  default     = 30
  description = "The rate in minutes at which the lambda function should be scheduled."
  type        = number

  validation {
    condition     = var.lambda_scheduler_rate_minutes > 0
    error_message = "The lambda_scheduler_rate_minutes must be greater than 0."
  }
}

variable "lambda_log_retention_in_days" {
  default     = 7
  description = "The number of days to retain the logs for the lambda function. defaults to 7 days. specify 0 to retain indefinitely."
  type        = number

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.lambda_log_retention_in_days)
    error_message = "The lambda_log_retention must be one of 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  }
}

variable "guarded_action_spec" {
  description = <<-EOT
    a map of action sets to protect under control tags. each key will produce a separate scp.
    action wildcards support is the same as AWS IAM policy actions.
  EOT
  default     = {}
  type = map(object({
    actions = list(string)
    deployment_targets = optional(object({
      organizational_unit_ids = optional(list(string))
      account_ids             = optional(list(string))
    }))
  }))

  validation {
    condition     = alltrue([for spec in values(var.guarded_action_spec) : length(spec.actions) > 0])
    error_message = "Ech spec must contain at least one action."
  }

  validation {
    condition     = alltrue([for k in keys(var.guarded_action_spec) : k != "" && k != null])
    error_message = "The keys cannot be null or empty."
  }

  validation {
    condition     = alltrue([for spec in values(var.guarded_action_spec) : length(values(spec.deployment_targets)) > 0 if spec.deployment_targets != null])
    error_message = "Each spec must contain at least one deployment target."
  }
}
