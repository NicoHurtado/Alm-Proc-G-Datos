-- Parte A, paso 4: capa plata, datos validados y con tipos.
-- Reemplace YOUR_BUCKET por el nombre de su bucket.
-- Ejecute UNA sentencia a la vez.

-- Sentencia 1: una vista que aplica las reglas de calidad a la tabla bronce.
-- Cada fila recibe un reject_reason (la primera regla que incumple), o NULL
-- si pasa todas. Reglas, en orden (entre paréntesis, el hallazgo que la
-- justifica en 02_findings.sql):
--   R1 invalid_publication_date  fecha vacía, ilegible o fuera de 2015 a hoy (2)
--   R2 invalid_base_price        precio base no numérico, cero o negativo (3)
--   R3 invalid_category          categoría UNSPSC distinta de V1.######## (4)
--   R4 invalid_entity_nit        NIT de la entidad con puntos, letras o vacío (5)
--   R5 undefined_department      departamento de la entidad No Definido (6)
--   R6 duplicate_row             copia idéntica de otra fila, se deja una (1)
CREATE OR REPLACE VIEW secop.bronze_processes_checked AS
WITH typed AS (
    SELECT *,
           CAST(try(date_parse(fecha_de_publicacion_del,
                               '%Y-%m-%dT%H:%i:%s.%f')) AS date)
               AS publication_date_value,
           try_cast(precio_base AS decimal(22, 2)) AS base_price_value
    FROM secop.bronze_processes
),
checked AS (
    SELECT *,
           CASE
               WHEN publication_date_value IS NULL
                   OR publication_date_value < DATE '2015-01-01'
                   OR publication_date_value > current_date
                   THEN 'invalid_publication_date'
               WHEN base_price_value IS NULL OR base_price_value <= 0
                   THEN 'invalid_base_price'
               WHEN NOT regexp_like(coalesce(codigo_principal_de_categoria, ''),
                                    '^V1\.[0-9]{8}$')
                   THEN 'invalid_category'
               WHEN NOT regexp_like(coalesce(nit_entidad, ''), '^[0-9]{5,12}$')
                   THEN 'invalid_entity_nit'
               WHEN coalesce(departamento_entidad, '')
                   IN ('', 'No Definido', 'No definido')
                   THEN 'undefined_department'
           END AS first_reason
    FROM typed
),
numbered AS (
    SELECT *,
           row_number() OVER (
               PARTITION BY first_reason,
                   entidad, nit_entidad, departamento_entidad, ciudad_entidad,
                   ordenentidad, codigo_pci, id_del_proceso,
                   referencia_del_proceso, ppi, id_del_portafolio,
                   nombre_del_procedimiento, descripci_n_del_procedimiento,
                   fase, fecha_de_publicacion_del, fecha_de_ultima_publicaci,
                   fecha_de_publicacion_fase, fecha_de_publicacion_fase_1,
                   fecha_de_publicacion, fecha_de_publicacion_fase_2,
                   fecha_de_publicacion_fase_3, precio_base,
                   modalidad_de_contratacion, justificaci_n_modalidad_de,
                   duracion, unidad_de_duracion, fecha_de_recepcion_de,
                   fecha_de_apertura_de_respuesta, fecha_de_apertura_efectiva,
                   ciudad_de_la_unidad_de, nombre_de_la_unidad_de,
                   proveedores_invitados, proveedores_con_invitacion,
                   visualizaciones_del, proveedores_que_manifestaron,
                   respuestas_al_procedimiento, respuestas_externas,
                   conteo_de_respuestas_a_ofertas, proveedores_unicos_con,
                   numero_de_lotes, estado_del_procedimiento,
                   id_estado_del_procedimiento, adjudicado, id_adjudicacion,
                   codigoproveedor, departamento_proveedor, ciudad_proveedor,
                   fecha_adjudicacion, valor_total_adjudicacion,
                   nombre_del_adjudicador, nombre_del_proveedor,
                   nit_del_proveedor_adjudicado, codigo_principal_de_categoria,
                   estado_de_apertura_del_proceso, tipo_de_contrato,
                   subtipo_de_contrato, categorias_adicionales, urlproceso,
                   codigo_entidad, estado_resumen
               ORDER BY id_del_proceso
           ) AS copy_number
    FROM checked
)
SELECT entidad, nit_entidad, departamento_entidad, ciudad_entidad,
       ordenentidad, codigo_pci, id_del_proceso, referencia_del_proceso, ppi,
       id_del_portafolio, nombre_del_procedimiento,
       descripci_n_del_procedimiento, fase, fecha_de_publicacion_del,
       fecha_de_ultima_publicaci, fecha_de_publicacion_fase,
       fecha_de_publicacion_fase_1, fecha_de_publicacion,
       fecha_de_publicacion_fase_2, fecha_de_publicacion_fase_3, precio_base,
       modalidad_de_contratacion, justificaci_n_modalidad_de, duracion,
       unidad_de_duracion, fecha_de_recepcion_de,
       fecha_de_apertura_de_respuesta, fecha_de_apertura_efectiva,
       ciudad_de_la_unidad_de, nombre_de_la_unidad_de, proveedores_invitados,
       proveedores_con_invitacion, visualizaciones_del,
       proveedores_que_manifestaron, respuestas_al_procedimiento,
       respuestas_externas, conteo_de_respuestas_a_ofertas,
       proveedores_unicos_con, numero_de_lotes, estado_del_procedimiento,
       id_estado_del_procedimiento, adjudicado, id_adjudicacion,
       codigoproveedor, departamento_proveedor, ciudad_proveedor,
       fecha_adjudicacion, valor_total_adjudicacion, nombre_del_adjudicador,
       nombre_del_proveedor, nit_del_proveedor_adjudicado,
       codigo_principal_de_categoria, estado_de_apertura_del_proceso,
       tipo_de_contrato, subtipo_de_contrato, categorias_adicionales,
       urlproceso, codigo_entidad, estado_resumen,
       CASE
           WHEN first_reason IS NOT NULL THEN first_reason
           WHEN copy_number > 1 THEN 'duplicate_row'
       END AS reject_reason
