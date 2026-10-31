# S14 · Mapeo CSV → esquema y criterios por tipo de error

Esquema destino: `biblioteca` (`postgres/init/01_esquema.sql`).
Tablas de paso: esquema `carga` (`postgres/init/02_carga.sql`).
Scripts: `postgres/scripts/S14-carga-libros-biblioteca.sql` y `postgres/scripts/S14-carga-lectores-biblioteca.sql`.

Cada línea del CSV se lee completa como texto en `carga.stg_linea`, se parte en campos en `carga.stg_libro` / `carga.stg_lector` (con `trim`) y se valida con un `CASE`: la **primera** regla que falla da el motivo. Las filas válidas pasan a `biblioteca`; las rechazadas quedan en `biblioteca.rechazo_carga` con archivo, línea, contenido y motivo. Todo ocurre dentro de una transacción (`BEGIN … COMMIT`).

## 1. Mapeo CSV → esquema

### Libros: `isbn, titulo, autor, categoria, anio_publicacion, ejemplares_disponibles`

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| *(la línea completa)* | — | Se parte por comas | Exactamente 6 campos ("tiene N columnas, se esperaban 6") |
| `isbn` | `libros.isbn` y `ejemplares.isbn` | `trim` | No vacío ("isbn vacío"); 10 o 13 dígitos, igual que el `CHECK` del esquema ("isbn no tiene 10 o 13 dígitos"); no existe en `libros` ("isbn ya existe en el catálogo"); no repetido en el mismo archivo ("isbn repetido en el archivo (línea N)") |
| `titulo` | `libros.titulo` | `trim` | No vacío ("título vacío"); máximo 200 caracteres ("título supera 200 caracteres") |
| `autor` | `autor.nombre_autor` → `libros.id_autor` | `trim`; se da de alta en `autor` si no existe y luego se busca su id | No vacío ("autor vacío"); máximo 120 caracteres ("autor supera 120 caracteres") |
| `categoria` | `categorias.genero` → `libros.id_categoria` | `trim`; se da de alta en `categorias` si no existe y luego se busca su id | No vacía ("categoría vacía"); máximo 60 caracteres ("categoría supera 60 caracteres") |
| `anio_publicacion` | `libros.anio_publicacion` | `trim`; texto → `integer`; vacío → `NULL` | Si viene: solo dígitos ("año no numérico") y entre 1000 y 2100, igual que el `CHECK` ("año fuera del rango permitido (1000-2100)") |
| `ejemplares_disponibles` | `ejemplares` (**n filas**) | `generate_series(1, n)`: `id_ejemplar` = 1…n, `estado` = `'disponible'` (por defecto) | Número entero ("ejemplares no numérico"); ≥ 0 ("ejemplares negativo") |
| *(no viene en el CSV)* | `libros.editorial` | Queda `NULL` | — |
| *(no viene en el CSV)* | `libros.libro_activo` | Toma el `DEFAULT true` | — |

### Lectores: `documento, nombres, apellidos, correo, telefono`

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| *(la línea completa)* | — | Se parte por comas | Exactamente 5 campos ("tiene N columnas, se esperaban 5") |
| `documento` | `usuarios.documento` | `trim` | No vacío ("documento vacío"); solo dígitos, 6 a 15 ("documento no numérico o de longitud inválida"); no existe en `usuarios` ("documento ya registrado"); no repetido en el archivo ("documento o correo repetido en el archivo (línea N)") |
| `nombres` | `usuarios.nombres` | `trim` | No vacío ("nombres vacío"); máximo 80 caracteres |
| `apellidos` | `usuarios.apellidos` | `trim` | No vacío ("apellidos vacío"); máximo 80 caracteres |
| `correo` | `usuarios.correo` | `trim` + `lower` (minúsculas) | No vacío ("correo vacío"); máximo 120 caracteres; formato `algo@dominio.ext` ("correo mal formado"); no existe en `usuarios`, sin importar mayúsculas ("correo ya registrado"); no repetido en el archivo ("correo repetido en el archivo (línea N)") |
| `telefono` | `usuarios.telefono` | `trim`; vacío → `NULL` | **Opcional**. Si viene: solo dígitos, 7 a 15 ("teléfono no numérico o de longitud inválida") |
| *(constante)* | `usuarios.rol` | Siempre `'lector'` | — |
| *(no viene en el CSV)* | `usuarios.usuario_activo` | Toma el `DEFAULT true` | — |
| *(no viene en el CSV)* | `usuarios.id_administrador` | Queda `NULL` | — |

## 2. Criterios por tipo de error

### Criterio general del grupo

1. **Dato obligatorio vacío → rechazar.** No se puede adivinar.
2. **Dato presente pero inválido (formato, tipo o rango) → rechazar.** Convertirlo sería inventar.
3. **Dato opcional vacío (año, teléfono) → cargar con `NULL`**, porque el esquema lo permite.
4. **Problema mecánico (espacios sobrantes, mayúsculas en el correo) → corregir y cargar**, porque no cambia el significado.
5. **Registro que ya existe → rechazar.** El CSV es de **altas**, no de actualizaciones; modificar el catálogo en silencio sería peligroso.

