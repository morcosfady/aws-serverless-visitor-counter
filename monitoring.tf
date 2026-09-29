# =====================================================================
# Project 5: Observability + cost guardrails for the visitor counter API
# All within AWS always-free limits (10 alarms, 3 dashboards, 2 budgets)
# =====================================================================

locals {
  api_id   = aws_apigatewayv2_api.api.id
  function = aws_lambda_function.counter.function_name
  table    = aws_dynamodb_table.counter.name
}

# ---------- 1. Alert channel ----------
resource "aws_sns_topic" "alerts" {
  name = "visitor-counter-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------- 2. Alarms: "tell me when users are affected" ----------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "visitor-counter-lambda-errors"
  alarm_description   = "Lambda threw an error (code bug or DynamoDB problem)"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = local.function }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "visitor-counter-api-5xx"
  alarm_description   = "Visitors are getting server errors"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = local.api_id, Stage = "$default" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "visitor-counter-api-slow"
  alarm_description   = "p90 latency above 1 second for 10 minutes"
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  dimensions          = { ApiId = local.api_id, Stage = "$default" }
  extended_statistic  = "p90"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "visitor-counter-lambda-throttles"
  alarm_description   = "Lambda is being throttled (traffic spike or abuse)"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = local.function }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ---------- 3. Dashboard: one screen for health ----------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "visitor-counter"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "API requests and errors"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", local.api_id, "Stage", "$default", { label = "Requests" }],
            [".", "4xx", ".", ".", ".", ".", { label = "4xx (client)" }],
            [".", "5xx", ".", ".", ".", ".", { label = "5xx (server)" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "API latency (ms)"
          region = var.region
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", local.api_id, "Stage", "$default", { stat = "p50", label = "p50" }],
            ["...", { stat = "p90", label = "p90" }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Lambda health"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", local.function],
            [".", "Errors", ".", "."],
            [".", "Throttles", ".", "."]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Lambda duration (ms) and DynamoDB writes"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", local.function, { stat = "Average", label = "Avg duration" }],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", local.table, { stat = "Sum", label = "DynamoDB writes", yAxis = "right" }]
          ]
        }
      },
      {
        type = "alarm", x = 0, y = 12, width = 24, height = 3
        properties = {
          title = "Alarm status"
          alarms = [
            aws_cloudwatch_metric_alarm.lambda_errors.arn,
            aws_cloudwatch_metric_alarm.api_5xx.arn,
            aws_cloudwatch_metric_alarm.api_latency.arn,
            aws_cloudwatch_metric_alarm.lambda_throttles.arn
          ]
        }
      }
    ]
  })
}

# ---------- 4. Cost guardrail (budget as code) ----------
resource "aws_budgets_budget" "monthly" {
  name         = "visitor-counter-monthly-guardrail"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 20
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}
