# Data Warehouse — Comparador de Hardware Ecuador (E4)

Data Warehouse en **PostgreSQL 16** (esquema estrella, fiel al diseño del E2),
cargado **exclusivamente desde la zona Staging del E3** (no desde Raw).

> 📌 **Instalación y arranque** (Docker, cargar datos, restaurar el dump): ver el
> **[README principal](../README.md)** — sección "Instalación y ejecución".
> Este documento cubre solo lo específico del DW: **credenciales, cómo
> consultarlo y sus archivos.**

---

## Credenciales de conexión

| Parámetro | Valor |
|---|---|
| Host | localhost |
| Puerto | 5433 |
| Base de datos | bi_hardware |
| Usuario | bi_user |
| Contraseña | bi_pass_2026 |

---

## Cómo VER / CONSULTAR la base de datos

### Opción 1 — Desde la terminal (sin instalar nada más)
```bash
docker exec -it bi_hardware_dw psql -U bi_user -d bi_hardware
```
Ya dentro (`bi_hardware=#`):
```sql
\dt                                             -- listar tablas
\dv                                             -- listar vistas (los KPIs)
SELECT COUNT(*) FROM fact_precios;              -- tabla de hechos
SELECT * FROM vw_kpi_menor_precio_modelo LIMIT 10;
\q                                              -- salir
```

### Opción 2 — Con una herramienta gráfica (recomendado para explorar)
Instalar **DBeaver** o **pgAdmin**, crear una conexión PostgreSQL con las
credenciales de arriba y navegar las tablas/vistas visualmente. También sirve
la extensión **PostgreSQL** de VS Code.

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
| `06_cargar_tasas.py` | Carga la serie temporal de tasas (para el dashboard) |
| `dump_bi_hardware.sql` | Dump ejecutable completo del DW (esquema + datos + vistas) |

---

## Detener / reiniciar el DW
```bash
docker stop bi_hardware_dw      # detener (los datos persisten en el volumen)
docker start bi_hardware_dw     # volver a levantar
```
