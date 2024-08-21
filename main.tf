provider "aws" {
  region = var.aws_region
}

# =========================
# IAM Role for Lambda
# =========================

# Define the IAM role that the Lambda function will assume
resource "aws_iam_role" "lambda_role" {
  name = "lambda_sagemaker_role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  })
}

# Create the IAM policy for the Lambda function to invoke the SageMaker endpoint
resource "aws_iam_policy" "lambda_policy" {
  name = "lambda_sagemaker_policy"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "sagemaker:InvokeEndpoint"
        ],
        "Resource": "*",
        "Effect": "Allow"
      }
    ]
  })
}

# Attach the policy to the IAM role
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# =========================
# Lambda Function
# =========================

# Create the Lambda function that handles API requests
resource "aws_lambda_function" "ml_model_lambda" {
  function_name = "ml_model_lambda"
  handler       = "lambda.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_role.arn
  filename      = "${path.module}/utils/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/utils/lambda.zip")

  timeout = var.lambda_timeout  # Set Lambda timeout

  environment {
    variables = {
      ENDPOINT_NAME = var.sagemaker_endpoint_name  # Set SageMaker endpoint name
    }
  }

  layers = var.lambda_layers  # Include necessary Lambda layers
}

# =========================
# API Gateway
# =========================

# Create the API Gateway REST API
resource "aws_api_gateway_rest_api" "ml_model_api" {
  name        = "MLModelAPI"
  description = "API Gateway for ML Model Prediction"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Define a proxy resource in API Gateway to forward requests to Lambda
resource "aws_api_gateway_resource" "proxy_resource" {
  rest_api_id = aws_api_gateway_rest_api.ml_model_api.id
  parent_id   = aws_api_gateway_rest_api.ml_model_api.root_resource_id
  path_part   = "{proxy+}"
}

# Define the API Gateway method (ANY) for the proxy resource
resource "aws_api_gateway_method" "proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.ml_model_api.id
  resource_id   = aws_api_gateway_resource.proxy_resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

# Define the method response for the API Gateway method
resource "aws_api_gateway_method_response" "proxy_method_response" {
  rest_api_id = aws_api_gateway_rest_api.ml_model_api.id
  resource_id = aws_api_gateway_resource.proxy_resource.id
  http_method = aws_api_gateway_method.proxy_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  # Allow CORS headers in the method response
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}


# Integrate the API Gateway method with the Lambda function
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.ml_model_api.id
  resource_id = aws_api_gateway_resource.proxy_resource.id
  http_method = aws_api_gateway_method.proxy_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ml_model_lambda.invoke_arn
}

# Define the integration response for the API Gateway integration
resource "aws_api_gateway_integration_response" "proxy_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.ml_model_api.id
  resource_id = aws_api_gateway_resource.proxy_resource.id
  http_method = aws_api_gateway_method.proxy_method.http_method
  status_code = aws_api_gateway_method_response.proxy_method_response.status_code

  # Properly define the response parameters for CORS
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
  }

  depends_on = [
    aws_api_gateway_method_response.proxy_method_response,
    aws_api_gateway_integration.lambda_integration
  ]
}


# Deploy the API Gateway
resource "aws_api_gateway_deployment" "ml_model_deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method_response.proxy_method_response,
    aws_api_gateway_integration_response.proxy_integration_response
  ]

  rest_api_id = aws_api_gateway_rest_api.ml_model_api.id
  stage_name  = "prod"
}

# API Gateway Trigger for Lambda
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ml_model_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ml_model_api.execution_arn}/*/*"
}

# =========================
# Configuration for Streamlit
# =========================

# Generate the config.yaml file for Streamlit
resource "local_file" "api_gateway_config" {
  content  = templatefile("${path.module}/config_template.yaml.tmpl",
    {
      endpoint      = aws_api_gateway_deployment.ml_model_deployment.invoke_url,
      endpoint_name = var.sagemaker_endpoint_name,
      default_price = var.default_var
    })
  filename = "${path.module}/utils/config.yaml"
}
