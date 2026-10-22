-- Parte A, paso 6: la misma pregunta en las tres capas.
-- Pregunta: en 2025, ¿qué departamentos (con al menos 100 procesos
-- adjudicados) tienen el mayor porcentaje de procesos con una sola oferta?
-- Después de cada sentencia anote "Datos escaneados" y "Tiempo en cola" /
-- "Tiempo de ejecución" que Athena muestra bajo el resultado (pestaña
-- "Estadísticas de consulta"). Ejecute cada una dos o tres veces y anote la
-- mediana, porque el tiempo varía entre ejecuciones.
-- Ejecute UNA sentencia a la vez.

-- Sentencia 1: bronce, texto sin validar; hay que convertir tipos en cada
-- consulta y quitar duplicados contando procesos distintos
SELECT departamento_entidad AS entity_department,
       count(DISTINCT id_del_proceso) AS awarded_processes,
       round(100.0 * count(DISTINCT IF(
           try_cast(respuestas_al_procedimiento AS integer) <= 1,
           id_del_proceso)) / count(DISTINCT id_del_proceso), 1)
           AS pct_single_bid
FROM secop.bronze_processes
WHERE adjudicado = 'Si'
  AND year(try(date_parse(fecha_de_publicacion_del,
                          '%Y-%m-%dT%H:%i:%s.%f'))) = 2025
GROUP BY departamento_entidad
HAVING count(DISTINCT id_del_proceso) >= 100
ORDER BY pct_single_bid DESC
LIMIT 10;

-- Sentencia 2: plata, con tipos y sin filas inválidas
SELECT entity_department,
       count(DISTINCT process_id) AS awarded_processes,
       round(100.0 * count(DISTINCT IF(responses <= 1, process_id))
             / count(DISTINCT process_id), 1) AS pct_single_bid
FROM secop.silver_processes
WHERE is_awarded AND year(publication_date) = 2025
GROUP BY entity_department
HAVING count(DISTINCT process_id) >= 100
ORDER BY pct_single_bid DESC
LIMIT 10;

-- Sentencia 3: oro, ya agregada
SELECT entity_department,
       sum(awarded_processes) AS awarded_processes,
       round(100.0 * sum(single_bid_processes) / sum(awarded_processes), 1)
           AS pct_single_bid
FROM secop.gold_competition_by_department_segment
WHERE year = 2025
GROUP BY entity_department
HAVING sum(awarded_processes) >= 100
ORDER BY pct_single_bid DESC
LIMIT 10;
