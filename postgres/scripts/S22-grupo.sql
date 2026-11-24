-- S22 - Parte A: reservas de salas de estudio
-- Uso: primero S22-reservas.sql (recrea el esquema), luego este archivo.
--   docker compose exec postgres psql -U curso -d curso -f /scripts/S22-reservas.sql
--   docker compose exec postgres psql -U curso -d curso -f /scripts/S22-grupo.sql
-- Las baterias incluyen sentencias que DEBEN fallar: el archivo se corre sin
-- ON_ERROR_STOP para que siga despues de cada error esperado.
-- Nota: los INSERT que fallan o se deshacen gastan valores de la identidad,
-- asi que las reservas creadas en A3 no quedan con los ids 10, 11 y 12.

SET search_path TO reservas;

-- ===========================================================
-- A1. Restricciones y acciones referenciales
-- ===========================================================

-- (a) Regla 1 (maximo 3 horas, mismo dia, entre 7:00 y 21:00) y asistentes positivos
ALTER TABLE reserva
    ADD CONSTRAINT reserva_orden      CHECK (fin > inicio),
    ADD CONSTRAINT reserva_duracion   CHECK (fin - inicio <= interval '3 hours'),
    ADD CONSTRAINT reserva_horario    CHECK (inicio::date = fin::date
                                             AND inicio::time >= time '07:00'
                                             AND fin::time    <= time '21:00'),
    ADD CONSTRAINT reserva_asistentes CHECK (asistentes > 0);

-- (b) Acciones ON DELETE (justificacion en el documento de respuestas)
-- sala_recurso -> sala: CASCADE (los recursos son parte de la sala)
ALTER TABLE sala_recurso
    DROP CONSTRAINT sala_recurso_id_sala_fkey,
    ADD CONSTRAINT sala_recurso_id_sala_fkey
        FOREIGN KEY (id_sala) REFERENCES sala ON DELETE CASCADE;

-- reserva -> sala: RESTRICT (no se pierde el historial de reservas)
ALTER TABLE reserva
    DROP CONSTRAINT reserva_id_sala_fkey,
    ADD CONSTRAINT reserva_id_sala_fkey
        FOREIGN KEY (id_sala) REFERENCES sala ON DELETE RESTRICT;

-- reserva -> estudiante: RESTRICT (historial y sanciones del estudiante)
ALTER TABLE reserva
    DROP CONSTRAINT reserva_codigo_fkey,
    ADD CONSTRAINT reserva_codigo_fkey
        FOREIGN KEY (codigo) REFERENCES estudiante ON DELETE RESTRICT;

-- (c) Bateria
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '10:00', dia(4) + time '09:00', 2);   -- debe fallar: reserva_orden
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '08:00', dia(4) + time '12:00', 2);   -- debe fallar: reserva_duracion
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '20:00', dia(4) + time '22:00', 2);   -- debe fallar: reserva_horario
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '10:00', dia(4) + time '11:00', 0);   -- debe fallar: reserva_asistentes

BEGIN;
DELETE FROM sala WHERE id_sala = 4;                  -- pasa: la sala 4 no tiene reservas
SELECT count(*) FROM sala_recurso WHERE id_sala = 4; -- 0: sus recursos se borran en cascada
ROLLBACK;
DELETE FROM sala WHERE id_sala = 1;                  -- debe fallar: tiene reservas (RESTRICT)

BEGIN;
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(1) + time '09:00', dia(1) + time '10:00', 9);   -- pasa todas las CHECK
ROLLBACK;

-- ===========================================================
-- A2. Funciones
-- ===========================================================

-- Horas reservadas (sin canceladas) por el estudiante en la semana del dia dado
CREATE OR REPLACE FUNCTION horas_semana(p_codigo varchar, p_dia date)
RETURNS numeric
LANGUAGE sql STABLE
AS $$
    SELECT round(coalesce(sum(extract(epoch FROM fin - inicio)) / 3600, 0), 1)
    FROM   reserva
    WHERE  codigo = p_codigo
      AND  estado <> 'cancelada'
      AND  date_trunc('week', inicio) = date_trunc('week', p_dia::timestamp);
$$;

