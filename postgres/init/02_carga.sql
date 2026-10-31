-- 02_carga.sql
-- Esquema de PASO (staging) para la carga masiva desde CSV (S14).
-- Se separa del esquema de negocio "biblioteca":
-- "biblioteca" guarda solo las tablas del sistema y "carga" guarda las tablas
-- de paso, que no tienen restricciones y se vacían al inicio de cada carga.
-- La bitácora de rechazos (biblioteca.rechazo_carga) sí queda en "biblioteca",
-- porque es un registro permanente que se consulta después de cada carga.

DROP SCHEMA IF EXISTS carga CASCADE;
CREATE SCHEMA carga;
SET search_path TO carga;

-- Una fila por línea del archivo, tal cual llega (todo como texto).
-- n numera las líneas en el orden de llegada: es el número que se reporta.
CREATE TABLE stg_linea (
    n      integer GENERATED ALWAYS AS IDENTITY,
    linea  text
);

-- Campos de cada línea de libros, todavía como texto, más el motivo de rechazo.
CREATE TABLE stg_libro (
    linea_csv               integer,
    contenido               text,
    num_campos              integer,
    isbn                    text,
    titulo                  text,
    autor                   text,
    categoria               text,
    anio_publicacion        text,
    ejemplares_disponibles  text,
    motivo                  text
);

-- Campos de cada línea de lectores, todavía como texto, más el motivo de rechazo.
CREATE TABLE stg_lector (
    linea_csv   integer,
    contenido   text,
    num_campos  integer,
    documento   text,
    nombres     text,
    apellidos   text,
    correo      text,
    telefono    text,
    motivo      text
);
