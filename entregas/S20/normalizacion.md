# Hito 3 – Normalización del proyecto Biblioteca

## 1. Esquema antes de la normalización

El esquema `biblioteca` contiene siete tablas de negocio: `usuarios`, `autor`, `categorias`, `libros`, `ejemplares`, `prestamos` y `rechazo_carga`.

Las tablas de carga CSV y `s16_control_prestamos_prueba` son auxiliares y quedan fuera del modelo de negocio.

## 2. Dependencias funcionales y claves candidatas

El análisis se basa en S19 y en las restricciones de `01_esquema.sql`.

Reglas de negocio confirmadas: cada persona tiene un solo rol; el nombre identifica a un autor y el género a una categoría; cada libro tiene un autor y una categoría; el número de ejemplar es local a cada ISBN; un mismo ejemplar puede prestarse varias veces en distintos momentos.

| Tabla | Claves candidatas | Dependencias funcionales y regla que las justifica |
|---|---|---|
| usuarios | id_usuario; documento; correo | Cada clave → nombres, apellidos, correo/documento, telefono, rol, usuario_activo, id_administrador. Regla: el documento y el correo identifican a una persona, y una persona tiene un solo registro y un solo rol (PK y `UNIQUE NOT NULL`). |
| autor | id_autor; nombre_autor | id_autor → nombre_autor y nombre_autor → id_autor. Regla: el proyecto toma el nombre como identificador del autor; la carga reutiliza el autor por su nombre (`UNIQUE NOT NULL`). |
| categorias | id_categoria; genero | id_categoria → genero y genero → id_categoria. Regla: cada nombre de género identifica una categoría (`UNIQUE NOT NULL`). |
| libros | isbn | isbn → id_categoria, id_autor, titulo, editorial, anio_publicacion, libro_activo. Regla: el ISBN identifica un libro del catálogo, con un autor y una categoría. id_autor e id_categoria no determinan el ISBN (un autor tiene varios libros). |
| ejemplares | (isbn, id_ejemplar) | (isbn, id_ejemplar) → estado. Regla: id_ejemplar es el número de copia dentro de cada libro, no un identificador global. |
| prestamos | (id_lector, isbn, id_ejemplar, fecha_hora_prestamo) | La clave → id_bibliotecario, fecha_vencimiento, fecha_devolucion. Regla: el mismo lector puede pedir el mismo ejemplar en ocasiones distintas, por eso la fecha y hora forman parte de la clave. El índice único parcial sobre (isbn, id_ejemplar) con `fecha_devolucion IS NULL` impide dos préstamos abiertos de una copia, pero no es clave para todo el historial. |
| rechazo_carga | id_rechazo | id_rechazo → archivo, linea, contenido, motivo, fecha_carga. Regla: cada fila es un evento de rechazo; (archivo, linea) no es clave porque una misma línea puede rechazarse en varios intentos de carga. |

Para las claves que el DDL ya declara, la evidencia es la propia restricción (PK o `UNIQUE NOT NULL`): una consulta de duplicados no puede devolver filas.

## 3. Formas normales y problemas encontrados

| Tabla | Forma normal | Observación |
|---|---|---|
| usuarios | FNBC de negocio | Marcador de rol generado. |
| autor | FNBC | Sin anomalías identificadas. |
| categorias | FNBC | Sin anomalías identificadas. |
| libros | FNBC | Autor y categoría mediante FK. |
| ejemplares | FNBC | El valor `prestado` de `estado` es un dato derivado guardado a propósito (ver sección 5). |
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
| ejemplares | 0 | 94 |
| prestamos | 0 | 64 |

Evidencia: `evidencias/conteos-prueba-init.txt`. Los scripts de `postgres/init/` corrieron sin errores en la base vacía.

### Reportes de S16 sobre el esquema

Se corrieron `datos-prueba.sql` y `reportes.sql` en la base del grupo (`evidencias/reportes-originales.txt`) y en `prueba_init` (`evidencias/reportes-prueba-init.txt`). Los reportes 1, 2 y 3 dan exactamente lo mismo: 21 libros en el top (empate en el puesto 20), Mariana Gómez y Santiago Rodríguez con 21 libros leídos, y Juan David Martínez como único moroso.

