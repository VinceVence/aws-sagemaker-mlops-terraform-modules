output "api_gateway_invoke_url" {
  description = "Invoke URL of the API Gateway"
  value       = aws_api_gateway_deployment.ml_model_deployment.invoke_url
}
