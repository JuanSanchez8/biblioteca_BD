-- Reporte 1: los 20 libros más prestados.
-- LEFT JOIN conserva libros sin préstamos (conteo 0); no entran al top 20
-- si hay al menos 20 libros con préstamos. WITH TIES incluye el empate
-- completo en el puesto 20. Con datos-prueba.sql se esperan 21 filas:
-- 19 libros con 3 préstamos y 2 empatados con 2.
\echo '== Reporte 1: los 20 libros más prestados (incluye empates) =='
WITH ranking AS (
    SELECT
        l.isbn,
        l.titulo,
        COUNT(p.isbn) AS total_prestamos
    FROM biblioteca.libros l
    LEFT JOIN biblioteca.prestamos p
        ON p.isbn = l.isbn
    GROUP BY
        l.isbn,
        l.titulo
    ORDER BY
        total_prestamos DESC
    FETCH FIRST 20 ROWS WITH TIES
)
SELECT
    isbn,
    titulo,
    total_prestamos
FROM ranking
ORDER BY
    total_prestamos DESC,
    titulo ASC;

-- Reporte 2: todos los lectores empatados con el máximo de préstamos devueltos.
-- Los préstamos abiertos no cuentan. Con datos-prueba.sql se esperan
-- Mariana Gómez Rojas y Santiago Rodríguez Pérez, con 21 cada uno.
\echo '== Reporte 2: lectores con más libros devueltos =='
WITH prestamos_por_lector AS (
    SELECT
        p.id_lector,
        COUNT(*) AS total_libros_leidos
    FROM biblioteca.prestamos p
    WHERE p.fecha_devolucion IS NOT NULL
    GROUP BY p.id_lector
),
maximo AS (
    SELECT MAX(total_libros_leidos) AS mayor_cantidad
    FROM prestamos_por_lector
)
SELECT
    u.id_usuario,
    u.nombres,
    u.apellidos,
    pl.total_libros_leidos
FROM prestamos_por_lector pl
JOIN biblioteca.usuarios u
    ON u.id_usuario = pl.id_lector
CROSS JOIN maximo m
WHERE u.rol = 'lector'
  AND pl.total_libros_leidos = m.mayor_cantidad
ORDER BY u.nombres, u.apellidos;

-- Reporte 3: cada lector con al menos un préstamo abierto vencido aparece
-- una sola vez. La mora usa fecha_vencimiento < CURRENT_DATE; vencer hoy
-- no cuenta. Con datos-prueba.sql se espera una fila: Juan David.
\echo '== Reporte 3: lectores morosos (una fila por lector) =='
SELECT
    u.id_usuario,
    u.nombres,
    u.apellidos,
    u.correo,
    u.telefono
FROM biblioteca.usuarios u
WHERE u.rol = 'lector'
  AND EXISTS (
      SELECT 1
      FROM biblioteca.prestamos p
      WHERE p.id_lector = u.id_usuario
        AND p.fecha_devolucion IS NULL
        AND p.fecha_vencimiento < CURRENT_DATE
  )
ORDER BY u.apellidos, u.nombres;

-- Reporte 4: una fila por préstamo abierto vencido, con contacto del lector.
-- Usa la misma regla estricta (< CURRENT_DATE), por lo que vencer hoy no
-- cuenta. Con datos-prueba.sql se esperan los dos préstamos de Juan David.
\echo '== Reporte 4: préstamos en mora para notificación =='
SELECT
    p.id_lector,
    u.nombres,
    u.apellidos,
    u.correo,
    u.telefono,
    p.isbn,
    l.titulo,
    p.fecha_hora_prestamo,
    p.fecha_vencimiento
FROM biblioteca.prestamos p
JOIN biblioteca.usuarios u
    ON u.id_usuario = p.id_lector
JOIN biblioteca.libros l
    ON l.isbn = p.isbn
WHERE p.fecha_devolucion IS NULL
  AND p.fecha_vencimiento < CURRENT_DATE
ORDER BY
    u.apellidos,
    u.nombres,
    p.fecha_vencimiento;