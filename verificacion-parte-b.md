# Verificación de la Parte B — Laboratorio S16

**Base de datos:** `curso`  
**Esquema:** `biblioteca`  
**Archivo:** `postgres/scripts/reportes.sql`

## Tabla de verificación

| Caso | Resultado esperado | Resultado obtenido | Corrección realizada |
|:---|:---|:---|:---|
| **1. Libro sin préstamos** | El libro debe conservarse con 0 préstamos, pero no entrar al top 20. | Se conserva mediante `LEFT JOIN`. Su conteo es 0 y no aparece en el top 20. | Se utilizó `LEFT JOIN` y `COUNT(p.isbn)` para contar únicamente préstamos existentes. |
| **2. Empate en el puesto 20** | Los dos libros empatados deben aparecer. | Se obtuvieron 21 filas: 19 libros con 3 préstamos y 2 con 2 préstamos. | Se eliminó el título del ordenamiento interno de `WITH TIES` y se dejó únicamente la cantidad de préstamos. |
| **3. Empate entre lectores** | Deben aparecer todos los lectores con la cantidad máxima de libros leídos. | Mariana Gómez Rojas y Santiago Rodríguez Pérez aparecen con 21 libros cada uno. | Se calculó el máximo mediante una CTE y se conservaron todos los empates. |
| **4. Lector con préstamos abiertos** | No debe aparecer entre los lectores que más libros han leído. | Juan David tiene 3 préstamos abiertos y 0 devueltos. No aparece en el Reporte 2. | Se agregó `fecha_devolucion IS NOT NULL`. |
| **5. Préstamo devuelto tarde** | No debe considerarse como mora. | El préstamo devuelto tarde de Mariana no aparece en los Reportes 3 ni 4. | Se agregó `fecha_devolucion IS NULL` para identificar préstamos sin devolver. |
| **6. Préstamo que vence hoy** | Debe aplicarse una regla para determinar si ya está en mora. | El préstamo que vence hoy no aparece en los Reportes 3 ni 4. | Se utilizó `fecha_vencimiento < CURRENT_DATE` y no `<=`. |
| **7. Lector con dos préstamos en mora** | Una aparición en el Reporte 3 y dos en el Reporte 4. | Juan David aparece una vez en el Reporte 3 y dos veces en el Reporte 4. | Se utilizó `EXISTS` en el Reporte 3 y una fila por préstamo en el Reporte 4. |
| **8. Lector sin préstamos** | No debe aparecer en los reportes de libros leídos ni de morosidad. | Los lectores sin préstamos no aparecen en los Reportes 2, 3 ni 4. | No fue necesario realizar correcciones. |

## Conclusión

Las ocho pruebas permitieron comprobar el funcionamiento de los cuatro reportes del esquema `biblioteca`.

Se verificó el tratamiento de los empates, los libros sin préstamos, los préstamos devueltos y los préstamos en mora.

La principal corrección se realizó en el Reporte 1, donde se ajustó el ordenamiento interno para que `WITH TIES` incluyera todos los libros empatados en el último puesto.

También se estableció que un préstamo se considera moroso cuando no ha sido devuelto y su fecha de vencimiento es anterior a `CURRENT_DATE`.