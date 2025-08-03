# 🚀 Procdoc OCR API - Quick Start

Deploy a complete serverless OCR API with AI summarization in under 10 minutes!

## Prerequisites ✅

1. **AWS Account** with administrative access
2. **AWS CLI** installed and configured (`aws configure`)
3. **Terraform** installed on your system
4. **Bedrock Access** - Enable Claude model in us-east-1 region

## One-Command Deployment 🎯

```bash
./deploy.sh
```

That's it! The script will:
- ✅ Check prerequisites
- 🏗️ Deploy all AWS infrastructure
- 📤 Upload and configure the frontend
- 🔗 Provide you with the website URL

## What Gets Deployed 📦

- **AWS Lambda** - OCR processing function
- **API Gateway** - REST API endpoint
- **S3 Bucket** - Static website hosting
- **IAM Roles** - Secure permissions
- **Textract** - OCR service integration
- **Bedrock** - AI summarization with Claude

## Test Your API 🧪

1. Open the website URL provided after deployment
2. Upload a tax document (PDF or image, max 10MB)
3. Click "Upload & Process"
4. View extracted text and AI-generated 3-line summary

## Architecture Flow 🏗️

```
Client → API Gateway → Lambda → Textract (OCR) → Bedrock (AI) → Response
```

## Cost Estimate 💰

- **Development/Testing**: ~$0.01-0.10 per document
- **Production**: Scales with usage
- **Free Tier**: Covers initial testing

## Cleanup 🧹

```bash
./cleanup.sh
```

Removes all AWS resources and local state files.

## Troubleshooting 🔧

**Common Issues:**
- **Bedrock Access**: Ensure Claude is enabled in us-east-1
- **File Size**: Max 10MB for synchronous processing
- **Permissions**: Use admin/power user AWS credentials

**Logs**: Check CloudWatch `/aws/lambda/procdoc-function`

## Next Steps 🚀

- Customize the AI prompt in `procdoc_lambda.py`
- Enhance the frontend UI
- Add authentication
- Scale for production workloads

---

**Need help?** Check the full `DEPLOYMENT_GUIDE.md` for detailed explanations.