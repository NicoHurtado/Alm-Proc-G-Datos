-- Parte A, paso 3: hallazgos, los defectos de calidad medidos con SQL.
-- Cada hallazgo se cuenta por separado: una fila puede tener varios defectos.
-- Ejecute UNA sentencia a la vez.

-- Sentencia 1: tabla de hallazgos, con las filas afectadas y su porcentaje
WITH flags AS (
    SELECT
        trim(coalesce(fecha_de_publicacion_del, '')) = ''
            AS empty_publication_date,
        coalesce(try_cast(precio_base AS double), 0) <= 0
            AS non_positive_base_price,
        NOT regexp_like(coalesce(codigo_principal_de_categoria, ''),
                        '^V1\.[0-9]{8}$') AS invalid_category,
        NOT regexp_like(coalesce(nit_entidad, ''), '^[0-9]{5,12}$')
            AS invalid_entity_nit,
        coalesce(departamento_entidad, '') IN ('', 'No Definido', 'No definido')
            AS undefined_department,
        adjudicado = 'Si'
            AND coalesce(try_cast(valor_total_adjudicacion AS double), 0) <= 0
            AS awarded_without_value
    FROM secop.bronze_processes
),
totals AS (
    SELECT count(*) AS total_rows,
           count_if(empty_publication_date) AS empty_publication_date,
           count_if(non_positive_base_price) AS non_positive_base_price,
           count_if(invalid_category) AS invalid_category,
           count_if(invalid_entity_nit) AS invalid_entity_nit,
           count_if(undefined_department) AS undefined_department,
           count_if(awarded_without_value) AS awarded_without_value
    FROM flags
),
duplicates AS (
    SELECT (SELECT count(*) FROM secop.bronze_processes)
           - (SELECT count(*)
              FROM (SELECT DISTINCT * FROM secop.bronze_processes))
           AS duplicate_row
),
findings AS (
    SELECT 1 AS n, 'duplicate_row' AS finding,
           'Copia idéntica de otra fila (las 59 columnas iguales)'
               AS description,
           duplicate_row AS affected_rows
    FROM duplicates
    UNION ALL
    SELECT 2, 'empty_publication_date',
           'Fecha de publicación vacía', empty_publication_date FROM totals
    UNION ALL
    SELECT 3, 'non_positive_base_price',
           'Precio base vacío, en cero o negativo', non_positive_base_price
    FROM totals
    UNION ALL
    SELECT 4, 'invalid_category',
           'Categoría UNSPSC vacía o UNSPECIFIED', invalid_category FROM totals
    UNION ALL
    SELECT 5, 'invalid_entity_nit',
           'NIT de la entidad con puntos, guion, letras o vacío',
           invalid_entity_nit FROM totals
    UNION ALL
    SELECT 6, 'undefined_department',
           'Departamento de la entidad No Definido', undefined_department
    FROM totals
    UNION ALL
    SELECT 7, 'awarded_without_value',
           'Adjudicado = Si pero valor adjudicado en cero',
           awarded_without_value FROM totals
)
SELECT f.n, f.finding, f.description, f.affected_rows,
       round(100.0 * f.affected_rows / t.total_rows, 2) AS pct_of_rows,
       t.total_rows
FROM findings f
CROSS JOIN totals t
ORDER BY f.n;

-- Sentencia 2: ejemplos de filas idénticas (mismo proceso repetido igual)
SELECT id_del_proceso, nombre_del_proveedor, valor_total_adjudicacion,
       count(*) AS copies
FROM secop.bronze_processes
GROUP BY id_del_proceso, nombre_del_proveedor, valor_total_adjudicacion,
         fecha_de_ultima_publicaci, estado_resumen
HAVING count(*) > 1
ORDER BY copies DESC
LIMIT 10;

-- Sentencia 3: un mismo proceso con varias filas distintas NO es un defecto:
-- SECOP publica una fila por cada adjudicación (lote o proveedor)
SELECT id_del_proceso, count(*) AS rows_in_bronze,
       count(DISTINCT nombre_del_proveedor) AS suppliers
FROM (SELECT DISTINCT * FROM secop.bronze_processes)
GROUP BY id_del_proceso
HAVING count(*) > 1
ORDER BY rows_in_bronze DESC
LIMIT 10;

-- Sentencia 4: precios base en cero y negativos
SELECT CASE WHEN try_cast(precio_base AS double) = 0 THEN 'zero'
            ELSE 'negative' END AS base_price, count(*) AS bronze_rows,
       min(try_cast(precio_base AS double)) AS min_value
FROM secop.bronze_processes
WHERE coalesce(try_cast(precio_base AS double), 0) <= 0
GROUP BY 1;

-- Sentencia 5: ejemplos de categorías y NIT inválidos
SELECT 'codigo_principal_de_categoria' AS column_name,
       codigo_principal_de_categoria AS value, count(*) AS bronze_rows
FROM secop.bronze_processes
WHERE NOT regexp_like(coalesce(codigo_principal_de_categoria, ''),
                      '^V1\.[0-9]{8}$')
GROUP BY codigo_principal_de_categoria
UNION ALL
SELECT 'nit_entidad', nit_entidad, count(*)
FROM secop.bronze_processes
WHERE NOT regexp_like(coalesce(nit_entidad, ''), '^[0-9]{5,12}$')
GROUP BY nit_entidad
ORDER BY bronze_rows DESC
LIMIT 15;
