# Guion del video

El video dura **máximo 10 minutos**. Tiene dos partes:

- **Primera parte (Nicolás, ~5:15):** presentación y parte A (capas Medallion).
- **Segunda parte (compañero, ~4:25):** parte B (streaming), CloudFormation y cierre.

Cada paso dice **a dónde ir**, **qué mostrar**, **qué debe salir en pantalla** y **qué decir**. Lo que va entre comillas es para leerlo o decirlo con sus palabras.

## Antes de grabar

1. Inicie el Learner Lab (punto verde) y abra la consola de AWS en la región **N. Virginia (us-east-1)**.
2. Zoom del navegador al **125 %** para que las tablas se lean.
3. Cámara encendida en una esquina de la grabación (OBS, Zoom o Teams). **Mientras cada uno habla, se tiene que ver su cara.**
4. Deje abiertas estas pestañas, en este orden: el README en GitHub, S3, Athena, IoT Core, SQS, Lambda, DynamoDB, CloudFormation.
5. No muestre credenciales: ni `~/.aws/credentials`, ni la página _AWS Details_ del Learner Lab.
6. **No vuelva a correr `publish_events.py`.** Los resultados de la parte B ya están guardados.

---

# PRIMERA PARTE: Nicolás (parte A)

### Paso 1. Presentación (0:00 – 0:30)

**A dónde ir:** la cámara, o el README en GitHub.

**Qué decir:**

> "Hola, somos Nicolás Hurtado y [nombre del compañero], y este es el Trabajo 1 de Almacenamiento y Procesamiento de Grandes Datos. Usamos los datos de nuestro proyecto integrador, ContrataMatch, un recomendador de contratos públicos que le muestra a cada empresa los procesos del Estado donde más probabilidad tiene de ganar. Yo voy a presentar la parte A, las capas Medallion en Athena, y [compañero] la parte B, el flujo de streaming."

### Paso 2. El conjunto de datos (0:30 – 1:15)

**A dónde ir:** el README en GitHub, sección **"1. Descripción del conjunto de datos"**.

**Qué mostrar:** la tabla de la descripción.

**Qué decir:**

> "Los datos son los procesos de contratación de SECOP II, que publica Colombia Compra Eficiente en datos.gov.co. Cada fila es un proceso de compra del Estado: la entidad, la descripción, la modalidad, el precio base, las fechas, cuántas ofertas recibió y quién ganó. El conjunto completo tiene 9,3 millones de filas; nosotros tomamos solo las modalidades con competencia, que son las que le sirven al recomendador, y nos quedan 1.290.057 filas reales, así que no tuvimos que aumentar datos. Tiene 59 columnas: textos, identificadores, fechas, montos y conteos. Pesa 1,7 GB en CSV y lo subimos como JSON Lines comprimido, de 436 MB, porque algunas descripciones tienen saltos de línea que rompen el CSV en Athena."

### Paso 3. Bronce (1:15 – 1:50)

**A dónde ir:** S3 → bucket `apgd-trabajo1-<id de la cuenta>` → carpeta `bronze/secop_processes/`.

**Qué debe salir:** el archivo `secop_procesos.jsonl.gz`, de 436 MB.

**Luego ir a:** Athena → Query editor → pestaña **Recent queries** → la consulta `SELECT count(*) AS bronze_rows FROM secop.bronze_processes`. También puede desplegar la tabla `bronze_processes` en el panel izquierdo para que se vean las columnas tipo `string`.

**Qué debe salir:** `bronze_rows = 1290057`.

**Qué decir:**

> "Esta es la capa bronce: el archivo tal como llegó, en S3. Sobre él creamos en Athena una tabla externa, bronze_processes, con las 59 columnas como texto, sin ningún cambio. Athena cuenta 1.290.057 filas, las mismas que descargamos."

### Paso 4. Hallazgos (1:50 – 2:40)

**A dónde ir:** Athena → Recent queries → la consulta que empieza por `WITH flags AS` (la tabla de hallazgos). Muestre solo esta tabla: las otras consultas de hallazgos traen nombres de proveedores.

**Qué debe salir:**

