# Data Warehouse — Entregable 4 (Comparador de Hardware Ecuador)

Data Warehouse en **PostgreSQL 16** (esquema estrella, fiel al diseño del E2),
cargado **exclusivamente desde la zona Staging del E3** (no desde Raw).

> **Guía rápida para el docente:** si solo quiere revisar la base de datos sin
> ejecutar el pipeline, vaya directo al **Paso 1** + **Paso 2 (Opción B: restaurar
> el dump)** + **Paso 3 (ver la base de datos)**. Toma ~3 minutos.

---

## Requisitos
- **Docker Desktop** (para el motor PostgreSQL).
- **Python 3.11+** con `pip install psycopg2-binary pandas` (solo si va a re-cargar
  desde Staging; no hace falta si restaura el dump).

---

## Paso 1 — Levantar el motor PostgreSQL 16 (Docker)

```bash
docker run -d --name bi_hardware_dw \
  -e POSTGRES_USER=bi_user -e POSTGRES_PASSWORD=bi_pass_2026 \
  -e POSTGRES_DB=bi_hardware -p 5432:5432 \
  -v bi_hardware_pgdata:/var/lib/postgresql/data postgres:16
```

**Credenciales de conexión:**

| Parámetro | Valor |
|---|---|
| Host | localhost |
| Puerto | 5432 |
| Base de datos | bi_hardware |
| Usuario | bi_user |
| Contraseña | bi_pass_2026 |

---

## Paso 2 — Cargar los datos (elija UNA opción)

**Opción A — Ejecutar el ETL desde Staging (reproducible):**
```bash
pip install psycopg2-binary pandas
python warehouse/02_cargar_dw.py          # crea el esquema y carga desde Staging
python warehouse/05_reporte_analitico.py  # crea las vistas KPI y muestra resultados
```

**Opción B — Restaurar el dump (lo más rápido, sin pipeline):**
```bash
docker exec -i bi_hardware_dw psql -U bi_user -d bi_hardware < warehouse/dump_bi_hardware.sql
```

---

## Paso 3 — VER / CONSULTAR la base de datos

### Opción 1 — Desde la terminal (sin instalar nada más)
Abrir una consola SQL dentro del contenedor:
```bash
docker exec -it bi_hardware_dw psql -U bi_user -d bi_hardware
```
Ya dentro (`bi_hardware=#`), algunos comandos útiles:
```sql
\dt                       -- listar tablas
\dv                       -- listar vistas (los KPIs)
SELECT COUNT(*) FROM fact_precios;              -- 940 hechos
SELECT * FROM vw_kpi_menor_precio_modelo LIMIT 10;   -- KPI: tienda más barata por modelo
\q                        -- salir
```

O ejecutar todo el archivo de consultas analíticas de una vez:
```bash
docker exec -i bi_hardware_dw psql -U bi_user -d bi_hardware -f - < warehouse/03_consultas_analiticas.sql
```

### Opción 2 — Con una herramienta gráfica (recomendado para explorar)
Instalar **DBeaver** (gratis) o **pgAdmin**, crear una conexión PostgreSQL con las
credenciales de arriba (host `localhost`, puerto `5432`, base `bi_hardware`,
usuario `bi_user`, contraseña `bi_pass_2026`) y navegar las tablas/vistas
visualmente. También sirve la extensión **PostgreSQL** de VS Code.

### Consultas de ejemplo (responden las preguntas del E1)
```sql
-- ¿En qué tienda está más barato cada modelo?
SELECT * FROM vw_kpi_menor_precio_modelo ORDER BY menor_precio_usd DESC;

-- ¿Qué tienda gana más veces en precio?
SELECT nombre_tienda, SUM(veces_mas_barata) AS veces
FROM vw_kpi_tienda_competitiva GROUP BY nombre_tienda ORDER BY veces DESC;

-- Brecha promedio de precios entre tiendas
SELECT ROUND(AVG(brecha_pct),1) AS brecha_promedio_pct FROM vw_kpi_brecha_modelo;

-- Outliers detectados automáticamente (IQR)
SELECT categoria, clave_canonica, nombre_tienda, precio_usd
FROM vw_kpi_outliers ORDER BY precio_usd DESC;
```

---

## Archivos del warehouse

| Archivo | Contenido |
|---|---|
| `01_schema_dw.sql` | DDL del esquema estrella (5 tablas, PK/FK, CHECK, índices) |
| `02_cargar_dw.py` | ETL Staging → DW (dimensiones + hechos) |
| `03_consultas_analiticas.sql` | Una consulta por pregunta de investigación del E1 |
| `04_kpis.sql` | 7 vistas de KPIs nativas (incluye detección de outliers IQR) |
| `05_reporte_analitico.py` | Ejecuta KPIs y consultas, muestra resultados reales |
| `dump_bi_hardware.sql` | Dump ejecutable completo del DW (esquema + datos + vistas) |

## Registros cargados

| Tabla | Registros |
|---|---|
| fact_precios | 940 |
| dim_producto | 794 |
| dim_tiempo | 365 |
| dim_fuente | 9 |
| dim_tienda | 6 |

---

## Detener / reiniciar el DW
```bash
docker stop bi_hardware_dw      # detener (los datos persisten en el volumen)
docker start bi_hardware_dw     # volver a levantar
```
