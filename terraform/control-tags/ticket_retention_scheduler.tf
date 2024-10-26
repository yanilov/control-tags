resource "aws_scheduler_schedule_group" "retention" {
  name = local.retention_name_base
}

resource "aws_iam_role" "retention_scheduler" {
  name = local.retention_role.scheduler.name
  path = local.retention_role.scheduler.path

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
            "aws:SourceArn"     = aws_scheduler_schedule_group.retention.arn
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "retention_scheduler" {
  name = "ticket-retention-scheduler"
  role = aws_iam_role.retention_scheduler.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.retention.arn
      }
    ]
  })
}


resource "aws_scheduler_schedule" "retention" {
  name        = local.retention_name_base
  description = "A schedule to run the ticket retention lambda"
  group_name  = aws_scheduler_schedule_group.retention.name

  schedule_expression = "rate(${var.lambda_scheduler_rate_minutes} minutes)"
  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:lambda:invoke"
    role_arn = aws_iam_role.retention_scheduler.arn

    input = jsonencode({
      FunctionName   = aws_lambda_function.retention.function_name
      InvocationType = "Event"
      Payload = jsonencode({
        ScheduleApprovalEviction = {}
      })
    })
  }
}
