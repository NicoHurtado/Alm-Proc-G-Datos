"""Convierte el CSV de SECOP II a JSON Lines comprimido, sin cambiar los valores.

Uso:
    python3 parte-a/scripts/csv_to_jsonl.py data/secop_procesos.csv \
        data/secop_procesos.jsonl.gz

Algunas descripciones traen saltos de línea dentro del campo. En CSV eso
parte el registro en varias líneas y la tabla de Athena lo leería mal; en
JSON Lines el salto queda escapado como \\n y cada proceso ocupa una línea.
Todos los valores se escriben como texto, igual que llegaron.
"""

import csv
import gzip
import json
import sys

csv.field_size_limit(sys.maxsize)


def main():
    source, target = sys.argv[1], sys.argv[2]
    rows = 0
    opener = gzip.open if target.endswith(".gz") else open
    with open(source, newline="", encoding="utf-8") as infile, \
            opener(target, "wt", encoding="utf-8") as outfile:
        for row in csv.DictReader(infile):
            outfile.write(json.dumps(row, ensure_ascii=False) + "\n")
            rows += 1
            if rows % 200_000 == 0:
                print(f"  {rows:,} filas", flush=True)
    print(f"filas escritas: {rows:,} -> {target}")


if __name__ == "__main__":
    main()
