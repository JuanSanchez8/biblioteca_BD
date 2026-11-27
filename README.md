# Proyecto Biblioteca · Bases de Datos (750006C)

Sistema de biblioteca del proyecto integrador. Este repositorio contiene
el entorno Docker, el esquema en PostgreSQL, la carga masiva desde CSV, las consultas de los reportes, la normalización del modelo y la lógica de negocio implementada mediante funciones, procedimientos almacenados y triggers.

***

## Estructura

```
docker-compose.yml                 Entorno: PostgreSQL 16 + pgAdmin
├── postgres/
│   ├── init/                               Se ejecuta solo, una vez, cuando la base se crea vacía
│   │   ├── 01_esquema.sql                  Esquema de negocio "biblioteca"
│   │   ├── 02_carga.sql                    Esquema "carga" con las tablas de paso (stg_*)
│   │   └── 03_programacion.sql
│   └── scripts/                            Dentro del contenedor: /scripts
│       ├── S14-carga-libros-biblioteca.sql
│       ├── S14-carga-lectores-biblioteca.sql
│       ├── datos-prueba.sql                Préstamos de prueba para los reportes (S16)
│       ├── reportes.sql                    Los 4 reportes del proyecto (S16)
│       ├── S16-tienda.sql                  Esquema de práctica de la parte A de S16
|       ├── S19-esquemas.sql
|       ├── S20-rendimiento.sql
|       ├── S22-reservas.sql
|       ├── S22-grupo.sql
|       ├── programacion.sql
|       ├── pruebas-programacion.sql
│       └── datos/                          CSV semilla del curso y CSV propios
├── docs/
│   └── mapeo-y-criterios.md                Mapeo CSV → esquema y criterios de error (S14)
├── entregas/
│   ├── S16/parte-a.sql                     Las 11 consultas de la parte A de S16
│   ├── S19/
│   ├── S20
│   └── S22/
|       └── evidencias/
|           ├── consistencia-ejemplares.txt
│           ├── funciones-procedimientos.txt
│           ├── pruebas-curso.txt
│           ├── pruebas-inicializacion.txt
│           ├── S22-parte-a.txt
│           └── triggers.txt
├── evidencias/                             Salidas de psql de las cargas y de los reportes
├── verificacion-parte-b.md                  Tabla de verificación de los reportes (S16)
└── README.md
```

---

## 1. Levantar el entorno

Requisitos: tener Docker Desktop abierto.

Desde la carpeta del proyecto, ejecuta:

```
docker compose up -d postgres pgadmin
docker compose logs postgres
```

La primera vez que se levanta el proyecto, si el volumen de PostgreSQL está vacío, PostgreSQL crea la base y ejecuta los scripts de postgres/init/. En los logs deben aparecer `01_esquema.sql`, `02_carga.sql` y `03_programacion.sql` sin errores.

Si el proyecto ya se había iniciado antes y el volumen conserva la base de datos, PostgreSQL no vuelve a ejecutar esos scripts. En su lugar, aparecerá el mensaje "Skipping initialization".

- **pgAdmin:** http://localhost:5050 (usuario `admin@curso.com`, contraseña `curso`). Registrar el servidor con host `postgres`, puerto `5432`, base `curso`, usuario y contraseña `curso`.
- **Desde fuera de Docker** (VS Code, DBeaver), PostgreSQL queda en `localhost:5433`.

**Si cambia algo en `postgres/init/`**

Los scripts de esta carpeta se ejecutan automáticamente cuando
PostgreSQL inicializa un volumen de datos vacío, en el siguiente orden:

1. `01_esquema.sql`: creación del esquema de negocio.
2. `02_carga.sql`: creación de las tablas de paso.
3. `03_programacion.sql`: creación de funciones, procedimientos y triggers.

Si la base de datos ya existe, la lógica del Hito 4 se puede instalar
o actualizar sin eliminar los datos:

```powershell
docker compose exec -T postgres psql -U curso -d curso -v ON_ERROR_STOP=1 -f /scripts/programacion.sql
```

El archivo `programacion.sql` es repetible y permite actualizar
los objetos de programación sin borrar las tablas de negocio.

No es necesario eliminar el volumen de PostgreSQL para instalar
la programación del Hito 4.
```

***

## 2. Cargar libros y lectores desde CSV

Carga los lectores semilla antes de ejecutar `datos-prueba.sql`. El fixture identifica a los cuatro lectores que necesita por documento, así que no depende de los valores generados en `id_usuario`.

```
docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/libros_semilla.csv -f /scripts/S14-carga-libros-biblioteca.sql

docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/S14-carga-libros-biblioteca.sql

docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/libros_prueba_propia_s14.csv -f /scripts/S14-carga-libros-biblioteca.sql

docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/lectores_semilla.csv -f /scripts/S14-carga-lectores-biblioteca.sql

docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/lectores_semilla_con_errores.csv -f /scripts/S14-carga-lectores-biblioteca.sql

docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/lectores_prueba_propia_s14.csv -f /scripts/S14-carga-lectores-biblioteca.sql
```


Ejecute los comandos en el orden indicado. Ejecutelos linea por linea.
Cada comando muestra un resumen con la cantidad de libros o lectores cargados y las filas rechazadas. Los resultados esperados para una base recién inicializada son: libros 32/0, 0/8 y 5/3; lectores 20/0, 0/6 y 5/3.

Los resultados de cada comando apareceran al final de cada ejecucion con el siguiente formato:

```
 x_cargados | filas_rechazadas
------------+------------------
          # |                #
```

Repetir una carga no duplica datos: las filas que ya existen se rechazan.

Las filas rechazadas quedan en la bitácora:

```
docker compose exec postgres psql -U curso -d curso -P pager=off -c "SELECT archivo, linea, motivo FROM biblioteca.rechazo_carga ORDER BY archivo, linea;"
```

Los criterios de validación están en `docs/mapeo-y-criterios.md`.

***

## 3. Datos de prueba y reportes

```
docker compose exec postgres psql -U curso -d curso -P pager=off -f /scripts/datos-prueba.sql
docker compose exec postgres psql -U curso -d curso -P pager=off -f /scripts/reportes.sql
```

`datos-prueba.sql` crea un bibliotecario de prueba si no existe y registra préstamos con fechas relativas a `CURRENT_DATE`, pensados para cubrir los 8 casos de verificación (empates, libro sin préstamos, devolución tarde, vencimiento hoy, mora repetida, lector sin préstamos).

| Reporte | Resultado esperado con los datos de prueba |
|---|---|
| 1. Los 20 libros más prestados | 21 filas (empate en el puesto 20) |
| 2. Lector(es) que más han leído | Mariana Gómez Rojas y Santiago Rodríguez Pérez, 21 cada uno |
| 3. Lectores morosos | 1 fila: Juan David |
| 4. Préstamos en mora | 2 filas: los dos préstamos vencidos de Juan David |

Decisiones: un préstamo está en mora si no se ha devuelto y `fecha_vencimiento < CURRENT_DATE` (vencer hoy todavía no es mora); "libros leídos" son préstamos devueltos; los empates se conservan. El detalle está en `verificacion-parte-b.md`.

## 4. Parte A de S16 (esquema tienda)

```
docker compose exec postgres psql -U curso -d curso -f /scripts/S16-tienda.sql
```

Luego abrir `entregas/S16/parte-a.sql` en el Query Tool de pgAdmin y ejecutarlo.

## 5. S19 (casos y revisión del esquema)

Desde la raíz del proyecto y con PostgreSQL en ejecución, preparar los datos
iniciales de los cuatro casos:

```
docker compose exec postgres psql -U curso -d curso -P pager=off -f /scripts/S19-esquemas.sql
```

Este script borra y recrea únicamente los esquemas `gimnasio`, `farmacia`,
`cursos_libres` y `envios`. Para volver a ejecutar las migraciones, correrlo
primero otra vez.

Después, copiar y ejecutar el archivo de casos con `psql`:

```
docker compose cp .\entregas\S19\casos.sql postgres:/tmp/S19-casos.sql
docker compose exec postgres psql -U curso -d curso -P pager=off -f /tmp/S19-casos.sql
```

`casos.sql` incluye la evidencia, migraciones y verificaciones de los cuatro
casos. La revisión del esquema Biblioteca está en `entregas\S19\parte-b.md`.

## 6. Lógica en la base de datos — Hito 4 (S22)

La lógica de negocio del proyecto Biblioteca se implementa mediante funciones, procedimientos almacenados y triggers de PostgreSQL. Su propósito es centralizar las validaciones, garantizar la integridad de los préstamos y mantener la consistencia de los ejemplares independientemente de la aplicación que acceda a la base de datos.

### 6.1. Objetos implementados

| Objeto | Tipo | Tabla / Evento | Regla o responsabilidad |
|---|---|---|---|
| `lector_en_mora` | Función | `prestamos` | Determina si un lector tiene préstamos abiertos cuya fecha de vencimiento es anterior a la fecha actual. |
| `registrar_prestamo` | Procedimiento | `prestamos` | Registra préstamos válidos, verifica los usuarios, la disponibilidad del ejemplar y la ausencia de mora. |
| `registrar_devolucion` | Procedimiento | `prestamos` | Registra la fecha de devolución y calcula los días de retraso. |
| `validar_prestamo` | Función de trigger | `prestamos` | Ejecuta las validaciones correspondientes a un nuevo préstamo abierto. |
| `actualizar_estado_ejemplar` | Función de trigger | `prestamos`, `ejemplares` | Sincroniza el estado del ejemplar con los préstamos abiertos. |
| `proteger_prestamo` | Función de trigger | `prestamos` | Impide modificar la identidad de un préstamo o reabrir uno devuelto. |
| `validar_estado_ejemplar` | Función de trigger | `ejemplares` | Comprueba la correspondencia entre el estado del ejemplar y sus préstamos abiertos. |
| `prestamo_validar` | Trigger | `prestamos` — BEFORE INSERT | Rechaza préstamos abiertos que incumplen las validaciones establecidas. |
| `prestamo_actualizar_estado` | Trigger | `prestamos` — AFTER INSERT, UPDATE, DELETE | Mantiene actualizado el estado del ejemplar. |
| `prestamo_proteger` | Trigger | `prestamos` — BEFORE UPDATE | Protege la identidad del préstamo e impide su reapertura. |
| `ejemplar_validar_estado` | Trigger | `ejemplares` — BEFORE INSERT, UPDATE OF estado | Rechaza estados incompatibles con la existencia de préstamos abiertos. |

### 6.2. Reglas de negocio implementadas

- El lector y el bibliotecario deben existir, tener el rol correspondiente y estar activos para registrar un nuevo préstamo abierto.
- El lector no debe tener préstamos en mora.
- El libro debe estar activo y el ejemplar debe encontrarse disponible.
- El plazo predeterminado de un préstamo es de 14 días.
- La duración de un préstamo debe ser positiva cuando se registra mediante el procedimiento.
- Un ejemplar no puede tener más de un préstamo abierto simultáneamente.
- Una devolución solo puede registrarse sobre un préstamo abierto.
- Un préstamo devuelto no puede volver a abrirse.
- La identidad de un préstamo existente no puede modificarse.
- El estado `prestado` de un ejemplar debe coincidir con la existencia de un préstamo abierto.

### 6.3. Justificación de los mecanismos utilizados

Los procedimientos almacenados permiten encapsular operaciones completas del negocio, como registrar un préstamo o una devolución. Esto evita repetir la lógica en diferentes aplicaciones y facilita su ejecución mediante la instrucción `CALL`.

Los triggers permiten ejecutar validaciones y actualizaciones automáticamente cuando se modifican las tablas. De esta manera, determinadas reglas se mantienen incluso cuando las operaciones se realizan directamente mediante instrucciones SQL, sin utilizar los procedimientos.

La función `lector_en_mora` centraliza el criterio utilizado para determinar si un lector tiene préstamos vencidos y permite reutilizarlo en las validaciones.

### 6.4. Mantenimiento de la desnormalización del Hito 3

En el Hito 3 se identificó que el estado `prestado` de un ejemplar puede derivarse de la existencia de un préstamo abierto. Sin embargo, se decidió conservar el atributo `estado` en la tabla `ejemplares` para facilitar las consultas de disponibilidad.

Esta redundancia controlada se mantiene mediante el trigger `prestamo_actualizar_estado`:

- Al registrar un préstamo abierto, el ejemplar pasa a `prestado`.
- Al registrar una devolución, el ejemplar vuelve a `disponible` si no existe otro préstamo abierto.
- Al eliminar un préstamo abierto, se libera el ejemplar cuando corresponde.
- Los estados `en_mantenimiento` y `perdido` representan condiciones independientes de los préstamos.

Adicionalmente, el trigger `ejemplar_validar_estado` impide modificar directamente el estado de un ejemplar de manera incompatible con sus préstamos abiertos.

La consulta de consistencia es:

```sql
SELECT e.isbn, e.id_ejemplar, e.estado
FROM biblioteca.ejemplares e
WHERE (e.estado = 'prestado')
IS DISTINCT FROM EXISTS (
    SELECT 1
    FROM biblioteca.prestamos p
    WHERE p.isbn = e.isbn
      AND p.id_ejemplar = e.id_ejemplar
      AND p.fecha_devolucion IS NULL
);
```

El resultado esperado es cero filas.

### 6.5. Instalación de la programación

Desde la raíz del proyecto, con PostgreSQL en ejecución:

```powershell
docker compose exec -T postgres psql -U curso -d curso -v ON_ERROR_STOP=1 -f /scripts/programacion.sql
```

El archivo utiliza `CREATE OR REPLACE` para las funciones y procedimientos, y `DROP TRIGGER IF EXISTS` antes de crear los triggers.

Una copia idéntica se encuentra en `postgres/init/03_programacion.sql`, lo que permite instalar automáticamente la programación al inicializar un volumen vacío.

### 6.6. Carga de datos y ejecución de pruebas

Para una base recién inicializada, primero se deben cargar los lectores y libros semilla:

```powershell
docker compose exec -T postgres psql -U curso -d curso -v ON_ERROR_STOP=1 -f /scripts/S14-carga-lectores-biblioteca.sql