-- Verdadero si la sala no tiene reservas activas que se crucen con [p_inicio, p_fin),
-- sin contar la reserva p_excluir
CREATE OR REPLACE FUNCTION sala_libre(p_sala integer, p_inicio timestamp, p_fin timestamp,
                                      p_excluir integer DEFAULT NULL)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM   reserva
        WHERE  id_sala = p_sala
          AND  estado = 'activa'
          AND  inicio < p_fin
          AND  p_inicio < fin
          AND  (p_excluir IS NULL OR id <> p_excluir)
    );
$$;

-- Bateria
SELECT codigo, horas_semana(codigo, dia(1))   AS proxima,
               horas_semana(codigo, dia(-13)) AS pasada
FROM   estudiante ORDER BY codigo;
-- proxima: Ana 5.0, Bruno 2.0, Carla 3.0, Diego 2.0, Elena 0.0, Felipe 0.0
-- pasada:  Bruno 2.0, Carla 2.0, Felipe 2.0, los demas 0.0

SELECT sala_libre(1, dia(1) + time '09:00', dia(1) + time '11:00')    AS a,   -- f
       sala_libre(1, dia(1) + time '12:00', dia(1) + time '14:00')    AS b,   -- t
       sala_libre(2, dia(3) + time '08:00', dia(3) + time '10:00')    AS c,   -- t
       sala_libre(1, dia(1) + time '08:00', dia(1) + time '10:00', 1) AS d;   -- t

-- ===========================================================
-- A3. Procedimientos
-- ===========================================================

