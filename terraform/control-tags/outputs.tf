output "control_tags_scp_id" {
  value = aws_organizations_policy.control_tags.id
  description = "policy ID for the generated control tags policy"
}