| Hallazgo                | Filas  | %    |
| ----------------------- | ------ | ---- |
| duplicate_row           | 84.013 | 6,51 |
| empty_publication_date  | 21.745 | 1,69 |
| non_positive_base_price | 39.425 | 3,06 |
| invalid_category        | 70.570 | 5,47 |
| invalid_entity_nit      | 264    | 0,02 |
| undefined_department    | 30.715 | 2,38 |
| awarded_without_value   | 4.162  | 0,32 |

**Qué decir:**

> "Antes de limpiar, medimos con SQL los defectos de calidad. Encontramos siete: 84 mil filas que son copias idénticas de otra, 70 mil procesos con la categoría de producto 'UNSPECIFIED', 39 mil con precio base en cero o negativo, 30 mil con el departamento 'No Definido', 21 mil sin fecha de publicación, 264 con el NIT de la entidad mal escrito y 4 mil adjudicados con valor en cero. Algo que aprendimos: que un mismo proceso aparezca en varias filas no es un error, porque SECOP publica una fila por cada adjudicación; solo cuentan como duplicadas las filas idénticas en las 59 columnas."

### Paso 5. Plata (2:40 – 3:40)

**A dónde ir:** primero el archivo `parte-a/sql/03_silver.sql` en GitHub, para mostrar las reglas (el `CASE`). Luego Athena → Recent queries → la consulta del cuadre (`SELECT bronze_rows, valid_rows, rejected_rows ...`) y la de motivos (`SELECT reject_reason, count(*) ...`).

**Qué debe salir:**

- Cuadre: `1290057 | 1064593 | 225464 | 1290057 | CUADRA`.
- Motivos: invalid_category 68.932, duplicate_row 68.114, invalid_base_price 38.580, undefined_department 27.852, invalid_publication_date 21.745, invalid_entity_nit 241.

**Qué decir:**

> "Con esos hallazgos escribimos seis reglas de calidad en SQL. Rechazamos la fila si no tiene fecha de publicación, porque el modelo se valida en el tiempo; si el precio base es cero o negativo, porque es una variable del modelo; si la categoría es 'UNSPECIFIED', porque el recomendador agrupa por categoría; si el NIT de la entidad está mal escrito, porque es la llave de la entidad; si el departamento no está definido, porque lo analizamos por territorio; y si la fila es una copia idéntica. Con esto creamos dos tablas Iceberg: silver_processes, con 1.064.593 filas válidas y ya con sus tipos, y silver_processes_rejected, con 225.464 filas rechazadas y su motivo. Y los conteos cuadran: un millón 64 mil más 225 mil da exactamente el millón 290 mil de bronce."

### Paso 6. Oro (3:40 – 4:15)

**A dónde ir:** Athena → Recent queries → la consulta de la respuesta (`SELECT entity_department, unspsc_segment, awarded_processes ... WHERE year = 2025 AND awarded_processes > 200`).

**Qué debe salir:** Boyacá 85 → 95,1 %; Meta 82 → 92,9 %; Boyacá 93 → 91,8 %; Boyacá 15 → 86,7 %; Antioquia 15 → 86,3 %.

**Qué decir:**

> "La capa oro responde una pregunta de negocio: en los procesos ya adjudicados, ¿en qué departamentos y tipos de producto se presenta una sola oferta? Es una tabla Iceberg agregada por año, departamento y segmento de producto, de 14.906 filas. En 2025, por ejemplo, en servicios de salud en Boyacá el 95 % de los procesos se adjudicó con una sola oferta, y en publicidad en el Meta el 93 %. Para ContrataMatch, esas son las oportunidades donde a una pequeña empresa más le conviene presentarse, porque compite casi sola."

### Paso 7. Comparación de las tres capas (4:15 – 4:45)

**A dónde ir:** el README en GitHub, sección **"6. Comparación"** (la tabla). Si quiere, muestre en Athena una de las tres consultas con su **Data scanned**.

**Qué debe salir:**

| Capa   | Datos escaneados | Tiempo  |
| ------ | ---------------- | ------- |
| Bronce | 416,07 MB        | 47,00 s |
| Plata  | 6,21 MB          | 1,35 s  |
| Oro    | 0,05 MB          | 0,67 s  |

