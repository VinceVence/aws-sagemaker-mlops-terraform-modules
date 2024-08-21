variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "sagemaker_endpoint_name" {
  description = "The name of the existing SageMaker endpoint"
  type        = string
  default     = "xgb-car-pricing-endpoint-lab-2024-08-18-14-44-41"
}


variable "lambda_timeout" {
  description = "Timeout for the Lambda function"
  type        = number
  default     = 60
}

variable "lambda_layers" {
  description = "Lambda layers to include"
  type        = list(string)
  default     = [
    "arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p312-numpy:5",
    "arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p312-pandas:7"
  ]
}

variable "default_var" {
  description = "Default variable for the model"
  type        = number
  default     = 1080000
}
