# Trabajo 1: capas Medallion y streaming con datos de SECOP II

**Curso:** SI7006/SI6003 Almacenamiento y Procesamiento de Grandes Datos, EAFIT, 2026-2
**Integrantes:** Nicolás Hurtado Amézquita, _(compañero)_
**Video:** _(enlace de YouTube, no listado)_

- [Resumen](#resumen)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Parte A: capas Medallion](#parte-a-capas-medallion)
- [Parte B: streaming](#parte-b-streaming)
- [Preguntas finales](#preguntas-finales)
- [Borrar los recursos](#borrar-los-recursos)

---

## Resumen

Los datos vienen de nuestro proyecto integrador, **ContrataMatch**, un recomendador de contratos públicos. El sistema le muestra a cada empresa los procesos abiertos de SECOP II donde más probabilidad tiene de ganar.

- **Parte A:** los procesos de contratación de SECOP II con competencia (≈1,29 millones de filas reales) pasan por bronce, plata y oro en Amazon Athena con tablas Apache Iceberg.
- **Parte B:** eventos de "una empresa presentó una oferta a un proceso" viajan por IoT Core → SQS → Lambda → DynamoDB.

Todos los recursos se crearon **a mano en la consola de AWS** (región us-east-1), sin infraestructura como código. Los pasos están en [docs/guia-consola.md](docs/guia-consola.md).

## Estructura del repositorio

| Ruta                                                                     | Contenido                                                     |
| ------------------------------------------------------------------------ | ------------------------------------------------------------- |
| [parte-a/scripts/download_secop.py](parte-a/scripts/download_secop.py)   | Descarga los procesos de datos.gov.co (API Socrata)           |
| [parte-a/scripts/csv_to_jsonl.py](parte-a/scripts/csv_to_jsonl.py)       | Pasa el CSV a JSON Lines comprimido sin cambiar valores       |
| [parte-a/sql/](parte-a/sql/)                                             | SQL de bronce, hallazgos, plata, oro, comparación y borrado   |
| [parte-b/lambda/lambda_function.py](parte-b/lambda/lambda_function.py)   | Lambda que consume SQS y escribe en DynamoDB                  |
| [parte-b/scripts/publish_events.py](parte-b/scripts/publish_events.py)   | Publica los eventos en IoT Core                               |
| [parte-b/scripts/report.py](parte-b/scripts/report.py)                   | Cuadra publicados = guardados + descartados y mide el retraso |
| [docs/guia-consola.md](docs/guia-consola.md)                             | Paso a paso en la consola de AWS                              |
| [docs/guion-video.md](docs/guion-video.md)                               | Guion del video (máximo 10 minutos)                           |

---

## Parte A: capas Medallion

### 1. Descripción del conjunto de datos

| Aspecto         | Valor                                                                                                                                                                                                                                                                                  |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Qué es          | Procesos de contratación pública publicados en SECOP II. Cada fila es un proceso (y, si tiene varias adjudicaciones, una fila por adjudicación) con la entidad, la descripción, la modalidad, el precio base, las fechas, el número de ofertas recibidas, el ganador y el valor adjudicado |
| De dónde viene  | Colombia Compra Eficiente, publicado en [datos.gov.co](https://www.datos.gov.co/d/p6dx-8zbt) (conjunto `p6dx-8zbt`), licencia CC BY-SA 4.0                                                                                                                                              |
| Recorte         | Solo las 11 modalidades con competencia (mínima cuantía, selección abreviada, subasta inversa, licitación pública, concurso de méritos y las modalidades "con ofertas"), el mismo recorte que usa ContrataMatch. El conjunto completo tiene 9,36 millones de filas                       |
| Filas           | **1.290.057** filas (903.683 procesos distintos; un proceso puede tener una fila por adjudicación), publicados entre el 28/04/2015 y el 20/10/2026. Descargados el 22/10/2026                                                                                                                                                                                                                                                           |
| Columnas        | 59                                                                                                                                                                                                                                                                                     |
| Tipos de datos  | Texto (entidad, descripción, modalidad, estado, proveedor), identificadores (id del proceso, NIT, código UNSPSC), fechas ISO 8601, montos en pesos y conteos enteros. En la API todo llega como texto                                                                                   |
| Peso            | 1,70 GB en CSV; 3,61 GB en JSON Lines; **436 MB** en JSON Lines con gzip, el archivo que se sube a S3                                                                                                                                                                                                        |
| Aumento de datos | No hace falta: son más de 1.000.000 de filas reales                                                                                                                                                                                                                                   |

**Por qué JSON Lines y no CSV.** Algunas descripciones traen saltos de línea dentro del campo (≈3,6 % de las filas en una muestra). La tabla CSV de Athena parte esos registros en varias filas rotas. En JSON Lines el salto queda escapado y cada proceso ocupa una línea. Los valores no cambian: todas las columnas siguen siendo texto, tal como llegan de la API.

### 2. Bronce

El archivo `s3://<bucket>/bronze/secop_processes/secop_procesos.jsonl.gz` se lee con la tabla externa `secop.bronze_processes`, que tiene las 59 columnas como `string` ([01_bronze.sql](parte-a/sql/01_bronze.sql)).

### 3. Hallazgos

Salen de [02_findings.sql](parte-a/sql/02_findings.sql). Cada defecto se cuenta por separado, así que una fila puede aparecer en varios.

| #   | Hallazgo                | Descripción                                            | Filas  | %    |
| --- | ----------------------- | ------------------------------------------------------ | ------ | ---- |
| 1   | duplicate_row           | Copia idéntica de otra fila (las 59 columnas iguales)  | 84.013 | 6,51 |
| 2   | empty_publication_date  | Fecha de publicación vacía                             | 21.745 | 1,69 |
| 3   | non_positive_base_price | Precio base en cero (39.101) o negativo (324)          | 39.425 | 3,06 |
| 4   | invalid_category        | Categoría UNSPSC `UNSPECIFIED`                         | 70.570 | 5,47 |
| 5   | invalid_entity_nit      | NIT de la entidad con puntos o guion (`900.479.658`)   | 264    | 0,02 |
| 6   | undefined_department    | Departamento de la entidad `No Definido`               | 30.715 | 2,38 |
| 7   | awarded_without_value   | `adjudicado = Si` pero valor adjudicado en cero        | 4.162  | 0,32 |

Cifras de Athena, ejecutadas el 22/10/2026. Coinciden con una réplica local de las mismas consultas en DuckDB.

También revisamos y **no** encontramos filas sin id del proceso o sin estado, precios base no numéricos, ni fechas ilegibles o fuera de rango. Por eso no hay reglas para esos casos.

Que un mismo `id_del_proceso` aparezca en varias filas **no es un defecto**: SECOP publica una fila por cada adjudicación (lote o proveedor). Solo las filas idénticas en las 59 columnas son duplicados.

### 4. Plata

Las reglas están en la vista `secop.bronze_processes_checked` ([03_silver.sql](parte-a/sql/03_silver.sql)). Cada fila rechazada lleva la primera regla que incumple.

| Regla | Motivo                     | Hallazgo | Rechaza | Por qué importa para el proyecto                                                                             |
| ----- | -------------------------- | -------- | ------- | ------------------------------------------------------------------------------------------------------------ |
| R1    | `invalid_publication_date` | 2        | 21.745  | La validación temporal del modelo y las features "nada del futuro" dependen de la fecha                       |
| R2    | `invalid_base_price`       | 3        | 38.580  | El precio base es una feature del ranking y una medida del dashboard; un valor en 0 o negativo la distorsiona |
| R3    | `invalid_category`         | 4        | 68.932  | El retrieval y el oro agrupan por segmento UNSPSC; `UNSPECIFIED` no se puede asignar                          |
| R4    | `invalid_entity_nit`       | 5        | 241     | El NIT es la llave de la entidad en el esquema estrella                                                      |
| R5    | `undefined_department`     | 6        | 27.852  | El análisis por territorio, y la pregunta de oro, necesitan el departamento                                  |
| R6    | `duplicate_row`            | 1        | 68.114  | Una copia exacta cuenta dos veces el mismo proceso y la misma adjudicación                                   |

Cada fila rechazada lleva un solo motivo, el de la primera regla que incumple. Por eso "Rechaza" es menor que "Filas" en la tabla de hallazgos: por ejemplo, de las 84.013 copias, 15.899 ya habían caído por otra regla.

El hallazgo 7 no se volvió regla. Son pocas filas y el proceso sí tiene válido el resto de los datos; queda documentado.

Resultado:

| Tabla                                 | Filas         |
| ------------------------------------- | ------------- |
| `bronze_processes`                    | 1.290.057     |
| `silver_processes` (Iceberg)          | 1.064.593     |
| `silver_processes_rejected` (Iceberg) | 225.464       |
| válidas + rechazadas                  | **1.290.057** |

### 5. Oro

**Pregunta de negocio:** en los procesos con competencia ya adjudicados, ¿en qué departamentos y segmentos de producto (UNSPSC) se presenta una sola oferta con más frecuencia?

Para ContrataMatch, esos son los procesos donde a una MiPyme más le conviene presentarse, porque compite contra menos empresas. También son donde el Estado pierde la posibilidad de comparar precios.

La tabla Iceberg `secop.gold_competition_by_department_segment` ([04_gold.sql](parte-a/sql/04_gold.sql)) agrega por año, departamento y segmento UNSPSC: procesos adjudicados, procesos con una sola oferta, porcentaje y promedio de ofertas. Son 14.906 filas, frente a 1.064.593 en plata.

Respuesta para 2025, entre las combinaciones con más de 200 procesos adjudicados:

| Departamento       | Segmento UNSPSC                                     | Adjudicados | Una sola oferta | %    |
| ------------------ | --------------------------------------------------- | ----------- | --------------- | ---- |
| Boyacá             | 85 Servicios de salud                               | 494         | 470             | 95,1 |
| Meta               | 82 Servicios editoriales, de diseño y publicidad    | 225         | 209             | 92,9 |
| Boyacá             | 93 Servicios políticos y de asuntos cívicos         | 1.043       | 957             | 91,8 |
| Boyacá             | 15 Combustibles y lubricantes                       | 255         | 221             | 86,7 |
| Antioquia          | 15 Combustibles y lubricantes                       | 204         | 176             | 86,3 |

Es decir: en salud, publicidad y combustibles de Boyacá, Meta y Antioquia, más de 8 de cada 10 procesos se adjudican con una sola oferta. Una empresa de esos rubros que se presente compite casi sola.

### 6. Comparación

Es la misma pregunta en las tres capas ([05_compare.sql](parte-a/sql/05_compare.sql)): en 2025, ¿qué departamentos tienen el mayor porcentaje de procesos adjudicados con una sola oferta?

Cada consulta se ejecutó 3 veces en Athena (engine v3); el tiempo es la mediana del tiempo de ejecución del motor.

| Capa   | Formato                   | Datos escaneados              | Tiempo de ejecución | Frente a bronce               |
| ------ | ------------------------- | ----------------------------- | ------------------- | ----------------------------- |
| Bronce | JSON Lines + gzip         | 416,07 MB (436.279.332 bytes) | 47,51 s             | —                             |
| Plata  | Iceberg (Parquet)         | 6,21 MB (6.508.593 bytes)     | 1,29 s              | 67 veces menos datos, 37 veces más rápida  |
| Oro    | Iceberg (Parquet), agregada | 0,05 MB (48.813 bytes)      | 0,97 s              | 8.938 veces menos datos, 49 veces más rápida |

**Interpretación:**

- **Bronce** es JSON comprimido con gzip: Athena tiene que leer el archivo completo, todas las columnas incluidas, aunque la consulta use cuatro. Además, convierte texto a fecha y a número en cada fila.
- **Plata** es Parquet columnar: solo se leen las columnas que usa la consulta (departamento, fecha, adjudicado, respuestas, id), ya con su tipo.
- **Oro** ya está agregada, con unos pocos miles de filas en lugar de más de un millón, así que la lectura es casi nula.

La diferencia de bytes escaneados también es una diferencia de costo, porque Athena cobra por datos escaneados.

Las respuestas tampoco son iguales. Bronce dice que Arauca tiene 80,3 % de procesos con una sola oferta y pone a La Guajira de segunda; plata y oro dicen 78,1 % y ponen a Caquetá de segunda. La diferencia son las filas que plata rechaza: copias, fechas vacías y precios en cero inflan los conteos de bronce. Plata y oro coinciden exactamente porque oro se calcula desde plata.

---

## Parte B: streaming

```text
publish_events.py ──► IoT Core (tema secop/offers) ──regla──► SQS ──► Lambda ──► DynamoDB
   (terminal)            SELECT * FROM 'secop/offers'      secop-offers-queue      secop_offers
                                                                                  secop_offers_rejected
```

### Esquema de los eventos

Cada evento es una oferta de una empresa a un proceso de SECOP:

```json
{
  "event_id": "4f0c...-uuid",
  "process_id": "CO1.REQ.5154156",
  "supplier_nit": "900123456",
  "supplier_name": "SUMINISTROS OFICINA SAS",
  "offer_value": 41250000.5,
  "category": "V1.43211500",
  "department": "Antioquia",
  "sent_at": 1761148800123
}
```

`sent_at` es la hora del envío en milisegundos, y la pone el script justo antes de publicar. Los datos son sintéticos, pero tienen la forma del conjunto "Proponentes por proceso" (`hgi6-6wh3`) del proyecto.

### Llave de DynamoDB

`secop_offers` usa la **partition key `process_id`** y la **sort key `event_id`**:

- La consulta natural del proyecto es "todas las ofertas de un proceso", para saber cuánta competencia tiene. Con `process_id` como partition key es un solo `Query`, sin `Scan`.
- Hay muchos procesos distintos, así que las escrituras se reparten entre particiones y no hay una partición caliente.
- `event_id` hace única cada oferta dentro del proceso. La Lambda escribe con `attribute_not_exists(event_id)`, así que un evento repetido no se guarda dos veces.

`secop_offers_rejected` usa como llave el `messageId` de SQS. Así, un mensaje que SQS entrega dos veces queda una sola vez.

### Función adaptada al esquema

[lambda_function.py](parte-b/lambda/lambda_function.py) valida cada mensaje y lo guarda o lo descarta con un motivo:

| Motivo                   | Cuándo                                                                       |
| ------------------------ | ---------------------------------------------------------------------------- |
| `invalid_json`           | El cuerpo no es JSON                                                         |
| `missing_<campo>`        | Falta un campo obligatorio                                                   |
| `invalid_process_id`     | `process_id` no tiene la forma `CO1.REQ.<número>`                            |
| `invalid_supplier_nit`   | El NIT no tiene entre 6 y 10 dígitos                                         |
| `invalid_offer_value`    | El valor no es numérico o es ≤ 0                                             |
| `invalid_sent_at`        | `sent_at` no es un entero                                                    |
| `duplicate_event`        | Ya existe ese `event_id` en ese proceso (se publicó dos veces)               |

Los válidos se guardan con los tipos de DynamoDB (`offer_value` como número) y con `stored_at` y `latency_ms = stored_at - sent_at`. Si SQS reentrega un mismo mensaje, la Lambda lo reconoce por el `messageId` y no lo cuenta dos veces.

### Publicación, cuadre y retraso

`python3 parte-b/scripts/publish_events.py --count 12000` y luego `python3 parte-b/scripts/report.py`. Alrededor del 8 % de los eventos se publica dañado a propósito.

Ejecutado el 22/10/2026: 12.000 eventos publicados en 95,8 s (125 eventos/s). La salida completa de `report.py` está en [docs/resultados/parte-b-report.txt](docs/resultados/parte-b-report.txt).

| Concepto                | Eventos    |
| ----------------------- | ---------- |
| Publicados              | 12.000     |
| Guardados en DynamoDB   | 11.051     |
| Descartados             | 949        |
| Guardados + descartados | **12.000** |

| Motivo del descarte    | Publicados así | Descartados en DynamoDB |
| ---------------------- | -------------- | ----------------------- |
| `invalid_offer_value`  | 260            | 260                     |
| `missing_supplier_nit` | 217            | 217                     |
| `duplicate_event`      | 217            | 217                     |
| `invalid_process_id`   | 139            | 139                     |
| `invalid_json`         | 116            | 116                     |

| Retraso envío → DynamoDB | ms    |
| ------------------------ | ----- |
| Promedio                 | 161   |
| Mediana                  | 142   |
| p95                      | 231   |
| Máximo                   | 2.973 |
| Mínimo                   | 93    |

`sent_at` lo toma el reloj del computador que publica y `stored_at` el de la Lambda, así que el retraso incluye la diferencia entre los dos relojes (sincronizados por NTP, del orden de milisegundos). Los 8 eventos más lentos (1,8 a 3,0 s) se publicaron en el primer segundo, cuando las primeras ejecuciones de la Lambda estaban arrancando en frío. El primer 10 % de los eventos promedia 290 ms y el resto 147 ms.

---

## Preguntas finales

### Parte A: si los datos fueran mil veces mayores, ¿qué cambiaríamos?

Serían ≈1.300 millones de filas y del orden de terabytes:

1. **Ingesta incremental, no un archivo.** Descargaríamos por día con marca de agua y guardaríamos bronce particionado por fecha de carga, que es lo que ContrataMatch planea con Lambda y EventBridge.
2. **Convertir a columnar desde el primer paso.** Bronce seguiría siendo inmutable, pero tendría una copia en Parquet particionada. Un escaneo completo del JSON costaría por cada consulta lo que hoy cuesta todo el trabajo.
3. **Particionar las tablas Iceberg** de plata por año y mes de publicación (y, si hace falta, por departamento), para que cada consulta lea solo las particiones que necesita. Además, compactarlas con `OPTIMIZE` y limpiar snapshots con `VACUUM`.
4. **Spark (EMR o Glue) en lugar de CTAS de Athena** para transformar. A esa escala el `row_number` sobre 59 columnas para los duplicados se vuelve muy costoso: lo cambiaríamos por un hash de la fila y un `MERGE` incremental, que procesa solo lo nuevo.
5. **Oro incremental:** recalcular solo las particiones afectadas, no toda la tabla.

### Parte B: ¿a partir de qué volumen dejaríamos esta forma de streaming y qué usaríamos?

IoT Core → SQS → Lambda → DynamoDB está bien para eventos sueltos de muchos dispositivos y para volúmenes de cientos a pocos miles de eventos por segundo. Cada evento se cobra varias veces (IoT, regla, SQS, invocación de Lambda, escritura en DynamoDB) y no hay orden ni relectura.

Con un flujo **sostenido de varios miles de eventos por segundo**, o cuando haga falta **orden por proceso, releer la historia o tener varios consumidores**, lo cambiaríamos por **Amazon Kinesis Data Streams** (o MSK/Kafka si el volumen es aún mayor). Kinesis agrupa los eventos en shards ordenados por llave, los guarda varios días para reprocesar, y puede llevarlos a S3 con Firehose para la analítica en el lakehouse, como en el laboratorio 5. Las ofertas a procesos públicos no llegan desde dispositivos IoT, así que IoT Core no aporta nada a esa escala.

---

## Borrar los recursos

Se sigue la sección "Al terminar: borrar todo" de [docs/guia-consola.md](docs/guia-consola.md#al-terminar-borrar-todo).
