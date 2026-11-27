-- ============================================================
-- HITO 4 - Pruebas de programacion en la base de datos
-- Proyecto: Biblioteca
-- Motor: PostgreSQL
--
-- Requisitos:
--   1. Ejecutar programacion.sql.
--   2. Ejecutar datos-prueba.sql.
--
-- Las pruebas se realizan dentro de una transaccion.
-- ROLLBACK conserva los datos originales.
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- Obtener el identificador del bibliotecario de pruebas.

    SELECT set_config(
    'biblioteca.id_bibliotecario_prueba',
    id_usuario::text,
    true
)
FROM biblioteca.usuarios
WHERE documento = '9000000001'
  AND rol = 'bibliotecario';

SELECT set_config(
    'biblioteca.id_lector_prueba',
    id_usuario::text,
    true
)
FROM biblioteca.usuarios
WHERE documento = '1000000001'
  AND rol = 'lector';

SELECT set_config(
    'biblioteca.id_lector_moroso_prueba',
    id_usuario::text,
    true
)
FROM biblioteca.usuarios
WHERE documento = '1000000004'
  AND rol = 'lector';

-- ============================================================
-- PRUEBA 1: Funcion lector_en_mora
-- Esperado: Mariana sin mora y Juan David con mora.
-- ============================================================

DO $$
BEGIN
    IF biblioteca.lector_en_mora(
           current_setting('biblioteca.id_lector_prueba')::integer
       ) IS DISTINCT FROM false
       OR biblioteca.lector_en_mora(
           current_setting('biblioteca.id_lector_moroso_prueba')::integer
       ) IS DISTINCT FROM true THEN

        RAISE EXCEPTION 'PRUEBA 1 FALLIDA';

    END IF;

    RAISE NOTICE 'PRUEBA 1 OK: deteccion de mora';
END;
$$;


-- ============================================================
-- PRUEBA 2: Registrar un prestamo valido.
-- Esperado: prestamo abierto, plazo de 14 dias y
-- ejemplar en estado prestado.
-- ============================================================

DO $$
BEGIN
    CALL biblioteca.registrar_prestamo(
        current_setting('biblioteca.id_lector_prueba')::integer,
        '9780000000001',
        2,
        current_setting('biblioteca.id_bibliotecario_prueba')::integer
    );

    IF NOT EXISTS (
        SELECT 1
        FROM biblioteca.prestamos
        WHERE id_lector =
              current_setting('biblioteca.id_lector_prueba')::integer
          AND isbn = '9780000000001'
          AND id_ejemplar = 2
          AND fecha_devolucion IS NULL
          AND fecha_vencimiento = CURRENT_DATE + 14
    ) THEN
        RAISE EXCEPTION 'PRUEBA 2 FALLIDA: prestamo';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM biblioteca.ejemplares
        WHERE isbn = '9780000000001'
          AND id_ejemplar = 2
          AND estado = 'prestado'
    ) THEN
        RAISE EXCEPTION 'PRUEBA 2 FALLIDA: estado';
    END IF;

    RAISE NOTICE 'PRUEBA 2 OK: prestamo valido';
END;
$$;


-- ============================================================
-- PRUEBA 3: Registrar una devolucion valida.
-- Esperado: fecha de devolucion registrada y
-- ejemplar disponible.
-- ============================================================

DO $$
BEGIN
    CALL biblioteca.registrar_devolucion(
        current_setting('biblioteca.id_lector_prueba')::integer,
        '9780000000001',
        2
    );

    IF EXISTS (
        SELECT 1
        FROM biblioteca.prestamos
        WHERE id_lector =
              current_setting('biblioteca.id_lector_prueba')::integer
          AND isbn = '9780000000001'
          AND id_ejemplar = 2
          AND fecha_devolucion IS NULL
    ) THEN
        RAISE EXCEPTION 'PRUEBA 3 FALLIDA: devolucion';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM biblioteca.ejemplares
        WHERE isbn = '9780000000001'
          AND id_ejemplar = 2
          AND estado = 'disponible'
    ) THEN
        RAISE EXCEPTION 'PRUEBA 3 FALLIDA: estado';
    END IF;

    RAISE NOTICE 'PRUEBA 3 OK: devolucion valida';
END;
$$;


-- ============================================================
-- PRUEBA 4: Rechazar un lector en mora.
-- ============================================================

DO $$
BEGIN
    BEGIN
        CALL biblioteca.registrar_prestamo(
            current_setting('biblioteca.id_lector_moroso_prueba')::integer,
            '9780000000001',
            1,
            current_setting('biblioteca.id_bibliotecario_prueba')::integer
        );

        RAISE EXCEPTION 'PRUEBA 4 FALLIDA';

    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> format(
                'El lector %s tiene prestamos en mora',
                current_setting('biblioteca.id_lector_moroso_prueba')
            ) THEN
                RAISE;
            END IF;

            RAISE NOTICE 'PRUEBA 4 OK: lector moroso rechazado';
    END;
END;
$$;


-- ============================================================
-- PRUEBA 5: Rechazar un ejemplar prestado.
-- ============================================================

DO $$
BEGIN
    BEGIN
        CALL biblioteca.registrar_prestamo(
            current_setting('biblioteca.id_lector_prueba')::integer,
            '9780000000018',
            1,
            current_setting('biblioteca.id_bibliotecario_prueba')::integer
        );

        RAISE EXCEPTION 'PRUEBA 5 FALLIDA';

    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <>
                'El ejemplar no esta disponible. Estado: prestado'
            THEN
                RAISE;
            END IF;

            RAISE NOTICE 'PRUEBA 5 OK: ejemplar ocupado rechazado';
    END;
