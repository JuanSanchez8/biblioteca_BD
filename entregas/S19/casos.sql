-- S19 - Parte A
-- Este archivo es el trabajo de los 4 casos de la entrega S19, en orden. 
-- Cada caso tiene su diagnostico, propuesta de esquema y migracion transaccional.

-- ===========================================================
-- Caso 1 - gimnasio
-- ===========================================================




-- ===========================================================
-- Caso 2 - farmacia
-- ===========================================================




-- ===========================================================
-- Caso 3 - cursos_libres
-- ===========================================================
-- (a) Diagnostico
--
-- Tabla original:
-- inscripcion (id PK serial, doc_participante, nombre_participante, correo,
--              cod_curso, nombre_curso, cod_sede, direccion_sede, valor_pagado)
--
-- Dependencias / reglas:
-- 1. (doc_participante, cod_curso) -> valor_pagado
--    Regla: un participante se inscribe a lo sumo una vez en cada curso, y el valor
--    pagado es propio de esa inscripcion (puede tener descuento).
--    => (doc_participante, cod_curso) es clave candidata, aunque no estaba declarada.
-- 2. doc_participante -> nombre_participante, correo     (datos del participante)
-- 3. correo -> doc_participante
--    Regla: no hay dos participantes con el mismo correo.
-- 4. cod_curso -> nombre_curso, cod_sede
--    Regla: cada curso se dicta en una sola sede.
-- 5. cod_sede -> direccion_sede                          (datos de la sede)
--
-- Problema principal (queja): la PK es un id serial que la base genera distinto en
-- cada fila, y no hay UNIQUE (doc_participante, cod_curso). Por eso se guardo dos
-- veces la inscripcion de Juliana Rey (1140000900) en C20 (ids 3 y 7) y el curso
-- Fotografia digital suma 580000 en lugar de 380000: 200000 de mas.
--
-- Problemas adicionales:
-- - No esta en 2FN: las dependencias 2 y 4 son parciales respecto a la clave
--   candidata (doc_participante, cod_curso). Nombre y correo del participante, y
--   nombre y sede del curso, se repiten en cada inscripcion.
-- - No esta en 3FN: cod_curso -> cod_sede -> direccion_sede es transitiva. La
--   direccion de la sede se repite en cada inscripcion de sus cursos.

-- (b) Evidencia
SET search_path TO cursos_libres;

-- Inscripciones repetidas en la clave natural
SELECT doc_participante, cod_curso, count(*) AS veces
FROM inscripcion
GROUP BY doc_participante, cod_curso
HAVING count(*) > 1;
-- Resultado: 1140000900 | C20 | 2

-- Recaudo por curso, tal como lo ve contabilidad
SELECT cod_curso, nombre_curso, sum(valor_pagado) AS recaudado
FROM inscripcion
GROUP BY cod_curso, nombre_curso
ORDER BY cod_curso;
-- Resultado: C20 Fotografia digital = 580000 (deberia ser 380000)

-- Redundancia de datos del participante
SELECT doc_participante, nombre_participante, count(*) AS veces
FROM inscripcion
GROUP BY doc_participante, nombre_participante
ORDER BY veces DESC;
-- Resultado: Juliana Rey 3, Valeria Ospina 2, Mateo Gil 2, Esteban Cruz 1

-- Redundancia de la direccion de la sede
SELECT cod_sede, direccion_sede, count(*) AS veces
FROM inscripcion
GROUP BY cod_sede, direccion_sede;
-- Resultado: S1 5 veces, S2 3 veces

-- (c) Esquema corregido
-- sede         (cod_sede PK, direccion_sede NOT NULL)
-- curso        (cod_curso PK, nombre_curso NOT NULL, cod_sede FK -> sede NOT NULL)
-- participante (doc_participante PK, nombre_participante NOT NULL,
--               correo UNIQUE NOT NULL)
-- inscripcion  (doc_participante FK -> participante, cod_curso FK -> curso,
--               valor_pagado NOT NULL, PK (doc_participante, cod_curso))

-- (d) Migracion
-- Decision sobre el duplicado: las filas id 3 y 7 son identicas (mismo participante,
-- curso y valor). Se conserva una sola (la primera registrada, id 3); como son
-- iguales, DISTINCT produce el mismo resultado.
--
-- Conteos esperados (calculados antes de migrar):
-- sede = 2 (S1, S2), curso = 3 (C10, C20, C30),
-- participante = 4 (documentos distintos), inscripcion = 7 (8 filas - 1 duplicada)