**Qué decir:**

> "Corrimos la misma pregunta en las tres capas. Bronce lee 416 megas y tarda 47 segundos, porque es JSON comprimido y Athena tiene que leer el archivo completo y convertir el texto en cada consulta. Plata lee 6 megas y tarda un segundo, porque es Parquet por columnas y solo lee las que necesita. Oro lee 50 kilobytes, porque ya está agregada. Y como Athena cobra por datos leídos, también es mucho más barato. Además, bronce da porcentajes un poco distintos, porque todavía cuenta las filas que plata rechaza."

### Paso 8. Pregunta final de la parte A (4:45 – 5:15)

**A dónde ir:** la cámara.

**Qué decir:**

> "Si los datos fueran mil veces mayores, unos 1.300 millones de filas, cambiaríamos cuatro cosas. Primero, no subiríamos un solo archivo: descargaríamos cada día solo lo nuevo y guardaríamos bronce partido por fecha. Segundo, convertiríamos a Parquet desde el comienzo y partiríamos las tablas Iceberg por año y mes, para que cada consulta lea solo lo que necesita. Tercero, transformaríamos con Spark en EMR o Glue en lugar de Athena, y buscaríamos los duplicados con un hash de la fila y un MERGE incremental, en vez de comparar las 59 columnas. Y cuarto, recalcularíamos oro solo con los días nuevos. Ahora [compañero] les presenta la parte B."

---

# SEGUNDA PARTE: compañero (parte B)

### Paso 9. El flujo de streaming (5:15 – 5:45)

**A dónde ir:** el README en GitHub, sección **"Parte B: streaming"** (el diagrama y el JSON del evento).

**Qué decir:**

> "Hola, soy [nombre]. En la parte B construimos un flujo de streaming distinto al del laboratorio 5: IoT Core, SQS, Lambda y DynamoDB. Cada evento representa una empresa que presenta una oferta a un proceso de SECOP: trae el id del evento, el proceso, el NIT y el nombre de la empresa, el valor ofertado, la categoría, el departamento y la hora de envío. Los datos son sintéticos, pero tienen la forma de los proponentes del proyecto."

### Paso 10. Regla de IoT Core (5:45 – 6:10)

**A dónde ir:** IoT Core → Message routing → Rules → `secop_offers_to_sqs`.

**Qué debe salir:** estado **Active**, el SQL `SELECT * FROM 'secop/offers'` y la acción **Simple Queue Service (SQS)**.

**Qué decir:**

> "Esta es la regla de IoT Core. Escucha el tema secop/offers y manda cada mensaje, tal cual, a una cola de SQS."

### Paso 11. Cola de SQS (6:10 – 6:25)

**A dónde ir:** SQS → `secop-offers-queue`.

**Qué debe salir:** tipo **Standard** y mensajes disponibles en **0**.

**Qué decir:**

> "Esta es la cola. Es estándar, porque la acción de IoT no admite colas FIFO, y ahora está en cero porque la Lambda ya procesó todos los mensajes."

### Paso 12. Función Lambda (6:25 – 7:05)

**A dónde ir:** Lambda → `secop-offers-consumer`. Muestre el diagrama de arriba, con **SQS** como trigger, y la pestaña **Code**, con la función `validate` y la lista `REQUIRED_FIELDS`.

**Qué decir:**

> "Esta es la función Lambda. Su trigger es la cola de SQS y recibe los mensajes de a diez. La adaptamos al esquema de los eventos: revisa que el cuerpo sea JSON, que estén todos los campos, que el proceso tenga la forma CO1.REQ seguida de un número, que el NIT tenga entre 6 y 10 dígitos y que el valor sea positivo. Si el evento es válido, lo guarda con sus tipos y calcula el retraso; si no, lo guarda en una tabla de descartes con el motivo."

### Paso 13. Tablas de DynamoDB y su llave (7:05 – 7:45)

**A dónde ir:** DynamoDB → Tables → `secop_offers` (pestaña Overview, donde se ven las llaves) → **Explore table items**. Después, `secop_offers_rejected` → Explore table items.

