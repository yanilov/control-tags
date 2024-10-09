# this file provisions counterpart roles for each permissionset and assignment

data "aws_ssoadmin_instances" "main" {}

locals {
  sso_instance_arn = tolist(data.aws_ssoadmin_instances.main.arns)[0]
}

# list all permission sets in the organization
data "aws_ssoadmin_permission_sets" "main" {
  instance_arn = local.sso_instance_arn
}


# lookup the permission by id
data "awscc_sso_permission_set" "main" {
  for_each = toset(data.aws_ssoadmin_permission_sets.main.arns)

  # ugly hack to get the permission id which cloudcontrol expects
  # see https://github.com/hashicorp/terraform-provider-awscc/issues/1065
  id = "${local.sso_instance_arn}|${each.key}"
}

data "aws_iam_policy_document" "mirror_role_trust_policy" {
  for_each = data.awscc_sso_permission_set.main

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
    principals {
      type = "AWS"
      # trust the sso role which is the counterpart of the permission set in the account,
      # regardless of the account, region, and unique suffix
      identifiers = [
        # jsonencode({ Ref = "AWS::AccountId" })
        "*"
        #"arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_${each.value.name}_*"
      ]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_${each.value.name}_*"]
    }
    # only if the resource account is the same as the principal account
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = ["$${aws:PrincipalAccount}"]
    }
    # only if the sso role session passes a source identity value that matches its own identitystore user id
    condition {
      test     = "StringEquals"
      variable = "sts:SourceIdentity"
      values   = ["$${identitystore:UserId}"]
    }
  }
}

locals {
  # reshape the tags property to a map
  permission_sets_fixed = { for key, value in data.awscc_sso_permission_set.main : key => merge(
    value,
    {
      tags = { for t in coalesce(value.tags, []) : t.key => t.value }
    })
  }

  filtered_permission_sets = {
    for key, value in local.permission_sets_fixed : key => value if lookup(
      value.tags,
      local.installer_tag_keys.grant_area_suffix,
      ""
    ) != ""
  }
}

# Create counterpart role as a clfor each permissionset
resource "aws_cloudformation_stack_set" "mirror_role" {
  for_each = local.filtered_permission_sets

  name             = "controltags-mirror-role-${each.value.name}"
  permission_model = "SERVICE_MANAGED"
  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  capabilities = ["CAPABILITY_NAMED_IAM"]
  template_body = jsonencode({
    Resources = {
      MirrorRole = {
        Type = "AWS::IAM::Role"
        Properties = merge(
          {
            Path               = "/tagctl/v1/sso/"
            RoleName           = "tagctl-mirror-${each.value.name}"
            MaxSessionDuration = tonumber(regexall("^PT(\\d+)H$", each.value.session_duration)[0][0]) * 3600
            #AssumeRolePolicyDocument = data.aws_iam_policy_document.mirror_role_trust_policy[each.key].json
            AssumeRolePolicyDocument = {
              Version = "2012-10-17"
              Statement = [
                {
                  Effect = "Allow"
                  Action = ["sts:AssumeRole", "sts:SetSourceIdentity"]
                  Principal = {
                    AWS = { Ref = "AWS::AccountId" }
                  }
                  Condition = {
                    ArnLike = {
                      "aws:PrincipalArn" = "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_${each.value.name}_*"
                    }
                    StringEquals = {
                      "sts:SourceIdentity" = "$${identitystore:UserId}"
                    }
                  }
                },
                {
                  Effect = "Allow"
                  Action = ["sts:TagSession"]
                  Principal = {
                    AWS = { Ref = "AWS::AccountId" }
                  }
                }
              ]
            }
            ManagedPolicyArns = concat(
              # AWS-managed policies
              coalesce(each.value.managed_policies, []),
              # customer-managed policies
              [for spec in coalesce(each.value.customer_managed_policy_references, []) :
                {
                  "Fn::Join" : [
                    "arn:aws:iam::",
                    { "Ref" : "AWS::AccountId" },
                    ":policy/${spec.path}/${spec.name}"
                  ]
                }
              ]
            )
            Policies = [for policy in each.value.inline_policy[*] : {
              PolicyName     = "inline"
              PolicyDocument = policy
              } if policy != ""
            ]
            Tags = [
              # place a grant area control tag on the mirror role, as specified by the permission set
              {
                Key   = local.grant_area_tag_key,
                Value = "${local.control_v1}/${each.value.tags[local.installer_tag_keys.grant_area_suffix]}"
              }
            ]
          },
          # append map for aws-managed policy boundary if exists
          try(coalesce(each.value.permissions_boundary.managed_policy_arn), null) == null ? {} : {
            PermissionsBoundary = each.value.permissions_boundary.managed_policy_arn
          },
          # append map for customer-managed policy boundary if exists
          try(coalesce(each.value.permissions_boundary.customer_managed_policy_reference.name), null) == null ? {} : {
            PermissionsBoundary = {
              "Fn::Join" : [
                "arn:aws:iam::",
                { "Ref" : "AWS::AccountId" },
                ":policy/${each.value.permissions_boundary.customer_managed_policy_reference.path}/${each.value.permissions_boundary.customer_managed_policy_reference.name}",
              ]
            }
        })
      }
    }
  })

  lifecycle {
    # perpetual diff suppression, this value cannot be specifies as it conflicts with the auto_deployment block
    ignore_changes = [administration_role_arn]
  }
}


# instanciate the stackset for each deployment target
resource "aws_cloudformation_stack_set_instance" "mirror_role" {
  for_each = aws_cloudformation_stack_set.mirror_role

  stack_set_name = each.value.name
  dynamic "deployment_targets" {
    for_each = length(local.dyn_deployment_targets) > 0 ? [null] : []
    content {
      accounts                = try(local.dyn_deployment_targets.account_ids, null)
      organizational_unit_ids = try(local.dyn_deployment_targets.organizational_unit_ids, null)
    }
  }
}