El reporte 4 muestra una diferencia (`evidencias/comparacion-reportes.txt`) que **no se debe al esquema**: `datos-prueba.sql` genera las fechas relativas a `CURRENT_DATE`. En la base del grupo los datos se cargaron el 30-oct y el reporte se corrió un día después, así que el préstamo que vence "hoy" (*Los miserables*, vence el 30-oct) ya estaba vencido y apareció en mora (3 filas). En `prueba_init` los datos y el reporte se corrieron el mismo día: ese préstamo no está en mora, porque la regla es `fecha_vencimiento < CURRENT_DATE`, y el reporte da **2 filas**, que es el resultado esperado de los casos 6 y 7 de la verificación de S16.

## 5. Desnormalizaciones deliberadas

**`ejemplares.estado = 'prestado'`.** Es la única redundancia del esquema. Que un ejemplar esté prestado se puede calcular: existe un préstamo abierto (`fecha_devolucion IS NULL`) para ese ejemplar. Se guarda a propósito por dos razones:

1. La columna `estado` hace falta de todas formas, porque `en_mantenimiento` y `perdido` no se pueden deducir de ninguna otra tabla. Con `prestado` en la misma columna, la disponibilidad del catálogo se resuelve filtrando una sola tabla (`estado = 'disponible'`), sin recorrer el historial de préstamos.
2. En la parte A de S20 se midió el mismo patrón: calcular la disponibilidad recorriendo préstamos tomó 13.07 ms; con índices, 4.30 ms; con el dato guardado, 0.59 ms (`parte-a.md`).

- **Mecanismo de consistencia:** por ahora, registrar un préstamo o una devolución actualiza `prestamos` y `ejemplares.estado` dentro de la **misma transacción**, como hace `datos-prueba.sql`. En el Hito 4 se reemplazará por un **trigger** sobre `prestamos` (al insertar, el ejemplar pasa a `prestado`; al registrar la devolución, vuelve a `disponible`).
- **Consulta de verificación:** la de la sección 3. Debe devolver 0 filas; devolvió **0 filas** en ambas bases (`evidencias/verificacion-consistencia.txt`).
- **Alternativa descartada:** quitar `prestado` de los valores de `estado` y calcularlo siempre. Es más normalizado, pero obligaría a cada consulta del catálogo a unir con `prestamos`.

**`prestamos.fecha_vencimiento` no es redundante.** Con el plazo por defecto de 14 días podría calcularse como `fecha_hora_prestamo + 14`, pero las reglas del proyecto permiten cambiar el plazo o dar plazos especiales. La fecha de vencimiento es un **hecho histórico** de cada préstamo: si se calculara con la regla vigente, un cambio de plazo alteraría las fechas de préstamos antiguos y haría aparecer o desaparecer moras. Guardarla es correcto en 3FN.

## 6. Esquema después

El esquema **no cambió**: `postgres/init/01_esquema.sql` es el mismo y crea directamente el esquema final, probado en `prueba_init`.

| Tabla | Forma normal final |
|---|---|
| usuarios | FNBC en los atributos de negocio (ver nota) |
| autor, categorias, libros, ejemplares, rechazo_carga | FNBC |
| prestamos | FNBC en los atributos de negocio (ver nota) |

**Nota:** las columnas generadas `rol_administrador`, `rol_lector` y `rol_bibliotecario` dependen de su identificador (`id_lector → rol_lector`, etc.), lo que en la relación física es una dependencia transitiva. Son auxiliares técnicos para validar los roles mediante FK compuestas: PostgreSQL las calcula y no se pueden modificar a mano, así que no generan anomalías de actualización. Ninguna tabla queda en 3FN sin estar en FNBC en sus atributos de negocio. La única redundancia del modelo es la de `ejemplares.estado`, documentada en la sección 5.
