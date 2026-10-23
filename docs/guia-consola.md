# Guía: recursos que se crean a mano en la consola de AWS

Esta guía tiene **solo lo que se crea a mano en la consola**. No hay que preparar archivos, pegar código ni escribir JSON. Todo se crea en la región **us-east-1 (N. Virginia)**: elíjala arriba a la derecha antes de empezar.

Lo demás se hace desde la terminal con la AWS CLI, después de crear los recursos: subir el archivo, cargar el código y la configuración de la Lambda, correr el SQL de Athena, publicar los eventos y medir. Ver [Después de crear los recursos](#después-de-crear-los-recursos).

- [0. CloudFormation sin stacks](#0-cloudformation-sin-stacks)
- [1. Bucket de S3](#1-bucket-de-s3)
- [2. Tablas de DynamoDB](#2-tablas-de-dynamodb)
- [3. Cola de SQS](#3-cola-de-sqs)
- [4. Función Lambda](#4-función-lambda)
- [5. Regla de IoT Core](#5-regla-de-iot-core)
- [6. Ubicación de resultados de Athena](#6-ubicación-de-resultados-de-athena)
- [Después de crear los recursos](#después-de-crear-los-recursos)
- [Al terminar: borrar todo](#al-terminar-borrar-todo)

---

## 0. CloudFormation sin stacks

Esta guía es para una cuenta de **AWS Academy Learner Lab**. Las notas que dicen _Cuenta personal_ son para una cuenta normal de AWS.

**CloudFormation → Stacks.** En Learner Lab siempre aparece un stack de AWS Academy (_"associate Learner Lab template (academy)"_). **No lo borre:** monta el rol `LabRole` y los permisos del laboratorio. Si quedan stacks de los laboratorios del curso (`big-data-labs-...`), vacíe primero sus buckets y después borre esos stacks.

En Learner Lab no se pueden crear roles de IAM: la Lambda y la regla de IoT usan el rol existente **`LabRole`**.

_Cuenta personal:_ CloudFormation debe quedar sin ningún stack.

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

→ **Create function**. Si aparece un error de `iam:CreateRole`, es porque no se cambió el rol. El código se carga después desde la terminal.

_Cuenta personal:_ deje el rol por defecto. Después, en **Configuration → Permissions →** clic en el rol → **Add permissions → Attach policies**, agregue `AWSLambdaSQSQueueExecutionRole` y `AmazonDynamoDBFullAccess`.

**Trigger:** de vuelta en la función, **Add trigger**:

| Campo      | Valor                |
| ---------- | -------------------- |
| Source     | SQS                  |
| SQS queue  | `secop-offers-queue` |
| Batch size | 10                   |
| Maximum concurrency | **2**       |

→ **Add**. Si no ve _Maximum concurrency_, abra **Additional settings** del trigger. Limita la Lambda a 2 ejecuciones en paralelo, para no pasar los límites del laboratorio.

## 5. Regla de IoT Core

**IoT Core → Message routing → Rules → Create rule**

| Paso                | Valor                                                                                         |
| ------------------- | --------------------------------------------------------------------------------------------- |
| Rule name           | `secop_offers_to_sqs`                                                                         |
| SQL version         | 2016-03-23 (por defecto)                                                                      |
| SQL statement       | `SELECT * FROM 'secop/offers'`                                                                |
| Rule action         | **Simple Queue Service (SQS)** → queue `secop-offers-queue` → Use Base64 encoding: **No**     |
| IAM role            | El rol existente **`LabRole`**                                                                |

→ **Next → Create**. La consola muestra el error _"We can't create a policy for the role LabRole to perform action sqs"_. Se puede cerrar: la regla queda creada y activa, y `LabRole` ya tiene permiso para enviar a SQS.

_Cuenta personal:_ **Create new role** → `secop-iot-to-sqs`.

## 6. Ubicación de resultados de Athena

**Athena → Query editor → Settings → Manage**

| Campo                          | Valor                                  |
| ------------------------------ | -------------------------------------- |
| Location of query result       | `s3://<su bucket>/athena-results/`     |

→ **Save**. Así el editor de Athena funciona para mostrar las consultas en el video.

---

## Después de crear los recursos

Esto se corre desde la terminal con la AWS CLI conectada a la cuenta (`aws configure` o `aws login`), sin crear recursos nuevos:

1. **Lambda:** cargar `parte-b/lambda/lambda_function.py` y configurar timeout de 30 s y las variables `OFFERS_TABLE` y `REJECTED_TABLE` (`aws lambda update-function-code`, `update-function-configuration`).
2. **S3:** subir `data/secop_procesos.jsonl.gz` a `bronze/secop_processes/` (`aws s3 cp`).
3. **Athena:** correr en orden los archivos de `parte-a/sql/` (`aws athena start-query-execution`). Las consultas quedan en **Recent queries** del editor de Athena para mostrarlas en el video.
4. **Eventos:** `python3 parte-b/scripts/publish_events.py --count 12000` y luego `python3 parte-b/scripts/report.py`.

---

## Al terminar: borrar todo

1. Athena: `parte-a/sql/06_drop.sql` (terminal).
2. S3: vaciar el bucket (**Empty**) y borrarlo (**Delete**).
3. IoT Core: borrar la regla `secop_offers_to_sqs`.
4. Lambda: borrar `secop-offers-consumer`.
5. SQS: borrar `secop-offers-queue`.
6. DynamoDB: borrar `secop_offers` y `secop_offers_rejected`.
7. _Cuenta personal:_ IAM → Roles: borrar `secop-offers-consumer-role-...` y `secop-iot-to-sqs`.
8. CloudWatch → Log groups: borrar `/aws/lambda/secop-offers-consumer`.