docker compose exec -T postgres psql -U curso -d curso -v ON_ERROR_STOP=1 -f /scripts/S14-carga-libros-biblioteca.sql
```

Después se generan los préstamos de prueba:

```powershell
docker compose exec -T postgres psql -U curso -d curso -v ON_ERROR_STOP=1 -f /scripts/datos-prueba.sql
```

El archivo `datos-prueba.sql` identifica a los lectores de prueba mediante su documento y obtiene los identificadores correspondientes.

Durante la carga controlada de los préstamos históricos se deshabilita temporalmente el trigger `prestamo_validar`, dentro de una transacción, para generar intencionalmente los casos de mora necesarios para los reportes de S16. El trigger se habilita nuevamente antes del `COMMIT`.

Esta excepción es exclusiva de los datos de prueba y requiere permisos de propietario sobre la tabla. No debe utilizarse para registrar préstamos reales.

Para ejecutar las pruebas automatizadas:

```powershell
docker compose exec -T postgres psql -U curso -d curso -v ON_ERROR_STOP=1 -f /scripts/pruebas-programacion.sql
```

Las pruebas se ejecutan dentro de una transacción que finaliza con `ROLLBACK`, conservando los datos originales.

### 6.7. Casos de prueba

| N.º | Caso de prueba | Resultado |
|---|---|---|
| 1 | Detección de mora | Correcto |
| 2 | Registro de un préstamo válido | Correcto |
| 3 | Registro de una devolución válida | Correcto |
| 4 | Rechazo de un lector moroso | Correcto |
| 5 | Rechazo de un ejemplar ocupado | Correcto |
| 6 | Rechazo de una devolución inexistente | Correcto |
| 7 | Protección de inserciones directas mediante trigger BEFORE | Correcto |
| 8 | Rechazo de la reapertura de un préstamo devuelto | Correcto |
| 9 | Rechazo de estados inconsistentes | Correcto |
| 10 | Cambio válido a estado de mantenimiento | Correcto |
| 11 | Protección de la identidad del préstamo | Correcto |
| 12 | Verificación de consistencia global | Correcto |

### 6.8. Verificación de inicialización independiente

Se creó una base de datos temporal denominada `prueba_init` para verificar que la programación pudiera instalarse desde cero sin afectar la base de datos principal.

Se ejecutaron los tres archivos de inicialización, se cargaron los lectores y libros semilla, se generaron los préstamos de prueba y se ejecutaron las doce pruebas automatizadas.

| Indicador | Base `curso` | Base `prueba_init` |
|---|---:|---:|
| Funciones implementadas | 5 | 5 |
| Procedimientos almacenados | 2 | 2 |
| Triggers implementados | 4 | 4 |
| Pruebas superadas | 12 | 12 |
| Pruebas fallidas | 0 | 0 |
| Préstamos conservados | 64 | 64 |
| Inconsistencias de ejemplares | 0 | 0 |

También se comprobó el funcionamiento con identificadores de usuarios diferentes en ambas bases de datos.

Después de guardar las evidencias, se eliminó la base temporal y se verificó que la base principal conservara sus 64 préstamos.

### 6.9. Evidencias

Las evidencias de ejecución se encuentran en `entregas/S22/evidencias/`:

- [Pruebas en la base principal](entregas/S22/evidencias/pruebas-curso.txt).
- [Pruebas de inicialización independiente](entregas/S22/evidencias/pruebas-inicializacion.txt).
- [Funciones y procedimientos](entregas/S22/evidencias/funciones-procedimientos.txt).
- [Triggers implementados](entregas/S22/evidencias/triggers.txt).
- [Consistencia de ejemplares](entregas/S22/evidencias/consistencia-ejemplares.txt).

### 6.10. Alcance y limitaciones

Las pruebas realizadas verifican el comportamiento funcional de los procedimientos, las funciones y los triggers. No constituyen pruebas exhaustivas de concurrencia.

La implementación no establece un límite máximo de préstamos simultáneos por lector. La restricción de mora y las demás reglas incorporadas deben contrastarse con las reglas de negocio del documento del proyecto integrador.

La desactivación temporal del trigger de validación se utiliza únicamente para generar los datos históricos de prueba.

### 6.11. Conclusión

La implementación del Hito 4 permite trasladar operaciones y validaciones importantes del sistema Biblioteca a la base de datos. Los procedimientos almacenados centralizan el registro de préstamos y devoluciones, mientras que los triggers mantienen la integridad y la consistencia de los ejemplares.

Las doce pruebas automatizadas superadas en dos bases de datos independientes demuestran el funcionamiento de los casos evaluados y la posibilidad de reproducir la instalación sin afectar los datos originales.