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

  resource_seal_tag_key       = "${local.mpa_tag_key}/seal"
  resource_seal_kind_tag_key  = "${local.resource_seal_tag_key}/kind"
  resource_seal_grant_tag_key = "${local.resource_seal_tag_key}/grant"

}

# general
locals {
  account_id = data.aws_caller_identity.main.account_id
}

# dynamically shaped
locals {
  dyn_deployment_targets = { for target_type, targets in var.deployment_targets : target_type => targets if length(targets) > 0 }
}

# sid generation
locals {
  sids_map = {
    # control tags
    ctl_no_grant      = "ct0"
    ctl_outside_grant = "ct1"
    ctl_lookalike     = "ct2"

    # multiparty approval
    anti_invalid_identity    = "ctmp0"
    anti_impersonate_non_sso = "ctmp1"
    anti_impersonate_sso     = "ctmp2"
    anti_non_human           = "ctmp3"
    anti_reflexive           = "ctmp4"
    anti_forge               = "ctmp5"

    # resource seals
    seal_op_no_approval           = "ctrs0"
    seal_op_outside_grant         = "ctrs1"
    seal_principal_outside_target = "ctrs2"
  }

  sid_selector = {
    short = local.sids_map
    long  = { for k, v in local.sids_map : k => replace(title(replace(k, "_", " ")), " ", "") }
    none  = { for k, v in local.sids_map : k => null }
  }

  sids = local.sid_selector[var.emit_scp_sids]
}
