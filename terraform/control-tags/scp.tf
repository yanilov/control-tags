locals {
    invalid_identity = "nil"
    invalid_ctrl_tag_value = "nil"

    sids = {
        invalid_identity = "CT00"
        ctrl_tagging_without_grant_path = "CT01"
        ctrl_tagging_outside_grant_area = "CT02"
        anti_impersonate_non_sso = "CT03"
        anti_impersonate_sso = "CT04"
        anti_reflexive ="CT05"
        anti_forge="CT06"
    }
    
}

data "aws_iam_policy_document" "reserved_values" {
    statement {
        sid = local.sids.invalid_identity
        effect = "Deny"
        actions = [ "sts:SetSourceIdentity" ]
        resources = [ "*" ]
        # the principal attempts to set a reserved "nil" value as source identity
        condition {
          test = "StringEquals"
          variable = "sts:SourceIdentity"
          values = [local.local.invalid_identity]
        }
    }
}

data "aws_iam_policy_document" "control_tags" {
  statement {
    sid = local.sids.ctrl_tagging_without_grant_path
    effect = "Deny"
    resources = ["*"]
    actions = ["*"]
    # the request contains a control tag
    condition {
      test = "ForAnyValue:StringLike"
      variable = "aws:TagKeys"
      values = ["${local.control_prefix}*"]
    }
    # the calling principal does not have a grant area control tag
    condition {
      test = "Null"
      variable = "aws:PrincipalTag/${local.grant_area_tag_key}"
      values = [ "true" ]
    }
  }

  statement {
    sid = local.sids.ctrl_tagging_outside_grant_area
    effect = "Deny"
    resources = ["*"]
    # the request contains a control tag
    condition {
      test = "ForAnyValue:StringLike"
      variable = "aws:TagKeys"
      values = ["${local.control_prefix}*"]
    }
    # a control tag in the request falls outside the calling principal's grant area.
    # well-known tag names are added in this condition s.t. IAC systems such as terraform 
    # will by able to apply resources with a combination of control and non-conrol tags in a single API call.
    condition {
      test = "ForAnyValue:StringNotLike"
      variable = "aws:TagKeys"
      values = concat(
        [
            "$${aws:PrincipalTag/${local.grant_area_tag_key}, '${local.invalid_ctrl_tag_value}'}",
            "$${aws:PrincipalTag/${local.grant_area_tag_key}, '${local.invalid_ctrl_tag_value}'}/*"
        ],
        var.well_known_tag_keys
      )
    }
  }
}

data "aws_iam_policy_document" "multiparty_approval" {
  # non-sso principal attempts to set source identity without being authorized
  statement {
    sid = local.sids.anti_impersonate_non_sso
    effect = "Deny"
    actions = "sts:SetSourceIdentity"
    condition {
      test = "StringNotEqualsIfExists"
      variable = "aws:PrincipalTag/${local.identity_broker_tag_key}"
      values = [ "true" ]
    }
    condition {
      test = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values = ["arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*"]
    }
  }
  # sso principal attempts to set source identity which does not match its store-id
  statement {
    sid = local.sids.anti_impersonate_sso
    effect = "Deny"
    actions = "sts:SetSourceIdentity"
    condition {
      test = "StringNotEqualsIfExists"
      variable = "sts:SourceIdentity"
      values = [ "$${identitystore:UserId, '${local.invalid_identity}'}" ]
    }
    condition {
      test = "ArnLike"
      variable = "aws:PrincipalArn"
      values = ["arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*"]
    }
  }
  
  # A 2pa ticket can only be set by principals with human identity.
  statement {
    effect = "Deny"
    #todo: originally actions = ["iam:Tag*"]. is * too restrictive? it could pave the way for resource-based approvals
    actions = ["*"] 
    resources = ["*"]
    condition {
      test = "ForAnyValue:StringLike"
      variable = "aws:TagKeys"
      values = [ "${local.mpa_tag_key}/*" ]
    }
    condition {
      test = "Null"
      variable = "aws:SourceIdentity"
      values = ["true"]
    }
  }

  # Limit the “receiver section” of the tag’s value to anything but the current principal’s identity.
  # todo: for reference, the original statement. the new one with * should be more flexible for resource-based approvals

  # statement {
  #   sid = local.sids.anti_reflexive
  #   effect = "Deny"
  #   actions = ["iam:TagUser", "iam:CreateUser", "iam:TagRole", "iam:CreateRole"]
  #   resources = ["*"]
  #   condition {
  #     test = "StringLike"
  #     variable = "aws:PrincipalTag/${local.approval_ticket_tag_key}"
  #     values = ["*/for/$${aws:SourceIdentity, '${local.invalid_identity}'}"]
  #   }
  # }
  statement {
    sid = local.sids.anti_reflexive
    effect = "Deny"
    actions = ["*"]
    resources = ["*"]
    condition {
      test = "Null"
      variable = "aws:RequestTag/${local.approval_ticket_tag_key}"
      values = ["false"]
    }
    condition {
      test = "StringLikeIfExists"
      variable = "aws:PrincipalTag/${local.approval_ticket_tag_key}"
      values = ["*/for/$${aws:SourceIdentity, '${local.invalid_identity}'}"]
    }
  }

  # Limit the “giver section” of the tag’s value to be just the current principal’s identity.
  statement {
    sid = local.sids.anti_forge
    effect = "Deny"
    #todo: originally actions = ["iam:TagUser", "iam:CreateUser", "iam:TagRole", "iam:CreateRole"]. is * too restrictive? it could pave the way for resource-based approvals
    actions = ["*"]
    #a the request attempts to tag an approval ticket
    condition {
      test = "Null"
      variable = "aws:RequestTag/${local.approval_ticket_tag_key}"
      values = ["false"]
    }
    # the approval ticket names the something that is NOT the calling principal as the giver
    condition {
      test = "StringNotLike"
      variable = "aws:RequestTag/${local.approval_ticket_tag_key}"
      values = ["by/$${aws:SourceIdentity, '${local.invalid_identity}'}/*"]
    }
  }
}

data "aws_iam_policy_document" "unified" {
    source_policy_documents = [ 
      data.data.aws_iam_policy_document.reserved_values.json, 
      data.data.aws_iam_policy_document.control_tags.json, 
      data.data.aws_iam_policy_document.multiparty_approval.json 
    ]
}

resource "aws_organizations_policy" "control_tags" {
    name = "control_tags"
    type = "SERVICE_CONTROL_POLICY"
    description = "Scalable tag-based integrity and multi-party approval."
    content = data.aws_iam_policy_document.unified.json
}