-- (a) Reservar: valida existencia y las reglas 5, 2, 3 y 4, en ese orden.
-- La regla 1 la imponen las restricciones CHECK de A1 al insertar.
CREATE OR REPLACE PROCEDURE reservar(p_codigo varchar, p_sala integer,
                                     p_inicio timestamp, p_fin timestamp,
                                     p_asistentes integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sancion    date;
    v_capacidad  integer;
    v_activa     boolean;
    v_horas      numeric;
    v_duracion   numeric;
    v_id         integer;
BEGIN
    -- El estudiante existe
    SELECT sancionado_hasta INTO v_sancion FROM estudiante WHERE codigo = p_codigo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El estudiante % no existe', p_codigo;
    END IF;

    -- Regla 5: un estudiante sancionado no puede reservar
    IF v_sancion IS NOT NULL AND v_sancion >= CURRENT_DATE THEN
        RAISE EXCEPTION 'El estudiante % esta sancionado hasta el %', p_codigo, v_sancion;
    END IF;

    -- La sala existe
    SELECT capacidad, activa INTO v_capacidad, v_activa FROM sala WHERE id_sala = p_sala;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sala % no existe', p_sala;
    END IF;

    -- Regla 2: sala en mantenimiento y capacidad
    IF NOT v_activa THEN
        RAISE EXCEPTION 'La sala % esta en mantenimiento', p_sala;
    END IF;
    IF p_asistentes > v_capacidad THEN
        RAISE EXCEPTION 'La sala % tiene capacidad para %, no para % asistentes',
                        p_sala, v_capacidad, p_asistentes;
    END IF;

    -- Regla 3: la sala no puede tener otra reserva activa que se cruce
    IF NOT sala_libre(p_sala, p_inicio, p_fin) THEN
        RAISE EXCEPTION 'La sala % ya esta ocupada entre % y %', p_sala, p_inicio, p_fin;
    END IF;

    -- Regla 4: maximo 6 horas por semana
    v_horas    := horas_semana(p_codigo, p_inicio::date);
    v_duracion := extract(epoch FROM p_fin - p_inicio) / 3600;
    IF v_horas + v_duracion > 6 THEN
        RAISE EXCEPTION 'El estudiante % lleva % horas esta semana; con esta reserva tendria % (maximo 6)',
                        p_codigo, v_horas, round(v_horas + v_duracion, 1);
    END IF;

    INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
    VALUES (p_sala, p_codigo, p_inicio, p_fin, p_asistentes)
    RETURNING id INTO v_id;

    RAISE NOTICE 'Reserva % creada', v_id;
END;
$$;

-- (b) Cancelar: regla 6, solo si esta activa y no ha empezado
CREATE OR REPLACE PROCEDURE cancelar(p_id integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado  varchar;
    v_inicio  timestamp;
BEGIN
    SELECT estado, inicio INTO v_estado, v_inicio FROM reserva WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La reserva % no existe', p_id;
    END IF;
    IF v_estado <> 'activa' THEN
        RAISE EXCEPTION 'La reserva % no esta activa (estado: %)', p_id, v_estado;
    END IF;
    IF v_inicio <= now() THEN
        RAISE EXCEPTION 'La reserva % ya empezo (%) y no se puede cancelar', p_id, v_inicio;
    END IF;

    UPDATE reserva SET estado = 'cancelada' WHERE id = p_id;
    RAISE NOTICE 'Reserva % cancelada', p_id;
END;
$$;

-- (c) Bateria
CALL reservar('2610005', 1, dia(4) + time '08:00', dia(4) + time '10:00', 2);   -- 1. error: Elena sancionada
CALL reservar('2610006', 4, dia(4) + time '08:00', dia(4) + time '10:00', 2);   -- 2. error: sala en mantenimiento
CALL reservar('2610006', 1, dia(4) + time '08:00', dia(4) + time '10:00', 5);   -- 3. error: capacidad 4, no 5
CALL reservar('2610006', 1, dia(1) + time '09:00', dia(1) + time '11:00', 2);   -- 4. error: sala ocupada
CALL reservar('2610001', 2, dia(4) + time '08:00', dia(4) + time '10:00', 3);   -- 5. error: Ana superaria 6 h (lleva 5.0)
CALL reservar('2610006', 1, dia(1) + time '12:00', dia(1) + time '14:00', 3);   -- 6. reserva creada
CALL reservar('2610004', 2, dia(3) + time '08:00', dia(3) + time '10:00', 4);   -- 7. reserva creada (la anterior estaba cancelada)
CALL reservar('2610001', 2, dia(4) + time '08:00', dia(4) + time '09:00', 3);   -- 8. reserva creada: Ana llega justo a 6
CALL reservar('2610099', 2, dia(4) + time '08:00', dia(4) + time '09:00', 3);   -- 9. error: el estudiante no existe
CALL cancelar(7);                                                                -- 10. error: la 7 no esta activa
CALL cancelar(2);                                                                -- 11. cancela la de Bruno

SELECT * FROM agenda;

-- ===========================================================
-- A4. Trigger de validacion
-- ===========================================================

-- (a) Sin trigger, las reglas 2 y 3 se pueden saltar con un INSERT directo
BEGIN;
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + time '10:00', dia(2) + time '11:00', 12);   -- pasa: 12 en sala de 10, cruzada con la de Ana
ROLLBACK;

-- (b) Reglas 2 y 3 para toda reserva activa, venga de donde venga
CREATE OR REPLACE FUNCTION validar_reserva()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacidad  integer;
    v_activa     boolean;
BEGIN
    IF NEW.estado <> 'activa' THEN
        RETURN NEW;                          -- canceladas, cumplidas, no_asistio: no se validan
    END IF;

    SELECT capacidad, activa INTO v_capacidad, v_activa FROM sala WHERE id_sala = NEW.id_sala;

    -- Regla 2
    IF NOT v_activa THEN
        RAISE EXCEPTION 'La sala % esta en mantenimiento', NEW.id_sala;
    END IF;
    IF NEW.asistentes > v_capacidad THEN
        RAISE EXCEPTION 'La sala % tiene capacidad para %, no para % asistentes',
                        NEW.id_sala, v_capacidad, NEW.asistentes;
    END IF;

    -- Regla 3 (se excluye la propia reserva para que un UPDATE no choque consigo misma)
    IF NOT sala_libre(NEW.id_sala, NEW.inicio, NEW.fin, NEW.id) THEN
        RAISE EXCEPTION 'La sala % ya esta ocupada entre % y %', NEW.id_sala, NEW.inicio, NEW.fin;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reserva_validar ON reserva;
CREATE TRIGGER reserva_validar
    BEFORE INSERT OR UPDATE ON reserva
    FOR EACH ROW
    EXECUTE FUNCTION validar_reserva();

-- (c) Bateria
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + time '10:00', dia(2) + time '11:00', 12);   -- debe fallar: capacidad
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + time '10:00', dia(2) + time '11:00', 6);    -- debe fallar: sala ocupada
UPDATE reserva SET inicio = dia(3) + time '09:00' WHERE id = 6;            -- debe fallar: cruza con la de Diego de las 8:00
UPDATE reserva SET asistentes = 5 WHERE id = 6;                            -- debe pasar
UPDATE reserva SET estado = 'activa' WHERE id = 5;                         -- debe fallar: reactivarla la cruza