FROM numbered;

-- Sentencia 2: qué pasa con las filas de bronce
SELECT coalesce(reject_reason, 'valid') AS result, count(*) AS bronze_rows
FROM secop.bronze_processes_checked
GROUP BY 1
ORDER BY bronze_rows DESC;

-- Sentencia 3: la tabla plata, con las filas que pasaron, con tipos
CREATE TABLE secop.silver_processes
WITH (
    table_type = 'ICEBERG',
    is_external = false,
    location = 's3://YOUR_BUCKET/silver/processes/',
    format = 'PARQUET'
) AS
SELECT id_del_proceso AS process_id,
       referencia_del_proceso AS process_reference,
       entidad AS entity_name,
       nit_entidad AS entity_nit,
       departamento_entidad AS entity_department,
       ciudad_entidad AS entity_city,
       ordenentidad AS entity_order,
       nombre_del_procedimiento AS process_name,
       descripci_n_del_procedimiento AS process_description,
       modalidad_de_contratacion AS modality,
       tipo_de_contrato AS contract_type,
       codigo_principal_de_categoria AS category_code,
       substr(codigo_principal_de_categoria, 4, 2) AS unspsc_segment,
       substr(codigo_principal_de_categoria, 4, 4) AS unspsc_family,
       CAST(date_parse(fecha_de_publicacion_del, '%Y-%m-%dT%H:%i:%s.%f')
            AS date) AS publication_date,
       CAST(precio_base AS decimal(22, 2)) AS base_price,
       try_cast(duracion AS integer) AS duration,
       unidad_de_duracion AS duration_unit,
       estado_del_procedimiento AS process_state,
       fase AS phase,
       adjudicado = 'Si' AS is_awarded,
       CAST(try(date_parse(fecha_adjudicacion, '%Y-%m-%dT%H:%i:%s.%f'))
            AS date) AS award_date,
       try_cast(valor_total_adjudicacion AS decimal(22, 2)) AS award_value,
       nombre_del_proveedor AS supplier_name,
       nit_del_proveedor_adjudicado AS supplier_nit,
       departamento_proveedor AS supplier_department,
       try_cast(proveedores_invitados AS integer) AS invited_suppliers,
       try_cast(proveedores_que_manifestaron AS integer)
           AS interested_suppliers,
       try_cast(respuestas_al_procedimiento AS integer) AS responses,
       try_cast(proveedores_unicos_con AS integer) AS unique_bidders,
       urlproceso AS process_url
FROM secop.bronze_processes_checked
WHERE reject_reason IS NULL;

-- Sentencia 4: las filas que no pasaron, tal como llegaron, con el motivo
CREATE TABLE secop.silver_processes_rejected
WITH (
    table_type = 'ICEBERG',
    is_external = false,
    location = 's3://YOUR_BUCKET/silver/processes_rejected/',
    format = 'PARQUET'
) AS
SELECT *
FROM secop.bronze_processes_checked
WHERE reject_reason IS NOT NULL;

-- Sentencia 5: los conteos cuadran, bronce = válidas + rechazadas
SELECT bronze_rows, valid_rows, rejected_rows,
       valid_rows + rejected_rows AS valid_plus_rejected,
       IF(bronze_rows = valid_rows + rejected_rows, 'CUADRA', 'NO CUADRA')
           AS check_result
FROM (SELECT count(*) AS bronze_rows FROM secop.bronze_processes)
CROSS JOIN (SELECT count(*) AS valid_rows FROM secop.silver_processes)
CROSS JOIN (SELECT count(*) AS rejected_rows
            FROM secop.silver_processes_rejected);

-- Sentencia 6: por qué se rechazaron las filas
SELECT reject_reason, count(*) AS rejected_rows
FROM secop.silver_processes_rejected
GROUP BY reject_reason
ORDER BY rejected_rows DESC;