BEGIN;

ALTER TABLE inscripcion RENAME TO inscripcion_vieja;

CREATE TABLE sede (
    cod_sede        char(2)     PRIMARY KEY,
    direccion_sede  varchar(60) NOT NULL
);

CREATE TABLE curso (
    cod_curso     char(3)     PRIMARY KEY,
    nombre_curso  varchar(60) NOT NULL,
    cod_sede      char(2)     NOT NULL REFERENCES sede
);

CREATE TABLE participante (
    doc_participante     varchar(15)  PRIMARY KEY,
    nombre_participante  varchar(80)  NOT NULL,
    correo               varchar(120) NOT NULL UNIQUE
);

CREATE TABLE inscripcion (
    doc_participante  varchar(15) NOT NULL REFERENCES participante,
    cod_curso         char(3)     NOT NULL REFERENCES curso,
    valor_pagado      integer     NOT NULL,
    PRIMARY KEY (doc_participante, cod_curso)
);

INSERT INTO sede
SELECT DISTINCT cod_sede, direccion_sede FROM inscripcion_vieja;

INSERT INTO curso
SELECT DISTINCT cod_curso, nombre_curso, cod_sede FROM inscripcion_vieja;

INSERT INTO participante
SELECT DISTINCT doc_participante, nombre_participante, correo FROM inscripcion_vieja;

INSERT INTO inscripcion
SELECT DISTINCT doc_participante, cod_curso, valor_pagado FROM inscripcion_vieja;

-- (e) Verificacion
-- Conteos obtenidos
SELECT 'sede' AS tabla, count(*) FROM sede
UNION ALL SELECT 'curso', count(*) FROM curso
UNION ALL SELECT 'participante', count(*) FROM participante
UNION ALL SELECT 'inscripcion', count(*) FROM inscripcion;
-- Resultado: sede 2, curso 3, participante 4, inscripcion 7 (coincide con lo esperado)

-- Queja resuelta en el esquema nuevo
SELECT c.cod_curso, c.nombre_curso, sum(i.valor_pagado) AS recaudado
FROM inscripcion i
JOIN curso c ON c.cod_curso = i.cod_curso
GROUP BY c.cod_curso, c.nombre_curso
ORDER BY c.cod_curso;
-- Resultado: C20 Fotografia digital = 380000

-- No se perdio ningun dato
SELECT doc_participante, nombre_participante, correo, cod_curso,
       nombre_curso, cod_sede, direccion_sede, valor_pagado
FROM inscripcion_vieja
EXCEPT
SELECT p.doc_participante, p.nombre_participante, p.correo, c.cod_curso,
       c.nombre_curso, s.cod_sede, s.direccion_sede, i.valor_pagado
FROM inscripcion i
JOIN participante p ON p.doc_participante = i.doc_participante
JOIN curso c        ON c.cod_curso = i.cod_curso
JOIN sede s         ON s.cod_sede = c.cod_sede;
-- Resultado: 0 filas

-- No se invento ningun dato
SELECT p.doc_participante, p.nombre_participante, p.correo, c.cod_curso,
       c.nombre_curso, s.cod_sede, s.direccion_sede, i.valor_pagado
FROM inscripcion i
JOIN participante p ON p.doc_participante = i.doc_participante
JOIN curso c        ON c.cod_curso = i.cod_curso
JOIN sede s         ON s.cod_sede = c.cod_sede
EXCEPT
SELECT doc_participante, nombre_participante, correo, cod_curso,
       nombre_curso, cod_sede, direccion_sede, valor_pagado
FROM inscripcion_vieja;
-- Resultado: 0 filas

DROP TABLE inscripcion_vieja;

COMMIT;

