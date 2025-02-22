locals {
  rcp_supported_actions = [
    "s3:*",
    "sqs:*",
    "sts:*",
    "kms:*",
    "secretsmanager:*"
  ]
  builtin_resource_seal_kinds = {
    secret = {
      sid = "ctrskb0"
      actions = [
        "secretsmanager:*",
        "kms:*"
      ]
      resources = [
        "arn:aws:secretsmanager:*:*:secret/*",
        "arn:aws:kms:*:*:key/*",
        "arn:aws:kms:*:*:alias/*"
      ]
    }
    trust_relay = {
      sid = "ctrskb1"
      actions = [
        "sts:Assume*",
        "sts:GetFederationToken"
      ]
      resources = ["*"]
    }
  }
}

data "aws_iam_policy_document" "resource_seals_core" {
  # deny seal-breaing requests(tag/untag), unless the principal has approval
  statement {
    sid    = local.sids.seal_op_no_approval
    effect = "Deny"
    principals {
      identifiers = ["*"]
      type        = "*"
    }
    actions   = local.rcp_supported_actions
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
    sid    = local.sids.seal_op_outside_grant
    effect = "Deny"
    principals {
      identifiers = ["*"]
      type        = "*"
    }
    actions   = local.rcp_supported_actions
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
    sid    = each.value.sid
    effect = "Deny"
    principals {
      identifiers = ["*"]
      type        = "*"
    }
    actions   = each.value.actions
    resources = each.value.resources
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

data "aws_iam_policy_document" "resource_seals_org_access" {
  statement {
    sid    = local.sids.seal_principal_outside_target
    effect = "Deny"
    principals {
      identifiers = ["*"]
      type        = "*"
    }
    actions   = local.rcp_supported_actions
    resources = ["*"]
    # reousce seal exists
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/${local.resource_seal_grant_tag_key}"
      values   = ["false"]
    }
    # principal acccount is not any of the deployment target accounts
    dynamic "condition" {
      for_each = try(length(var.deployment_targets.account_ids) > 0, false) ? [1] : []
      content {
        test     = "StringNotEquals"
        variable = "aws:PrincipalAccount"
        values   = var.deployment_targets.account_ids
      }
    }
    # principal org path does not contain the any of the deployment target OUs
    dynamic "condition" {
      for_each = try(length(var.deployment_targets.organizational_unit_ids) > 0, false) ? [1] : []
      content {
        test     = "ForAllValues:StringNotLike"
        variable = "aws:PrincipalOrgPaths"
        values   = [for ou_id in var.deployment_targets.organizational_unit_ids : "*/${ou_id}/*"]
      }
    }
  }
}


data "aws_iam_policy_document" "unified_mpa_seals" {
  source_policy_documents = concat(
    [
      data.aws_iam_policy_document.resource_seals_core.json,
      data.aws_iam_policy_document.resource_seals_org_access.json
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
