-- ============================================================
-- S16 - Datos de prueba para los cuatro reportes de biblioteca
-- Base de datos: curso | Esquema: biblioteca
-- Script repetible: reemplaza solo los préstamos que él mismo registra.
-- Las columnas rol_lector y rol_bibliotecario son GENERATED ALWAYS.
-- Crea o reutiliza el bibliotecario de pruebas, sin asumir su ID.
-- Fechas relativas a CURRENT_DATE.
-- ============================================================

\set ON_ERROR_STOP on
BEGIN;



INSERT INTO biblioteca.usuarios (
    documento, nombres, apellidos, correo, rol
)
VALUES (
    '9000000001', 'Bibliotecario', 'Pruebas',
    'bibliotecario.pruebas@curso.edu.co', 'bibliotecario'
)
ON CONFLICT DO NOTHING;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM biblioteca.usuarios
        WHERE documento = '9000000001'
          AND rol = 'bibliotecario'
    ) THEN
        RAISE EXCEPTION
            'No existe un bibliotecario de pruebas válido con documento 9000000001';
    END IF;
END;
$$;

SELECT id_usuario AS id_bibliotecario
FROM biblioteca.usuarios
WHERE documento = '9000000001'
  AND rol = 'bibliotecario'
\gset

DO $$
DECLARE
    faltantes text;
BEGIN
    SELECT string_agg(r.documento, ', ' ORDER BY r.documento)
    INTO faltantes
    FROM (VALUES
        ('1000000001'),
        ('1000000002'),
        ('1000000003'),
        ('1000000004')
    ) AS r(documento)
    WHERE NOT EXISTS (
        SELECT 1
        FROM biblioteca.usuarios u
        WHERE u.documento = r.documento
          AND u.rol = 'lector'
    );

    IF faltantes IS NOT NULL THEN
        RAISE EXCEPTION
            'Faltan lectores requeridos para los datos de prueba (documentos: %). Cargue lectores_semilla.csv primero.',
            faltantes;
    END IF;
END;
$$;

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
lectores AS (
    SELECT u.id_usuario AS id_lector, r.documento, r.dias_antes
    FROM (VALUES
        ('1000000001', 100),
        ('1000000002', 70),
        ('1000000003', 40),
        ('1000000004', 30)
    ) AS r(documento, dias_antes)
    JOIN biblioteca.usuarios u
      ON u.documento = r.documento
     AND u.rol = 'lector'
),
devueltos AS (
    SELECT
        r.id_lector,
        c.isbn,
        1 AS id_ejemplar,
        (CURRENT_DATE - r.dias_antes)::timestamp + TIME '09:00'
            AS fecha_hora_prestamo,
        :id_bibliotecario AS id_bibliotecario,
        CURRENT_DATE - r.dias_antes + 14 AS fecha_vencimiento,
        (
            CURRENT_DATE - r.dias_antes
            + CASE
                WHEN c.isbn = '9780000000014'
                     AND r.documento = '1000000001'
                    THEN 20 -- devolución seis días tarde
                ELSE 10
              END
        )::date AS fecha_devolucion
    FROM catalogo c
    CROSS JOIN lectores r
    WHERE r.documento <> '1000000004'
      AND (
          c.cantidad = 3
          OR r.documento IN ('1000000001', '1000000002')
      )
),
abiertos AS (
    SELECT
        r.id_lector,
        '9780000000018'::varchar AS isbn,
        1 AS id_ejemplar,
        (CURRENT_DATE - 30)::timestamp + TIME '10:00'
            AS fecha_hora_prestamo,
        :id_bibliotecario AS id_bibliotecario,
        CURRENT_DATE - 16 AS fecha_vencimiento,
        NULL::date AS fecha_devolucion
    FROM lectores r
    WHERE r.documento = '1000000004'
    UNION ALL
    SELECT
        r.id_lector, '9780000000028'::varchar, 1,
        (CURRENT_DATE - 25)::timestamp + TIME '11:00',
        :id_bibliotecario, CURRENT_DATE - 11, NULL::date
    FROM lectores r
    WHERE r.documento = '1000000004'
    UNION ALL
    SELECT
        r.id_lector, '9780000000027'::varchar, 1,
        (CURRENT_DATE - 14)::timestamp + TIME '12:00',
        :id_bibliotecario, CURRENT_DATE, NULL::date
    FROM lectores r
    WHERE r.documento = '1000000004'
)
SELECT * FROM devueltos
UNION ALL
SELECT * FROM abiertos;

-- Borrar solo préstamos cuyas claves están registradas por este script.
DELETE FROM biblioteca.prestamos p
USING biblioteca.s16_control_prestamos_prueba c
WHERE p.id_lector = c.id_lector
  AND p.isbn = c.isbn
  AND p.id_ejemplar = c.id_ejemplar
  AND p.fecha_hora_prestamo = c.fecha_hora_prestamo;

DELETE FROM biblioteca.s16_control_prestamos_prueba;

-- Carga controlada de datos historicos de S16.
-- Los prestamos vencidos son intencionales para probar
-- los reportes de mora y vencimientos.
-- Se desactiva exclusivamente el trigger de validacion
-- de nuevos prestamos durante esta carga de prueba.

ALTER TABLE biblioteca.prestamos
DISABLE TRIGGER prestamo_validar;

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

ALTER TABLE biblioteca.prestamos
ENABLE TRIGGER prestamo_validar;

-- Registrar las claves exactas para una ejecución repetible y segura.
INSERT INTO biblioteca.s16_control_prestamos_prueba (
    id_lector, isbn, id_ejemplar, fecha_hora_prestamo
)
SELECT id_lector, isbn, id_ejemplar, fecha_hora_prestamo
FROM s16_nuevos_prestamos;

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

-- Caso 1: hacer visible que un libro sin préstamos queda con conteo cero;
-- no aparece en el top 20 cuando hay al menos 20 libros prestados.
SELECT
    l.isbn,
    l.titulo,
    COUNT(p.isbn) AS total_prestamos
FROM biblioteca.libros l
LEFT JOIN biblioteca.prestamos p
    ON p.isbn = l.isbn
GROUP BY l.isbn, l.titulo
HAVING COUNT(p.isbn) = 0
ORDER BY l.isbn
LIMIT 1;