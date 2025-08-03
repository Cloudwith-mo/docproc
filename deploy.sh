#!/bin/bash

# Procdoc OCR API Deployment Script
set -e

echo "🚀 Starting Procdoc OCR API Deployment..."

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install Terraform first."
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install AWS CLI first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

echo "✅ Prerequisites check passed!"

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init

# Plan deployment
echo "📝 Creating deployment plan..."
terraform plan -out=tfplan

# Ask for confirmation
echo ""
read -p "🤔 Do you want to proceed with deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled."
    exit 1
fi

# Apply Terraform
echo "🏗️  Deploying infrastructure..."
terraform apply tfplan

# Get outputs
echo "📊 Getting deployment outputs..."
API_URL=$(terraform output -raw api_url)
WEBSITE_URL=$(terraform output -raw website_url)
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

echo ""
echo "✅ Infrastructure deployed successfully!"
echo ""
echo "📋 Deployment Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔗 API Endpoint: $API_URL"
echo "🌐 Website URL: $WEBSITE_URL"
echo "🪣 S3 Bucket: $BUCKET_NAME"
echo ""

# Update frontend with API URL
echo "🔄 Updating frontend with API URL..."
sed "s|REPLACE_WITH_YOUR_API_URL|$API_URL|g" index.html > index_updated.html

# Upload frontend to S3
echo "📤 Uploading frontend to S3..."
aws s3 cp index_updated.html s3://$BUCKET_NAME/index.html --content-type "text/html"

# Clean up temporary file
rm index_updated.html

echo ""
echo "🎉 Deployment Complete!"
echo ""
echo "🧪 Testing Instructions:"
echo "1. Open: $WEBSITE_URL"
echo "2. Upload a tax document (PDF or image)"
echo "3. Click 'Upload & Process'"
echo "4. View the extracted text and AI summary"
echo ""
echo "🔧 Troubleshooting:"
echo "• Check CloudWatch Logs: /aws/lambda/procdoc-function"
echo "• Ensure Bedrock Claude access is enabled in us-east-1"
echo "• Verify file size is under 10MB"
echo ""
echo "💰 Cost Estimate:"
echo "• Textract: ~$1.50 per 1,000 pages"
echo "• Bedrock: ~$0.003 per 1K tokens"
echo "• Lambda/API Gateway: Free tier covers light usage"
echo ""
echo "🧹 To cleanup: ./cleanup.sh"