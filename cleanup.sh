#!/bin/bash

# Procdoc OCR API Cleanup Script
set -e

echo "🧹 Starting Procdoc OCR API Cleanup..."

# Check if Terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo "❌ No Terraform state found. Nothing to cleanup."
    exit 1
fi

# Get S3 bucket name before destroying
BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")

if [ ! -z "$BUCKET_NAME" ]; then
    echo "🗑️  Emptying S3 bucket: $BUCKET_NAME"
    aws s3 rm s3://$BUCKET_NAME --recursive || echo "⚠️  Could not empty bucket (may already be empty)"
fi

# Ask for confirmation
echo ""
read -p "🤔 Are you sure you want to destroy all resources? This cannot be undone! (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 1
fi

# Destroy infrastructure
echo "💥 Destroying infrastructure..."
terraform destroy -auto-approve

# Clean up local files
echo "🧽 Cleaning up local files..."
rm -f terraform.tfstate*
rm -f tfplan
rm -f procdoc_lambda.zip
rm -f .terraform.lock.hcl
rm -rf .terraform/

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "📋 What was removed:"
echo "• All AWS resources (Lambda, API Gateway, S3, IAM roles)"
echo "• Local Terraform state files"
echo "• Generated zip files"
echo ""
echo "📁 What remains:"
echo "• Source code files (main.tf, procdoc_lambda.py, index.html)"
echo "• Documentation files"
echo ""
echo "🔄 To redeploy: ./deploy.sh"