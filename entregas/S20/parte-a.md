# S20 – Taller de desnormalización para rendimiento

## Parte A: Experimentación con desnormalización

### A1. Medición inicial

Se ejecutó el script `S20-rendimiento.sql` sobre PostgreSQL, utilizando el esquema independiente `rendimiento`, sin modificar el esquema principal del proyecto Biblioteca.

El conjunto inicial de datos contiene:

| Tabla | Registros |
|---|---:|
| Libros | 5.000 |
| Ejemplares | 15.000 |
| Lectores | 2.000 |
| Préstamos | 303.750 |

Se utilizó `EXPLAIN ANALYZE` para medir los tiempos de ejecución de las consultas.

La consulta del catálogo para los títulos que coinciden con `Libro 12%`, calculando la disponibilidad de los ejemplares, obtuvo un tiempo promedio de **13.071 ms** antes de incorporar los índices adicionales.

### A2. Optimización mediante índices

Antes de desnormalizar, se evaluó la posibilidad de mejorar el rendimiento mediante índices.

Se utilizaron los siguientes índices:

- `ejemplar_isbn_idx`: facilita la búsqueda de ejemplares asociados a un libro.
- `prestamo_abierto_idx`: índice parcial que facilita la búsqueda de préstamos abiertos.

Después de incorporar los índices, el tiempo promedio de ejecución de la consulta del catálogo disminuyó a **4.301 ms**.

Esto representa una reducción aproximada del 67,10 % respecto a la consulta inicial, sin necesidad de almacenar información redundante.

### A3. Desnormalización mediante un atributo calculado

Se incorporó el atributo `disponibles` en la tabla `rendimiento.libro`, con el propósito de almacenar directamente la cantidad de ejemplares disponibles de cada libro.

De esta manera, la consulta del catálogo evita calcular la disponibilidad mediante las relaciones entre libros, ejemplares y préstamos cada vez que se ejecuta.

El tiempo promedio obtenido fue de **0.586 ms**.

La reducción respecto a la consulta inicial fue del 95,52 %, equivalente a una aceleración aproximada de 22,31 veces.

#### Prueba de inconsistencia

Para comprobar los riesgos de almacenar información redundante, se registró un préstamo sin actualizar el atributo `disponibles`.

La vista `rendimiento.descuadre` permitió detectar la siguiente inconsistencia:

| ISBN | Disponibilidad almacenada | Disponibilidad calculada |
|---|---:|---:|
| 9780000000001 | 3 | 2 |

El resultado demuestra que almacenar un atributo calculado mejora el rendimiento de lectura, pero introduce la necesidad de mantenerlo sincronizado con las operaciones de préstamo y devolución.

Como mecanismo de consistencia, se propone actualizar el contador dentro de la misma transacción o utilizar triggers que automaticen dicha actualización.

### A4. Desnormalización mediante una vista materializada

Se evaluó la consulta correspondiente a los 20 libros más prestados.

La consulta original, que calcula los resultados directamente a partir de los préstamos, obtuvo un tiempo promedio de **101.768 ms**.

Posteriormente, se utilizó la vista materializada `rendimiento.top_prestados`, obteniendo un tiempo promedio de **0.180 ms**.

La reducción del tiempo de ejecución fue aproximadamente del 99,82 %.

#### Prueba de actualización de la vista materializada

Se insertaron 4.000 préstamos históricos adicionales correspondientes al libro número 5.000.

La consulta directa sobre los datos actualizados mostró que este libro alcanzó un total de 4.021 préstamos. Sin embargo, la vista materializada no reflejó inmediatamente los cambios.

Para actualizarla se ejecutó:

```sql
REFRESH MATERIALIZED VIEW rendimiento.top_prestados;
```

Después de ejecutar esta instrucción, la vista materializada reflejó los datos actualizados.

Esta prueba demuestra que las vistas materializadas permiten acelerar considerablemente las consultas de agregación, pero pueden presentar información desactualizada entre una actualización y otra.

Su utilización resulta conveniente cuando no se requiere información en tiempo real y existe una estrategia definida de actualización.

### A5. Análisis del atributo `fecha_esperada`

El atributo `fecha_esperada` representa la fecha prevista de devolución de un préstamo.

Si la duración de todos los préstamos fuera siempre de 14 días y esta regla nunca cambiara, la fecha esperada podría calcularse a partir de la fecha del préstamo, por lo que almacenarla sería redundante.

Sin embargo, si las políticas de préstamo pueden cambiar, conservar la fecha esperada permite mantener las condiciones originales bajo las cuales se realizó cada préstamo.

Por ejemplo, si posteriormente el plazo de devolución cambia de 14 a 21 días, los préstamos anteriores deben conservar su fecha de devolución originalmente establecida.

Por esta razón, se considera justificado almacenar este atributo como un dato histórico del préstamo cuando representa una condición establecida al momento de registrarlo.

## Tabla de mediciones

Los siguientes valores corresponden a los tiempos promedio de ejecución obtenidos durante las pruebas, expresados en milisegundos.

| Consulta | Sin índices adicionales | Con índices (A2) | Desnormalizada (A3 o A4) |
|---|---:|---:|---:|
| Catálogo (`Libro 12%`) | 13.071 ms | 4.301 ms | 0.586 ms |
| Top 20 más prestados | 101.768 ms | No aplica | 0.180 ms |

## Comparación de rendimiento

| Optimización | Reducción del tiempo | Aceleración |
|---|---:|---:|
| Catálogo con índices | 67,10 % | 3,04 veces |
| Catálogo desnormalizado | 95,52 % | 22,31 veces |
| Top 20 con vista materializada | 99,82 % | 565,38 veces |

## Conclusiones

- La creación de índices permite mejorar el rendimiento sin introducir redundancia en los datos.
- La desnormalización mediante atributos calculados puede reducir considerablemente los tiempos de consulta, pero requiere mecanismos adicionales de consistencia.
- Las vistas materializadas son útiles para consultas de agregación costosas, siempre que se establezca una estrategia de actualización.
- La desnormalización debe estar respaldada por mediciones de rendimiento y no aplicarse de manera indiscriminada.
- Se recomienda priorizar un esquema normalizado y evaluar los índices antes de introducir información redundante.
- Las decisiones de desnormalización deben considerar tanto el rendimiento como la integridad y actualización de los datos.