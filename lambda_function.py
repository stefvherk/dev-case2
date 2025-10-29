import os
import json
import boto3
import uuid
from datetime import datetime
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
sns = boto3.client("sns")
dynamodb = boto3.resource("dynamodb")

# Environment variables
TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
DDB_TABLE = os.environ.get("DDB_TABLE")

# DynamoDB table reference
table = dynamodb.Table(DDB_TABLE)

def lambda_handler(event, context):
    invocation_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat()

    # Prepare log message
    event_str = json.dumps(event, indent=2)
    message = f"New pfSense log entry:\n{event_str}"

    # 1️⃣ Send SNS notification
    try:
        sns.publish(
            TopicArn=TOPIC_ARN,
            Message=message,
            Subject="Alert: New pfSense log"
        )
        logger.info(f"SNS notification sent successfully. InvocationID: {invocation_id}")
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {e}")

    # 2️⃣ Log invocation to DynamoDB
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

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Notification sent and logged",
            "InvocationID": invocation_id,
            "Timestamp": timestamp
        })
    }
