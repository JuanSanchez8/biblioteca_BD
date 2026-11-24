# S22 · Parte A: respuestas

El SQL completo está en [`postgres/scripts/S22-grupo.sql`](../../postgres/scripts/S22-grupo.sql) y la salida de las baterías en [`evidencias/S22-parte-a.txt`](evidencias/S22-parte-a.txt). Todas las pruebas dieron el resultado esperado.

## A1 (b). Acción `ON DELETE` de cada FK

| FK | Acción | Justificación |
|---|---|---|
| `sala_recurso → sala` | `CASCADE` | Los recursos son un atributo multivaluado de la sala: no existen sin ella, así que se borran con ella. |
| `reserva → sala` | `RESTRICT` | Borrar la sala borraría o dejaría huérfano el historial de reservas. Una sala que deja de usarse se marca con `activa = false`, no se borra. |
| `reserva → estudiante` | `RESTRICT` | Las reservas son el historial del estudiante y la base de sus sanciones (regla 5). Un estudiante con reservas no se puede borrar. |

En la batería, `DELETE` de la sala 4 pasa y sus recursos desaparecen en cascada (`count = 0`); `DELETE` de la sala 1 falla porque tiene reservas.

## A1 (d). El `INSERT` que pasa todas las restricciones

La reserva de 9 personas en la Sala A el lunes de 9:00 a 10:00 viola dos reglas:

- **Regla 2 (capacidad):** la Sala A tiene capacidad para 4, no para 9.
- **Regla 3 (cruce):** se cruza con la reserva de Ana (8:00 a 10:00).

Ninguna restricción `CHECK` lo puede impedir porque un `CHECK` solo ve **la fila que se está insertando o modificando** (S21, sección 3.4). La capacidad está en otra tabla (`sala`) y el cruce depende de **otras filas** de `reserva`. PostgreSQL no permite subconsultas dentro de un `CHECK` (`cannot use subquery in check constraint`). Estas reglas necesitan una función, un procedimiento o un trigger (o, para el cruce, una restricción `EXCLUDE`, ver el reto).

## A4 (b). ¿Qué pasa si `sala_libre` no excluye la propia reserva?

En un `UPDATE`, la fila vieja todavía existe en la tabla cuando corre el trigger `BEFORE`. Si no se excluye, `sala_libre` encuentra la misma reserva, que siempre se "cruza" consigo misma, y el trigger rechaza **cualquier** modificación de una reserva activa, aunque no cambie la hora. Por ejemplo, `UPDATE reserva SET asistentes = 5 WHERE id = 6` fallaría con "sala ocupada". Por eso se pasa `NEW.id` como `p_excluir`.

## A4 (d). ¿Las reglas 4 y 5 van en el trigger o solo en el procedimiento?

**Solo en el procedimiento.** Según S21 (sección 8), un trigger `BEFORE` es para las reglas entre filas que **nadie debe poder saltarse**. Las reglas 2 y 3 son de ese tipo: dos grupos en la misma sala a la misma hora, o más personas que sillas, es imposible sin importar quién reserve. Por eso van en el trigger, que se aplica a toda escritura.

Las reglas 4 (6 horas por semana) y 5 (sanción) son **políticas sobre el estudiante que pide la reserva**, pensadas para el autoservicio. Otros actores escriben en `reserva` con razones válidas para no cumplirlas. Por ejemplo, la coordinación reserva la Sala C para un evento a nombre de un monitor: ese monitor puede superar las 6 horas o estar sancionado, y la reserva igual es legítima. Si las reglas 4 y 5 estuvieran en el trigger, nadie podría hacer esa excepción. En el procedimiento `reservar`, que es el camino de los estudiantes, se aplican siempre que corresponde.

(La duración de 4 horas del ejemplo choca con `reserva_duracion`, que es una regla de los datos. Si la coordinación necesita eventos más largos, hay que cambiar esa regla, no saltársela.)

## A5. ¿Por qué el último `UPDATE` no sanciona a Bruno? ¿Qué pasaría sin el `WHEN`?

`UPDATE reserva SET asistentes = 2 WHERE id = 8` **no sanciona a Bruno** por dos razones:

1. El trigger es `AFTER UPDATE OF estado`: solo se considera cuando el `UPDATE` incluye la columna `estado` en el `SET`. Aquí solo cambia `asistentes`.
2. Aunque el `UPDATE` incluyera `estado`, el `WHEN (NEW.estado = 'no_asistio' AND OLD.estado <> 'no_asistio')` exige un **cambio** hacia `no_asistio`. La reserva 8 ya era `no_asistio`.

**Sin el `WHEN`**, el trigger se ejecutaría en cualquier `UPDATE` que nombre `estado`, sin importar el valor: cancelar una reserva, marcarla `cumplida` o volver a escribir `no_asistio` en una que ya lo era sancionaría al estudiante. Además, cada corrección repetida le renovaría los 7 días. El `WHEN` limita la sanción al momento exacto en que se registra la inasistencia, y además evita llamar a la función cuando no hace falta.

## A6 (b). 2 000 reservas vencidas: sentencias y disparos

| | `cerrar_vencidas_ciclo()` | `cerrar_vencidas()` |
|---|---|---|
| Sentencias `UPDATE` | **2 000** (una por vuelta), más el `SELECT` del ciclo y 2 000 `RAISE NOTICE` | **1** |
| Disparos de `reserva_validar` | **2 000** | **2 000** |

El trigger es `FOR EACH ROW`, así que se ejecuta una vez **por fila afectada**, no por sentencia (S21, sección 6.1): en las dos versiones se modifican 2 000 filas, así que hay 2 000 disparos. En ambos casos el trigger termina de inmediato, porque `NEW.estado = 'cumplida'` no es `'activa'`. `reserva_sancionar` no ejecuta su función ninguna vez, porque su `WHEN` es falso. La diferencia está en el número de sentencias: con la versión de conjunto, el optimizador procesa las 2 000 filas de una vez, en lugar de ejecutar un `UPDATE` por fila (S21, sección 7).

## Reto. Regla 3 con `EXCLUDE`

Con `reserva_sin_cruce` y el trigger desactivado, el `INSERT` que se cruza con la reserva de Ana falla (`conflicting key value violates exclusion constraint`) y el que no se cruza pasa. Según la tabla de S21 (sección 8), se empieza por arriba: lo que se puede declarar como restricción no se programa en un trigger. Si se usa `reserva_sin_cruce`, el trigger ya **no necesita la parte de `sala_libre`**, porque la restricción impone la regla 3. En el trigger queda solo la **regla 2** (sala en mantenimiento y capacidad), porque depende de otra tabla (`sala`) y ninguna restricción la puede expresar.
