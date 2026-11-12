-- S19 - Parte A
-- Este archivo es el trabajo de los 4 casos de la entrega S19, en orden. 
-- Cada caso tiene su diagnostico, propuesta de esquema y migracion transaccional.

-- ===========================================================
-- Caso 1 - gimnasio
-- ===========================================================

-- (a) DIAGNOSTICO
-- Tabla original:
-- socio (id_socio PK, nombre, plan, valor_plan, clases)

-- Problema principal:
-- La columna clases almacena varios valores separados por ';'.
-- Esto representa un grupo de valores multivaluados y no
-- cumple con el diseño relacional esperado en 1FN.

-- Ejemplo:
-- Laura Cifuentes: 'Yoga; Spinning'
-- Maria Fernanda: 'Pilates;yoga'
-- Andres Mosquera: 'Spinning; Funcional; Yoga '

-- La consulta con LIKE produce resultados incorrectos:
-- Yoga = 2, cuando realmente son 3.
-- Spinning = 3, cuando realmente son 2.

-- Problema adicional:
-- El valor del plan se repite para todos los socios
-- que tienen el mismo tipo de plan.

-- Dependencias funcionales:
-- 1. id_socio -> nombre, plan, valor_plan, clases
--    Cada socio se identifica por su id_socio.
-- 2. plan -> valor_plan
--    Cada tipo de plan tiene un valor fijo.

-- Existe una dependencia transitiva:
-- id_socio -> plan -> valor_plan.
-- Por ello, el almacenamiento de valor_plan en socio
-- incumple 3FN.

-- Solucion:
-- Separar planes, socios, clases e inscripciones.

-- (b) EVIDENCIA DEL PROBLEMA

-- Consulta incorrecta que explica la queja:
SELECT
    'Yoga' AS clase,
    COUNT(*) AS socios
FROM gimnasio.socio
WHERE clases LIKE '%Yoga%'

UNION ALL

SELECT
    'Spinning' AS clase,
    COUNT(*) AS socios
FROM gimnasio.socio
WHERE clases LIKE '%Spinning%';
-- Resultado observado:
-- Yoga     | 2
-- Spinning | 3

-- Conteo correcto separando las clases:
SELECT
    INITCAP(LOWER(TRIM(c.clase))) AS clase,
    COUNT(*) AS total_socios
FROM gimnasio.socio s
CROSS JOIN LATERAL
    string_to_table(s.clases, ';') AS c(clase)
GROUP BY LOWER(TRIM(c.clase))
ORDER BY clase;
-- Resultado observado:
-- Funcional         | 2
-- Pilates           | 1
-- Spinning          | 2
-- Spinning Avanzado | 1
-- Yoga              | 3

-- Evidencia de redundancia de planes:
SELECT
    plan,
    valor_plan,
    COUNT(*) AS total_socios
FROM gimnasio.socio
GROUP BY plan, valor_plan
ORDER BY plan;
-- Resultado observado:
-- Anual      | 850000 | 2
-- Mensual    |  90000 | 3
-- Trimestral | 240000 | 1

-- (c) ESQUEMA CORREGIDO:
-- plan (
--     nombre_plan PK,
--     valor_plan NOT NULL
-- )
-- socio_nuevo (
--     id_socio PK,
--     nombre NOT NULL,
--     nombre_plan FK -> plan
-- )
-- clase (
--     id_clase PK,
--     nombre UNIQUE NOT NULL
-- )
-- inscripcion_clase (
--     id_socio FK -> socio_nuevo,
--     id_clase FK -> clase,
--     PK (id_socio, id_clase)
-- )
-- Se utiliza una tabla intermedia porque un socio puede inscribirse 
-- en varias clases y una clase puede tener varios socios.

-- (d) MIGRACION TRANSACCIONAL
-- Conteos esperados antes de migrar:
-- Planes: 3
-- Socios: 6
-- Clases: 5
-- Inscripciones: 9

