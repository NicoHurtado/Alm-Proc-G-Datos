-- Parte A, paso 5: capa oro, lista para responder una pregunta de negocio.
-- Pregunta: en los procesos con competencia ya adjudicados, ¿en qué
-- departamentos y segmentos de producto (UNSPSC) se presenta una sola oferta
-- con más frecuencia? Son las oportunidades donde a una MiPyme le conviene
-- presentarse, porque compite contra menos empresas, y donde el Estado
-- pierde la posibilidad de comparar precios.
-- Reemplace YOUR_BUCKET por el nombre de su bucket.
-- Ejecute UNA sentencia a la vez.

-- Sentencia 1: competencia por año, departamento y segmento UNSPSC.
-- Plata tiene una fila por adjudicación; primero se deja una por proceso.
CREATE TABLE secop.gold_competition_by_department_segment
WITH (
    table_type = 'ICEBERG',
    is_external = false,
    location = 's3://YOUR_BUCKET/gold/competition_by_department_segment/',
    format = 'PARQUET'
) AS
WITH processes AS (
    SELECT process_id,
           min(publication_date) AS publication_date,
           arbitrary(entity_department) AS entity_department,
           arbitrary(unspsc_segment) AS unspsc_segment,
           max(base_price) AS base_price,
           max(responses) AS responses
    FROM secop.silver_processes
    WHERE is_awarded
    GROUP BY process_id
)
SELECT year(publication_date) AS year,
       entity_department,
       unspsc_segment,
       count(*) AS awarded_processes,
       count_if(responses <= 1) AS single_bid_processes,
       round(100.0 * count_if(responses <= 1) / count(*), 1)
           AS pct_single_bid,
       round(avg(responses), 2) AS avg_responses,
       sum(base_price) AS total_base_price
FROM processes
GROUP BY year(publication_date), entity_department, unspsc_segment;

-- Sentencia 2: cuántas filas tiene oro frente a plata
SELECT 'silver_processes' AS table_name, count(*) AS table_rows
FROM secop.silver_processes
UNION ALL
SELECT 'gold_competition_by_department_segment', count(*)
FROM secop.gold_competition_by_department_segment;

-- Sentencia 3: la respuesta. Departamentos y segmentos de 2025 con más de
-- 200 procesos adjudicados, ordenados por el porcentaje con una sola oferta
SELECT entity_department, unspsc_segment, awarded_processes,
       single_bid_processes, pct_single_bid, avg_responses
FROM secop.gold_competition_by_department_segment
WHERE year = 2025 AND awarded_processes > 200
ORDER BY pct_single_bid DESC
LIMIT 15;
