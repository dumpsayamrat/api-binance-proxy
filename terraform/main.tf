provider "aws" {
  region = var.aws_region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    key = "api-binance-proxy/terraform.tfstate"
    # The bucket and region parameters will be injected in CI/CD pipeline
  }
}

# Lambda IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "api-binance-proxy-lambda-role"

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

# Lambda permissions policy
resource "aws_iam_policy" "lambda_policy" {
  name        = "api-binance-proxy-lambda-policy"
  description = "IAM policy for the Binance API proxy Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda function
resource "aws_lambda_function" "api_binance_proxy" {
  function_name = "api-binance-proxy"
  filename      = "lambda-function.zip"
  role          = aws_iam_role.lambda_role.arn
  handler       = "bootstrap"
  runtime       = "provided.al2"
  memory_size   = 128
  timeout       = 30

  environment {
    variables = {
      RUST_LOG = "info"
    }
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "api" {
  name        = "binance-proxy-api"
  description = "API Gateway for Binance API Proxy"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway Resource: /api
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "api"
}

# API Gateway Resource: /api/{proxy+}
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "{proxy+}"
}

# API Gateway Method: ANY
resource "aws_api_gateway_method" "proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
  api_key_required = true

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_binance_proxy.invoke_arn
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.api.id
  # stage_name was removed but will be handled by the separate stage resource

  lifecycle {
    create_before_destroy = true
  }
}

# Add separate API Gateway Stage resource (recommended approach)
# Note: This may need to be imported if the stage already exists
resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = var.environment
  
  # This lifecycle rule helps prevent destroying and recreating the stage
  lifecycle {
    create_before_destroy = true
    # This prevents the stage from being destroyed during this migration
    prevent_destroy = true
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_binance_proxy.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# API Key for authentication
resource "aws_api_gateway_api_key" "api_key" {
  name        = "binance-proxy-api-key"
  description = "API key for the Binance API proxy"
  enabled     = true
}

# Usage plan for API key
resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "binance-proxy-usage-plan"
  description = "Usage plan for the Binance API proxy"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.stage.stage_name
  }

  # Optional: Configure throttling
  throttle_settings {
    burst_limit = 10
    rate_limit  = 5
  }

  # Optional: Configure quota
  quota_settings {
    limit  = 1000
    period = "DAY"
  }
}

# Associate the API key with the usage plan
resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  key_id        = aws_api_gateway_api_key.api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
}

# Output API Gateway REST API ID (needed for importing stage)
output "aws_api_gateway_rest_api_id" {
  value = aws_api_gateway_rest_api.api.id
}

# Output API Gateway invoke URL
output "api_gateway_invoke_url" {
  value = "${aws_api_gateway_stage.stage.invoke_url}/api"
}

# Output API Key
output "api_key" {
  value     = aws_api_gateway_api_key.api_key.value
  sensitive = true
}