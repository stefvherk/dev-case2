resource "aws_sns_topic" "admin_notifications" {
  name = "admin-notifications"
}

resource "aws_sns_topic_subscription" "admin_email" {
  topic_arn = aws_sns_topic.admin_notifications.arn
  protocol  = "email"
  endpoint  = "547380@student.fontys.nl"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-sns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_sns_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

resource "aws_lambda_function" "notify_admin" {
  function_name = "notify-admin"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.admin_notifications.arn
      DDB_TABLE     = aws_dynamodb_table.lambda_invocations.name
    }
  }
}

resource "aws_lambda_permission" "allow_cloudwatch_logs" {
  statement_id  = "AllowExecutionFromCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notify_admin.function_name
  principal     = "logs.amazonaws.com"
}

resource "time_sleep" "wait_lambda_ready" {
  depends_on      = [aws_lambda_function.notify_admin, aws_lambda_permission.allow_cloudwatch_logs]
  create_duration = "30s"
}

resource "aws_cloudwatch_log_subscription_filter" "pfsense_logs_to_lambda" {
  name            = "pfsense-logs-to-lambda"
  log_group_name  = aws_cloudwatch_log_group.pfsense_logs.name
  filter_pattern  = ""
  destination_arn = aws_lambda_function.notify_admin.arn

  depends_on = [
    time_sleep.wait_lambda_ready
  ]
}

resource "aws_dynamodb_table" "lambda_invocations" {
  name           = "lambda-invocations"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "InvocationID"
  attribute {
    name = "InvocationID"
    type = "S"
  }

  tags = {
    Name = "Lambda Invocation Logs"
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_access" {
  name = "lambda-dynamodb-access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.lambda_invocations.arn
      }
    ]
  })
}