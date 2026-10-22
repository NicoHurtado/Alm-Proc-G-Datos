"""Ejecuta en Athena, una por una, las sentencias de un archivo de parte-a/sql.

Uso:
    python3 parte-a/scripts/run_athena.py parte-a/sql/01_bronze.sql \
        --bucket trabajo1-apgd [--only 2 3] [--repeat 3]

Reemplaza YOUR_BUCKET por el bucket, espera cada consulta y muestra el
resultado, los datos escaneados y el tiempo de ejecución que reporta Athena.
Las consultas quedan en el historial (Recent queries) del editor de Athena.
"""

import argparse
import re
import time

import boto3


def split_statements(sql):
    """Separa el archivo en sentencias; cada una termina en ';' al final de línea."""
    statements = []
    for chunk in re.split(r";\s*\n", sql + "\n"):
        code = "\n".join(line for line in chunk.splitlines()
                         if not line.strip().startswith("--")).strip()
        if code:
            statements.append(code.rstrip(";"))
    return statements


def run(athena, sql, workgroup):
    query_id = athena.start_query_execution(
        QueryString=sql, WorkGroup=workgroup)["QueryExecutionId"]
    while True:
        execution = athena.get_query_execution(
            QueryExecutionId=query_id)["QueryExecution"]
        state = execution["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            return query_id, execution
        time.sleep(1)


def print_rows(athena, query_id, limit):
    page = athena.get_query_results(QueryExecutionId=query_id,
                                    MaxResults=limit + 1)
    rows = [[cell.get("VarCharValue", "") for cell in row["Data"]]
            for row in page["ResultSet"]["Rows"]]
    if not rows:
        return
    widths = [
        min(60, max(len(row[i]) if i < len(row) else 0 for row in rows))
        for i in range(len(rows[0]))
    ]
    for index, row in enumerate(rows):
        print("  " + " | ".join(value[:60].ljust(widths[i])
                                for i, value in enumerate(row)))
        if index == 0:
            print("  " + "-+-".join("-" * width for width in widths))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("sql_file")
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--workgroup", default="primary")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--only", type=int, nargs="*",
                        help="números de sentencia a ejecutar (desde 1)")
    parser.add_argument("--repeat", type=int, default=1,
                        help="veces que se ejecuta cada sentencia")
    parser.add_argument("--rows", type=int, default=20)
    args = parser.parse_args()

    with open(args.sql_file, encoding="utf-8") as file:
        sql = file.read().replace("YOUR_BUCKET", args.bucket)
    athena = boto3.client("athena", region_name=args.region)

    for number, statement in enumerate(split_statements(sql), start=1):
        if args.only and number not in args.only:
            continue
        print(f"\n=== Sentencia {number}: {statement.splitlines()[0][:70]}")
        for attempt in range(args.repeat):
            query_id, execution = run(athena, statement, args.workgroup)
            status = execution["Status"]
            stats = execution.get("Statistics", {})
            scanned = stats.get("DataScannedInBytes", 0)
            millis = stats.get("EngineExecutionTimeInMillis", 0)
            print(f"  [{status['State']}] escaneado {scanned / 1024**2:,.2f} MB"
                  f" ({scanned:,} bytes), ejecución {millis / 1000:.2f} s,"
                  f" total {stats.get('TotalExecutionTimeInMillis', 0) / 1000:.2f} s")
            if status["State"] != "SUCCEEDED":
                print("  " + status.get("StateChangeReason", ""))
                raise SystemExit(1)
        if execution.get("StatementType") == "DML":
            print_rows(athena, query_id, args.rows)


if __name__ == "__main__":
    main()
