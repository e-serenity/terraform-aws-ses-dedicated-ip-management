# ---------------------------------------------------------------------------------------------------------------------
# SENDING REPORTS LAMBDA
# ---------------------------------------------------------------------------------------------------------------------

module "sending_reports_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "6.0.0"

  function_name = "${var.name_prefix}-ses-sending-reports"
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  source_path     = "./lambda/store-reports"
  memory_size   = 128
  timeout       = 60
  architectures = ["arm64"]

  cloudwatch_logs_retention_in_days = 7

  environment_variables = {
    DYNAMODB_BOUNCE_TABLE_NAME = module.dynamodb_table_bounce.dynamodb_table_id
  }
}

resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  depends_on       = [module.sending_reports_lambda]
  event_source_arn = module.sqs_sending_reports.queue_arn
  enabled          = true
  function_name    = module.sending_reports_lambda.lambda_function_arn
  batch_size       = 50
  maximum_batching_window_in_seconds     = 15
}

resource "aws_iam_policy" "run_application_events_logging_policy" {
  depends_on  = [module.dynamodb_table_bounce]
  name        = "${var.name_prefix}-lambda_access_policy"
  description = "Allows application events logging for Lambda"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
        "sqs:ChangeMessageVisibility"]
        Resource = [module.sqs_sending_reports.queue_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = [module.dynamodb_table_bounce.dynamodb_table_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "run_events_logging_attachment" {
  depends_on = [aws_iam_policy.run_application_events_logging_policy]
  policy_arn = aws_iam_policy.run_application_events_logging_policy.arn
  role       = module.sending_reports_lambda.lambda_role_name
}
