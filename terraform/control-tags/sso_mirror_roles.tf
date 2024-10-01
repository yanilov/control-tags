# this file provisions counterpart roles for each permissionset and assignment

data "aws_ssoadmin_instances" "main" {}

locals {
  sso_instance_arn = tolist(data.aws_ssoadmin_instances.main.arns)[0]
}

# list all permission sets in the organization
data "aws_ssoadmin_permission_sets" "main" {
  instance_arn = local.sso_instance_arn
}

# locals {
#   permission_set_arn_to_id = { for arn in data.aws_ssoadmin_permission_sets.main.arns : arn => reverse(split("/", arn))[0] }
# }


# lookup the permission by id
data "awscc_sso_permission_set" "main" {
  for_each = toset(data.aws_ssoadmin_permission_sets.main.arns)

  # ugly hack to get the permission id which cloudcontrol expects
  # see https://github.com/hashicorp/terraform-provider-awscc/issues/1065
  id = "${local.sso_instance_arn}|${each.key}"

  # todo: is instance_arn needed for fetching this datasource?
  # the aws provider counterpart needs it, but the awscc provider does not, according to docs
  # instance_arn = local.sso_instance_arn

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
      "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_${each.value.name}_*"]
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

# Create counterpart role as a clfor each permissionset
resource "aws_cloudformation_stack_set" "mirror_role" {
  for_each = data.awscc_sso_permission_set.main

  name             = "controltags-mirror-role-${each.value.name}"
  permission_model = "SERVICE_MANAGED"
  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }
  capabilities = ["CAPABILITY_NAMED_IAM"]
  template_body = jsonencode({
    Resources = {
      mirror_role = {
        Type = "AWS::IAM::Role"
        Properties = merge(
          {
            Path                     = "/tagctl/v1/sso"
            RoleName                 = "tagctl_mirror_${each.value.name}"
            MaxSessionDuration       = each.value.session_duration
            AssumeRolePolicyDocument = data.aws_iam_policy_document.mirror_role_trust_policy[each.key].json
            ManagedPolicyArns = concat(
              // AWS-managed policies
              try(coalesce(each.value.managed_policies), []),
              // customer-managed policies
              [
                for spec in try(coalesce(each.value.customer_managed_policy_references), []) :
                {
                  "Fn::Join" : [
                    "arn:aws:iam::",
                    { "Ref" : "AWS::AccountId" },
                    ":policy/${spec.path}/${spec.name}"
                  ]
                }
              ]
            )
            Policies = each.value.inline_policy == null ? null : [{
              PolicyName     = "inline"
              PolicyDocument = each.value.inline_policy
            }]
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
}


# instanciate the stackset for each deployment target
resource "aws_cloudformation_stack_set_instance" "mirror_role" {
  for_each = aws_cloudformation_stack_set.mirror_role

  stack_set_name = each.value.name
  dynamic "deployment_targets" {
    for_each = length(local.dyn_deployment_targets) > 0 ? [null] : []
    content {
      accounts                = local.dyn_deployment_targets.account_ids
      organizational_unit_ids = local.dyn_deployment_targets.organizational_unit_ids
    }
  }
}