BEGIN;
-- Crear tabla de planes.
CREATE TABLE gimnasio.plan (
    nombre_plan VARCHAR(20) PRIMARY KEY,
    valor_plan INTEGER NOT NULL
        CHECK (valor_plan >= 0)
);
-- Crear tabla de socios normalizados.
CREATE TABLE gimnasio.socio_nuevo (
    id_socio INTEGER PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL,
    nombre_plan VARCHAR(20) NOT NULL,
    FOREIGN KEY (nombre_plan)
        REFERENCES gimnasio.plan(nombre_plan)
);
-- Crear tabla de clases.
CREATE TABLE gimnasio.clase (
    id_clase INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE
);
-- Crear tabla de inscripciones.
CREATE TABLE gimnasio.inscripcion_clase (
    id_socio INTEGER NOT NULL,
    id_clase INTEGER NOT NULL,
    PRIMARY KEY (id_socio, id_clase),
    FOREIGN KEY (id_socio)
        REFERENCES gimnasio.socio_nuevo(id_socio),
    FOREIGN KEY (id_clase)
        REFERENCES gimnasio.clase(id_clase)
);
-- Migrar planes sin duplicados.
INSERT INTO gimnasio.plan (nombre_plan, valor_plan)
SELECT DISTINCT
    plan,
    valor_plan
FROM gimnasio.socio;
-- Migrar socios.
INSERT INTO gimnasio.socio_nuevo (
    id_socio,
    nombre,
    nombre_plan
)
SELECT
    id_socio,
    nombre,
    plan
FROM gimnasio.socio;
-- Migrar clases normalizando mayusculas y espacios.
INSERT INTO gimnasio.clase (nombre)
SELECT DISTINCT
    INITCAP(LOWER(TRIM(c.clase)))
FROM gimnasio.socio s
CROSS JOIN LATERAL
    string_to_table(s.clases, ';') AS c(clase)
WHERE TRIM(c.clase) <> '';
-- Migrar inscripciones.
INSERT INTO gimnasio.inscripcion_clase (
    id_socio,
    id_clase
)
SELECT DISTINCT
    s.id_socio,
    cl.id_clase
FROM gimnasio.socio s
CROSS JOIN LATERAL
    string_to_table(s.clases, ';') AS c(clase)
JOIN gimnasio.clase cl
    ON cl.nombre = INITCAP(LOWER(TRIM(c.clase)));

-- (e) VERIFICACION
-- Conteos de las tablas normalizadas.
SELECT 'Planes' AS tabla, COUNT(*) AS registros
FROM gimnasio.plan
UNION ALL
SELECT 'Socios', COUNT(*)
FROM gimnasio.socio_nuevo
UNION ALL
SELECT 'Clases', COUNT(*)
FROM gimnasio.clase
UNION ALL
SELECT 'Inscripciones', COUNT(*)
FROM gimnasio.inscripcion_clase;
-- Resultado esperado y observado:
-- Planes        | 3
-- Socios        | 6
-- Clases        | 5
-- Inscripciones | 9
-- Resolver la queja original con el esquema corregido.
SELECT
    c.nombre AS clase,
    COUNT(ic.id_socio) AS total_socios
FROM gimnasio.clase c
LEFT JOIN gimnasio.inscripcion_clase ic
    ON ic.id_clase = c.id_clase
GROUP BY c.id_clase, c.nombre
ORDER BY c.nombre;
-- Resultado:
-- Funcional         | 2
-- Pilates           | 1
-- Spinning          | 2
-- Spinning Avanzado | 1
-- Yoga              | 3
COMMIT;

-- PREGUNTA PROPIA DEL CASO 1
-- ¿Donde guardar el horario de cada clase?
-- El horario debe guardarse en una tabla independiente
-- llamada horario_clase, relacionada con clase mediante
-- una clave foranea.

-- horario_clase (
--     id_horario PK,
--     id_clase FK,
--     dia_semana,
--     hora_inicio,
--     hora_fin
-- )
-- Una clase puede tener varios horarios durante la semana.
-- En el diseño original, las clases estaban almacenadas
-- como texto dentro de socio.clases, sin identificadores
-- individuales ni una entidad clase.
-- Por esta razon no era posible relacionar correctamente
-- los horarios mediante claves foraneas.

-- ===========================================================
-- Caso 2 - farmacia
-- ===========================================================

-- ===========================================================
-- Caso 3 - cursos_libres
-- ===========================================================

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