**Qué debe salir:** `secop_offers` con partition key `process_id` y sort key `event_id`, y los ítems con `latency_ms`; `secop_offers_rejected` con ítems y su columna `reason`.

**Qué decir:**

> "Los eventos válidos se guardan en secop_offers. La llave es el id del proceso como partition key y el id del evento como sort key. La escogimos porque la consulta natural del proyecto es 'todas las ofertas de un proceso', para saber cuánta competencia tiene, y con esta llave es una sola consulta. Además, como hay muchos procesos, las escrituras se reparten y no se satura una partición. El id del evento hace única cada oferta, así que si un evento llega repetido no se guarda dos veces. Los descartados van a secop_offers_rejected, con su motivo."

### Paso 14. Publicación de los eventos (7:45 – 8:05)

**A dónde ir:** GitHub → `docs/resultados/parte-b-publish.txt`.

**Qué debe salir:** `publicados: 12,000 en 375.0 s`, con 11.051 válidos y el resto por tipo de defecto.

**Qué decir:**

> "Publicamos 12.000 eventos con un script que usa la API de IoT Core; tardó unos 6 minutos. A propósito, un 8 % salió dañado: valores negativos, sin NIT, procesos mal escritos, texto que no es JSON y eventos repetidos."

### Paso 15. Conteos y retraso (8:05 – 8:40)

**A dónde ir:** GitHub → `docs/resultados/parte-b-report.txt`. También puede volver a correr `python3 parte-b/scripts/report.py` en la terminal, porque solo lee.

**Qué debe salir:** publicados 12.000, guardados 11.051, descartados 949, `CUADRA`; retraso promedio 718 ms y máximo 6.753 ms.

**Qué decir:**

> "Y todo cuadra: de los 12.000 publicados, 11.051 están guardados en DynamoDB y 949 descartados, y cada tipo de descarte coincide exactamente con lo que publicamos dañado. El retraso entre el envío y la llegada a DynamoDB fue de 718 milisegundos en promedio y de 6,8 segundos como máximo. Limitamos la Lambda a dos ejecuciones en paralelo, así que cuando llegaban más eventos de los que alcanzaba a procesar, esperaban en la cola; por eso los más lentos fueron los del final de la publicación."

### Paso 16. CloudFormation (8:40 – 8:55)

**A dónde ir:** CloudFormation → Stacks (región us-east-1). Abra el stack que aparece → pestaña **Resources**.

**Qué debe salir:** un solo stack, con la descripción _"associate Learner Lab template (academy)"_, y en Resources cosas como `LabRole` y `VocLabPolicy`.

**Qué decir:**

> "Todos los recursos los creamos a mano en la consola, sin infraestructura como código. En CloudFormation solo aparece este stack, que no es nuestro: lo crea AWS Academy al iniciar el Learner Lab y monta los roles del laboratorio. Nosotros no creamos ningún stack."

### Paso 17. Pregunta final de la parte B y cierre (8:55 – 9:40)

**A dónde ir:** la cámara.

**Qué decir:**

> "¿A partir de qué volumen dejaríamos este flujo? IoT Core, SQS, Lambda y DynamoDB funcionan bien para eventos sueltos y para cientos o pocos miles de eventos por segundo. Pero cada evento se cobra varias veces, y no hay orden ni forma de volver a leer la historia. Si tuviéramos un flujo sostenido de varios miles de eventos por segundo, o necesitáramos orden por proceso, reprocesar o tener varios consumidores, lo cambiaríamos por Amazon Kinesis Data Streams, o por Kafka si fuera aún más grande, y llevaríamos los datos a S3 con Firehose para analizarlos en el lakehouse. Además, las ofertas no vienen de dispositivos, así que IoT Core no aporta nada a esa escala. Eso es todo, gracias."

---

## Después de grabar

- Revise que el video dure menos de 10:00 y que los dos se vean hablando.
- Súbalo a YouTube como **no listado**.
- Borre los recursos con la guía ([guia-consola.md](guia-consola.md), sección "Al terminar: borrar todo").
