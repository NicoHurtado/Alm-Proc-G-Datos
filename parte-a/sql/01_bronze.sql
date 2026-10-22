-- Parte A, paso 2: capa bronce, los datos tal como llegaron de datos.gov.co.
-- Reemplace YOUR_BUCKET por el nombre de su bucket.
-- En el editor de Athena ejecute UNA sentencia a la vez.

-- Sentencia 1: la base de datos del trabajo
CREATE DATABASE IF NOT EXISTS secop;

-- Sentencia 2: tabla externa sobre el archivo, con todas las columnas como texto
CREATE EXTERNAL TABLE secop.bronze_processes (
    entidad                        string,
    nit_entidad                    string,
    departamento_entidad           string,
    ciudad_entidad                 string,
    ordenentidad                   string,
    codigo_pci                     string,
    id_del_proceso                 string,
    referencia_del_proceso         string,
    ppi                            string,
    id_del_portafolio              string,
    nombre_del_procedimiento       string,
    descripci_n_del_procedimiento  string,
    fase                           string,
    fecha_de_publicacion_del       string,
    fecha_de_ultima_publicaci      string,
    fecha_de_publicacion_fase      string,
    fecha_de_publicacion_fase_1    string,
    fecha_de_publicacion           string,
    fecha_de_publicacion_fase_2    string,
    fecha_de_publicacion_fase_3    string,
    precio_base                    string,
    modalidad_de_contratacion      string,
    justificaci_n_modalidad_de     string,
    duracion                       string,
    unidad_de_duracion             string,
    fecha_de_recepcion_de          string,
    fecha_de_apertura_de_respuesta string,
    fecha_de_apertura_efectiva     string,
    ciudad_de_la_unidad_de         string,
    nombre_de_la_unidad_de         string,
    proveedores_invitados          string,
    proveedores_con_invitacion     string,
    visualizaciones_del            string,
    proveedores_que_manifestaron   string,
    respuestas_al_procedimiento    string,
    respuestas_externas            string,
    conteo_de_respuestas_a_ofertas string,
    proveedores_unicos_con         string,
    numero_de_lotes                string,
    estado_del_procedimiento       string,
    id_estado_del_procedimiento    string,
    adjudicado                     string,
    id_adjudicacion                string,
    codigoproveedor                string,
    departamento_proveedor         string,
    ciudad_proveedor               string,
    fecha_adjudicacion             string,
    valor_total_adjudicacion       string,
    nombre_del_adjudicador         string,
    nombre_del_proveedor           string,
    nit_del_proveedor_adjudicado   string,
    codigo_principal_de_categoria  string,
    estado_de_apertura_del_proceso string,
    tipo_de_contrato               string,
    subtipo_de_contrato            string,
    categorias_adicionales         string,
    urlproceso                     string,
    codigo_entidad                 string,
    estado_resumen                 string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://YOUR_BUCKET/bronze/secop_processes/';

-- Sentencia 3: cuántas filas llegaron
SELECT count(*) AS bronze_rows FROM secop.bronze_processes;

-- Sentencia 4: las primeras filas
SELECT * FROM secop.bronze_processes LIMIT 10;
