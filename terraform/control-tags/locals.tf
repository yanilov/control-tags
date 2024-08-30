locals {
  control_prefix          = "tagctl/"
  grant_area_tag_key      = "${local.control_prefix}v1/meta/grant_path"
  identity_broker_tag_key = "${local.control_prefix}v1/meta/id_broker"
  mpa_tag_key             = "${local.control_prefix}v1/admin/mpa"
  approval_ticket_tag_key = "${local.mpa_tag_key}/ticket"
}
