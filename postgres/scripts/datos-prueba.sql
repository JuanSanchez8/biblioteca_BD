-- ============================================================
-- S16 - Datos de prueba para los cuatro reportes de biblioteca
-- Base de datos: curso | Esquema: biblioteca
-- Script repetible: reemplaza solo los préstamos que él mismo registra.
-- Las columnas rol_lector y rol_bibliotecario son GENERATED ALWAYS.
-- Bibliotecario reservado para estas pruebas: id_usuario = 21.
-- Fechas relativas a CURRENT_DATE.
-- ============================================================

\set ON_ERROR_STOP on
BEGIN;

CREATE TABLE IF NOT EXISTS biblioteca.s16_control_prestamos_prueba (
    id_lector integer NOT NULL,
    isbn varchar NOT NULL,
    id_ejemplar integer NOT NULL,
    fecha_hora_prestamo timestamp without time zone NOT NULL,
    PRIMARY KEY (id_lector, isbn, id_ejemplar, fecha_hora_prestamo)
);

CREATE TEMP TABLE s16_nuevos_prestamos ON COMMIT DROP AS
WITH catalogo (isbn, cantidad) AS (
    VALUES
        ('9780000000014', 3), -- 1984
        ('9780000000019', 3), -- Alicia en el país de las maravillas
        ('9780000000020', 3), -- Breve historia del tiempo
        ('9780000000001', 3), -- Cien años de soledad
        ('9780000000011', 3), -- Como agua para chocolate
        ('9780000000021', 3), -- Cosmos
        ('9780000000026', 3), -- Crimen y castigo
        ('9780000000003', 3), -- Crónica de una muerte anunciada
        ('9780000000009', 3), -- Don Quijote de la Mancha
        ('9780000000029', 3), -- Drácula
        ('9780000000008', 3), -- El Aleph
        ('9780000000002', 3), -- El amor en los tiempos del cólera
        ('9780000000031', 3), -- El nombre del viento
        ('9780000000023', 3), -- El origen de las especies
        ('9780000000017', 3), -- El principito
        ('9780000000012', 3), -- El túnel
        ('9780000000016', 3), -- Fahrenheit 451
        ('9780000000007', 3), -- Ficciones
        ('9780000000030', 3), -- Frankenstein
        ('9780000000032', 2), -- Harry Potter y la piedra filosofal
        ('9780000000006', 2)  -- La casa de los espíritus
),
lectores (id_lector, dias_antes) AS (
    VALUES (1, 100), (2, 70), (3, 40)
),
devueltos AS (
    SELECT
        r.id_lector,
        c.isbn,
        1 AS id_ejemplar,
        (CURRENT_DATE - r.dias_antes)::timestamp + TIME '09:00'
            AS fecha_hora_prestamo,
        21 AS id_bibliotecario,
        CURRENT_DATE - r.dias_antes + 14 AS fecha_vencimiento,
        (
            CURRENT_DATE - r.dias_antes
            + CASE
                WHEN c.isbn = '9780000000014' AND r.id_lector = 1
                    THEN 20 -- devolución seis días tarde
                ELSE 10
              END
        )::date AS fecha_devolucion
    FROM catalogo c
    CROSS JOIN lectores r
    WHERE c.cantidad = 3 OR r.id_lector IN (1, 2)
),
abiertos AS (
    SELECT
        4 AS id_lector,
        '9780000000018'::varchar AS isbn,
        1 AS id_ejemplar,
        (CURRENT_DATE - 30)::timestamp + TIME '10:00'
            AS fecha_hora_prestamo,
        21 AS id_bibliotecario,
        CURRENT_DATE - 16 AS fecha_vencimiento,
        NULL::date AS fecha_devolucion
    UNION ALL
    SELECT
        4, '9780000000028'::varchar, 1,
        (CURRENT_DATE - 25)::timestamp + TIME '11:00',
        21, CURRENT_DATE - 11, NULL::date
    UNION ALL
    SELECT
        4, '9780000000027'::varchar, 1,
        (CURRENT_DATE - 14)::timestamp + TIME '12:00',
        21, CURRENT_DATE, NULL::date
)
SELECT * FROM devueltos
UNION ALL
SELECT * FROM abiertos;

-- Liberar los ejemplares usados por el conjunto anterior, si existía.
UPDATE biblioteca.ejemplares e
SET estado = 'disponible'
WHERE EXISTS (
    SELECT 1
    FROM biblioteca.s16_control_prestamos_prueba c
    WHERE c.isbn = e.isbn AND c.id_ejemplar = e.id_ejemplar
);

