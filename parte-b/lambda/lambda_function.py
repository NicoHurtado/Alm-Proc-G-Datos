"""Consume la cola de SQS y guarda en DynamoDB las ofertas a procesos de SECOP.

Cada mensaje de la cola es un evento que la regla de IoT Core copió del tema
secop/offers. Los eventos válidos van a la tabla OFFERS_TABLE y los que no
siguen el esquema van a REJECTED_TABLE con el motivo del descarte.
"""

import json
import os
import re
import time
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
offers = dynamodb.Table(os.environ.get("OFFERS_TABLE", "secop_offers"))
rejected = dynamodb.Table(
    os.environ.get("REJECTED_TABLE", "secop_offers_rejected"))

REQUIRED_FIELDS = [
    "event_id", "process_id", "supplier_nit", "supplier_name", "offer_value",
    "category", "department", "sent_at"
]
NIT_PATTERN = re.compile(r"^\d{6,10}$")
PROCESS_PATTERN = re.compile(r"^CO1\.REQ\.\d+$")


def now_ms():
    return int(time.time() * 1000)


def validate(event):
    """Devuelve el motivo del descarte, o None si el evento es válido."""
    if not isinstance(event, dict):
        return "not_an_object"
    for field in REQUIRED_FIELDS:
        if event.get(field) in (None, ""):
            return f"missing_{field}"
    if not PROCESS_PATTERN.match(str(event["process_id"])):
        return "invalid_process_id"
    if not NIT_PATTERN.match(str(event["supplier_nit"])):
        return "invalid_supplier_nit"
    try:
        value = Decimal(str(event["offer_value"]))
    except ArithmeticError:
        return "invalid_offer_value"
    if value <= 0:
        return "invalid_offer_value"
    if not isinstance(event["sent_at"], int):
        return "invalid_sent_at"
    return None


def reject(message_id, reason, body, stored_at):
    rejected.put_item(
        Item={
            "message_id": message_id,
            "reason": reason,
            "body": body[:2000],
            "stored_at": stored_at,
        })


def save(message_id, event, stored_at):
    item = {
        "process_id": event["process_id"],
        "event_id": event["event_id"],
        "supplier_nit": str(event["supplier_nit"]),
        "supplier_name": event["supplier_name"],
        "offer_value": Decimal(str(event["offer_value"])),
        "category": event["category"],
        "department": event["department"],
        "sent_at": event["sent_at"],
        "stored_at": stored_at,
        "latency_ms": stored_at - event["sent_at"],
        "message_id": message_id,
    }
    try:
        offers.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(event_id)")
        return "saved"
    except ClientError as error:
        if error.response["Error"]["Code"] != "ConditionalCheckFailedException":
            raise
    existing = offers.get_item(Key={
        "process_id": event["process_id"],
        "event_id": event["event_id"]
    }).get("Item", {})
    if existing.get("message_id") == message_id:
        return "redelivered"
    return "duplicate_event"


def lambda_handler(event, context):
    counts = {}
    for record in event["Records"]:
        message_id = record["messageId"]
        body = record["body"]
        stored_at = now_ms()
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            payload = None
            result = "invalid_json"
        else:
            result = validate(payload)
        if result is None:
            result = save(message_id, payload, stored_at)
        if result not in ("saved", "redelivered"):
            reject(message_id, result, body, stored_at)
        counts[result] = counts.get(result, 0) + 1
    print(json.dumps(counts))
    return counts
