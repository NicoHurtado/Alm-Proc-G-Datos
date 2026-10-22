# Guion del video (máximo 10 minutos)

Condiciones que no se pueden olvidar:

- **Los dos hablan y se les ve la cara mientras hablan**, con la cámara en una esquina de la grabación de pantalla (OBS, Zoom o Teams grabando).
- **Dura máximo 10:00.** El guion apunta a ~9:00 para dejar margen.
- **No se muestran credenciales.** Nada de `aws configure`, de `~/.aws/credentials`, de la página *AWS Details* del Learner Lab ni de llaves.
- **Las tablas se leen bien:** zoom del navegador al 125 % o 150 % y el panel de resultados de Athena agrandado.
- Se sube a YouTube como **no listado**.

Persona 1 = Nicolás. Persona 2 = compañero.

| Tiempo    | Quién | Qué se muestra                                                                          | Qué se dice                                                                                                                                       |
| --------- | ----- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0:00–0:30 | P1+P2 | Cámara de los dos, luego el README                                                      | Nombres, curso, ContrataMatch en una frase y las dos partes del trabajo                                                                         |
| 0:30–1:30 | P1    | README, sección Descripción; página de datos.gov.co                                     | Qué es SECOP II, de dónde viene, el recorte a modalidades con competencia, filas, columnas, tipos y peso. Por qué JSON Lines                     |
| 1:30–2:10 | P1    | S3: el archivo en `bronze/secop_processes/`. Athena: `CREATE` de bronce y `count(*)`     | Tabla externa con las 59 columnas como texto; el conteo de filas                                                                                 |
| 2:10–3:10 | P2    | Athena: resultado de la tabla de hallazgos (sentencia 1 de `02_findings.sql`)           | Los 7 hallazgos con su número y porcentaje. Que el id repetido no es defecto (sentencia 3)                                                         |
| 3:10–4:20 | P2    | `03_silver.sql`: las reglas en la vista; resultado de las sentencias 5 y 6               | Las 6 reglas y el hallazgo que justifica cada una. Iceberg de válidas y de rechazadas con motivo. **"bronce = válidas + rechazadas: CUADRA"**    |
| 4:20–5:00 | P1    | `04_gold.sql`: la tabla de oro y la respuesta (sentencia 3)                             | La pregunta de negocio y qué departamentos y segmentos tienen más procesos con una sola oferta; para qué le sirve a ContrataMatch               |
| 5:00–5:45 | P1    | Las tres consultas de `05_compare.sql` con "Datos escaneados" y "Tiempo"; tabla del README | Bytes y tiempos de bronce, plata y oro y por qué bajan: JSON completo vs Parquet columnar vs datos ya agregados                                 |
| 5:45–6:50 | P2    | Consola: DynamoDB (las 2 tablas y su llave), SQS (la cola), IoT Core (la regla y su SQL), Lambda (código y trigger SQS) | El flujo IoT Core → SQS → Lambda → DynamoDB. Por qué `process_id` + `event_id`. Cómo la Lambda valida el esquema y los motivos de descarte |
| 6:50–7:50 | P2    | Terminal: [parte-b-publish.txt](resultados/parte-b-publish.txt) (12.000 publicados) y [parte-b-report.txt](resultados/parte-b-report.txt) (o volver a correr `report.py`, que solo lee); DynamoDB con ítems | Publicados = guardados + descartados (CUADRA), descartes por motivo, retraso promedio y máximo                                                    |
| 7:50–8:05 | P1    | CloudFormation → Stacks en us-east-1, vacío                                             | "Todo se creó a mano en la consola: no hay ningún stack"                                                                                         |
| 8:05–8:45 | P1    | Cámara                                                                                  | Pregunta A: datos mil veces mayores (ver README)                                                                                                 |
| 8:45–9:25 | P2    | Cámara                                                                                  | Pregunta B: desde qué volumen y qué usarían (ver README)                                                                                        |
| 9:25–9:35 | P1+P2 | Cámara                                                                                  | Cierre                                                                                                                                            |

## Consejos para grabar rápido

- **No vuelvan a correr `publish_events.py`**: con la misma semilla genera los mismos `event_id`, así que todos saldrían como `duplicate_event` y el cuadre ya no sería el del README. `report.py` sí se puede repetir, porque solo lee.
- Corra todas las consultas **antes** de grabar. En el video basta con mostrar el historial de Athena (**Recent queries**) o volver a correr las consultas cortas.
- Puede grabar en varios clips y unirlos, siempre que el total no pase de 10:00.
- En `report.py` y en la tabla de hallazgos, deténgase 2 o 3 segundos para que se lean los números.
- Al terminar de grabar, borre los recursos (guía, sección "Al terminar: borrar todo").
