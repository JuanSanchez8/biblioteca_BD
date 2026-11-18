# Hito 3 · Documento de normalización

**Proyecto:** Biblioteca
**Estado:** borrador de trabajo; el análisis de S19 está revisado y quedan pendientes al final las decisiones aún no confirmadas.

## 1. Esquema antes de la revisión

El esquema de negocio `biblioteca`, definido en [`postgres/init/01_esquema.sql`](../../postgres/init/01_esquema.sql), contiene estas tablas:

| Tabla | Clave primaria | Relaciones principales |
|---|---|---|
| `usuarios` | `id_usuario` | `id_administrador` referencia otro usuario. |
| `categorias` | `id_categoria` | — |
| `autor` | `id_autor` | — |
| `libros` | `isbn` | Referencia `categorias` y `autor`. |
| `ejemplares` | (`isbn`, `id_ejemplar`) | Referencia `libros`. |
| `prestamos` | (`id_lector`, `isbn`, `id_ejemplar`, `fecha_hora_prestamo`) | Referencia usuarios con rol, y el ejemplar prestado. |
| `rechazo_carga` | `id_rechazo` | Bitácora de filas rechazadas al importar datos. |

Las tablas `carga.stg_*` se usan como preparación temporal de archivos y no se incluyen como entidades del esquema de negocio. El análisis original por tabla está en [`entregas/S19/parte-b.md`](../S19/parte-b.md).

## 2. Claves candidatas y dependencias funcionales

Las reglas de negocio confirmadas para esta revisión son: cada persona tiene un solo rol; el nombre identifica un autor y el género identifica una categoría; cada libro tiene un autor y una categoría; y el número de ejemplar es local a cada ISBN. Los CSV de libros tienen una columna de autor y una de categoría, en concordancia con estas reglas.

| Tabla | Claves candidatas | Dependencias funcionales y justificación |
|---|---|---|
| `usuarios` | `id_usuario`; `documento`; `correo` | Cada clave determina los demás atributos (**DDL:** PK y `UNIQUE NOT NULL`). La unicidad de documento y correo, junto con un registro por persona, representa la regla de un rol por persona. |
| `categorias` | `id_categoria`; `genero` | `id_categoria → genero` (**PK**); `genero → id_categoria` (**DDL:** `UNIQUE NOT NULL`; cada nombre identifica una categoría). |
| `autor` | `id_autor`; `nombre_autor` | `id_autor → nombre_autor` (**PK**); `nombre_autor → id_autor` (**DDL:** `UNIQUE NOT NULL`; el proyecto adopta el nombre como identificador único). Un autor puede estar asociado a varios libros. |
| `libros` | `isbn` | `isbn → id_categoria, id_autor, titulo, editorial, anio_publicacion, libro_activo` (**DDL:** PK; el ISBN identifica el libro del catálogo). El modelo permite un autor y una categoría por libro. |
| `ejemplares` | (`isbn`, `id_ejemplar`) | (`isbn`, `id_ejemplar`) `→ estado` (**DDL:** PK compuesta). |
| `prestamos` | (`id_lector`, `isbn`, `id_ejemplar`, `fecha_hora_prestamo`) | La clave determina `id_bibliotecario`, `fecha_vencimiento` y `fecha_devolucion` (**DDL:** PK compuesta). El índice único parcial evita dos préstamos abiertos de una misma copia, pero no es clave candidata para todo el historial. |
| `rechazo_carga` | `id_rechazo` | `id_rechazo → archivo, linea, contenido, motivo, fecha_carga` (**DDL:** PK). (`archivo`, `linea`) no es clave: una misma fila puede rechazarse en más de un intento. |

Las reglas de unicidad de nombres de autor y categoría y de roles por persona están impuestas por el DDL y fueron confirmadas para el proyecto. Las columnas generadas `rol_administrador`, `rol_lector` y `rol_bibliotecario` son auxiliares para validar las claves foráneas por rol; no son atributos descriptivos del negocio.

## 3. Forma normal y diagnóstico

