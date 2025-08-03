terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "procdoc"
}

# IAM Role for Lambda
resource "aws_iam_role" "procdoc_lambda_role" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach policies
resource "aws_iam_role_policy_attachment" "lambda_basic_policy" {
  role       = aws_iam_role.procdoc_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "textract_policy" {
  role       = aws_iam_role.procdoc_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonTextractFullAccess"
}

resource "aws_iam_role_policy_attachment" "bedrock_policy" {
  role       = aws_iam_role.procdoc_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}

# Package Lambda code
data "archive_file" "procdoc_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/procdoc_lambda.py"
  output_path = "${path.module}/procdoc_lambda.zip"
}

# Lambda Function
resource "aws_lambda_function" "procdoc_lambda" {
  function_name = "${var.project_name}-function"
  filename      = data.archive_file.procdoc_lambda_package.output_path
  handler       = "procdoc_lambda.lambda_handler"
  runtime       = "python3.9"
  timeout       = 60
  memory_size   = 512
  role          = aws_iam_role.procdoc_lambda_role.arn
  
  source_code_hash = data.archive_file.procdoc_lambda_package.output_base64sha256
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "procdoc_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["*"]
  }
}

# Integration with Lambda
resource "aws_apigatewayv2_integration" "procdoc_integration" {
  api_id           = aws_apigatewayv2_api.procdoc_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.procdoc_lambda.arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

# Route
resource "aws_apigatewayv2_route" "procdoc_route" {
  api_id    = aws_apigatewayv2_api.procdoc_api.id
  route_key = "POST /process"
  target    = "integrations/${aws_apigatewayv2_integration.procdoc_integration.id}"
}

# Stage
resource "aws_apigatewayv2_stage" "procdoc_stage" {
  api_id      = aws_apigatewayv2_api.procdoc_api.id
  name        = "prod"
  auto_deploy = true
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "apigw_invoke" {
  function_name = aws_lambda_function.procdoc_lambda.function_name
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.procdoc_api.execution_arn}/*/*"
}

# Random suffix for bucket name
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# S3 bucket for frontend
resource "aws_s3_bucket" "procdoc_site" {
  bucket = "${var.project_name}-frontend-${random_string.suffix.id}"
}

# Website configuration
resource "aws_s3_bucket_website_configuration" "procdoc_site_config" {
  bucket = aws_s3_bucket.procdoc_site.id

  index_document {
    suffix = "index.html"
  }
}

# Public access block
resource "aws_s3_bucket_public_access_block" "site_public_access" {
  bucket = aws_s3_bucket.procdoc_site.id

  block_public_acls       = false
  block_public_policy     = false
  restrict_public_buckets = false
  ignore_public_acls      = false
}

# Bucket policy
resource "aws_s3_bucket_policy" "site_policy" {
  bucket = aws_s3_bucket.procdoc_site.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = "*",
      Action    = "s3:GetObject",
      Resource  = "${aws_s3_bucket.procdoc_site.arn}/*"
    }]
  })
  
  depends_on = [aws_s3_bucket_public_access_block.site_public_access]
}

# Get current AWS region
data "aws_region" "current" {}

# Outputs
output "api_url" {
  value = "${aws_apigatewayv2_api.procdoc_api.api_endpoint}/prod/process"
  description = "API Gateway endpoint URL"
}

output "website_url" {
  value = "http://${aws_s3_bucket.procdoc_site.id}.s3-website-${data.aws_region.current.name}.amazonaws.com"
  description = "S3 static website URL"
}

output "s3_bucket_name" {
  value = aws_s3_bucket.procdoc_site.id
  description = "S3 bucket name for frontend"
}