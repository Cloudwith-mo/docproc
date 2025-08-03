# Beginner Guide to Build and Deploy Procdoc OCR API with Terraform and AWS

## Deploying the Procdoc TaxDoc OCR API in One Day (Terraform & AWS)

### Overview and Architecture

We will build a serverless OCR API (named Procdoc) that takes tax document images/PDFs, extracts text using Amazon Textract, then summarizes the text using Amazon Bedrock (Claude). The solution uses AWS Lambda as the backend compute and Amazon API Gateway to expose a RESTful endpoint.

**Key AWS Components:**
- **Amazon Textract** – OCR service that extracts text from images or PDFs
- **Amazon Bedrock (Claude)** – AI model for generating summaries
- **AWS Lambda** – serverless function that glues everything together
- **Amazon API Gateway** – provides REST endpoint for clients
- **Amazon S3** – hosts static frontend for testing

## Prerequisites and Setup

Before we begin, ensure the following:

1. **AWS Account and CLI**: AWS CLI installed and configured (`aws configure`)
2. **Terraform**: Install Terraform on your system
3. **AWS IAM Permissions**: Administrative access or power user account
4. **Amazon Bedrock Access**: Enable Claude model in us-east-1 region
5. **Development Environment**: Unix-like terminal (or WSL for Windows)

## Step 1: Initialize the Terraform Project

Create project directory:
```bash
mkdir procdoc && cd procdoc
```

Create `main.tf`:
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
```

Initialize Terraform:
```bash
terraform init
```

## Step 2: Create Lambda Function Code

Create `procdoc_lambda.py`:
```python
import boto3
import base64
import json

textract = boto3.client('textract')
bedrock = boto3.client('bedrock-runtime', region_name="us-east-1")

def lambda_handler(event, context):
    try:
        body = event.get("body", "")
        if event.get("isBase64Encoded", False):
            image_bytes = base64.b64decode(body)
        else:
            event_data = json.loads(body) if body else {}
            if "file_data" in event_data:
                image_bytes = base64.b64decode(event_data["file_data"])
            else:
                return {"statusCode": 400, "body": json.dumps("No file data provided")}

        # OCR with Textract
        textract_response = textract.detect_document_text(Document={"Bytes": image_bytes})
        text_lines = [item["Text"] for item in textract_response.get("Blocks", []) 
                     if item.get("BlockType") == "LINE"]
        full_text = "\n".join(text_lines)
        
        if not full_text:
            return {"statusCode": 400, "body": json.dumps("OCR found no text")}

        # Generate summary with Claude
        prompt = f"Summarize this tax document in 3 lines:\n{full_text}"
        
        bedrock_response = bedrock.invoke_model(
            contentType="application/json",
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 200,
                "messages": [{"role": "user", "content": prompt}]
            }),
            modelId="anthropic.claude-3-sonnet-20240229-v1:0"
        )
        
        result_json = json.loads(bedrock_response['body'].read().decode('utf-8'))
        summary_text = result_json.get("content", [{}])[0].get("text", "")

        result = {
            "extracted_text": full_text,
            "summary": summary_text.strip().split('\n')[:3]
        }
        return {"statusCode": 200, "body": json.dumps(result)}
        
    except Exception as e:
        print("Error:", str(e))
        return {"statusCode": 500, "body": json.dumps(f"Server error: {str(e)}")}
```

## Step 3: Define IAM Role and Permissions

Add to `main.tf`:
```hcl
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
```

## Step 4: Define Lambda Function Resource

Add to `main.tf`:
```hcl
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
}
```

## Step 5: Set Up API Gateway

Add to `main.tf`:
```hcl
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
```

## Step 6: Set Up S3 Bucket for Frontend

Add to `main.tf`:
```hcl
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
}

# Outputs
output "api_url" {
  value = "${aws_apigatewayv2_api.procdoc_api.api_endpoint}/prod/process"
}

output "website_url" {
  value = "http://${aws_s3_bucket.procdoc_site.id}.s3-website-${data.aws_region.current.name}.amazonaws.com"
}

