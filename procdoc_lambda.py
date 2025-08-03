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
        prompt = f"Summarize this tax document in exactly 3 lines:\n{full_text}"
        
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

        # Split summary into 3 lines
        summary_lines = [line.strip() for line in summary_text.strip().split('\n') if line.strip()]
        if len(summary_lines) > 3:
            summary_lines = summary_lines[:3]
        elif len(summary_lines) < 3:
            # Pad with empty strings if less than 3 lines
            summary_lines.extend([""] * (3 - len(summary_lines)))

        result = {
            "extracted_text": full_text,
            "summary": summary_lines
        }
        return {"statusCode": 200, "body": json.dumps(result)}
        
    except Exception as e:
        print("Error:", str(e))
        return {"statusCode": 500, "body": json.dumps(f"Server error: {str(e)}")}