-- ============================================================
-- KPIs NATIVOS DEL DATA WAREHOUSE (vistas lógicas)
-- Los 5+ KPIs del E1 viven aquí como VIEWs ejecutables en el motor.
-- ============================================================

-- ── Detección automatizada de outliers (regla IQR por categoría) ──
-- Marca precios atípicos (ej. PCs armadas mal clasificadas).
DROP VIEW IF EXISTS vw_kpi_outliers CASCADE;
CREATE VIEW vw_kpi_outliers AS
WITH q AS (
    SELECT p.categoria,
           PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY f.precio_usd) AS q1,
           PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY f.precio_usd) AS q3
    FROM fact_precios f
    JOIN dim_producto p ON f.id_producto = p.id_producto
    GROUP BY p.categoria
)
SELECT f.id_hecho, p.categoria, p.clave_canonica, t.nombre_tienda, f.precio_usd,
       ROUND(q.q1::numeric, 2) AS q1, ROUND(q.q3::numeric, 2) AS q3
FROM fact_precios f
JOIN dim_producto p ON f.id_producto = p.id_producto
JOIN dim_tienda   t ON f.id_tienda   = t.id_tienda
JOIN q ON q.categoria = p.categoria
WHERE f.precio_usd > q.q3 + 1.5 * (q.q3 - q.q1)
   OR f.precio_usd < q.q1 - 1.5 * (q.q3 - q.q1);

-- ── Base de precios válidos: hechos SIN outliers (para KPIs de comparación) ──
DROP VIEW IF EXISTS vw_precios_validos CASCADE;
CREATE VIEW vw_precios_validos AS
SELECT f.*, p.clave_canonica, p.categoria, p.marca, p.identificado,
       t.nombre_tienda
FROM fact_precios f
JOIN dim_producto p ON f.id_producto = p.id_producto
JOIN dim_tienda   t ON f.id_tienda   = t.id_tienda
WHERE f.id_hecho NOT IN (SELECT id_hecho FROM vw_kpi_outliers);

-- KPI 1 — Menor precio por modelo (USD) y tienda que lo ofrece
DROP VIEW IF EXISTS vw_kpi_menor_precio_modelo CASCADE;
CREATE VIEW vw_kpi_menor_precio_modelo AS
WITH ranked AS (
    SELECT id_producto, clave_canonica, categoria, marca,
           nombre_tienda, precio_usd,
           RANK()  OVER (PARTITION BY id_producto ORDER BY precio_usd ASC) AS rk,
           COUNT(*) OVER (PARTITION BY id_producto) AS n_tiendas
    FROM vw_precios_validos
    WHERE identificado = TRUE
)
SELECT clave_canonica, categoria, marca,
       nombre_tienda AS tienda_mas_barata,
       precio_usd    AS menor_precio_usd,
       n_tiendas
FROM ranked
WHERE rk = 1 AND n_tiendas >= 2;

-- KPI 2 — Tienda más competitiva (frecuencia con que ofrece el menor precio)
DROP VIEW IF EXISTS vw_kpi_tienda_competitiva CASCADE;
CREATE VIEW vw_kpi_tienda_competitiva AS
SELECT tienda_mas_barata AS nombre_tienda, categoria,
       COUNT(*) AS veces_mas_barata
FROM vw_kpi_menor_precio_modelo
GROUP BY tienda_mas_barata, categoria;

-- KPI 3 — Brecha porcentual máx–mín por modelo
DROP VIEW IF EXISTS vw_kpi_brecha_modelo CASCADE;
CREATE VIEW vw_kpi_brecha_modelo AS
SELECT clave_canonica, categoria,
       MIN(precio_usd) AS precio_min_usd,
       MAX(precio_usd) AS precio_max_usd,
       ROUND((MAX(precio_usd) - MIN(precio_usd)) / MIN(precio_usd) * 100, 1) AS brecha_pct
FROM vw_precios_validos
WHERE identificado = TRUE
GROUP BY clave_canonica, categoria
HAVING COUNT(DISTINCT id_tienda) >= 2;

-- KPI 4 — Ahorro potencial por modelo (vs precio promedio del mercado)
DROP VIEW IF EXISTS vw_kpi_ahorro_potencial CASCADE;
CREATE VIEW vw_kpi_ahorro_potencial AS
SELECT clave_canonica, categoria,
       ROUND(AVG(precio_usd), 2) AS precio_promedio_usd,
       MIN(precio_usd)           AS precio_min_usd,
       ROUND((AVG(precio_usd) - MIN(precio_usd)) / AVG(precio_usd) * 100, 1) AS ahorro_pct
FROM vw_precios_validos
WHERE identificado = TRUE
GROUP BY clave_canonica, categoria
HAVING COUNT(DISTINCT id_tienda) >= 2;

-- KPI 5 — Precio promedio (normalizado USD) por categoría y tienda
DROP VIEW IF EXISTS vw_kpi_precio_promedio_cat CASCADE;
CREATE VIEW vw_kpi_precio_promedio_cat AS
SELECT categoria, nombre_tienda,
       COUNT(*)                    AS n_ofertas,
       ROUND(AVG(precio_usd), 2)   AS precio_promedio_usd,
       ROUND(MIN(precio_usd), 2)   AS precio_min_usd,
       ROUND(MAX(precio_usd), 2)   AS precio_max_usd
FROM vw_precios_validos
GROUP BY categoria, nombre_tienda;

-- KPI 6 — Cobertura de identificación (ofertas con modelo canónico)
DROP VIEW IF EXISTS vw_kpi_cobertura CASCADE;
CREATE VIEW vw_kpi_cobertura AS
SELECT p.categoria,
       COUNT(*)                                        AS total_ofertas,
       SUM(CASE WHEN p.identificado THEN 1 ELSE 0 END) AS ofertas_identificadas,
       ROUND(100.0 * SUM(CASE WHEN p.identificado THEN 1 ELSE 0 END) / COUNT(*), 1) AS cobertura_pct
FROM fact_precios f
JOIN dim_producto p ON f.id_producto = p.id_producto
GROUP BY p.categoria;
