# Proyecto Biblioteca · Bases de Datos (750006C)

Sistema de biblioteca del proyecto integrador. Este repositorio contiene el entorno Docker, el esquema en PostgreSQL, la carga masiva desde CSV y las consultas de los reportes.

## Estructura

```
docker-compose.yml                 Entorno: PostgreSQL 16 + pgAdmin
postgres/
  init/                            Se ejecuta solo, una vez, cuando la base se crea vacía
    01_esquema.sql                 Esquema de negocio "biblioteca"
    02_carga.sql                   Esquema "carga" con las tablas de paso (stg_*)
  scripts/                         Dentro del contenedor: /scripts
    S14-carga-libros-biblioteca.sql
    S14-carga-lectores-biblioteca.sql
    datos-prueba.sql               Préstamos de prueba para los reportes (S16)
    reportes.sql                   Los 4 reportes del proyecto (S16)
    S16-tienda.sql                 Esquema de práctica de la parte A de S16
    datos/                         CSV semilla del curso y CSV propios
docs/
  mapeo-y-criterios.md             Mapeo CSV → esquema y criterios de error (S14)
entregas/
  S16/parte-a.sql                  Las 11 consultas de la parte A de S16
evidencias/                        Salidas de psql de las cargas y de los reportes
verificacion-parte-b.md            Tabla de verificación de los reportes (S16)
```

## 1. Levantar el entorno

Requisitos: Docker Desktop abierto.

```
docker compose up -d postgres pgadmin
docker compose logs postgres
```

En los logs deben aparecer `01_esquema.sql` y `02_carga.sql` sin errores.

- **pgAdmin:** http://localhost:5050 (usuario `admin@curso.com`, contraseña `curso`). Registrar el servidor con host `postgres`, puerto `5432`, base `curso`, usuario y contraseña `curso`.
- **Desde fuera de Docker** (VS Code, DBeaver), PostgreSQL queda en `localhost:5433`.

**Si cambia algo en `postgres/init/`**, hay que recrear la base para que vuelva a ejecutarse (borra los datos):

```
docker compose down
docker volume ls                     # buscar el volumen que termina en pg_curso_data
docker volume rm <nombre_del_volumen>
docker compose up -d postgres pgadmin
```

## 2. Cargar libros y lectores desde CSV

El orden importa: los lectores semilla deben quedar con `id_usuario` del 1 al 20, porque `datos-prueba.sql` los usa.

```
docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/libros_semilla.csv -f /scripts/S14-carga-libros-biblioteca.sql
docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/S14-carga-libros-biblioteca.sql
docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/libros_prueba_propia_s14.csv -f /scripts/S14-carga-libros-biblioteca.sql
docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/lectores_semilla.csv -f /scripts/S14-carga-lectores-biblioteca.sql
docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/lectores_semilla_con_errores.csv -f /scripts/S14-carga-lectores-biblioteca.sql
docker compose exec postgres psql -U curso -d curso -P pager=off -v archivo=/scripts/datos/lectores_prueba_propia_s14.csv -f /scripts/S14-carga-lectores-biblioteca.sql
```

Resultado esperado (cargadas / rechazadas): libros 32/0, 0/8, 5/3; lectores 20/0, 0/6, 5/3.
Repetir una carga no duplica datos: las filas que ya existen se rechazan.

Las filas rechazadas quedan en la bitácora:

```
docker compose exec postgres psql -U curso -d curso -P pager=off -c "SELECT archivo, linea, motivo FROM biblioteca.rechazo_carga ORDER BY archivo, linea;"
```

Los criterios de validación están en `docs/mapeo-y-criterios.md`.

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
