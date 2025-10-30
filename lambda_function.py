import os
import json
import boto3
import uuid
from datetime import datetime
import logging
import re
import base64
import gzip

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client("sns")
dynamodb = boto3.resource("dynamodb")

TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
DDB_TABLE = os.environ.get("DDB_TABLE")
table = dynamodb.Table(DDB_TABLE)

SUSPICIOUS_PATTERNS = [
    r"login attempt",
    r"authentication error",
    r"VPN.*denied",
]

def is_suspicious(log_entry: str):
    """Check if a log entry matches any suspicious pattern and return the matched pattern"""
    for pattern in SUSPICIOUS_PATTERNS:
        if re.search(pattern, log_entry, re.IGNORECASE):
            return pattern
    return None

def extract_log_from_event(event):
    """
    Extract log lines from CloudWatch Logs, SNS messages, or direct log keys.
    Logs the exact string being checked.
    """
    logger.info(f"Raw event received: {json.dumps(event)}")

    # CloudWatch Logs event
    if "awslogs" in event and "data" in event["awslogs"]:
        try:
            compressed_payload = base64.b64decode(event["awslogs"]["data"])
            uncompressed_payload = gzip.decompress(compressed_payload)
            payload_json = json.loads(uncompressed_payload)
            logs = [log["message"] for log in payload_json.get("logEvents", [])]
            extracted = "\n".join(logs)
            logger.info(f"Extracted log lines for checking:\n{extracted}")
            return extracted
        except Exception as e:
            logger.error(f"Failed to parse CloudWatch Logs event: {e}")

    # SNS event
    if "Records" in event:
        try:
            record = event["Records"][0]
            if "Sns" in record and "Message" in record["Sns"]:
                extracted = record["Sns"]["Message"]
                logger.info(f"Extracted SNS message for checking:\n{extracted}")
                return extracted
        except Exception as e:
            logger.warning(f"Failed to parse SNS message: {e}")

    # Direct log
    extracted = event.get("log") or event.get("message") or str(event)
    logger.info(f"Extracted direct log/message for checking:\n{extracted}")
    return extracted

def lambda_handler(event, context):
    invocation_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat()

    event_str = extract_log_from_event(event)
    matched_pattern = is_suspicious(event_str)

    if matched_pattern:
        logger.info(f"Suspicious pattern detected: '{matched_pattern}'")

        message = f"Suspicious pfSense log detected (pattern: {matched_pattern}):\n{event_str}"

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
                    "Event": event_str,
                    "MatchedPattern": matched_pattern
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
