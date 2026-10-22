-- Parte A: borrar la vista y las tablas al terminar.
-- Borrar las tablas Iceberg borra también sus datos. Borrar bronze_processes
-- no borra el archivo: hay que vaciar y borrar el bucket en la consola de S3.
-- Ejecute UNA sentencia a la vez.

DROP VIEW secop.bronze_processes_checked;

DROP TABLE secop.gold_competition_by_department_segment;

DROP TABLE secop.silver_processes_rejected;

DROP TABLE secop.silver_processes;

DROP TABLE secop.bronze_processes;

DROP DATABASE secop;