-- ===========================================================
-- A5. Trigger que reacciona a un cambio de estado
-- ===========================================================

-- Regla 5: quien no se presenta queda sancionado 7 dias.
CREATE OR REPLACE FUNCTION sancionar_inasistencia()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE estudiante
    SET    sancionado_hasta = CURRENT_DATE + 7
    WHERE  codigo = NEW.codigo;
    RETURN NULL;                             -- AFTER: el valor de retorno se ignora
END;
$$;

DROP TRIGGER IF EXISTS reserva_sancionar ON reserva;
CREATE TRIGGER reserva_sancionar
    AFTER UPDATE OF estado ON reserva
    FOR EACH ROW
    WHEN (NEW.estado = 'no_asistio' AND OLD.estado <> 'no_asistio')
    EXECUTE FUNCTION sancionar_inasistencia();

-- Bateria
UPDATE reserva SET estado = 'no_asistio' WHERE id = 7;    -- Felipe no se presento
SELECT codigo, nombre, sancionado_hasta - CURRENT_DATE AS dias
FROM   estudiante WHERE sancionado_hasta IS NOT NULL;     -- Elena 30, Felipe 7
CALL reservar('2610006', 3, dia(5) + time '08:00', dia(5) + time '10:00', 2);   -- debe fallar: Felipe sancionado
UPDATE reserva SET asistentes = 2 WHERE id = 8;           -- Bruno: ya era no_asistio; no queda sancionado
SELECT codigo, nombre, sancionado_hasta - CURRENT_DATE AS dias
FROM   estudiante WHERE sancionado_hasta IS NOT NULL;     -- sigue: Elena 30, Felipe 7 (Bruno no aparece)

-- ===========================================================
-- A6. Ciclo o conjunto
-- ===========================================================

-- Version original (fila por fila), para comparar; no se ejecuta
CREATE OR REPLACE PROCEDURE cerrar_vencidas_ciclo()
LANGUAGE plpgsql
AS $$
DECLARE
    r  record;
BEGIN
    FOR r IN SELECT id FROM reserva WHERE estado = 'activa' AND fin < now() LOOP
        UPDATE reserva SET estado = 'cumplida' WHERE id = r.id;
        RAISE NOTICE 'Reserva % cerrada', r.id;
    END LOOP;
END;
$$;

-- (a) La misma tarea en una sola sentencia sobre el conjunto
CREATE OR REPLACE PROCEDURE cerrar_vencidas()
LANGUAGE sql
AS $$
    UPDATE reserva
    SET    estado = 'cumplida'
    WHERE  estado = 'activa' AND fin < now();
$$;

SELECT id, estado FROM reserva WHERE id = 9;              -- activa
CALL cerrar_vencidas();
SELECT id, estado FROM reserva WHERE id = 9;              -- cumplida

SELECT * FROM agenda;

-- ===========================================================
-- Reto: la regla 3 como restriccion EXCLUDE
-- ===========================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE reserva ADD CONSTRAINT reserva_sin_cruce
    EXCLUDE USING gist (id_sala WITH =, tsrange(inicio, fin) WITH &&)
    WHERE (estado = 'activa');

ALTER TABLE reserva DISABLE TRIGGER reserva_validar;

INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610003', dia(1) + time '09:00', dia(1) + time '10:00', 2);   -- debe fallar: reserva_sin_cruce

BEGIN;
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610003', dia(1) + time '15:00', dia(1) + time '16:00', 2);   -- pasa: no se cruza
ROLLBACK;

ALTER TABLE reserva ENABLE TRIGGER reserva_validar;
