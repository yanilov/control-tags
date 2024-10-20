# tagging related
locals {
  control_prefix = "tagctl:"
  disallowed_control_prefix_lookalikes = [for ch in split("", ".+=@_/-") :
    "tagctl${ch}"
  ]
  control_v1 = "${local.control_prefix}v1"

  grant_area_tag_key      = "${local.control_v1}/meta/grant_area"
  identity_broker_tag_key = "${local.control_v1}/meta/id_broker"
  mpa_tag_key             = "${local.control_v1}/admin/mpa"
  approval_ticket_tag_key = "${local.mpa_tag_key}/ticket"

}

# dynamically shaped
locals {
  dyn_deployment_targets = { for target_type, targets in var.deployment_targets : target_type => targets if length(targets) > 0 }
}
