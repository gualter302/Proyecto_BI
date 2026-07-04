-- ============================================================
-- CONSULTAS ANALÍTICAS — una por cada pregunta de investigación (E1)
-- Todas ejecutan JOINs explícitos hecho <-> dimensiones.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- PREGUNTA PRINCIPAL
-- ¿Qué tienda ofrece el menor precio para cada modelo de CPU y GPU
--  (precio normalizado a USD)?
-- Técnica: RANK() como función de ventana (partición por producto).
-- ─────────────────────────────────────────────────────────────
SELECT categoria, clave_canonica AS modelo, marca,
       tienda_mas_barata, menor_precio_usd, n_tiendas
FROM vw_kpi_menor_precio_modelo
ORDER BY categoria, menor_precio_usd DESC
LIMIT 15;

-- ─────────────────────────────────────────────────────────────
-- SECUNDARIA 1
-- ¿Cuál es la diferencia porcentual entre el menor y el mayor precio
--  observado para un mismo modelo entre todas las tiendas?
-- ─────────────────────────────────────────────────────────────
SELECT categoria, clave_canonica AS modelo,
       precio_min_usd, precio_max_usd, brecha_pct
FROM vw_kpi_brecha_modelo
ORDER BY brecha_pct DESC
LIMIT 10;

-- Promedio general de la brecha (respuesta cuantitativa directa)
SELECT ROUND(AVG(brecha_pct), 1) AS brecha_promedio_pct,
       COUNT(*) AS modelos_comparados
FROM vw_kpi_brecha_modelo;

-- ─────────────────────────────────────────────────────────────
-- SECUNDARIA 2
-- ¿Qué tienda ofrece con mayor frecuencia el menor precio por categoría?
-- ─────────────────────────────────────────────────────────────
SELECT categoria, nombre_tienda, veces_mas_barata
FROM vw_kpi_tienda_competitiva
ORDER BY categoria, veces_mas_barata DESC;

-- Ranking global de competitividad (qué tienda gana más veces en total)
SELECT nombre_tienda, SUM(veces_mas_barata) AS total_veces_mas_barata
FROM vw_kpi_tienda_competitiva
GROUP BY nombre_tienda
ORDER BY total_veces_mas_barata DESC;

-- ─────────────────────────────────────────────────────────────
-- SECUNDARIA 3  (adaptada: mercado 100% ecuatoriano)
-- Entre las tiendas ecuatorianas, ¿cuál mantiene el nivel de precios
--  más alto y cuál el más bajo? (índice de nivel de precios por tienda)
-- Técnica: DENSE_RANK sobre el precio promedio por categoría.
-- ─────────────────────────────────────────────────────────────
WITH prom AS (
    SELECT t.nombre_tienda, p.categoria, AVG(f.precio_usd) AS precio_prom
    FROM fact_precios f
    JOIN dim_producto p ON f.id_producto = p.id_producto
    JOIN dim_tienda   t ON f.id_tienda   = t.id_tienda
    WHERE p.identificado = TRUE
    GROUP BY t.nombre_tienda, p.categoria
),
rk AS (
    SELECT nombre_tienda, categoria, ROUND(precio_prom, 2) AS precio_prom,
           DENSE_RANK() OVER (PARTITION BY categoria ORDER BY precio_prom ASC) AS rank_barato
    FROM prom
)
SELECT nombre_tienda,
       ROUND(AVG(rank_barato), 2) AS indice_nivel_precios,  -- menor = más barata
       COUNT(*) AS categorias_evaluadas
FROM rk
GROUP BY nombre_tienda
ORDER BY indice_nivel_precios ASC;

-- ─────────────────────────────────────────────────────────────
-- SECUNDARIA 4
-- ¿Cuál es el ahorro potencial promedio al elegir el menor precio
--  frente al precio promedio del mercado?
-- ─────────────────────────────────────────────────────────────
SELECT ROUND(AVG(ahorro_pct), 1) AS ahorro_potencial_promedio_pct,
       COUNT(*) AS modelos_evaluados
FROM vw_kpi_ahorro_potencial;

-- Top modelos con mayor ahorro potencial
SELECT categoria, clave_canonica AS modelo,
       precio_promedio_usd, precio_min_usd, ahorro_pct
FROM vw_kpi_ahorro_potencial
ORDER BY ahorro_pct DESC
LIMIT 8;

-- ─────────────────────────────────────────────────────────────
-- PLUS — Detección automatizada de outliers (regla IQR)
-- ─────────────────────────────────────────────────────────────
SELECT categoria, clave_canonica AS modelo, nombre_tienda, precio_usd, q1, q3
FROM vw_kpi_outliers
ORDER BY precio_usd DESC
LIMIT 10;
