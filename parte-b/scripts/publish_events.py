"""Publica en AWS IoT Core eventos sintéticos de ofertas a procesos de SECOP II.

Uso (en AWS CloudShell, que ya tiene boto3 y las credenciales):
    python3 publish_events.py --count 12000

Cada evento es una empresa que presenta una oferta a un proceso. Una parte de
los eventos se publica dañada a propósito (sin NIT, valor negativo, proceso
inválido, texto que no es JSON o un evento repetido) para que la Lambda los
descarte. Al final escribe published_events.csv con cada mensaje publicado y
su tipo, e imprime cuántos se publicaron de cada tipo.
"""

import argparse
import csv
import json
import random
import threading
import time
import uuid
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

import boto3
from botocore.config import Config

TOPIC = "secop/offers"

DEPARTMENTS = [
    "Antioquia", "Atlántico", "Bolívar", "Boyacá", "Caldas", "Cauca",
    "Cesar", "Córdoba", "Cundinamarca", "Distrito Capital de Bogotá", "Huila",
    "Magdalena", "Meta", "Nariño", "Norte de Santander", "Quindío",
    "Risaralda", "Santander", "Sucre", "Tolima", "Valle del Cauca"
]
CATEGORIES = [
    "V1.42131600", "V1.43211500", "V1.44121600", "V1.72141100",
    "V1.76111500", "V1.80111600", "V1.81112200", "V1.85101500",
    "V1.90101600", "V1.92121500"
]
SUFFIXES = ["SAS", "LTDA", "S.A.", "SAS BIC"]
WORDS = [
    "SUMINISTROS", "SOLUCIONES", "INGENIERIA", "SERVICIOS", "DOTACIONES",
    "TECNOLOGIA", "LOGISTICA", "CONSTRUCCIONES", "MEDICAL", "OFICINA"
]

# Probabilidad de cada tipo de evento; el resto son válidos.
DEFECTS = {
    "missing_supplier_nit": 0.02,
    "invalid_offer_value": 0.02,
    "invalid_process_id": 0.01,
    "invalid_json": 0.01,
    "duplicate_event": 0.02,
}


def make_suppliers(rng, size=400):
    suppliers = []
    for _ in range(size):
        name = " ".join(rng.sample(WORDS, 2)) + " " + rng.choice(SUFFIXES)
        suppliers.append((str(rng.randint(800000000, 901999999)), name))
    return suppliers


def make_event(rng, suppliers):
    nit, name = rng.choice(suppliers)
    return {
        "event_id": str(uuid.UUID(int=rng.getrandbits(128), version=4)),
        "process_id": f"CO1.REQ.{rng.randint(1000000, 9999999)}",
        "supplier_nit": nit,
        "supplier_name": name,
        "offer_value": round(rng.lognormvariate(17.5, 1.2), 2),
        "category": rng.choice(CATEGORIES),
        "department": rng.choice(DEPARTMENTS),
    }


def pick_kind(rng):
    draw = rng.random()
    for kind, probability in DEFECTS.items():
        if draw < probability:
            return kind
        draw -= probability
    return "valid"


def build_messages(count, seed):
    """Devuelve una lista de (tipo, evento) lista para publicar."""
    rng = random.Random(seed)
    suppliers = make_suppliers(rng)
    messages = []
    valid_events = []
    while len(messages) < count:
        kind = pick_kind(rng)
        if kind == "duplicate_event" and not valid_events:
            kind = "valid"
        if kind == "duplicate_event":
            event = dict(rng.choice(valid_events))
        else:
            event = make_event(rng, suppliers)
        if kind == "missing_supplier_nit":
            del event["supplier_nit"]
        elif kind == "invalid_offer_value":
            event["offer_value"] = -event["offer_value"]
        elif kind == "invalid_process_id":
            event["process_id"] = "PROCESO-" + event["process_id"][-7:]
        elif kind == "valid":
            valid_events.append(event)
        messages.append((kind, event))
    return messages


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=12000)
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--seed", type=int, default=262)
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--output", default="published_events.csv")
    args = parser.parse_args()

    iot = boto3.client("iot", region_name=args.region)
    endpoint = iot.describe_endpoint(
        endpointType="iot:Data-ATS")["endpointAddress"]
    client = boto3.client("iot-data",
                          region_name=args.region,
                          endpoint_url=f"https://{endpoint}",
                          config=Config(retries={
                              "max_attempts": 10,
                              "mode": "adaptive"
                          },
                                        max_pool_connections=args.workers))

    messages = build_messages(args.count, args.seed)
    rows = []
    lock = threading.Lock()

    def publish(message):
        kind, event = message
        sent_at = int(time.time() * 1000)
        if kind == "invalid_json":
            payload = (f"event_id={event['event_id']};"
                       f"process_id={event['process_id']};sent_at={sent_at}")
        else:
            payload = json.dumps(dict(event, sent_at=sent_at),
                                 ensure_ascii=False)
        client.publish(topic=TOPIC, qos=1, payload=payload.encode("utf-8"))
        with lock:
            rows.append((event["event_id"], kind, sent_at))
            if len(rows) % 1000 == 0:
                print(f"  publicados: {len(rows):,}", flush=True)

    started = time.time()
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        list(pool.map(publish, messages))
    elapsed = time.time() - started

    with open(args.output, "w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow(["event_id", "kind", "sent_at"])
        writer.writerows(rows)

    counts = Counter(kind for _, kind, _ in rows)
    print(f"publicados: {len(rows):,} en {elapsed:.1f} s "
          f"({len(rows) / elapsed:.0f} eventos/s)")
    for kind, total in counts.most_common():
        print(f"  {kind:22} {total:6,}")
    print(f"detalle: {args.output}")


if __name__ == "__main__":
    main()
