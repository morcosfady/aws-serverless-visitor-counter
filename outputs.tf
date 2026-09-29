output "api_url" {
  description = "Open this in a browser to test"
  value       = "${aws_apigatewayv2_api.api.api_endpoint}/count"
}
