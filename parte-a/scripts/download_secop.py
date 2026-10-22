"""Descarga de datos.gov.co los procesos de SECOP II con competencia, en CSV.

Uso:
    python3 parte-a/scripts/download_secop.py data/secop_procesos.csv

Lee la API Socrata por páginas, ordenadas por :id para que no se repitan
ni se pierdan filas entre páginas, varias a la vez, y las une en un solo CSV
con un encabezado. Si se interrumpe, al correrlo de nuevo solo baja las
páginas que faltan.
"""

import csv
import os
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

DATASET = "p6dx-8zbt"
BASE_URL = f"https://www.datos.gov.co/resource/{DATASET}.csv"
PAGE_SIZE = 50_000
WORKERS = 6

csv.field_size_limit(sys.maxsize)

COMPETITIVE_MODALITIES = [
    "Mínima cuantía",
    "Selección Abreviada de Menor Cuantía",
    "Selección abreviada subasta inversa",
    "Contratación régimen especial (con ofertas)",
    "Contratación Directa (con ofertas)",
    "Licitación pública",
    "Concurso de méritos abierto",
    "Licitación pública Obra Publica",
    "Licitación Pública Acuerdo Marco de Precios",
    "Seleccion Abreviada Menor Cuantia Sin Manifestacion Interes",
    "Concurso de méritos con precalificación",
]


def where_clause():
    values = ", ".join("'" + m.replace("'", "''") + "'"
                       for m in COMPETITIVE_MODALITIES)
    return f"modalidad_de_contratacion in ({values})"


def fetch(params, retries=5):
    url = BASE_URL + "?" + urllib.parse.urlencode(params)
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=600) as response:
                return response.read()
        except OSError as error:
            wait = 10 * (attempt + 1)
            print(f"  error: {error}; reintento en {wait} s", flush=True)
            time.sleep(wait)
    raise RuntimeError(f"no se pudo descargar {url}")


def count_rows():
    body = fetch({"$select": "count(*)", "$where": where_clause()})
    return int(body.decode("utf-8").splitlines()[1].strip('"'))


def count_records(path):
    with open(path, newline="", encoding="utf-8") as file:
        return sum(1 for _ in csv.reader(file)) - 1


def download_page(offset, expected, folder, retries=6):
    """Descarga una página a su propio archivo y comprueba que esté completa.

    La API a veces corta la respuesta antes de tiempo sin dar error, así que
    una página se acepta solo si trae exactamente las filas esperadas.
    """
    path = os.path.join(folder, f"page_{offset:09d}.csv")
    for attempt in range(retries):
        if os.path.exists(path) and count_records(path) == expected:
            print(f"  página {offset:,} lista", flush=True)
            return path
        if attempt:
            print(f"  página {offset:,} incompleta; reintento", flush=True)
        body = fetch({
            "$where": where_clause(),
            "$order": ":id",
            "$limit": PAGE_SIZE,
            "$offset": offset,
        })
        with open(path + ".tmp", "wb") as file:
            file.write(body)
        os.replace(path + ".tmp", path)
    raise RuntimeError(f"la página {offset:,} no llegó completa")


def main():
    output = sys.argv[1] if len(sys.argv) > 1 else "data/secop_procesos.csv"
    folder = output + ".pages"
    os.makedirs(folder, exist_ok=True)
    total = count_rows()
    print(f"filas a descargar: {total:,}", flush=True)
    offsets = range(0, total, PAGE_SIZE)
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        paths = list(
            pool.map(
                lambda o: download_page(o, min(PAGE_SIZE, total - o), folder),
                offsets))
    with open(output, "wb") as file:
        for index, path in enumerate(paths):
            with open(path, "rb") as page:
                header, _, rows = page.read().partition(b"\n")
            if index == 0:
                file.write(header + b"\n")
            file.write(rows)
            if rows and not rows.endswith(b"\n"):
                file.write(b"\n")
    print(f"listo: {output} con {count_records(output):,} filas")


if __name__ == "__main__":
    main()
