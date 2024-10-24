data "aws_iam_policy_document" "retention_worker" {
  # allow the lambda to write logs
  source_policy_documents = [data.aws_iam_policy_document.retention_logging.json]

  # allow removing the approval ticket tag from roles and users
  statement {
    sid    = "ListIAMTags"
    effect = "Allow"
    actions = [
      "iam:ListUsers",
      "iam:ListRoles",
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
      values   = [local.approval_ticket_tag_key]
    }
  }
}

# the role that the lambda will assume in each
resource "aws_cloudformation_stack_set" "retention" {
  name             = local.retention_role.worker.name
  permission_model = "SERVICE_MANAGED"
  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }
  capabilities = ["CAPABILITY_NAMED_IAM"]
  template_body = jsonencode({
    Resources = {
      TicketRetentionRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = local.retention_role.worker.name
          Path     = local.retention_role.worker.path
          AssumeRolePolicyDocument = jsonencode({
            Version = "2012-10-17"
            Statement = [
              {
                Effect = "Allow"
                Principal = {
                  AWS = aws_iam_role.retention_manager.arn
                }
                Action = "sts:AssumeRole"
              }
            ]
          })
          Description        = "A role which periodically removes stale approval tickets"
          MaxSessionDuration = 3600
          Policies = [
            {
              PolicyName     = local.retention_role.worker.name
              PolicyDocument = data.aws_iam_policy_document.retention_worker.json
            }
          ]
          Tags = [
            {
              Key   = local.grant_area_tag_key
              Value = local.approval_ticket_tag_key
            }
          ]
        }
      }
    }
  })

  lifecycle {
    # perpetual diff suppression, this value cannot be specifies as it conflicts with the auto_deployment block
    ignore_changes = [administration_role_arn]
  }
}

# the instance of the stack set in each of the specified accounts
resource "aws_cloudformation_stack_set_instance" "retention" {
  count = length(values(var.deployment_targets)) > 0 ? 1 : 0

  stack_set_name = aws_cloudformation_stack_set.retention.name
  dynamic "deployment_targets" {
    for_each = length(local.dyn_deployment_targets) > 0 ? [null] : []
    content {
      accounts                = try(local.dyn_deployment_targets.account_ids, null)
      organizational_unit_ids = try(local.dyn_deployment_targets.organizational_unit_ids, null)
    }
  }
}
