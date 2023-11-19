data "aws_iam_policy_document" "approval_ticket_lifecycle" {
  statement {
    sid    = "ListIAMTags"
    effect = "Allow"
    actions = [
      "iam:ListPolicyTags",
      "iam:ListRoleTags",
      "iam:ListUserTags",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "RemoveApprovalTicket"
    effect = "Allow"
    actions = [
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:UntagUser"
    ]
    resources = ["*"]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = [local.local.approval_ticket_tag_key]
    }
  }
}

data "aws_iam_policy_document" "org_traversal" {
  statement {
    sid    = "TraverseAccountsAffectedByPolicy"
    effect = "Allow"
    actions = [
      "organizations:ListPolicies",
      "organizations:ListTargetsForPolicy",
      "organizations:ListChildren"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "trust_policy" {
  statement {
    effect  = "Allow"
    actions = "sts:AssumeRole"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
  statement {
    effect    = "Allow"
    actions   = "lambda:InvokeFunction"
    resources = ["arn:aws:lambda:*:${data.aws_caller_identity.account_id}:function:${local.retention_lambda_name}"]
  }
}

resource "aws_cloudformation_stack_set" "retention" {
  name             = "controltags-ticket-retention"
  permission_model = "SERVICE_MANAGED"
  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }
  capabilities = ["CAPABILITY_NAMED_IAM"]
  template_body = jsonencode({
    Resources = {
      ticket_retention_role = {
        Type = "AWS::IAM::Role"
        Properties = {
          AssumeRolePolicyDocument = data.aws_iam_policy_document.trust_policy.json
          Description              = "A role which periodically removes stale and invalid approval tickets"
          MaxSessionDuration       = 3600
          Path                     = "/tagctl/v1/mpa"
          Policies = [
            {
              PolicyName     = "approval_ticket_lifecycle"
              PolicyDocument = data.aws_iam_policy_document.approval_ticket_lifecycle.json
            },
            {
              PolicyName     = "org_traversal"
              PolicyDocument = data.aws_iam_policy_document.org_traversal.json
            }
          ]
          RoleName = "mpa_ticket_retention"
        }
      }
    }
  })
}
