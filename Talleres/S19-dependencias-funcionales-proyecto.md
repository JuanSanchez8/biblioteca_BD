# S19 · Dependencias funcionales del proyecto Biblioteca

Este documento sirve como borrador para el pre-trabajo de S19 y como punto de
partida para la revisión del esquema en la Parte B. Se basa en el DDL actual de
[`biblioteca`](../postgres/init/01_esquema.sql) y [`carga`](../postgres/init/02_carga.sql).
Antes de entregarlo, el grupo debe comprobar que las reglas descritas siguen
siendo las reglas reales del proyecto.

## Cómo leer y validar la tabla

Una dependencia funcional `X → Y` significa que, si dos filas coinciden en los
atributos de `X`, necesariamente coinciden también en los de `Y`. La flecha debe
justificarse con una regla del negocio o una restricción del esquema; que los
datos actuales no tengan duplicados no basta para afirmar que la dependencia
siempre se cumple.

- Una clave primaria determina todos los atributos de su tabla.
- Una clave `UNIQUE NOT NULL` también determina todos los atributos de su tabla
  y, por tanto, es una clave candidata.
- Una clave foránea garantiza que el valor referenciado existe, pero no crea
  por sí sola una dependencia funcional en la tabla que contiene la FK.
- Se anotan dependencias no triviales en forma compacta: una determinante hacia
  el resto de atributos relevantes. No hace falta listar las dependencias que
  se obtienen por transitividad.
- **DDL** indica que la dependencia se desprende de una restricción declarada.
  **Regla de negocio** indica una regla que el grupo debe confirmar y que podría
  no estar impuesta por una restricción SQL.

## Esquema de negocio `biblioteca`

| Tabla | Claves candidatas declaradas | Dependencias funcionales y regla que las justifica |
|---|---|---|
| `usuarios` | `id_usuario`; `documento`; `correo` | `id_usuario → documento, nombres, apellidos, correo, telefono, rol, usuario_activo, id_administrador, rol_administrador` (**DDL:** PK). `documento →` esos mismos atributos (**DDL:** `UNIQUE NOT NULL`). `correo →` esos mismos atributos (**DDL:** `UNIQUE NOT NULL`). La dependencia desde `documento` y `correo` implica que, según el diseño actual, una persona no puede tener más de un registro/rol. Si el negocio permite que una persona tenga varios roles, hay que revisar ese diseño antes de dar por válida esta regla. |
| `categorias` | `id_categoria`; `genero` | `id_categoria → genero` (**DDL:** PK). `genero → id_categoria` (**DDL:** `UNIQUE NOT NULL`; el nombre del género identifica una categoría). |
| `autor` | `id_autor`; `nombre_autor` | `id_autor → nombre_autor` (**DDL:** PK). `nombre_autor → id_autor` (**DDL:** `UNIQUE NOT NULL`; el esquema trata el nombre como único). Confirmar si dos autores homónimos deben poder registrarse por separado; si sí, `nombre_autor` no debería ser clave candidata por sí solo. |
| `libros` | `isbn` | `isbn → id_categoria, id_autor, titulo, editorial, anio_publicacion, libro_activo` (**DDL:** `isbn` es PK). El diseño asume que cada ISBN identifica un registro de libro y sus datos de catálogo. Un autor o una categoría pueden aparecer en varios libros, así que `id_autor` y `id_categoria` no determinan `isbn`. |
| `ejemplares` | `(isbn, id_ejemplar)` | `(isbn, id_ejemplar) → estado` (**DDL:** PK compuesta). `id_ejemplar` es el número de copia dentro de un libro, no un identificador global; por eso no determina por sí solo una fila. |
| `prestamos` | `(id_lector, isbn, id_ejemplar, fecha_hora_prestamo)` | `(id_lector, isbn, id_ejemplar, fecha_hora_prestamo) → id_bibliotecario, fecha_vencimiento, fecha_devolucion` (**DDL:** PK compuesta). La regla permite que el mismo lector solicite el mismo ejemplar en ocasiones distintas; por eso la fecha y hora forma parte de la clave. La unicidad parcial de `(isbn, id_ejemplar)` cuando `fecha_devolucion IS NULL` solo impide dos préstamos abiertos simultáneos de una copia: no es una dependencia funcional incondicional para todo el historial. |
| `rechazo_carga` | `id_rechazo` | `id_rechazo → archivo, linea, contenido, motivo, fecha_carga` (**DDL:** PK). `(archivo, linea)` **no** se toma como clave: una misma fila de origen puede generar un rechazo en más de un intento de carga. |

### Observaciones importantes para la revisión

1. En `libros`, autor y categoría se guardan mediante sus identificadores. No se
   repiten allí `nombre_autor` ni `genero`; esas dependencias están en sus
   respectivas tablas y se relacionan mediante FKs.
2. `fecha_devolucion` puede ser `NULL` mientras el préstamo siga abierto. Los
   `CHECK` de fechas validan el orden temporal, pero no agregan claves
   candidatas.
3. Las columnas `rol_lector`, `rol_bibliotecario` y `rol_administrador` son
   generadas para validar roles en las FKs. No son identificadores de filas.
4. El esquema tiene PK para los ejemplares, pero no declara que
   `ejemplares.estado = 'disponible'` equivalga a “no tiene un préstamo abierto”.
   Si esa equivalencia es una regla del proyecto, debe verificarse y mantenerse
   explícitamente; no se debe asumir como dependencia funcional a partir del
   DDL actual.

## Tablas técnicas de carga: esquema `carga`

Estas tablas son staging temporal, no entidades del modelo de negocio. Se
incluyen para dejar claro qué reglas tienen y cuáles no están protegidas por el
DDL.

| Tabla | Claves candidatas declaradas | Dependencias funcionales y regla que las justifica |
|---|---|---|
| `stg_linea` | Ninguna declarada | El proceso asigna `n` consecutivo a cada línea copiada y usa `linea` para guardar su contenido: durante una carga, se espera `n → linea` (**regla del proceso**, no una PK/`UNIQUE` en el DDL). |
| `stg_libro` | Ninguna declarada | Durante una ejecución del cargador, cada `linea_csv` proviene de una línea de `stg_linea` y determina `contenido`, `num_campos`, los campos extraídos y `motivo` (**regla del proceso de S14**). La tabla no declara `PRIMARY KEY` ni `UNIQUE` sobre `linea_csv`, así que la dependencia no está garantizada por el DDL. |
| `stg_lector` | Ninguna declarada | Durante una ejecución del cargador, cada `linea_csv` proviene de una línea de `stg_linea` y determina `contenido`, `num_campos`, los campos extraídos y `motivo` (**regla del proceso de S14**). La tabla no declara `PRIMARY KEY` ni `UNIQUE` sobre `linea_csv`, así que la dependencia no está garantizada por el DDL. |

## Uso en la Parte B de S19

Para cada tabla del esquema de negocio, copien sus dependencias y completen la
tabla de análisis que pide S19: claves candidatas, forma normal más alta,
problema encontrado, consulta que aporte evidencia y cambio propuesto. Si una
dependencia depende de una regla del negocio que aún no está confirmada,
indíquenlo; no la presenten como un hecho probado por los datos.

Las claves candidatas y dependencias de este borrador describen el DDL que está
en el repositorio. La evidencia de datos y la decisión sobre si el diseño
cumple las reglas del proyecto se deben trabajar en la sesión y confirmar con
el grupo.
