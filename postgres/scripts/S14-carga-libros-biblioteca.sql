-- S14. Carga de libros al esquema definitivo biblioteca.
-- Convierte cada fila valida en libro, autor, categoria y ejemplares.
-- Las filas rechazadas quedan en biblioteca.rechazo_carga.
-- Para elegir otro archivo, ejecutar psql con -v archivo=/scripts/datos/....
\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/libros_semilla.csv
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

CREATE TEMP TABLE stg_libro (
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
) ON COMMIT DROP;

COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;

INSERT INTO stg_libro (
    linea_csv, contenido, num_campos, isbn, titulo, autor, categoria,
    anio_publicacion, ejemplares_disponibles
)
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       trim(split_part(linea, ',', 4)),
       trim(split_part(linea, ',', 5)),
       trim(split_part(linea, ',', 6))
FROM stg_linea;

UPDATE stg_libro SET motivo = CASE
    WHEN num_campos <> 6 THEN
        'tiene ' || num_campos || ' columnas, se esperaban 6'
    WHEN isbn = '' THEN 'isbn vacío'
    WHEN isbn !~ '^[0-9]{10}([0-9]{3})?$' THEN 'isbn no tiene 10 o 13 dígitos'
    WHEN titulo = '' THEN 'título vacío'
    WHEN char_length(titulo) > 200 THEN 'título supera 200 caracteres'
    WHEN autor = '' THEN 'autor vacío'
    WHEN char_length(autor) > 120 THEN 'autor supera 120 caracteres'
    WHEN categoria = '' THEN 'categoría vacía'
    WHEN char_length(categoria) > 60 THEN 'categoría supera 60 caracteres'
    WHEN anio_publicacion <> ''
         AND anio_publicacion !~ '^[0-9]{1,4}$' THEN 'año no numérico'
    WHEN anio_publicacion <> ''
         AND anio_publicacion::integer NOT BETWEEN 1000 AND 2100 THEN
        'año fuera del rango permitido (1000-2100)'
    WHEN ejemplares_disponibles !~ '^-?[0-9]{1,9}$' THEN
        'ejemplares no numérico'
    WHEN ejemplares_disponibles::integer < 0 THEN 'ejemplares negativo'
    WHEN EXISTS (
        SELECT 1
        FROM biblioteca.libros l
        WHERE l.isbn = stg_libro.isbn
    ) THEN 'isbn ya existe en el catálogo'
END;

UPDATE stg_libro AS actual
SET motivo = 'isbn repetido en el archivo (línea ' || anterior.linea_csv || ')'
FROM (
    SELECT isbn, min(linea_csv) AS linea_csv
    FROM stg_libro
    WHERE motivo IS NULL
    GROUP BY isbn
    HAVING count(*) > 1
) AS anterior
WHERE actual.motivo IS NULL
  AND actual.isbn = anterior.isbn
  AND actual.linea_csv > anterior.linea_csv;

INSERT INTO biblioteca.categorias (genero)
SELECT DISTINCT categoria
FROM stg_libro AS s
WHERE s.motivo IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM biblioteca.categorias AS c
      WHERE c.genero = s.categoria
  )
ON CONFLICT (genero) DO NOTHING;

INSERT INTO biblioteca.autor (nombre_autor)
SELECT DISTINCT s.autor
FROM stg_libro AS s
WHERE s.motivo IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM biblioteca.autor AS a
      WHERE a.nombre_autor = s.autor
  );

INSERT INTO biblioteca.libros (
    isbn, id_categoria, id_autor, titulo, anio_publicacion
)
SELECT s.isbn, c.id_categoria, a.id_autor, s.titulo,
       NULLIF(s.anio_publicacion, '')::integer
FROM stg_libro AS s
JOIN biblioteca.categorias AS c ON c.genero = s.categoria
JOIN biblioteca.autor AS a ON a.nombre_autor = s.autor
WHERE s.motivo IS NULL;

INSERT INTO biblioteca.ejemplares (isbn, id_ejemplar)
SELECT s.isbn, copia.n
FROM stg_libro AS s
CROSS JOIN LATERAL generate_series(
    1, s.ejemplares_disponibles::integer
) AS copia(n)
WHERE s.motivo IS NULL;

INSERT INTO biblioteca.rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_libro
WHERE motivo IS NOT NULL;

SELECT count(*) FILTER (WHERE motivo IS NULL) AS libros_cargados,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS filas_rechazadas
FROM stg_libro;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_libro
WHERE motivo IS NOT NULL
ORDER BY linea_csv;

COMMIT;
