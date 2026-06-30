-- ============================================================
-- STAR SCHEMA — Proyecto BI Hardware (UPSE 2026-1)
-- Motor: PostgreSQL 16
-- ============================================================

-- ── DIMENSIONES ──────────────────────────────────────────────

CREATE TABLE dim_tiempo (
    id_tiempo    SERIAL PRIMARY KEY,
    fecha        DATE    UNIQUE NOT NULL,
    semana_iso   INT     NOT NULL,
    mes          INT     NOT NULL CHECK (mes BETWEEN 1 AND 12),
    trimestre    INT     NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
    anio         INT     NOT NULL,
    nombre_dia   VARCHAR(15) NOT NULL
);

CREATE TABLE dim_fuente (
    id_fuente               SERIAL PRIMARY KEY,
    nombre_fuente           VARCHAR(80)  UNIQUE NOT NULL,
    tipo_extraccion         VARCHAR(20)  NOT NULL
                                CHECK (tipo_extraccion IN ('Web Scraping','API Publica','Archivo CSV')),
    tecnologia              VARCHAR(50)  NOT NULL,
    frecuencia_actualizacion VARCHAR(20) NOT NULL
                                CHECK (frecuencia_actualizacion IN ('Diaria','Semanal','Unica')),
    url_o_endpoint          VARCHAR(200)
);

CREATE TABLE dim_tienda (
    id_tienda       SERIAL PRIMARY KEY,
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
    id_producto      SERIAL PRIMARY KEY,
    clave_canonica   VARCHAR(120) UNIQUE NOT NULL,
    marca            VARCHAR(60)  NOT NULL,
    categoria        VARCHAR(20)  NOT NULL
                         CHECK (categoria IN ('CPU','GPU','RAM','SSD','Monitor','Periferico')),
    subcategoria     VARCHAR(50),          -- ej: DDR5, NVMe, IPS, Mecanico, Headset, Teclado
    modelo_raw       VARCHAR(200),         -- nombre original antes de normalizar
    especificaciones TEXT
);

-- ── TABLA DE HECHOS ──────────────────────────────────────────

CREATE TABLE fact_precios (
    id_hecho         SERIAL PRIMARY KEY,
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

-- ── DATOS SEMILLA (dim_tienda) ────────────────────────────────

INSERT INTO dim_tienda (nombre_tienda, pais, moneda_nativa, tipo_tienda, url_base) VALUES
  ('Newegg',               'EE.UU.',       'USD', 'Tienda especializada',     'https://www.newegg.com'),
  ('PCComponentes',        'Espana',        'EUR', 'Tienda especializada',     'https://www.pccomponentes.com'),
  ('Scan',                 'Reino Unido',   'GBP', 'Tienda especializada',     'https://www.scan.co.uk'),
  ('CanadaComputers',      'Canada',        'CAD', 'Tienda especializada',     'https://www.canadacomputers.com'),
  ('eBay',                 'Global',        'USD', 'Marketplace global',       'https://www.ebay.com'),
  ('MercadoLibre Ecuador', 'Ecuador',       'USD', 'Marketplace ecuatoriano',  'https://www.mercadolibre.com.ec');

-- ── DATOS SEMILLA (dim_fuente) ────────────────────────────────

INSERT INTO dim_fuente (nombre_fuente, tipo_extraccion, tecnologia, frecuencia_actualizacion, url_o_endpoint) VALUES
  ('Scraping Newegg',          'Web Scraping', 'Playwright', 'Semanal', 'https://www.newegg.com'),
  ('Scraping PCComponentes',   'Web Scraping', 'Playwright', 'Semanal', 'https://www.pccomponentes.com'),
  ('Scraping Scan',            'Web Scraping', 'Playwright', 'Semanal', 'https://www.scan.co.uk'),
  ('Scraping CanadaComputers', 'Web Scraping', 'Playwright', 'Semanal', 'https://www.canadacomputers.com'),
  ('API eBay Browse',          'API Publica',  'requests/OAuth', 'Semanal', 'https://api.ebay.com/buy/browse/v1/item_summary/search'),
  ('API MercadoLibre EC',      'API Publica',  'requests/OAuth', 'Semanal', 'https://api.mercadolibre.com/sites/MEC/search'),
  ('API Frankfurter',          'API Publica',  'requests',       'Diaria',  'https://api.frankfurter.dev/latest'),
  ('CSV Kaggle Computer Parts','Archivo CSV',  'pandas read_csv','Unica',   'https://www.kaggle.com/datasets/');
