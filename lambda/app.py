import json
import os
import logging
import boto3

logger = logging.getLogger()
logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))

def lambda_handler(event, context):
    # simple echo with env awareness
    body = {}
    if event.get("body"):
        try:
            body = json.loads(event["body"])
        except Exception:
            body = {"message": event.get("body")}
    message = body.get("message", "hello from ai-agent")
    return {
        "statusCode": 200,
        "body": json.dumps({
            "env": os.environ.get("ENVIRONMENT"),
            "message": f"echo: {message}"
        })
    }
