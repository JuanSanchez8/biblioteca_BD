-- S14. Carga de lectores al esquema definitivo biblioteca.
-- Inserta usuarios con rol lector y registra rechazos en biblioteca.rechazo_carga.
-- Para elegir otro archivo, ejecutar psql con -v archivo=/scripts/datos/....
\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/lectores_semilla.csv
\endif

BEGIN;

CREATE TABLE IF NOT EXISTS biblioteca.rechazo_carga (
    id         integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    archivo    text        NOT NULL,
    linea      integer     NOT NULL,
    contenido  text        NOT NULL,
    motivo     text        NOT NULL,
    fecha      timestamptz NOT NULL DEFAULT now()
);

CREATE TEMP TABLE stg_linea (
    n      integer GENERATED ALWAYS AS IDENTITY,
    linea  text
) ON COMMIT DROP;

CREATE TEMP TABLE stg_lector (
    linea_csv   integer,
    contenido   text,
    num_campos  integer,
    documento   text,
    nombres     text,
    apellidos   text,
    correo      text,
    telefono    text,
    motivo      text
) ON COMMIT DROP;

COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;

INSERT INTO stg_lector (
    linea_csv, contenido, num_campos, documento, nombres, apellidos,
    correo, telefono
)
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       lower(trim(split_part(linea, ',', 4))),
       trim(split_part(linea, ',', 5))
FROM stg_linea;

UPDATE stg_lector SET motivo = CASE
    WHEN num_campos <> 5 THEN
        'tiene ' || num_campos || ' columnas, se esperaban 5'
    WHEN documento = '' THEN 'documento vacío'
    WHEN documento !~ '^[0-9]{6,15}$' THEN
        'documento no numérico o de longitud inválida'
    WHEN nombres = '' THEN 'nombres vacío'
    WHEN char_length(nombres) > 80 THEN 'nombres supera 80 caracteres'
    WHEN apellidos = '' THEN 'apellidos vacío'
    WHEN char_length(apellidos) > 80 THEN 'apellidos supera 80 caracteres'
    WHEN correo = '' THEN 'correo vacío'
    WHEN char_length(correo) > 120 THEN 'correo supera 120 caracteres'
    WHEN correo !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$' THEN 'correo mal formado'
    WHEN telefono <> '' AND telefono !~ '^[0-9]{7,15}$' THEN
        'teléfono no numérico o de longitud inválida'
    WHEN EXISTS (
        SELECT 1
        FROM biblioteca.usuarios AS u
        WHERE u.documento = stg_lector.documento
    ) THEN 'documento ya registrado'
    WHEN EXISTS (
        SELECT 1
        FROM biblioteca.usuarios AS u
        WHERE lower(u.correo) = stg_lector.correo
    ) THEN 'correo ya registrado'
END;

UPDATE stg_lector AS actual
SET motivo = 'documento o correo repetido en el archivo (línea '
             || anterior.linea_csv || ')'
FROM (
    SELECT documento, min(linea_csv) AS linea_csv
    FROM stg_lector
    WHERE motivo IS NULL
    GROUP BY documento
    HAVING count(*) > 1
) AS anterior
WHERE actual.motivo IS NULL
  AND actual.documento = anterior.documento
  AND actual.linea_csv > anterior.linea_csv;

UPDATE stg_lector AS actual
SET motivo = 'correo repetido en el archivo (línea '
             || anterior.linea_csv || ')'
FROM (
    SELECT correo, min(linea_csv) AS linea_csv
    FROM stg_lector
    WHERE motivo IS NULL
    GROUP BY correo
    HAVING count(*) > 1
) AS anterior
WHERE actual.motivo IS NULL
  AND actual.correo = anterior.correo
  AND actual.linea_csv > anterior.linea_csv;

INSERT INTO biblioteca.usuarios (
    documento, nombres, apellidos, correo, telefono, rol
)
SELECT documento, nombres, apellidos, correo, NULLIF(telefono, ''), 'lector'
FROM stg_lector
WHERE motivo IS NULL;

INSERT INTO biblioteca.rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_lector
WHERE motivo IS NOT NULL;

SELECT count(*) FILTER (WHERE motivo IS NULL) AS lectores_cargados,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS filas_rechazadas
FROM stg_lector;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_lector
WHERE motivo IS NOT NULL
ORDER BY linea_csv;

COMMIT;
