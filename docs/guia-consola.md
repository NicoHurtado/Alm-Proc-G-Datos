# Guía: recursos que se crean a mano en la consola de AWS

Esta guía tiene **solo lo que se crea a mano en la consola**. No hay que preparar archivos, pegar código ni escribir JSON. Todo se crea en la región **us-east-1 (N. Virginia)**: elíjala arriba a la derecha antes de empezar.

Lo demás se hace desde la terminal con la AWS CLI, después de crear los recursos: subir el archivo, cargar el código y la configuración de la Lambda, correr el SQL de Athena, publicar los eventos y medir. Ver [Después de crear los recursos](#después-de-crear-los-recursos).

- [0. CloudFormation sin stacks](#0-cloudformation-sin-stacks)
- [1. Bucket de S3](#1-bucket-de-s3)
- [2. Tablas de DynamoDB](#2-tablas-de-dynamodb)
- [3. Cola de SQS](#3-cola-de-sqs)
- [4. Función Lambda](#4-función-lambda)
- [5. Regla de IoT Core](#5-regla-de-iot-core)
- [Después de crear los recursos](#después-de-crear-los-recursos)
- [Al terminar: borrar todo](#al-terminar-borrar-todo)

---

## 0. CloudFormation sin stacks

**CloudFormation → Stacks.** Si quedan stacks de los laboratorios (`big-data-labs-...`), vacíe primero sus buckets en S3 y después borre los stacks.

**Si la cuenta es de AWS Academy Learner Lab**, va a ver un stack con un nombre como `c225165a...t1w<id de la cuenta>`, con la descripción _"associate Learner Lab template (academy)"_. **No lo borre.** Lo crea AWS Academy al iniciar el laboratorio y monta el rol `LabRole` y los permisos de la cuenta; sin él, el laboratorio deja de funcionar. En el video se muestra que es el único stack y que no es nuestro (pestaña **Template** o **Resources**).

En Learner Lab tampoco se pueden crear roles de IAM: la Lambda y la regla de IoT usan el rol existente **`LabRole`**.

## 1. Bucket de S3

**S3 → Create bucket**

| Campo       | Valor                                                                           |
| ----------- | ------------------------------------------------------------------------------- |
| Bucket name | `apgd-trabajo1-<id de la cuenta>` (el id de 12 dígitos, arriba a la derecha)    |
| Lo demás    | Por defecto                                                                     |

→ **Create bucket**. No hace falta crear carpetas ni subir nada.

## 2. Tablas de DynamoDB

**DynamoDB → Tables → Create table**, dos veces:

| Campo         | Tabla 1                 | Tabla 2                 |
| ------------- | ----------------------- | ----------------------- |
| Table name    | `secop_offers`          | `secop_offers_rejected` |
| Partition key | `process_id` (String)   | `message_id` (String)   |
| Sort key      | `event_id` (String)     | (vacío)                 |
| Settings      | Default settings        | Default settings        |

→ **Create table**.

## 3. Cola de SQS

**SQS → Create queue**

| Campo              | Valor                |
| ------------------ | -------------------- |
| Type               | **Standard**         |
| Name               | `secop-offers-queue` |
| Visibility timeout | **3 Minutes**        |
| Lo demás           | Por defecto          |

→ **Create queue**.

## 4. Función Lambda

**Lambda → Create function**

| Campo          | Valor                                                    |
| -------------- | -------------------------------------------------------- |
| Opción         | Author from scratch                                      |
| Function name  | `secop-offers-consumer`                                  |
| Runtime        | **Python 3.13**                                          |
| Execution role | Abra **Additional settings** → en el rol de ejecución elija **Use an existing role** → **`LabRole`** |

→ **Create function**. Si aparece un error de `iam:CreateRole`, es porque no se cambió el rol: Learner Lab no deja crear roles. El código se carga después desde la terminal. `LabRole` ya tiene permisos para leer de SQS y escribir en DynamoDB.

**Trigger:** de vuelta en la función, **Add trigger**:

| Campo      | Valor                |
| ---------- | -------------------- |
| Source     | SQS                  |
| SQS queue  | `secop-offers-queue` |
| Batch size | 10                   |

→ **Add**.

## 5. Regla de IoT Core

**IoT Core → Message routing → Rules → Create rule**

| Paso                | Valor                                                                                         |
| ------------------- | --------------------------------------------------------------------------------------------- |
| Rule name           | `secop_offers_to_sqs`                                                                         |
| SQL version         | 2016-03-23 (por defecto)                                                                      |
| SQL statement       | `SELECT * FROM 'secop/offers'`                                                                |
| Rule action         | **Simple Queue Service (SQS)** → queue `secop-offers-queue` → Use Base64 encoding: **No**     |
| IAM role            | El rol existente **`LabRole`**                                                                |

→ **Next → Create**. En Learner Lab la consola muestra el error _"We can't create a policy for the role LabRole to perform action sqs"_. Se puede cerrar: la regla queda creada y activa, y `LabRole` ya tiene permiso para enviar mensajes a SQS.

---

## Después de crear los recursos

Esto se corre desde la terminal con la AWS CLI conectada a la cuenta (`aws configure` o `aws login`), sin crear recursos nuevos:

1. **Lambda:** cargar `parte-b/lambda/lambda_function.py` y configurar timeout de 30 s y las variables `OFFERS_TABLE` y `REJECTED_TABLE` (`aws lambda update-function-code`, `update-function-configuration`).
2. **S3:** subir `data/secop_procesos.jsonl.gz` a `bronze/secop_processes/` (`aws s3 cp`).
3. **Athena:** fijar la ubicación de resultados del workgroup `primary` en `s3://<bucket>/athena-results/` y correr en orden los archivos de `parte-a/sql/` (`aws athena start-query-execution`). Las consultas quedan en **Recent queries** del editor de Athena para mostrarlas en el video.
4. **Eventos:** `python3 parte-b/scripts/publish_events.py --count 12000` y luego `python3 parte-b/scripts/report.py`.

---

## Al terminar: borrar todo

1. Athena: `parte-a/sql/06_drop.sql` (terminal).
2. S3: vaciar el bucket (**Empty**) y borrarlo (**Delete**).
3. IoT Core: borrar la regla `secop_offers_to_sqs`.
4. Lambda: borrar `secop-offers-consumer`.
5. SQS: borrar `secop-offers-queue`.
6. DynamoDB: borrar `secop_offers` y `secop_offers_rejected`.
7. CloudWatch → Log groups: borrar `/aws/lambda/secop-offers-consumer`.
