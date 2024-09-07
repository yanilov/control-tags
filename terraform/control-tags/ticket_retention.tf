locals {
  retention_lambda_name = "mpa_ticket_retention"
  retention_lambda_arn  = "arn:aws:lambda:*:${data.aws_caller_identity.account_id}:function:${local.retention_lambda_name}"
}

# a policy document that allows to remove the approval ticket tag from roles and users
data "aws_iam_policy_document" "approval_ticket_lifecycle" {
  statement {
    sid    = "ListIAMTags"
    effect = "Allow"
    actions = [
      "iam:ListRoleTags",
      "iam:ListUserTags",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "RemoveApprovalTicket"
    effect = "Allow"
    actions = [
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

# a policy document that allows to traverse the organization's structure
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

# allows the lambda (in manager mode) to invoke itself (in worker mode)
data "aws_iam_policy_document" "invoke_self" {
  statement {
    sid = "InvokeSelf"

    effect    = "Allow"
    actions   = "lambda:InvokeFunction"
    resources = [local.retention_lambda_arn]
  }
}


# trust policy for the retention lambda role.
data "aws_iam_policy_document" "trust_policy" {
  statement {
    effect  = "Allow"
    actions = "sts:AssumeRole"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# the role that the lambda will assume in each
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
          Description              = "A role which periodically removes stale approval tickets"
          MaxSessionDuration       = 3600
          Path                     = "/tagctl/v1/mpa"
          Policies = [
            {
              PolicyName     = "invoke_self",
              PolicyDocument = data.aws_iam_policy_document.invoke_self.json
            },
            {
              PolicyName     = "approval_ticket_lifecycle"
              PolicyDocument = data.aws_iam_policy_document.approval_ticket_lifecycle.json
            },
            {
              PolicyName     = "org_traversal"
              PolicyDocument = data.aws_iam_policy_document.org_traversal.json
            }
          ]
          RoleName = "tagctl_ticket_retention"
        }
      }
    }
  })
}

resource "aws_cloudformation_stack_set_instance" "retention" {
  stack_set_name = aws_cloudformation_stack_set.retention
  deployment_targets {
    accounts                = var.deployment_targets.account_ids
    organizational_unit_ids = var.deployment_targets.organizational_unit_ids
  }
}
