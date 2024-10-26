locals {
  retention_lambda_arn = "arn:aws:lambda:*:${data.aws_caller_identity.main.account_id}:function:${local.retention_lambda_name}"
}

data "aws_iam_policy_document" "retention_manager" {
  # allow the lambda to write logs
  source_policy_documents = [data.aws_iam_policy_document.retention_logging.json]

  # traverse the organization's structure
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
  # allows the lambda (in manager mode) to invoke itself (in worker mode)
  statement {
    sid       = "InvokeLambdaAsWorker"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [local.retention_lambda_arn]
  }
  # allows the lambda (in worker mode) to assume the worker role
  statement {
    sid       = "AssumeWorkerRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role${local.retention_role.worker.path}${local.retention_role.worker.name}"]
  }
}

resource "aws_iam_role" "retention_manager" {
  name = local.retention_role.manager.name
  path = local.retention_role.manager.path

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "retention_manager" {
  name   = "ticket-retention-manager"
  role   = aws_iam_role.retention_manager.name
  policy = data.aws_iam_policy_document.retention_manager.json
}

resource "aws_lambda_function" "retention" {
  depends_on = [aws_cloudformation_stack_set.retention, aws_cloudformation_stack_set_instance.retention]

  function_name = local.retention_lambda_name
  role          = aws_iam_role.retention_manager.arn
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  handler       = "rust.handler"
  timeout       = var.lambda_timetout_seconds

  filename         = var.lambda_archive_file
  source_code_hash = filebase64sha256(var.lambda_archive_file)

  logging_config {
    log_group  = aws_cloudwatch_log_group.retention_lambda.name
    log_format = "JSON"
  }

  environment {
    variables = {
      "MAX_TICKET_TTL_SECONDS" = var.max_ticket_ttl_seconds
      "WORKER_ROLE_NAME"       = local.retention_role.worker.name
      "WORKER_ROLE_PATH"       = local.retention_role.worker.path
      "CONTROL_TAGS_SCP_ID"    = aws_organizations_policy.control_tags.id
    }
  }
}