-- Pregunta propia
-- La tabla tiene una PK de una sola columna (id), pero eso no la pone en 2FN.
-- Las formas normales se evaluan sobre TODAS las claves candidatas, no solo la PK
-- declarada. Por la regla del negocio, (doc_participante, cod_curso) tambien
-- identifica una inscripcion, asi que es clave candidata aunque nadie la haya
-- declarado. Respecto a ella, doc_participante -> nombre, correo y
-- cod_curso -> nombre_curso, cod_sede son dependencias parciales: no esta en 2FN.
-- Agregar un id no normaliza nada; solo cambia el nombre de la PK.
--
-- Al diseno original le faltaba UNIQUE (doc_participante, cod_curso). Con esa
-- restriccion, la segunda inscripcion de Juliana Rey en C20 habria sido rechazada
-- y contabilidad no habria contado 200000 de mas.



-- ===========================================================
-- Caso 4 - envios
-- ===========================================================


-- La evidencia (b) de las consultas ya ejecutadas se conserva aparte en evidencias/S19-caso4-envios.txt.

-- (a) Diagnostico
--
-- Tabla original:
-- envio (num_guia PK, fecha, ciudad_destino, departamento, zona,
--        tarifa_kg, peso_kg, valor)
--
-- Dependencias / reglas:
-- 1. num_guia -> fecha, ciudad_destino, departamento, zona, tarifa_kg, peso_kg, valor
--    Regla: cada numero de guia identifica un envio (PK).
-- 2. zona -> tarifa_kg
--    Regla: el enunciado dice que cada zona tiene una tarifa por kilo. En los datos de prueba no hay zonas con tarifas contradictorias.
-- 3. ciudad_destino -> departamento, zona
--    Regla: el enunciado dice que cada ciudad pertenece a un departamento y a una zona. Si los nombres de ciudad no son unicos en el 
--    mundo real, la determinante debe ser una clave de ciudad, no solo el nombre.
-- 4. peso_kg, tarifa_kg -> valor calculado
--    Regla: valor = peso_kg * tarifa_kg. No es una regla declarada como restriccion en el DDL original; G07 la contradice.
--
-- Problema principal (queja): G07 tiene peso 4 kg y tarifa 6000/kg, por lo que el cobro calculado es 24000, pero valor guarda 42000. 
-- Es un dato derivado inconsistente.
--
-- Problema adicional: tarifa_kg se repite en los envios de una misma zona.
-- Como zona -> tarifa_kg, en la tabla original hay una dependencia transitiva desde num_guia a tarifa_kg a traves de zona; la tarifa 
-- vigente deberia definirse una sola vez por zona. Esto es un problema de diseno / normalizacion (3FN) si se considera tarifa_kg un dato 
-- de la zona.
--
-- La evidencia de datos esta en evidencias/S19-caso4-envios.txt. Sus consultas comprueban estos registros de prueba; las reglas de negocio 
-- se justifican con el enunciado, no solo con la ausencia de contradicciones en los datos.

-- (c) Propuesta de esquema corregido (diseno, aun no migracion)
--
-- departamento (
--   id_departamento PK,
--   nombre UNIQUE NOT NULL
-- )
--
-- zona (
--   id_zona PK,
--   tarifa_kg_vigente NOT NULL
-- )
--
-- ciudad (
--   id_ciudad PK,
--   nombre NOT NULL,
--   id_departamento FK -> departamento,
--   id_zona FK -> zona,
--   UNIQUE (nombre, id_departamento)
-- )
--
-- envio (
--   num_guia PK,
--   fecha NOT NULL,
--   id_ciudad FK -> ciudad,
--   peso_kg NOT NULL,
--   tarifa_kg_aplicada NOT NULL
-- )
--
-- La zona se asigna a la ciudad (no al departamento), porque una zona puede cubrir ciudades de mas de un departamento: Antioquia y 
-- Bogota D.C. comparten la zona 2 en los datos de prueba. No se asume que departamento determine zona.
--
-- Se guarda en cada envio la tarifa_kg_aplicada al momento del despacho, no solo una FK a la tarifa vigente. Asi, al cambiar la 
-- tarifa de una zona en enero, los envios de octubre conservan el precio que se les aplico. Aunque el numero pueda coincidir con una 
-- tarifa de zona, aqui representa un hecho historico del envio y no una copia actualizable de la tarifa vigente.
--
-- valor no se almacena: se obtiene como peso_kg * tarifa_kg_aplicada en una consulta o vista. Al migrar, se debe corregir G07 a 24000 
-- segun la regla dada y dejar constancia de esa correccion.
--
-- (d) La migracion transaccional y (e) sus verificaciones se agregaran despues de confirmar este diseno.
