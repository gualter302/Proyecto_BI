-- ============================================================
-- DATA WAREHOUSE — Proyecto BI Hardware (UPSE, E4 2026)
-- Motor: PostgreSQL 16   |   Modelo: Esquema Estrella (fiel al E2)
-- Se carga EXCLUSIVAMENTE desde la zona Staging del E3.
-- ============================================================

DROP TABLE IF EXISTS fact_precios CASCADE;
DROP TABLE IF EXISTS dim_tiempo   CASCADE;
DROP TABLE IF EXISTS dim_fuente   CASCADE;
DROP TABLE IF EXISTS dim_tienda   CASCADE;
DROP TABLE IF EXISTS dim_producto CASCADE;

-- ── DIMENSIONES ──────────────────────────────────────────────

CREATE TABLE dim_tiempo (
    id_tiempo    INT PRIMARY KEY,
    fecha        DATE    UNIQUE NOT NULL,
    semana_iso   INT     NOT NULL,
    mes          INT     NOT NULL CHECK (mes BETWEEN 1 AND 12),
    trimestre    INT     NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
    anio         INT     NOT NULL,
    nombre_dia   VARCHAR(15) NOT NULL
);

CREATE TABLE dim_fuente (
    id_fuente                INT PRIMARY KEY,
    nombre_fuente            VARCHAR(80)  UNIQUE NOT NULL,
    tipo_extraccion          VARCHAR(20)  NOT NULL
                                 CHECK (tipo_extraccion IN ('Web Scraping','API Publica','Archivo CSV','Fuente Propia')),
    tecnologia               VARCHAR(50)  NOT NULL,
    frecuencia_actualizacion VARCHAR(20)  NOT NULL
                                 CHECK (frecuencia_actualizacion IN ('Diaria','Semanal','Unica')),
    url_o_endpoint           VARCHAR(200)
);

CREATE TABLE dim_tienda (
    id_tienda       INT PRIMARY KEY,
    nombre_tienda   VARCHAR(80) UNIQUE NOT NULL,
    pais            VARCHAR(50) NOT NULL,
    moneda_nativa   CHAR(3)     NOT NULL,
    tipo_tienda     VARCHAR(30) NOT NULL
                        CHECK (tipo_tienda IN (
                            'Tienda especializada',
                            'Marketplace global',
                            'Marketplace ecuatoriano'
                        )),
    url_base        VARCHAR(150)
);

CREATE TABLE dim_producto (
    id_producto      INT PRIMARY KEY,
    clave_canonica   VARCHAR(160) UNIQUE NOT NULL,
    marca            VARCHAR(60)  NOT NULL,
    categoria        VARCHAR(20)  NOT NULL
                         CHECK (categoria IN ('CPU','GPU','RAM','SSD','Monitor','Periferico')),
    subcategoria     VARCHAR(50),
    modelo_raw       VARCHAR(250),
    identificado     BOOLEAN NOT NULL DEFAULT FALSE   -- TRUE si tiene modelo canonico (CPU/GPU)
);

-- ── TABLA DE HECHOS ──────────────────────────────────────────

CREATE TABLE fact_precios (
    id_hecho         INT PRIMARY KEY,
    id_producto      INT  NOT NULL REFERENCES dim_producto(id_producto),
    id_tienda        INT  NOT NULL REFERENCES dim_tienda(id_tienda),
    id_tiempo        INT  NOT NULL REFERENCES dim_tiempo(id_tiempo),
    id_fuente        INT  NOT NULL REFERENCES dim_fuente(id_fuente),
    precio_original  DECIMAL(12,4) NOT NULL CHECK (precio_original > 0),
    moneda_original  CHAR(3)       NOT NULL,
    tasa_cambio_usd  DECIMAL(10,6) NOT NULL CHECK (tasa_cambio_usd > 0),
    precio_usd       DECIMAL(12,4) NOT NULL CHECK (precio_usd > 0),
    stock_disponible BOOLEAN       NOT NULL DEFAULT TRUE,
    fecha_extraccion TIMESTAMP     NOT NULL,
    url_producto     TEXT
);

-- ── INDICES ──────────────────────────────────────────────────
CREATE INDEX idx_fact_producto ON fact_precios(id_producto);
CREATE INDEX idx_fact_tienda   ON fact_precios(id_tienda);
CREATE INDEX idx_fact_tiempo   ON fact_precios(id_tiempo);
CREATE INDEX idx_dim_prod_cat  ON dim_producto(categoria);
CREATE INDEX idx_dim_prod_key  ON dim_producto(clave_canonica);