END;
$$;


-- ============================================================
-- PRUEBA 6: Rechazar una devolucion inexistente.
-- ============================================================

DO $$
BEGIN
    BEGIN
        CALL biblioteca.registrar_devolucion(
            999, '9780000000001', 1
        );

        RAISE EXCEPTION 'PRUEBA 6 FALLIDA';

    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <>
                'No existe un prestamo abierto para el lector 999, ISBN 9780000000001, ejemplar 1'
            THEN
                RAISE;
            END IF;

            RAISE NOTICE 'PRUEBA 6 OK: devolucion inexistente rechazada';
    END;
END;
$$;


-- ============================================================
-- PRUEBA 7: Trigger BEFORE.
-- Intentar insertar directamente un prestamo a un moroso.
-- ============================================================

DO $$
BEGIN
    BEGIN
        INSERT INTO biblioteca.prestamos (
            id_lector,
            isbn,
            id_ejemplar,
            id_bibliotecario,
            fecha_vencimiento
        )
        VALUES (
            current_setting('biblioteca.id_lector_moroso_prueba')::integer,
            '9780000000001',
            1,
            current_setting('biblioteca.id_bibliotecario_prueba')::integer,
            CURRENT_DATE + 14
        );

        RAISE EXCEPTION 'PRUEBA 7 FALLIDA';

    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <> format(
                'El lector %s tiene prestamos en mora',
                current_setting('biblioteca.id_lector_moroso_prueba')
            ) THEN
                RAISE;
            END IF;

            RAISE NOTICE 'PRUEBA 7 OK: trigger BEFORE protege INSERT';
    END;
END;
$$;


-- ============================================================
-- PRUEBA 8: Impedir reapertura de un prestamo devuelto.
-- ============================================================

DO $$
BEGIN
    BEGIN
        UPDATE biblioteca.prestamos
        SET fecha_devolucion = NULL
        WHERE id_lector =
              current_setting('biblioteca.id_lector_prueba')::integer
          AND isbn = '9780000000001'
          AND id_ejemplar = 2
          AND fecha_devolucion IS NOT NULL;

        RAISE EXCEPTION 'PRUEBA 8 FALLIDA';

    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <>
                'No se puede reabrir un prestamo devuelto'
            THEN
                RAISE;
            END IF;

            RAISE NOTICE 'PRUEBA 8 OK: reapertura rechazada';
    END;
END;
$$;


-- ============================================================
-- PRUEBA 9: Impedir cambios inconsistentes de estado.
-- ============================================================

DO $$
BEGIN
    BEGIN
        UPDATE biblioteca.ejemplares
        SET estado = 'disponible'
        WHERE isbn = '9780000000018'
          AND id_ejemplar = 1;

        RAISE EXCEPTION 'PRUEBA 9 FALLIDA';

    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <>
                'El estado del ejemplar no coincide con sus prestamos abiertos'
            THEN
                RAISE;
            END IF;

            RAISE NOTICE 'PRUEBA 9 OK: estado inconsistente rechazado';
    END;
END;
$$;


-- ============================================================
-- PRUEBA 10: Permitir mantenimiento de ejemplar disponible.
-- ============================================================

DO $$
BEGIN
    UPDATE biblioteca.ejemplares
    SET estado = 'en_mantenimiento'
    WHERE isbn = '9780000000001'
      AND id_ejemplar = 2;

    IF NOT EXISTS (
        SELECT 1
        FROM biblioteca.ejemplares
        WHERE isbn = '9780000000001'
          AND id_ejemplar = 2
          AND estado = 'en_mantenimiento'
    ) THEN
        RAISE EXCEPTION 'PRUEBA 10 FALLIDA';
    END IF;

    RAISE NOTICE 'PRUEBA 10 OK: mantenimiento permitido';
END;
$$;


-- ============================================================
-- PRUEBA 11: Impedir modificaciones de identidad.
-- ============================================================

DO $$
BEGIN
    BEGIN
        UPDATE biblioteca.prestamos
        SET id_lector =
            current_setting('biblioteca.id_lector_prueba')::integer
        WHERE id_lector =
              current_setting('biblioteca.id_lector_moroso_prueba')::integer
          AND isbn = '9780000000018'
          AND fecha_devolucion IS NULL;

        RAISE EXCEPTION 'PRUEBA 11 FALLIDA';

    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM <>
                'No se permite modificar la identidad del prestamo'
            THEN
                RAISE;
            END IF;

            RAISE NOTICE 'PRUEBA 11 OK: identidad protegida';
    END;
END;
$$;


-- ============================================================
-- PRUEBA 12: Consistencia global.
-- Esperado: cero ejemplares inconsistentes.
-- ============================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM biblioteca.ejemplares e
        WHERE (e.estado = 'prestado')
        IS DISTINCT FROM EXISTS (
            SELECT 1
            FROM biblioteca.prestamos p
            WHERE p.isbn = e.isbn
              AND p.id_ejemplar = e.id_ejemplar
              AND p.fecha_devolucion IS NULL
        )
    ) THEN
        RAISE EXCEPTION 'PRUEBA 12 FALLIDA';
    END IF;

    RAISE NOTICE 'PRUEBA 12 OK: consistencia global';
END;
$$;


-- ============================================================
-- Revertir todos los cambios realizados durante las pruebas.
-- ============================================================

ROLLBACK;

SELECT '12 PRUEBAS SUPERADAS CORRECTAMENTE' AS resultado;

SELECT COUNT(*) AS total_prestamos
FROM biblioteca.prestamos;