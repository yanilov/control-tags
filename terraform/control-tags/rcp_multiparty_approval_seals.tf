locals {
  builtin_resource_seal_kinds = {
    total = {
      sid     = "CTRSKB0"
      actions = ["*"]
    }
    trust_relay = {
      sid         = "CTRSKB1"
      not_actions = ["iam:Get*", "iam:List*", "sts:*"]
    }
  }
}

data "aws_iam_policy_document" "resource_seals_core" {
  # deny seal-breaing requests(tag/untag), unless the principal has approval
  statement {
    sid       = local.sids.seal_op_no_approval
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    # request involves tagging/untagging
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:TagKeys"
      values   = ["${local.resource_seal_tag_key}/*"]
    }
    condition {
      test     = "StringNotLikeIfExists"
      variable = "aws:PrincipalTag/${local.approval_ticket_tag_key}"
      values = [for tag_key in local.human_identity_tag_keys :
        "*/for/$${${tag_key}, '${local.invalid.identity}'}"
      ]
    }
  }
  # deny sealing with a grant outside the principal's grant area
  statement {
    sid       = local.sids.seal_op_outside_grant
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/${local.resource_seal_grant_tag_key}"
      values   = ["false"]
    }
    condition {
      test     = "StringNotLikeIfExists"
      variable = "aws:RequestTag/${local.resource_seal_grant_tag_key}"
      values = [
        "$${aws:PrincipalTag/${local.grant_area_tag_key}, '${local.invalid.ctl_tag_value}'}",
        "$${aws:PrincipalTag/${local.grant_area_tag_key}, '${local.invalid.ctl_tag_value}'}/*"
      ]
    }
  }
}


data "aws_iam_policy_document" "resource_seals_kinds" {
  for_each = local.builtin_resource_seal_kinds
  statement {
    sid         = each.value.sid
    effect      = "Deny"
    actions     = try(each.value.actions, null)
    not_actions = try(each.value.not_actions, null)
    resources   = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.resource_seal_kind_tag_key}"
      values   = [each.key]
    }
    condition {
      test     = "StringNotLikeIfExists"
      variable = "aws:PrincipalTag/${local.approval_ticket_tag_key}"
      values = [for tag_key in local.human_identity_tag_keys :
        "*/for/$${${tag_key}, '${local.invalid.identity}'}"
      ]
    }
  }
}


data "aws_iam_policy_document" "unified_mpa_seals" {
  source_policy_documents = concat(
    [
      data.aws_iam_policy_document.resource_seals_core.json,
    ],
    [for _, doc in data.aws_iam_policy_document.resource_seals_kinds : doc.json]
  )
}

resource "aws_organizations_policy" "mpa_seals" {
  name        = "multi_party_approval_resource_seals"
  type        = "RESOURCE_CONTROL_POLICY"
  description = "Scalable multi-party approval for resources."
  content     = data.aws_iam_policy_document.unified_mpa_seals.minified_json
}

# attach the control tags RCP to all deployment targets
resource "aws_organizations_policy_attachment" "mpa_seals" {
  for_each = toset(flatten(values(var.deployment_targets)))

  # the RCP must be attached after the mirror roles have been set up
  depends_on = [aws_cloudformation_stack_set.mirror_role]

  policy_id = aws_organizations_policy.mpa_seals.id
  target_id = each.value
}
