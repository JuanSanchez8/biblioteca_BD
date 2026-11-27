-- ============================================================
-- HITO 4 - Programacion en la base de datos
-- Proyecto Biblioteca
-- PostgreSQL 16
-- ============================================================

BEGIN;

SET search_path TO biblioteca;

-- ============================================================
-- 1. FUNCION: lector_en_mora
-- Regla: un lector esta en mora cuando tiene al menos
-- un prestamo abierto cuya fecha de vencimiento ya paso.
-- ============================================================

CREATE OR REPLACE FUNCTION biblioteca.lector_en_mora(
    p_id_lector integer
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM biblioteca.prestamos p
        WHERE p.id_lector = p_id_lector
          AND p.fecha_devolucion IS NULL
          AND p.fecha_vencimiento < CURRENT_DATE
    );
$$;

-- ============================================================
-- 2. PROCEDIMIENTO: registrar_prestamo
-- Regla: registrar un prestamo validando el lector,
-- el bibliotecario y la disponibilidad del ejemplar.
-- Plazo por defecto: 14 dias.
-- ============================================================

CREATE OR REPLACE PROCEDURE biblioteca.registrar_prestamo(
    p_id_lector integer,
    p_isbn varchar,
    p_id_ejemplar integer,
    p_id_bibliotecario integer,
    p_dias integer DEFAULT 14
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado varchar(20);
BEGIN

    -- 1. Validar el lector.
    IF NOT EXISTS (
        SELECT 1
        FROM biblioteca.usuarios
        WHERE id_usuario = p_id_lector
          AND rol = 'lector'
          AND usuario_activo = true
    ) THEN
        RAISE EXCEPTION
            'El lector % no existe o no esta activo',
            p_id_lector;
    END IF;

    -- 2. Validar que el lector no tenga mora.
    IF biblioteca.lector_en_mora(p_id_lector) THEN
        RAISE EXCEPTION
            'El lector % tiene prestamos en mora',
            p_id_lector;
    END IF;

    -- 3. Validar el bibliotecario.
    IF NOT EXISTS (
        SELECT 1
        FROM biblioteca.usuarios
        WHERE id_usuario = p_id_bibliotecario
          AND rol = 'bibliotecario'
          AND usuario_activo = true
    ) THEN
        RAISE EXCEPTION
            'El bibliotecario % no existe o no esta activo',
            p_id_bibliotecario;
    END IF;

    -- 4. Validar el libro.
    IF NOT EXISTS (
        SELECT 1
        FROM biblioteca.libros
        WHERE isbn = p_isbn
          AND libro_activo = true
    ) THEN
        RAISE EXCEPTION
            'El libro % no existe o no esta activo',
            p_isbn;
    END IF;

    -- 5. Consultar y bloquear el ejemplar.
    SELECT estado
    INTO v_estado
    FROM biblioteca.ejemplares
    WHERE isbn = p_isbn
      AND id_ejemplar = p_id_ejemplar
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'El ejemplar % del libro % no existe',
            p_id_ejemplar, p_isbn;
    END IF;

    -- 6. Validar disponibilidad.
    IF v_estado <> 'disponible' THEN
        RAISE EXCEPTION
            'El ejemplar no esta disponible. Estado: %',
            v_estado;
    END IF;

    -- 7. Validar que no tenga un prestamo abierto.
    IF EXISTS (
        SELECT 1
        FROM biblioteca.prestamos
        WHERE isbn = p_isbn
          AND id_ejemplar = p_id_ejemplar
          AND fecha_devolucion IS NULL
    ) THEN
        RAISE EXCEPTION
            'El ejemplar ya tiene un prestamo abierto';
    END IF;

    -- 8. Validar el plazo.
    IF p_dias IS NULL OR p_dias <= 0 THEN
        RAISE EXCEPTION
            'El plazo del prestamo debe ser positivo';
    END IF;

    -- 9. Registrar el prestamo.
    INSERT INTO biblioteca.prestamos (
        id_lector,
        isbn,
        id_ejemplar,
        fecha_hora_prestamo,
        id_bibliotecario,
        fecha_vencimiento,
        fecha_devolucion
    )
    VALUES (
        p_id_lector,
        p_isbn,
        p_id_ejemplar,
        now(),
        p_id_bibliotecario,
        CURRENT_DATE + p_dias,
        NULL
    );

    RAISE NOTICE
        'Prestamo registrado correctamente para el lector %',
        p_id_lector;

END;
$$;

-- ============================================================
-- 3. PROCEDIMIENTO: registrar_devolucion
-- Regla: solo se puede devolver un ejemplar que tenga
-- un prestamo abierto para el lector indicado.
-- ============================================================

CREATE OR REPLACE PROCEDURE biblioteca.registrar_devolucion(
    p_id_lector integer,
    p_isbn varchar,
    p_id_ejemplar integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_fecha_vencimiento date;
    v_dias_mora integer;
BEGIN

    -- 1. Registrar la devolucion del prestamo abierto.
    UPDATE biblioteca.prestamos
    SET fecha_devolucion = CURRENT_DATE
    WHERE id_lector = p_id_lector
      AND isbn = p_isbn
      AND id_ejemplar = p_id_ejemplar
      AND fecha_devolucion IS NULL
    RETURNING fecha_vencimiento
    INTO v_fecha_vencimiento;

    -- 2. Verificar que existia un prestamo abierto.
    IF NOT FOUND THEN
        RAISE EXCEPTION
            'No existe un prestamo abierto para el lector %, ISBN %, ejemplar %',
            p_id_lector, p_isbn, p_id_ejemplar;
    END IF;

    -- 3. Calcular los dias de retraso.
    v_dias_mora := GREATEST(
        CURRENT_DATE - v_fecha_vencimiento,
        0
    );

    -- 4. Informar el resultado.
    IF v_dias_mora > 0 THEN
        RAISE NOTICE
            'Devolucion registrada con % dias de retraso',
            v_dias_mora;
    ELSE
        RAISE NOTICE
            'Devolucion registrada correctamente, sin retraso';
    END IF;

END;
$$;

-- ============================================================
-- 4. FUNCION DE TRIGGER: validar_prestamo
-- Regla: impedir nuevos prestamos a lectores morosos
-- o inactivos y ejemplares no disponibles.
-- Protege tambien las inserciones directas.
-- ============================================================

CREATE OR REPLACE FUNCTION biblioteca.validar_prestamo()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado varchar(20);
BEGIN

    -- Los prestamos historicos ya devueltos no
    -- representan nuevas solicitudes de prestamo.
    IF NEW.fecha_devolucion IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Validar que el lector exista y este activo.
    IF NOT EXISTS (
        SELECT 1
        FROM biblioteca.usuarios
        WHERE id_usuario = NEW.id_lector
          AND rol = 'lector'
          AND usuario_activo = true
    ) THEN
        RAISE EXCEPTION
            'El lector % no existe o no esta activo',
            NEW.id_lector;
    END IF;

    -- Validar que el lector no tenga mora.
    IF biblioteca.lector_en_mora(NEW.id_lector) THEN
        RAISE EXCEPTION
            'El lector % tiene prestamos en mora',
            NEW.id_lector;
    END IF;

    -- Validar que el bibliotecario este activo.
    IF NOT EXISTS (
        SELECT 1
        FROM biblioteca.usuarios
        WHERE id_usuario = NEW.id_bibliotecario
          AND rol = 'bibliotecario'
          AND usuario_activo = true
    ) THEN
        RAISE EXCEPTION
            'El bibliotecario % no existe o no esta activo',
            NEW.id_bibliotecario;
    END IF;

    -- Validar que el libro este activo.
    IF NOT EXISTS (
        SELECT 1
        FROM biblioteca.libros
        WHERE isbn = NEW.isbn
          AND libro_activo = true
    ) THEN
        RAISE EXCEPTION
            'El libro % no existe o no esta activo',
            NEW.isbn;
    END IF;

    -- Consultar y bloquear el ejemplar.
    SELECT estado
    INTO v_estado
    FROM biblioteca.ejemplares
    WHERE isbn = NEW.isbn
      AND id_ejemplar = NEW.id_ejemplar
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'El ejemplar solicitado no existe';
    END IF;

    -- Validar disponibilidad.
    IF v_estado <> 'disponible' THEN
        RAISE EXCEPTION
            'El ejemplar no esta disponible. Estado: %',
            v_estado;
    END IF;

    RETURN NEW;

END;
$$;


-- ============================================================
-- 5. TRIGGER BEFORE: prestamo_validar
-- Ejecuta las validaciones antes de insertar un prestamo.
-- ============================================================

DROP TRIGGER IF EXISTS prestamo_validar
ON biblioteca.prestamos;

CREATE TRIGGER prestamo_validar
BEFORE INSERT ON biblioteca.prestamos
FOR EACH ROW
EXECUTE FUNCTION biblioteca.validar_prestamo();

-- ============================================================
-- 6. FUNCION DE TRIGGER: actualizar_estado_ejemplar
-- Regla: un ejemplar esta prestado si tiene un prestamo
-- abierto. Al cerrar el prestamo, vuelve a estar disponible.
-- Mantiene la desnormalizacion documentada en el Hito 3.
-- ============================================================

CREATE OR REPLACE FUNCTION biblioteca.actualizar_estado_ejemplar()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    -- 1. Revisar el ejemplar anterior cuando se modifica
    -- o elimina un prestamo abierto.
    IF TG_OP IN ('UPDATE', 'DELETE') THEN

        IF OLD.fecha_devolucion IS NULL THEN

            UPDATE biblioteca.ejemplares e
            SET estado = 'disponible'
            WHERE e.isbn = OLD.isbn
              AND e.id_ejemplar = OLD.id_ejemplar
              AND e.estado = 'prestado'
              AND NOT EXISTS (
                  SELECT 1
                  FROM biblioteca.prestamos p
                  WHERE p.isbn = e.isbn
                    AND p.id_ejemplar = e.id_ejemplar
                    AND p.fecha_devolucion IS NULL
              );

        END IF;

    END IF;

    -- 2. Marcar como prestado el ejemplar asociado
    -- a un prestamo abierto.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN

        IF NEW.fecha_devolucion IS NULL THEN

            UPDATE biblioteca.ejemplares
            SET estado = 'prestado'
            WHERE isbn = NEW.isbn
              AND id_ejemplar = NEW.id_ejemplar;

        END IF;

    END IF;

    -- El valor retornado por un trigger AFTER se ignora.
    RETURN NULL;

END;
$$;


-- ============================================================
-- 7. TRIGGER AFTER: prestamo_actualizar_estado
-- Sincroniza prestamos con el estado de los ejemplares.
-- ============================================================

DROP TRIGGER IF EXISTS prestamo_actualizar_estado
ON biblioteca.prestamos;

CREATE TRIGGER prestamo_actualizar_estado
AFTER INSERT OR UPDATE OR DELETE
ON biblioteca.prestamos
FOR EACH ROW
EXECUTE FUNCTION biblioteca.actualizar_estado_ejemplar();

-- ============================================================
-- 8. FUNCION DE TRIGGER: proteger_prestamo
-- Regla: proteger la identidad del prestamo y evitar
-- la reapertura de prestamos devueltos.
-- ============================================================

CREATE OR REPLACE FUNCTION biblioteca.proteger_prestamo()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    -- Proteger los datos que identifican el prestamo.
    IF NEW.id_lector IS DISTINCT FROM OLD.id_lector
       OR NEW.isbn IS DISTINCT FROM OLD.isbn
       OR NEW.id_ejemplar IS DISTINCT FROM OLD.id_ejemplar
       OR NEW.fecha_hora_prestamo IS DISTINCT FROM
          OLD.fecha_hora_prestamo THEN

        RAISE EXCEPTION
            'No se permite modificar la identidad del prestamo';

    END IF;

    -- Impedir la reapertura de un prestamo devuelto.
    IF OLD.fecha_devolucion IS NOT NULL
       AND NEW.fecha_devolucion IS NULL THEN

        RAISE EXCEPTION
            'No se puede reabrir un prestamo devuelto';

    END IF;

    RETURN NEW;

END;
$$;


-- ============================================================
-- 9. TRIGGER BEFORE UPDATE: prestamo_proteger
-- ============================================================

DROP TRIGGER IF EXISTS prestamo_proteger
ON biblioteca.prestamos;

CREATE TRIGGER prestamo_proteger
BEFORE UPDATE ON biblioteca.prestamos
FOR EACH ROW
EXECUTE FUNCTION biblioteca.proteger_prestamo();

-- ============================================================
-- 10. FUNCION DE TRIGGER: validar_estado_ejemplar
-- Regla: el estado prestado debe coincidir con la
-- existencia de un prestamo abierto.
-- ============================================================

CREATE OR REPLACE FUNCTION biblioteca.validar_estado_ejemplar()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_prestamo_abierto boolean;
BEGIN

    SELECT EXISTS (
        SELECT 1
        FROM biblioteca.prestamos p
        WHERE p.isbn = NEW.isbn
          AND p.id_ejemplar = NEW.id_ejemplar
          AND p.fecha_devolucion IS NULL
    )
    INTO v_prestamo_abierto;

    IF (NEW.estado = 'prestado')
       IS DISTINCT FROM v_prestamo_abierto THEN

        RAISE EXCEPTION
            'El estado del ejemplar no coincide con sus prestamos abiertos';

    END IF;

    RETURN NEW;

END;
$$;


-- ============================================================
-- 11. TRIGGER BEFORE: ejemplar_validar_estado
-- ============================================================

DROP TRIGGER IF EXISTS ejemplar_validar_estado
ON biblioteca.ejemplares;

CREATE TRIGGER ejemplar_validar_estado
BEFORE INSERT OR UPDATE OF estado
ON biblioteca.ejemplares
FOR EACH ROW
EXECUTE FUNCTION biblioteca.validar_estado_ejemplar();

COMMIT;