data "aws_region" "current" {}
```

## Step 7: Create Frontend

Create `index.html`:
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Procdoc OCR Demo</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 600px; margin: 2em auto; }
    h1 { text-align: center; }
    .input-section { margin-bottom: 1em; }
    #result { white-space: pre-wrap; border: 1px solid #ccc; padding: 1em; margin-top: 1em; }
    button { padding: 10px 20px; background: #007bff; color: white; border: none; cursor: pointer; }
  </style>
</head>
<body>
  <h1>Procdoc – Tax Document OCR Demo</h1>
  <div class="input-section">
    <input type="file" id="fileInput" accept="image/*,.pdf" />
    <button id="uploadBtn">Upload & Process</button>
  </div>
  <h3>Result:</h3>
  <div id="result">[Waiting for input]</div>

  <script>
    const uploadBtn = document.getElementById('uploadBtn');
    const fileInput = document.getElementById('fileInput');
    const resultDiv = document.getElementById('result');

    // Replace with your API Gateway endpoint after deployment
    const API_URL = "REPLACE_WITH_YOUR_API_URL";

    uploadBtn.onclick = async () => {
      const file = fileInput.files[0];
      if (!file) {
        alert("Please select a file first.");
        return;
      }
      resultDiv.textContent = "Processing...";

      try {
        const arrayBuffer = await file.arrayBuffer();
        const uint8Array = new Uint8Array(arrayBuffer);
        const binaryString = uint8Array.reduce((data, byte) => data + String.fromCharCode(byte), '');
        const base64Data = btoa(binaryString);

        const response = await fetch(API_URL, {
          method: 'POST',
          body: base64Data,
          headers: { "Content-Type": "application/octet-stream" }
        });
        
        const resultText = await response.text();
        let resultObj;
        try {
          resultObj = JSON.parse(resultText);
        } catch {
          resultObj = resultText;
        }

        if (response.ok) {
          if (typeof resultObj === 'object') {
            resultDiv.textContent = JSON.stringify(resultObj, null, 2);
          } else {
            resultDiv.textContent = resultObj;
          }
        } else {
          resultDiv.textContent = "Error: " + resultText;
        }
      } catch (err) {
        console.error("Request failed", err);
        resultDiv.textContent = "Error calling API: " + err;
      }
    };
  </script>
</body>
</html>
```

## Step 8: Deploy Infrastructure

1. **Review plan:**
```bash
terraform plan
```

2. **Apply configuration:**
```bash
terraform apply
```

3. **Note the outputs** (API URL and Website URL)

## Step 9: Upload Frontend and Test

1. **Upload frontend to S3:**
```bash
# Replace bucket name with your actual bucket name from terraform output
aws s3 cp index.html s3://procdoc-frontend-xxxxxx/
```

2. **Update API URL in frontend:**
   - Edit the uploaded `index.html` in S3 console
   - Replace `REPLACE_WITH_YOUR_API_URL` with your actual API Gateway URL

3. **Test the application:**
   - Open the S3 website URL in your browser
   - Upload a tax document image or PDF
   - Click "Upload & Process"
   - View the extracted text and AI-generated summary

## Cleanup

To avoid ongoing costs:
```bash
# Empty S3 bucket first
aws s3 rm s3://your-bucket-name --recursive

# Destroy infrastructure
terraform destroy
```

## Troubleshooting

- **Bedrock Access**: Ensure Claude model is enabled in us-east-1
- **Lambda Timeout**: Increase timeout if processing takes longer
- **CORS Issues**: Check API Gateway CORS configuration
- **CloudWatch Logs**: Check `/aws/lambda/procdoc-function` for errors

## Cost Optimization

- Textract: ~$1.50 per 1,000 pages
- Bedrock: Pay per token (pennies for short texts)
- Lambda/API Gateway: Free tier covers light usage
- S3: Minimal storage costs

This serverless architecture scales automatically and only charges for actual usage!