-- Borrar solo préstamos cuyas claves están registradas por este script.
DELETE FROM biblioteca.prestamos p
USING biblioteca.s16_control_prestamos_prueba c
WHERE p.id_lector = c.id_lector
  AND p.isbn = c.isbn
  AND p.id_ejemplar = c.id_ejemplar
  AND p.fecha_hora_prestamo = c.fecha_hora_prestamo;

DELETE FROM biblioteca.s16_control_prestamos_prueba;

-- No incluir las columnas de rol: PostgreSQL las genera automáticamente.
INSERT INTO biblioteca.prestamos (
    id_lector,
    isbn,
    id_ejemplar,
    fecha_hora_prestamo,
    id_bibliotecario,
    fecha_vencimiento,
    fecha_devolucion
)
SELECT
    id_lector,
    isbn,
    id_ejemplar,
    fecha_hora_prestamo,
    id_bibliotecario,
    fecha_vencimiento,
    fecha_devolucion
FROM s16_nuevos_prestamos;

-- Registrar las claves exactas para una ejecución repetible y segura.
INSERT INTO biblioteca.s16_control_prestamos_prueba (
    id_lector, isbn, id_ejemplar, fecha_hora_prestamo
)
SELECT id_lector, isbn, id_ejemplar, fecha_hora_prestamo
FROM s16_nuevos_prestamos;

-- Solo estos tres ejemplares quedan prestados al finalizar.
UPDATE biblioteca.ejemplares e
SET estado = 'prestado'
WHERE EXISTS (
    SELECT 1
    FROM s16_nuevos_prestamos t
    WHERE t.isbn = e.isbn
      AND t.id_ejemplar = e.id_ejemplar
      AND t.fecha_devolucion IS NULL
);

COMMIT;

-- Resumen de los préstamos pertenecientes a este conjunto de pruebas.
SELECT
    COUNT(*) AS total_prestamos,
    COUNT(*) FILTER (WHERE p.fecha_devolucion IS NOT NULL)
        AS prestamos_devueltos,
    COUNT(*) FILTER (WHERE p.fecha_devolucion IS NULL)
        AS prestamos_abiertos,
    COUNT(*) FILTER (
        WHERE p.fecha_devolucion IS NULL
          AND p.fecha_vencimiento < CURRENT_DATE
    ) AS prestamos_en_mora,
    COUNT(*) FILTER (
        WHERE p.fecha_devolucion IS NULL
          AND p.fecha_vencimiento = CURRENT_DATE
    ) AS prestamos_que_vencen_hoy
FROM biblioteca.prestamos p
JOIN biblioteca.s16_control_prestamos_prueba c
  ON p.id_lector = c.id_lector
 AND p.isbn = c.isbn
 AND p.id_ejemplar = c.id_ejemplar
 AND p.fecha_hora_prestamo = c.fecha_hora_prestamo;

-- Resumen por lector (incluye lectores sin préstamos).
SELECT
    u.id_usuario,
    u.nombres,
    u.apellidos,
    COUNT(p.isbn) AS total_prestamos,
    COUNT(p.isbn) FILTER (
        WHERE p.fecha_devolucion IS NOT NULL
    ) AS devueltos
FROM biblioteca.usuarios u
LEFT JOIN biblioteca.prestamos p
    ON p.id_lector = u.id_usuario
   AND EXISTS (
       SELECT 1
       FROM biblioteca.s16_control_prestamos_prueba c
       WHERE c.id_lector = p.id_lector
         AND c.isbn = p.isbn
         AND c.id_ejemplar = p.id_ejemplar
         AND c.fecha_hora_prestamo = p.fecha_hora_prestamo
   )
WHERE u.rol = 'lector'
GROUP BY u.id_usuario, u.nombres, u.apellidos
ORDER BY u.id_usuario;

-- Resumen por libro (incluye libros sin préstamos).
SELECT
    l.titulo,
    COUNT(p.isbn) AS total_prestamos
FROM biblioteca.libros l
LEFT JOIN biblioteca.prestamos p
    ON p.isbn = l.isbn
   AND EXISTS (
       SELECT 1
       FROM biblioteca.s16_control_prestamos_prueba c
       WHERE c.id_lector = p.id_lector
         AND c.isbn = p.isbn
         AND c.id_ejemplar = p.id_ejemplar
         AND c.fecha_hora_prestamo = p.fecha_hora_prestamo
   )
GROUP BY l.isbn, l.titulo
ORDER BY total_prestamos DESC, l.titulo;
