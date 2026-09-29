import json
import os

import boto3

table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def handler(event, context):
    # Atomic +1 (safe even with many visitors at once)
    result = table.update_item(
        Key={"id": "portfolio"},
        UpdateExpression="ADD visits :one",
        ExpressionAttributeValues={":one": 1},
        ReturnValues="UPDATED_NEW",
    )
    count = int(result["Attributes"]["visits"])

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"count": count}),
    }
