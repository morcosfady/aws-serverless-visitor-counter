# ---------- 1. DynamoDB: stores the counter ----------
resource "aws_dynamodb_table" "counter" {
  name         = "visitor-counter"
  billing_mode = "PAY_PER_REQUEST" # pay per use, $0 at portfolio traffic
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  server_side_encryption { enabled = true }
}

# ---------- 2. IAM: Lambda may ONLY update this one table ----------
resource "aws_iam_role" "lambda" {
  name = "visitor-counter-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "least-privilege"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.counter.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      }
    ]
  })
}

# ---------- 3. Lambda: adds +1 and returns the count ----------
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/counter.py"
  output_path = "${path.module}/build/counter.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/visitor-counter"
  retention_in_days = 7 # keep logs short = no storage cost
}

resource "aws_lambda_function" "counter" {
  function_name    = "visitor-counter"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "counter.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 5
  memory_size      = 128

  environment {
    variables = { TABLE_NAME = aws_dynamodb_table.counter.name }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# ---------- 4. API Gateway (HTTP API): public URL ----------
resource "aws_apigatewayv2_api" "api" {
  name          = "visitor-counter-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [var.allowed_origin] # only your portfolio
    allow_methods = ["GET"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.counter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "count" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /count"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  # Throttling: protects against abuse and surprise bills
  default_route_settings {
    throttling_rate_limit  = 5
    throttling_burst_limit = 10
  }
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*/count"
}
