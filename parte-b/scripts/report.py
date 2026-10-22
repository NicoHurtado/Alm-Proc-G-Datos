"""Cuadra los eventos publicados con los guardados y descartados, y mide el retraso.

Uso (en AWS CloudShell, en la carpeta donde quedó published_events.csv):
    python3 report.py

Lee las dos tablas de DynamoDB completas (scan) y compara con el archivo que
dejó publish_events.py. El retraso es stored_at - sent_at: desde que el
script publicó el evento hasta que la Lambda lo escribió en DynamoDB.
"""

import argparse
import csv
from collections import Counter

import boto3


def scan(table, attributes):
    items = []
    kwargs = {"ProjectionExpression": ", ".join(f"#{a}" for a in attributes),
              "ExpressionAttributeNames": {f"#{a}": a for a in attributes}}
    while True:
        page = table.scan(**kwargs)
        items.extend(page["Items"])
        if "LastEvaluatedKey" not in page:
            return items
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]


def percentile(values, fraction):
    index = min(len(values) - 1, int(round(fraction * (len(values) - 1))))
    return values[index]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--published", default="published_events.csv")
    parser.add_argument("--offers-table", default="secop_offers")
    parser.add_argument("--rejected-table", default="secop_offers_rejected")
    parser.add_argument("--region", default="us-east-1")
    args = parser.parse_args()

    with open(args.published, encoding="utf-8") as file:
        published = list(csv.DictReader(file))
    published_kinds = Counter(row["kind"] for row in published)

    dynamodb = boto3.resource("dynamodb", region_name=args.region)
    saved = scan(dynamodb.Table(args.offers_table),
                 ["event_id", "latency_ms"])
    rejected = scan(dynamodb.Table(args.rejected_table), ["reason"])
    reasons = Counter(item["reason"] for item in rejected)

    print("== Conteos")
    print(f"publicados               {len(published):8,}")
    print(f"guardados en DynamoDB    {len(saved):8,}")
    print(f"descartados              {len(rejected):8,}")
    total = len(saved) + len(rejected)
    status = "CUADRA" if total == len(published) else "NO CUADRA"
    print(f"guardados + descartados  {total:8,}  -> {status}")

    print("\n== Publicados por tipo vs. resultado en DynamoDB")
    print(f"{'tipo':24}{'publicados':>12}{'en DynamoDB':>14}")
    print(f"{'valid':24}{published_kinds['valid']:12,}{len(saved):14,}")
    for kind in sorted(k for k in published_kinds if k != "valid"):
        print(f"{kind:24}{published_kinds[kind]:12,}{reasons[kind]:14,}")
    for reason in sorted(set(reasons) - set(published_kinds)):
        print(f"{reason:24}{0:12,}{reasons[reason]:14,}")

    latencies = sorted(int(item["latency_ms"]) for item in saved)
    if latencies:
        print("\n== Retraso de envío a DynamoDB (ms)")
        print(f"promedio  {sum(latencies) / len(latencies):10,.0f}")
        print(f"mediana   {percentile(latencies, 0.50):10,}")
        print(f"p95       {percentile(latencies, 0.95):10,}")
        print(f"máximo    {latencies[-1]:10,}")
        print(f"mínimo    {latencies[0]:10,}")


if __name__ == "__main__":
    main()