### Errores de los archivos del curso (14)

**`libros_semilla_con_errores.csv`**

| # | Fila (isbn) | Problema real en el archivo | Qué se hace | Motivo registrado | Regla |
|---|---|---|---|---|---|
| 1 | 9780000000001 | ISBN ya existe en el catálogo | Rechazar | isbn ya existe en el catálogo | 5 |
| 2 | 9780000000033 | Título vacío | Rechazar | título vacío | 1 |
| 3 | 9780000000034 | Año = `"dos"` (el README dice que son los ejemplares, pero en el archivo el `dos` está en la columna del año) | Rechazar | año no numérico | 2 |
| 4 | 9780000000035 | Año = `"MCMXLIX"` (número romano) | Rechazar | año no numérico | 2 |
| 5 | 9780000000036 | Una columna de más (desalineada) | Rechazar | tiene 7 columnas, se esperaban 6 | 2 |
| 6 | 9780000000037 | Autor vacío | Rechazar | autor vacío | 1 |
| 7 | *(vacío)* | ISBN vacío | Rechazar | isbn vacío | 1 |
| 8 | 9780000000038 | Ejemplares = -3 | Rechazar | ejemplares negativo | 2 |

**`lectores_semilla_con_errores.csv`**

| # | Fila (documento) | Problema | Qué se hace | Motivo registrado | Regla |
|---|---|---|---|---|---|
| 9 | 1000000001 | Documento ya registrado | Rechazar | documento ya registrado | 5 |
| 10 | 1000000021 | Correo vacío | Rechazar | correo vacío | 1 |
| 11 | 1000000022 | Correo sin `@` | Rechazar | correo mal formado | 2 |
| 12 | 1000000023 | Teléfono no numérico (`tres-cero-cero`) | Rechazar | teléfono no numérico o de longitud inválida | 2 (el teléfono es opcional, pero si viene debe ser válido) |
| 13 | *(vacío)* | Documento vacío | Rechazar | documento vacío | 1 |
| 14 | 1000000025 | Nombres vacío | Rechazar | nombres vacío | 1 |

### Errores propios (CSV del grupo)

**`libros_prueba_propia_s14.csv`** (5 válidas + 3 errores)

| Fila | Problema | Motivo registrado |
|---|---|---|
| 9780000000101 (segunda aparición) | El mismo ISBN dos veces **dentro del archivo** | isbn repetido en el archivo (línea 3) |
| 978000000010 | ISBN de 12 dígitos | isbn no tiene 10 o 13 dígitos |
| 9780000000105 | Año 2150 | año fuera del rango permitido (1000-2100) |

**`libros_propio_s14_5validas_3errores.csv`** (5 válidas + 3 errores)

| Fila | Problema | Motivo registrado |
|---|---|---|
| 9789999999901 (segunda aparición) | El mismo ISBN dos veces dentro del archivo | isbn repetido en el archivo |
| 9789999999906 | Año 2201 | año fuera del rango permitido (1000-2100) |
| 9789999999907 | Categoría de más de 60 caracteres | categoría supera 60 caracteres |

**`lectores_prueba_propia_s14.csv`** (5 válidas + 3 errores)

| Fila | Problema | Motivo registrado |
|---|---|---|
| 1000000105 | Correo repetido con otras mayúsculas (`Valentina.Ortiz@Correo.com`) | correo repetido en el archivo (línea 3) |
| 10000A0106 | Documento con una letra | documento no numérico o de longitud inválida |
| 1000000107 | Correo sin punto en el dominio (`lucia.herrera@correo`) | correo mal formado |

### Correcciones automáticas (no son rechazos)

| Caso | Qué se hace |
|---|---|
| Espacios al inicio o al final de cualquier campo | Se corrigen con `trim` y se carga |
| Correo con mayúsculas | Se pasa a minúsculas con `lower` y se carga |
| Año vacío / teléfono vacío | Se carga con `NULL` |

## 3. Prueba de la última línea de defensa

- **Qué se hizo:** se comentó la regla *"título vacío"* del `CASE` y se recargó `libros_semilla_con_errores.csv`.
- **Resultado:** 1 cargado y 7 rechazados. El libro `9780000000033`, **con título vacío, entró al catálogo sin ningún error**, junto con sus 3 ejemplares. La bitácora registró solo los otros 7.
- **Por qué:** el script guarda el campo vacío como texto vacío (`''`), no como `NULL`, así que el `NOT NULL` del esquema no lo detecta. Para esta regla el validador era la **única** defensa.
- **Acciones:** se restauró la regla y se borró el libro inválido.
- **Hallazgo adicional:** la regla *"ejemplares negativo"* tampoco tiene respaldo en el esquema: con `generate_series(1, -3)` no se crea ningún ejemplar y no hay error.

**Mejoras pendientes** (para el Hito 3):
- Agregar `CHECK (trim(columna) <> '')` en las columnas de texto obligatorias (`titulo`, `nombre_autor`, `genero`, `nombres`, `apellidos`).
- Representar en el esquema que un libro no puede tener cantidad negativa de ejemplares.