| Tabla | Forma normal más alta | Diagnóstico y evidencia |
|---|---|---|
| `usuarios` | FNBC para los atributos de negocio. | No se identifica anomalía en los datos de negocio bajo la regla de un rol por persona. `id_usuario`, `documento` y `correo` están protegidos por PK/`UNIQUE NOT NULL`. En la relación física estricta, `id_administrador → rol_administrador` por la columna generada; esa columna auxiliar hace que la tabla no alcance 3FN si se cuenta como atributo ordinario. |
| `categorias` | FNBC. | Sin anomalía identificada. La PK y `UNIQUE NOT NULL` protegen las dos claves candidatas declaradas. |
| `autor` | FNBC bajo la regla adoptada. | Sin anomalía identificada. La PK y `UNIQUE NOT NULL` protegen las dos claves candidatas declaradas. |
| `libros` | FNBC. | Sin anomalía de normalización identificada. Autor y categoría se guardan mediante FK, no como nombres repetidos. |
| `ejemplares` | FNBC. | La clave compuesta identifica la copia. La consistencia de `estado` con los préstamos abiertos es un problema entre tablas, no una dependencia funcional que viole la forma normal de `ejemplares`; se revisa abajo. |
| `prestamos` | FNBC para los atributos de negocio. | Sin anomalía de normalización identificada. En la relación física estricta, `id_lector → rol_lector` e `id_bibliotecario → rol_bibliotecario` por columnas generadas auxiliares; al contarlas como atributos ordinarios, la tabla no alcanza 3FN. |
| `rechazo_carga` | FNBC. | Sin anomalía identificada. Repetir archivo y línea puede registrar intentos distintos y no es una duplicación indebida. |

Para las claves candidatas que el DDL ya declara, la evidencia es la PK y las restricciones `UNIQUE NOT NULL`; una consulta de duplicados no puede demostrar la regla mejor que esas restricciones. Las dependencias también se apoyan en las reglas de negocio confirmadas, no solo en los datos cargados.

### Consistencia entre ejemplares y préstamos

El proyecto requiere que `ejemplares.estado = 'prestado'` coincida exactamente con la existencia de un préstamo abierto para esa copia. El DDL no garantiza por sí solo esta correspondencia. Esta consulta detecta las filas que no coinciden; **su resultado aún está pendiente de ejecutar y registrar**:

```sql
SELECT e.isbn, e.id_ejemplar, e.estado
FROM biblioteca.ejemplares e
WHERE (e.estado = 'prestado') IS DISTINCT FROM EXISTS (
    SELECT 1
    FROM biblioteca.prestamos p
    WHERE p.isbn = e.isbn
      AND p.id_ejemplar = e.id_ejemplar
      AND p.fecha_devolucion IS NULL
);
```

### Texto obligatorio vacío

`NOT NULL` no impide insertar una cadena vacía. Los cargadores S14 rechazan esos valores, pero el esquema permite ingresarlos por otras vías. [`docs/mapeo-y-criterios.md`](../../docs/mapeo-y-criterios.md) registra este límite y propone evaluar restricciones `CHECK` para `libros.titulo`, `autor.nombre_autor`, `categorias.genero`, `usuarios.nombres` y `usuarios.apellidos`. Este es un asunto de integridad de datos, no una violación de forma normal; falta comprobar si hay valores vacíos y decidir si se agregan las restricciones.

## 4. Cambios de normalización

Con el análisis actual no se encontró una dependencia que requiera descomponer tablas ni trasladar datos. Por tanto, no se propone una migración de datos de normalización y `postgres/scripts/normalizacion.sql` puede no existir si no se realizan cambios. Si se decide agregar restricciones para textos vacíos, se documentará ese ajuste de esquema y se reflejará en `postgres/init/`; no es una migración de descomposición.


## 5. prueba_init

```
docker compose exec postgres psql -U curso -d curso -tAc "SELECT 1 FROM pg_database WHERE datname = 'prueba_init';"
```

Si no devuelve nada, ejecute:

```
docker compose exec postgres psql -U curso -d curso -c "CREATE DATABASE prueba_init;"
docker compose exec postgres psql -U curso -d prueba_init -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/01_esquema.sql
docker compose exec postgres psql -U curso -d prueba_init -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/02_carga.sql
```

## Pendientes por dialogar o completar

1. Decidir si se agregan los `CHECK` para evitar textos obligatorios vacíos; antes, ejecutar la consulta de evidencia y registrar su resultado.
2. Acordar cómo se mantendrá sincronizado el estado del ejemplar con el préstamo (por ahora, actualización en una misma transacción; un trigger podría quedar para el Hito 4) y ejecutar la consulta de verificación.
3. Mantener explícita en la entrega la diferencia entre FNBC de los atributos de negocio y la forma normal estricta de las tablas físicas con columnas auxiliares generadas.
4. Probar `postgres/init/` en una base vacía y ejecutar `datos-prueba.sql` y `reportes.sql` de S16 contra el esquema final; registrar los resultados.
5. Completar las secciones finales del Hito 3: cambios aplicados y conteos, desnormalizaciones y mecanismos de consistencia, esquema después, y evidencias/resultados de las pruebas.
