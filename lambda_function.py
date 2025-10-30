import os
import json
import boto3
import uuid
from datetime import datetime
import logging
import re

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client("sns")
dynamodb = boto3.resource("dynamodb")

TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
DDB_TABLE = os.environ.get("DDB_TABLE")

table = dynamodb.Table(DDB_TABLE)

SUSPICIOUS_PATTERNS = [
    r"filterlog: .*block",          # blocked firewall packets
    r"login attempt",               # failed admin logins
    r"VPN.*denied",                 # denied VPN connections
]

def is_suspicious(log_entry: str) -> bool:
    """Check if a log entry matches any suspicious pattern"""
    for pattern in SUSPICIOUS_PATTERNS:
        if re.search(pattern, log_entry, re.IGNORECASE):
            return True
    return False

def lambda_handler(event, context):
    invocation_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat()

    event_str = json.dumps(event, indent=2)

    # Only send SNS and log if suspicious
    if is_suspicious(event_str):
        message = f"Suspicious pfSense log detected:\n{event_str}"

        try:
            sns.publish(
                TopicArn=TOPIC_ARN,
                Message=message,
                Subject="Alert: Suspicious pfSense log"
            )
            logger.info(f"SNS notification sent successfully. InvocationID: {invocation_id}")
        except Exception as e:
            logger.error(f"Failed to send SNS notification: {e}")

        try:
            table.put_item(
                Item={
                    "InvocationID": invocation_id,
                    "Timestamp": timestamp,
                    "Event": event_str
                }
            )
            logger.info(f"DynamoDB log successful. InvocationID: {invocation_id}")
        except Exception as e:
            logger.error(f"Failed to write to DynamoDB: {e}")
    else:
        logger.info("Log is not suspicious — skipping SNS notification.")

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Processed log",
            "InvocationID": invocation_id,
            "Timestamp": timestamp
        })
    }
