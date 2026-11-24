# Hito 3 – Normalización del proyecto Biblioteca

## 1. Esquema antes de la normalización

El esquema `biblioteca` contiene siete tablas de negocio: `usuarios`, `autor`, `categorias`, `libros`, `ejemplares`, `prestamos` y `rechazo_carga`.

Las tablas de carga CSV y `s16_control_prestamos_prueba` son auxiliares y quedan fuera del modelo de negocio.

## 2. Dependencias funcionales y claves candidatas

El análisis se basa en S19 y en las restricciones de `01_esquema.sql`.

| Tabla | Claves candidatas | Dependencia y regla |
|---|---|---|
| usuarios | id_usuario, documento, correo | Cada clave determina los demás atributos (PK y UNIQUE NOT NULL). |
| autor | id_autor, nombre_autor | Cada clave determina la otra por unicidad. |
| categorias | id_categoria, genero | Cada clave determina la otra por unicidad. |
| libros | isbn | Determina los atributos bibliográficos (PK). |
| ejemplares | (isbn, id_ejemplar) | Determina el estado del ejemplar (PK compuesta). |
| prestamos | (id_lector, isbn, id_ejemplar, fecha_hora_prestamo) | Determina bibliotecario, vencimiento y devolución (PK compuesta). |
| rechazo_carga | id_rechazo | Determina los datos del evento de rechazo (PK). |

## 3. Formas normales y problemas encontrados

| Tabla | Forma normal | Observación |
|---|---|---|
| usuarios | FNBC de negocio | Marcador de rol generado. |
| autor | FNBC | Sin anomalías identificadas. |
| categorias | FNBC | Sin anomalías identificadas. |
| libros | FNBC | Autor y categoría mediante FK. |
| ejemplares | FNBC | Riesgo de inconsistencia con préstamos abiertos. |
| prestamos | FNBC de negocio | Marcadores de roles generados. |
| rechazo_carga | FNBC | Historial independiente de rechazos. |

Los atributos generados `rol_administrador`, `rol_lector` y `rol_bibliotecario` permiten garantizar los roles mediante claves foráneas compuestas. Constituyen excepciones técnicas a la 3FN estricta de las relaciones físicas, pero no son modificables manualmente.

Para verificar la consistencia entre ejemplares y préstamos abiertos se ejecutó:

```sql
SELECT e.isbn, e.id_ejemplar, e.estado
FROM biblioteca.ejemplares e
WHERE (e.estado = 'prestado') IS DISTINCT FROM EXISTS (
    SELECT 1 FROM biblioteca.prestamos p
    WHERE p.isbn = e.isbn
      AND p.id_ejemplar = e.id_ejemplar
      AND p.fecha_devolucion IS NULL
);
```

**Resultado:** cero inconsistencias en ambas bases. Sin embargo, el esquema todavía no garantiza automáticamente esta correspondencia ante todas las operaciones.

## 4. Cambios aplicados y verificación

No se realizaron migraciones estructurales porque los atributos de negocio cumplen FNBC bajo las reglas identificadas. Se conservaron las redundancias técnicas justificadas; por ello no se creó `normalizacion.sql`.

Se reconstruyó el esquema en la base independiente `prueba_init`, ejecutando los scripts de inicialización, las cargas S14 y los datos de prueba S16.

| Tabla | Antes de cargar | Después de cargar |
|---|---:|---:|
| usuarios | 0 | 21 |
| autor | 0 | 29 |
| categorias | 0 | 9 |
| libros | 0 | 32 |
| ejemplares | 0