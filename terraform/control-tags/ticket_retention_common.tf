locals {
  retention_name_base        = "tagctl-ticket-retention"
  retention_lambda_name      = local.retention_name_base
  retention_lambda_log_group = "/aws/lambda/${local.retention_lambda_name}"

  retention_role = {
    worker    = { name = "${local.retention_name_base}-worker", path = "/tagctl/mpa/retention/" }
    manager   = { name = "${local.retention_name_base}-manager", path = "/tagctl/mpa/retention/" }
    scheduler = { name = "${local.retention_name_base}-scheduler", path = "/tagctl/mpa/retention/" }
  }
}

resource "aws_cloudwatch_log_group" "retention_lambda" {
  name              = local.retention_lambda_log_group
  retention_in_days = var.lambda_log_retention_in_days
}

# allows the lambda to write logs to CloudWatch
data "aws_iam_policy_document" "retention_logging" {
  statement {
    sid    = "LogToCloudWatch"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      aws_cloudwatch_log_group.retention_lambda.arn,
      "${aws_cloudwatch_log_group.retention_lambda.arn}:log-stream:*"
    ]
  }
}
