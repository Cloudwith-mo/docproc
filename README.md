# TaxDoc OCR-API on AWS

A serverless document processing API that accepts live uploads, performs OCR extraction using AWS Textract, and returns structured JSON data with AI-generated 3-line summaries.

## Features

- **Live Document Upload**: Accept PDF/image uploads via presigned S3 URLs
- **OCR Processing**: Extract text and structured data using AWS Textract
- **AI Summaries**: Generate concise 3-line summaries using Amazon Bedrock
- **JSON Output**: Return structured data in JSON format
- **Async Processing**: Non-blocking upload with status polling
- **Scalable**: Serverless architecture handles variable workloads

## Architecture

```
┌──────┐  POST /upload             S3:ObjectCreated     ┌──────────┐
│Client│ ───────────────▶ API GW ──────────────────────▶│uploads   │
└──┬───┘ 200: {upload_url, job_id, result_url}          └──────────┘
   │                                                   trigger
GET /result/{job_id}                                     ▼
   │                                            ┌────────────────┐
   ├──────────────▶ API GW ──▶ DynamoDB────────▶│process_doc λ   │
   │                                ▲          │1. Textract OCR │
   │                                │          │2. Bedrock TLDR │
   │                           PUT item        │3. save JSON    │
   │                                │          └────────────────┘
   │                                │                  │
   │                                │           ┌──────────────┐
   │                               update        │results bucket│
   │                                │            └──────────────┘
   │                                │
   └─────────────────────────────status/summary
```

## API Endpoints

### POST /upload
Initiates document upload and processing.

**Response:**
```json
{
  "upload_url": "https://s3.amazonaws.com/bucket/presigned-url",
  "job_id": "uuid-job-identifier",
  "result_url": "/result/uuid-job-identifier"
}
```

### GET /result/{job_id}
Retrieves processing status and results.

**Response (Processing):**
```json
{
  "status": "processing",
  "job_id": "uuid-job-identifier"
}
```

**Response (Complete):**
```json
{
  "status": "complete",
  "job_id": "uuid-job-identifier",
  "summary": [
    "Document contains tax form 1040 for tax year 2023.",
    "Total income reported: $75,000 with $12,000 in deductions.",
    "Refund amount: $2,500 to be direct deposited."
  ],
  "extracted_data": {
    "form_type": "1040",
    "tax_year": "2023",
    "fields": {
      "total_income": 75000,
      "deductions": 12000,
      "refund_amount": 2500
    }
  }
}
```

## AWS Services Used

- **API Gateway**: REST API endpoints
- **Lambda**: Document processing function
- **S3**: File storage (uploads & results)
- **DynamoDB**: Job status tracking
- **Textract**: OCR text extraction
- **Bedrock**: AI summary generation

## Quick Start

1. **Upload Document**
   ```bash
   curl -X POST https://api.example.com/upload
   ```

2. **Upload File to Presigned URL**
   ```bash
   curl -X PUT "presigned-url" --data-binary @document.pdf
   ```

3. **Check Results**
   ```bash
   curl https://api.example.com/result/{job_id}
   ```

## Deployment

The system uses serverless architecture for automatic scaling and cost optimization. Processing time typically ranges from 10-30 seconds depending on document complexity.

## Supported Formats

- PDF documents
- JPEG/PNG images
- Maximum file size: 10MB
- Supported languages: English (primary)

## Error Handling

- Invalid file formats return 400 status
- Processing failures are logged and return 500 status
- Job status includes error details when applicable