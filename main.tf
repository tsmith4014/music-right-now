provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "aws_lambda_function" "slack_music_bot" {
  function_name = "slack_music_bot"
  handler       = "lambda_function.handler"
  runtime       = "python3.8"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "${path.module}/lambda.zip"
  environment {
    variables = {
      SLACK_SIGNING_SECRET = var.slack_signing_secret
      SLACK_BOT_TOKEN      = var.slack_bot_token
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.slack_music_bot.function_name}"
  retention_in_days = 14
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "Slack Music Bot API"
  description = "API Gateway for the Slack Music Bot"
}

resource "aws_api_gateway_resource" "slack_command" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "slack"
}

resource "aws_api_gateway_method" "post_slack_command" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.slack_command.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.slack_command.id
  http_method             = aws_api_gateway_method.post_slack_command.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.slack_music_bot.arn}/invocations"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
  depends_on = [
    aws_api_gateway_integration.lambda
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_music_bot.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.api.id}/*/POST/slack"
}
