--
-- PostgreSQL database dump
--

\restrict TYHeOSmtwqmy434WMEPBndSQxKAzBLtC7G3wyg3rIlVPtBRtOIYldJ7JhKIMHJz

-- Dumped from database version 16.14 (Debian 16.14-1.pgdg13+1)
-- Dumped by pg_dump version 16.14 (Debian 16.14-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: dim_fuente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dim_fuente (
    id_fuente integer NOT NULL,
    nombre_fuente character varying(80) NOT NULL,
    tipo_extraccion character varying(20) NOT NULL,
    tecnologia character varying(50) NOT NULL,
    frecuencia_actualizacion character varying(20) NOT NULL,
    url_o_endpoint character varying(200),
    CONSTRAINT dim_fuente_frecuencia_actualizacion_check CHECK (((frecuencia_actualizacion)::text = ANY ((ARRAY['Diaria'::character varying, 'Semanal'::character varying, 'Unica'::character varying])::text[]))),
    CONSTRAINT dim_fuente_tipo_extraccion_check CHECK (((tipo_extraccion)::text = ANY ((ARRAY['Web Scraping'::character varying, 'API Publica'::character varying, 'Archivo CSV'::character varying, 'Fuente Propia'::character varying])::text[])))
);


--
-- Name: dim_producto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dim_producto (
    id_producto integer NOT NULL,
    clave_canonica character varying(160) NOT NULL,
    marca character varying(60) NOT NULL,
    categoria character varying(20) NOT NULL,
    subcategoria character varying(50),
    modelo_raw character varying(250),
    identificado boolean DEFAULT false NOT NULL,
    CONSTRAINT dim_producto_categoria_check CHECK (((categoria)::text = ANY ((ARRAY['CPU'::character varying, 'GPU'::character varying, 'RAM'::character varying, 'SSD'::character varying, 'Monitor'::character varying, 'Periferico'::character varying])::text[])))
);


--
-- Name: dim_tiempo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dim_tiempo (
    id_tiempo integer NOT NULL,
    fecha date NOT NULL,
    semana_iso integer NOT NULL,
    mes integer NOT NULL,
    trimestre integer NOT NULL,
    anio integer NOT NULL,
    nombre_dia character varying(15) NOT NULL,
    CONSTRAINT dim_tiempo_mes_check CHECK (((mes >= 1) AND (mes <= 12))),
    CONSTRAINT dim_tiempo_trimestre_check CHECK (((trimestre >= 1) AND (trimestre <= 4)))
);


--
-- Name: dim_tienda; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dim_tienda (
    id_tienda integer NOT NULL,
    nombre_tienda character varying(80) NOT NULL,
    pais character varying(50) NOT NULL,
    moneda_nativa character(3) NOT NULL,
    tipo_tienda character varying(30) NOT NULL,
    url_base character varying(150),
    CONSTRAINT dim_tienda_tipo_tienda_check CHECK (((tipo_tienda)::text = ANY ((ARRAY['Tienda especializada'::character varying, 'Marketplace global'::character varying, 'Marketplace ecuatoriano'::character varying])::text[])))
);


--
-- Name: fact_precios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_precios (
    id_hecho integer NOT NULL,
    id_producto integer NOT NULL,
    id_tienda integer NOT NULL,
    id_tiempo integer NOT NULL,
    id_fuente integer NOT NULL,
    precio_original numeric(12,4) NOT NULL,
    moneda_original character(3) NOT NULL,
    tasa_cambio_usd numeric(10,6) NOT NULL,
    precio_usd numeric(12,4) NOT NULL,
    stock_disponible boolean DEFAULT true NOT NULL,
    fecha_extraccion timestamp without time zone NOT NULL,
    url_producto text,
    CONSTRAINT fact_precios_precio_original_check CHECK ((precio_original > (0)::numeric)),
    CONSTRAINT fact_precios_precio_usd_check CHECK ((precio_usd > (0)::numeric)),
    CONSTRAINT fact_precios_tasa_cambio_usd_check CHECK ((tasa_cambio_usd > (0)::numeric))
);


--
-- Name: vw_kpi_outliers; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_kpi_outliers AS
 WITH q AS (
         SELECT p_1.categoria,
            percentile_cont((0.25)::double precision) WITHIN GROUP (ORDER BY ((f_1.precio_usd)::double precision)) AS q1,
            percentile_cont((0.75)::double precision) WITHIN GROUP (ORDER BY ((f_1.precio_usd)::double precision)) AS q3
           FROM (public.fact_precios f_1
             JOIN public.dim_producto p_1 ON ((f_1.id_producto = p_1.id_producto)))
          GROUP BY p_1.categoria
        )
 SELECT f.id_hecho,
    p.categoria,
    p.clave_canonica,
    t.nombre_tienda,
    f.precio_usd,
    round((q.q1)::numeric, 2) AS q1,
    round((q.q3)::numeric, 2) AS q3
   FROM (((public.fact_precios f
     JOIN public.dim_producto p ON ((f.id_producto = p.id_producto)))
     JOIN public.dim_tienda t ON ((f.id_tienda = t.id_tienda)))
     JOIN q ON (((q.categoria)::text = (p.categoria)::text)))
  WHERE (((f.precio_usd)::double precision > (q.q3 + ((1.5)::double precision * (q.q3 - q.q1)))) OR ((f.precio_usd)::double precision < (q.q1 - ((1.5)::double precision * (q.q3 - q.q1)))));


--
-- Name: vw_precios_validos; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_precios_validos AS
 SELECT f.id_hecho,
    f.id_producto,
    f.id_tienda,
    f.id_tiempo,
    f.id_fuente,
    f.precio_original,
    f.moneda_original,
    f.tasa_cambio_usd,
    f.precio_usd,
    f.stock_disponible,
    f.fecha_extraccion,
    f.url_producto,
    p.clave_canonica,
    p.categoria,
    p.marca,
    p.identificado,
    t.nombre_tienda
   FROM ((public.fact_precios f
     JOIN public.dim_producto p ON ((f.id_producto = p.id_producto)))
     JOIN public.dim_tienda t ON ((f.id_tienda = t.id_tienda)))
  WHERE (NOT (f.id_hecho IN ( SELECT vw_kpi_outliers.id_hecho
           FROM public.vw_kpi_outliers)));


--
-- Name: vw_kpi_ahorro_potencial; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_kpi_ahorro_potencial AS
 SELECT clave_canonica,
    categoria,
    round(avg(precio_usd), 2) AS precio_promedio_usd,
    min(precio_usd) AS precio_min_usd,
    round((((avg(precio_usd) - min(precio_usd)) / avg(precio_usd)) * (100)::numeric), 1) AS ahorro_pct
   FROM public.vw_precios_validos
  WHERE (identificado = true)
  GROUP BY clave_canonica, categoria
 HAVING (count(DISTINCT id_tienda) >= 2);


--
-- Name: vw_kpi_brecha_modelo; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_kpi_brecha_modelo AS
 SELECT clave_canonica,
    categoria,
    min(precio_usd) AS precio_min_usd,
    max(precio_usd) AS precio_max_usd,
    round((((max(precio_usd) - min(precio_usd)) / min(precio_usd)) * (100)::numeric), 1) AS brecha_pct
   FROM public.vw_precios_validos
  WHERE (identificado = true)
  GROUP BY clave_canonica, categoria
 HAVING (count(DISTINCT id_tienda) >= 2);


--
-- Name: vw_kpi_cobertura; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_kpi_cobertura AS
 SELECT p.categoria,
    count(*) AS total_ofertas,
    sum(
        CASE
            WHEN p.identificado THEN 1
            ELSE 0
        END) AS ofertas_identificadas,
    round(((100.0 * (sum(
        CASE
            WHEN p.identificado THEN 1
            ELSE 0
        END))::numeric) / (count(*))::numeric), 1) AS cobertura_pct
   FROM (public.fact_precios f
     JOIN public.dim_producto p ON ((f.id_producto = p.id_producto)))
  GROUP BY p.categoria;


--
-- Name: vw_kpi_menor_precio_modelo; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_kpi_menor_precio_modelo AS
 WITH ranked AS (
         SELECT vw_precios_validos.id_producto,
            vw_precios_validos.clave_canonica,
            vw_precios_validos.categoria,
            vw_precios_validos.marca,
            vw_precios_validos.nombre_tienda,
            vw_precios_validos.precio_usd,
            rank() OVER (PARTITION BY vw_precios_validos.id_producto ORDER BY vw_precios_validos.precio_usd) AS rk,
            count(*) OVER (PARTITION BY vw_precios_validos.id_producto) AS n_tiendas
           FROM public.vw_precios_validos
          WHERE (vw_precios_validos.identificado = true)
        )
 SELECT clave_canonica,
    categoria,
    marca,
    nombre_tienda AS tienda_mas_barata,
    precio_usd AS menor_precio_usd,
    n_tiendas
   FROM ranked
  WHERE ((rk = 1) AND (n_tiendas >= 2));


--
-- Name: vw_kpi_precio_promedio_cat; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_kpi_precio_promedio_cat AS
 SELECT categoria,
    nombre_tienda,
    count(*) AS n_ofertas,
    round(avg(precio_usd), 2) AS precio_promedio_usd,
    round(min(precio_usd), 2) AS precio_min_usd,
    round(max(precio_usd), 2) AS precio_max_usd
   FROM public.vw_precios_validos
  GROUP BY categoria, nombre_tienda;


--
-- Name: vw_kpi_tienda_competitiva; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_kpi_tienda_competitiva AS
 SELECT tienda_mas_barata AS nombre_tienda,
    categoria,
    count(*) AS veces_mas_barata
   FROM public.vw_kpi_menor_precio_modelo
  GROUP BY tienda_mas_barata, categoria;


--
-- Data for Name: dim_fuente; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dim_fuente (id_fuente, nombre_fuente, tipo_extraccion, tecnologia, frecuencia_actualizacion, url_o_endpoint) FROM stdin;
1	Scraping CompuGamer	Web Scraping	Playwright	Semanal	https://compugamer.com.ec
2	Scraping Computron	Web Scraping	Playwright	Semanal	https://www.computron.com.ec
3	Scraping MTEC	Web Scraping	Playwright	Semanal	https://mtec-ec.com
4	Scraping NomadaWare	Web Scraping	Playwright	Semanal	https://nomadaware.com.ec
5	Scraping TecnoGame	Web Scraping	Playwright	Semanal	https://tecnogame.ec
6	Scraping Tecnosmart	Web Scraping	Playwright	Semanal	https://www.tecnosmart.com.ec
7	API Frankfurter	API Publica	requests	Diaria	https://api.frankfurter.dev/v1/latest
8	CSV CPU Specs (AMD)	Archivo CSV	pandas read_csv	Unica	https://raw.githubusercontent.com/felixsteinke/cpu-spec-dataset
9	Encuesta Propia Hardware	Fuente Propia	Formulario	Unica	raw/fuente_propia/encuesta_hardware
\.


--
-- Data for Name: dim_producto; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dim_producto (id_producto, clave_canonica, marca, categoria, subcategoria, modelo_raw, identificado) FROM stdin;
1	core ultra 7 265	Intel	CPU	NaN	Procesador Intel Core Ultra 7 265 con Intel Graphics, LGA 1851, 5.3GHz, 20 Núcleos, 30MB Caché, Incluye Disipador – 2da. Generación Arrow Lake	t
2	rtx 4060 8gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL GEFORCE RTX 4060 8GB GDDR6 OC EDITION – GPU TWEAK III – DLSS 3 – HDMI/DP (DUAL-RTX4060-O8G-WHITE)	t
3	rtx4050	NVIDIA	GPU	NaN	Laptop Lenovo LOQ AMD RYZEN 7 7735HS – 16GB RAM – 512GB SSD – GEFORCE RTX4050 – 15.6″ FHD 144HZ – W11H – LUNA GRAY (83D0000LEC)	t
4	rtx 5060 8gb	NVIDIA	GPU	NaN	Mini PC ASUS ROG NUC 15 | Ultra 7 255HX | 32GB DDR5 | 1TB SSD | RTX 5060 8GB | Win11H	t
5	rtx 5050 8gb	NVIDIA	GPU	NaN	Laptop ASUS TUF A16 FA608UH-RV063 | RYZEN 7 260 | 16GB RAM | 1TB SSD | RTX 5050 8GB | 16.0″	t
6	rtx 5070 12gb	NVIDIA	GPU	NaN	PC ASUS ROG G700TF-7265KF036X Core Ultra 7 265KF | RTX 5070 12GB | 32GB DDR5 | 1TB SSD | Win 11 Pro	t
7	rtx 5080 16g	NVIDIA	GPU	NaN	TARJETA DE VIDEO MSI GEFORCE RTX 5080 16G INSPIRE 3X – OC EDITION – 16GB GDDR7 – HDMI 2.1b/DP v2.1b (912-V531-203)	t
8	rtx 5090	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 5090 WINDFORCE OC – 32GB GDDR7 – PCIE 5.0 – HDMI 2.1b/DP 2.1b (GV-N5090WF3OC-32GD)	t
9	rtx 5060ti 16g	NVIDIA	GPU	NaN	TARJETA DE VIDEO MSI GEFORCE RTX 5060TI 16G VENTUS 2X OC PLUS – 16GB GDDR7 – DP/HDMI – 2 FAN – HDMI/DP – BLACK (912-V537-017)	t
10	rtx 5080 g	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 5080 GAMING OC 16GB GDDR7 – HDMI 2.1B /DP 1.4B (GV-N5080GAMING OC-16GD)	t
11	rtx 5060ti	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 5060TI EAGLE MAX OC 16GB GDDR7 – OC EDITION – DP 2.1b / HDMI 2.1b – BLACK (GV-N5060TIEAGLEMAX OC-16GD)	t
12	rtx 4070 ti	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS TUF GEFORCE RTX 4070 TI SUPER BTF WHITE EDITION – 16GB GDDR6X – HDMI/DP (TUF-RTX4070S-O16G-BFT-WHITE)	t
13	rtx 4060ti 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS PROART GEFORCE RTX 4060TI 16GB GDDR6 – ADVANCED EDTION – HDMI 2.1a/DP 1.4a – BLACK (PROART-RTX4060TI-A 16G)	t
14	rtx 4070 super	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL GEFORCE RTX 4070 SUPER – 12GB GDDR6X – OC EDITION – HDMI/DP (DUAL-RTX4070S-O12G)	t
15	rtx 5070 ti 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS PRIME RTX 5070 TI 16GB GDDR7 (PRIME-RTX5070TI-O16G)	t
16	rtx 5060	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE AORUS ELITE GEFORCE RTX 5060 – 8GB GDDR7 – 3 Ventiladores – BLACK (GV-N5060AORUS E-8GD)	t
17	rtx5090 32gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS TUF GAMING RTX5090 32GB GDDR7 – PCIE 5.0 – DP/HDMI – BLACK (TUF-RTX5090-32G-GAMING)	t
18	rtx 4060 ti	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL GEFORCE RTX 4060 TI OC EDITION 8GB GDDR6 – HDMI/DP (DUAL-RTX4060TI-O8G)	t
19	rtx 3050 8gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO MSI GEFORCE RTX 3050 8GB GDDR6 VENTUS 2X XS – DP/HDMI/DVI-D (912-V809-4266)	t
20	rtx 4090 g	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 4090 GAMING OC EDITION – 24GB GDDR6X DP 1.4/HDMI 2.1 – PCI-E 4.0 (GV-N4090GAMING OC-24GD)	t
21	rtx 4080 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE AORUS MASTER GEFORCE RTX 4080 16GB GDDR6X REV 1.0 – OC EDITION – WINDFORCE – DLSS/RAY TRACING/REFLEX/STUDIO – DP/HDMI (GV-N4080AORUS M-16GD)	t
22	rtx 4070ti 12gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS TUF GAMING GEFORCE RTX 4070TI 12GB GDDR6X – HDMI 2.1a/ DP 1.4a – ARGB – BLACK ( TUF-RTX4070TI-12G-GAMING)	t
23	rtx 4070 ti 12gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS TUF GAMING GEFORCE RTX 4070 Ti 12GB GDDR6X – OC EDITION (TUF-RTX4070TI-O12G-GAMING)	t
24	rtx 4090 24gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS ROG STRIX GEFORCE RTX 4090 24GB GDDR6X – OC EDITION (ROG-STRIX-RTX4090-O24G-GAMING)	t
25	rtx 4070 ti super 16gb	NVIDIA	GPU	NaN	PC/Torre CPU Core i9-14900K, Z790, SSD 1TB, 32GB DDR5 + RTX 4070 TI SUPER 16GB	t
26	rx 6900xt	AMD	GPU	NaN	TARJETA DE VIDEO GIGABYTE AORUS EXTREME AMD RADEON RX 6900XT – 16GB GDDR6 – 4K UHD – PCI-E 4.0 – WATERBLOCK – DP 1.4 WITH DSC/HDMI 2.1 VRR + AORUS ROBOT XTREME (GV-R69XTAORUSX WB-16GD)	t
27	rtx 3050 6gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO MSI VENTUS 2X – RTX 3050 6GB GDDR6 OC- HDMI/DP – PCIe 4.0 – RAY TRACING/DLSS (912-V812-060)	t
28	core i9-14900f	Intel	CPU	NaN	Procesador Intel Core I9-14900F 4.3GHz hasta 5.80GHz cache 32MB Socket LGA1700	t
29	rtx 5060 8g	NVIDIA	GPU	NaN	TARJETA DE VIDEO MSI GEFORCE RTX 5060 8G VENTUS 3X OC EDITION – 8GB GDDR7 – HDMI 2.1b/DP v2.1b (912-V537-036)	t
30	core ultra 7 265f	Intel	CPU	NaN	Procesador Intel core ultra 7 265F 1.8GHz hasta 5.3GHz 36MB LGA1851	t
31	core i9-14900	Intel	CPU	NaN	Procesador Intel Core I9-14900 Raptor Lake 4.30GHz hasta 5.4GHz cache 32MB	t
32	ryzen 3 3200g	AMD	CPU	NaN	Procesador Ryzen 3 3200G 4 Nucleos – AMD	t
33	core i7 14700f	Intel	CPU	NaN	Procesador Core i7 14700F 14va 20N+28H – Intel	t
34	core ultra 9 285k	Intel	CPU	NaN	Procesador Intel core ultra 9 285K 3.2GHz hasta 5.7GHz 40MB LGA1851	t
35	ryzen 7 9700x	AMD	CPU	NaN	Procesador AMD Ryzen 7 9700X 3.8GHz hasta 5.5GHz 32mb AM5 no	t
36	core i7-14700f	Intel	CPU	NaN	Procesador Intel Core i7-14700F Raptor Lake 2.10GHz hasta 5.40GHz cache 28MB	t
37	rtx 5070ti g	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 5070TI GAMING OC 16GB GDDR7 – DP 2.1b / HDMI 2.1b – BLACK (GV-N507TGAMING OC-16GD)	t
38	rtx 5060ti 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL GEFORCE RTX 5060TI 16GB GDDR7 – OC EDITION – PCIE- 5.0 – HDMI/DP (DUAL-RTX5060TI-O16G-EVO)	t
39	rtx 5090 32gb	NVIDIA	GPU	NaN	Tarjeta de video ASUS ROG ASTRAL GeForce RTX 5090 32GB GDDDR7	t
40	gtx 1630	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS PHOENIX GEFORCE GTX 1630 4GB GDDR6 – AUTO EXTREME HDMI/DP/DVI-D (PH-GTX1630-4G)	t
41	rtx3050 6gb	NVIDIA	GPU	NaN	Laptop MSI Thin 15 B13UDX-3085XEC | CORE i5-13420H | 8GB RAM | 512GB SSD | RTX3050 6GB | 15.6″ 144HZ (9S7-16R831-3085)	t
42	ryzen 9 9900x	AMD	CPU	NaN	Procesador AMD Ryzen 9 9900X 4.4GHz hasta 5.6GHz 64mb AM5 no	t
43	rx 9060 xt	AMD	GPU	NaN	TARJETA DE VIDEO XFX SWIFT WHITE RADEON RX 9060 XT 16GB OC GDDR6	t
44	rx 9070 xt	AMD	GPU	NaN	TARJETA DE VIDEO XFX SWIFT AMD RADEON RX 9070 XT 16GB GDDR6	t
45	rtx 5060 ti 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL EVO GEFORCE RTX 5060 TI 16GB OC	t
46	rtx 5080 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ZOTAC AMP EXTREME INFINITY GEFORCE RTX 5080 16GB GDDR7	t
47	ryzen 7 7700 5	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 7700 5.3GHZ 8+16 AM5	t
48	ryzen 5 8600g	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 8600G 6+12 5.0GHZ +RADEON 760M	t
49	ryzen 7 8700g	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 8700G 8+16 5.1GHZ +RADEON 780M	t
50	ryzen 5 8500g	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 8500G RADEON 740M	t
51	ryzen 5 9600x	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 9600X 5.4GHZ 6+12 AM5	t
52	core ultra 7 265kf	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 7 265KF 5.5GHZ 33TOPS 20+20 LGA 1851	t
53	ryzen 5 8400f	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 8400F 6+12 4.7GHZ	t
54	core ultra 5 225f	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 5 225F 4.9GHZ 19TOPS 10+10 LGA 1851	t
55	ryzen 7 8700f	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 8700F 5GHZ 8+16 AM5	t
56	ryzen 9 9950x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 9 9950X3D 5.7GHZ 16+32 AM5	t
57	ryzen 9 9900x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 9 9900X3D 5.5GHZ 12+24 AM5	t
58	ryzen 9 5900xt	AMD	CPU	NaN	PROCESADOR AMD RYZEN 9 5900XT 4.8GHZ 16+32 AM4	t
59	ryzen 5 9600 5	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 9600 5.2GHZ 6+12 AM5	t
60	core ultra 5 225	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 5 225 4.9GHZ 19TOPS 10+10 LGA 1851	t
61	rtx 3050	NVIDIA	GPU	NaN	Tarjeta de video Gigabyte Windforce RTX 3050 OC 8GB (GV-N3050GAMING OC-8GD)	t
62	rx 580 8gb	AMD	GPU	NaN	Tarjeta de video Asus Dual RX 580 8GB OC – (Dual-RX580-O8G)	t
63	rx 6700xt	AMD	GPU	NaN	GPU Asus TUF RX 6700XT OC EDITION – 12GB – (90YV0G80-M0AA00)	t
64	rtx 3050 4gb	NVIDIA	GPU	NaN	Laptop Asus TUF Gaming A15 FA506NC-HN016 | RYZEN 5 7535HS | 16GB DDR5 | 512GB SSD | RTX 3050 4GB | 15.6 | GRAPHITE BLACK	t
65	rx 6900 xt	AMD	GPU	NaN	TARJETA DE VIDEO GIGABYTE AORUS XTREME RADEON RX 6900 XT 16GB GDDR6	t
66	rx 9070 16gb	AMD	GPU	NaN	TARJETA DE VIDEO GIGABYTE GAMING AMD RADEON RX 9070 16GB OC GDDR6	t
67	core ultra 5 235	Intel	CPU	NaN	Procesador Intel core ultra 5 235 2.9GHz hasta 5GHz 26MB LGA1851	t
68	ryzen 3 5300g	AMD	CPU	NaN	Procesador Ryzen 3 5300G 4.2Ghz – AMD	t
69	core ultra 5 250kf	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 5 250KF PLUS 5.3GHZ 22TOPS 18+18 LGA 1851	t
70	ryzen 7 260	AMD	CPU	NaN	Laptop Gigabyte Gaming A16 | Ryzen 7 260 | 16GB DDR5 | 1TB | RTX 5070 8GB | 16″ FHD+ (9RGA6AB7WHKHJK0LA3M0)	t
71	ryzen 7 170	AMD	CPU	NaN	Laptop Lenovo IdeaPad Slim 3 | Touch 15.3″ | Ryzen 7 170 | 16G | 512GB	t
72	core i9-13900h	Intel	CPU	NaN	Laptop Acer Aspire A15-51M-99W4 | Core i9-13900H | 16GB DDR5 | 512GB | 15.6″ | Grist	t
73	core i7-13620h	Intel	CPU	NaN	Laptop Lenovo IdeaPad Slim 3 15IRH10 | Core i7-13620H | 16GB | 512GB | 15.3″ (83K100QCLM)	t
74	ryzen 7 7735hs	AMD	CPU	NaN	Laptop Lenovo LOQ AMD RYZEN 7 7735HS – 16GB RAM – 512GB SSD – GEFORCE RTX4050 – 15.6″ FHD 144HZ – W11H – LUNA GRAY (83D0000LEC)	t
75	core i5-13420h	Intel	CPU	NaN	Laptop MSI Thin 15 B13UDX-3085XEC | CORE i5-13420H | 8GB RAM | 512GB SSD | RTX3050 6GB | 15.6″ 144HZ (9S7-16R831-3085)	t
76	ryzen 7 7445h	AMD	CPU	NaN	Laptop HP Victus 15-FB3022LA | Ryzen 7 7445H | 16GB | 512GB | RTX4050 6GB | Win11Home	t
77	core i7-1355u	Intel	CPU	NaN	LAPTOP HP 15-FD0276LA | Core i7-1355U | 16GB RAM | 512GB SSD | 15.6″	t
78	ryzen 7 7730u	AMD	CPU	NaN	Laptop Dell Inspiron DC15255 | Ryzen 7 7730u | 16GB | 512GB | 15.6″ Tactil | Win 11 Home (G8MK9)	t
79	core i5-1334u	Intel	CPU	NaN	Laptop Dell 15 DC15250-5315BLK-PUS | Core i5-1334u | 8GB RAM | 512GB SSD | TouchScreen 15.6″ | Win11	t
80	ryzen 5 5600g	AMD	CPU	NaN	Torre CPU PC AMD Ryzen 5 5600G | 16GB DDR4 | SSD 500GB | Fuente + Case	t
81	core i9-14900k	Intel	CPU	NaN	PC/Torre CPU Core i9-14900K, Z790, SSD 1TB, 32GB DDR5 + RTX 4070 TI SUPER 16GB	t
82	core i7-14700kf	Intel	CPU	NaN	PC/Torre CPU Core i7-14700KF, TUF Z790, SSD 1TB, 32GB DDR5 + RTX 5070 12GB	t
83	core i9-14900kf	Intel	CPU	NaN	Procesador Intel Core i9-14900KF 24-Cores/32-Hilos (8P+16E) Base 3.2GHz Turbo 6GHz – Caché 36MB – LGA1700 – Sin Gráficos – 14th Gen	t
84	core i9-10980hx	Intel	CPU	NaN	REPUESTO PROCESADOR PARA LAPTOP SRH8T – INTEL CORE I9-10980HX – 10TH GEN	t
85	core ultra 9 285	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 9 285 – 24 CORES – 36MB – LGA1851	t
86	core ultra 7 265k	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 7 265K – 30MB – LGA1851 – 20-cores (8P+12E) – GRAPHICS	t
87	ryzen 7 5700g	AMD	CPU	NaN	Procesador AMD Ryzen 7 5700G – Con Graficos Radeon VEGA	t
88	core i5-10600kf	Intel	CPU	NaN	Procesador Intel Core i5-10600KF – Sin Graficos	t
89	core i7-4790k	Intel	CPU	NaN	Procesador Intel Core i7-4790K	t
90	core ultra 7 270k	Intel	CPU	NaN	Procesador Intel Core Ultra 7 270K Plus | 24-Cores | LGA1181	t
91	core i5-14400	Intel	CPU	NaN	PROCESADOR INTEL CORE i5-14400 – 2.5GHZ – 14TH – LGA1700 – UHD770 – 10 CORES – 20MB CACHE	t
92	core i3-13100f	Intel	CPU	NaN	PROCESADOR INTEL CORE i3-13100F – 3.40GHZ – 13TH – LGA1700 – 4 CORES – 12MB CACHE	t
93	core i7-14700k	Intel	CPU	NaN	Procesador Intel Core i7-14700K 20-Cores/28-Hilos (8P+12E) Base 3.4GHz Turbo 5.4GHz – Caché 33MB – Gráficos Intel – LGA1700 14th Gen	t
94	core i7-8700k	Intel	CPU	NaN	PROCESADOR INTEL CORE i7-8700K – 12MB – 3.7GHZ – LGA1151 – 6-CORES – 95W – INTEL GRAPHICS	t
95	core i7-14700	Intel	CPU	NaN	PROCESADOR INTEL CORE i7-14700 – 3.40GHZ BASE – 33MB – LGA1700	t
96	ryzen 9 9950x	AMD	CPU	NaN	PROCESADOR AMD RYZEN 9 9950X 4.3GHz – TURBO 5.7GHZ – 16 CORES – 32 HILOS – AM5 – 170W	t
97	ryzen 5 5500	AMD	CPU	NaN	Procesador AMD Ryzen 5 5500	t
98	ryzen 7 7800x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 7800X3D – 8 CORES – BASE 4.2GHZ – AM5 – CACHE 8MB	t
99	ryzen 7 7700 3	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 7700 3.8GHz BASE – 8 CORES – 16 HILOS – 8MB – AM5 – 65W (100000592BOX)	t
100	ryzen 7 9850x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 9850X3D 8-CORES/16-HILOS 4.7GHz | AM5	t
101	ryzen 7 5700x	AMD	CPU	NaN	Procesador AMD Ryzen 7 5700X 3.4GHz – 4.6Ghz – 8-Core – 16 Threads – AM4	t
102	core i3-14100f	Intel	CPU	NaN	PROCESADOR INTEL CORE i3-14100F – 3.5 GHZ – 14TH – LGA1700 – 4 CORES	t
103	ryzen 5 5600gt	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 5600GT 3.6GHZ TURBO 4.6GHz AM4 6-CORE 12 THREADS – Gráficos Radeon VEGA integrados	t
104	core i7-12700	Intel	CPU	NaN	Procesador Intel Core i7-12700	t
105	core ultra 5 245k	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 5 245K – BASE 4.2GHZ – 26MB – 159W – LGA1851	t
106	ryzen 7 9800x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 9800X3D 8-Núcleos 16-Hilos 4.7GHz Base – 5.2GHz Turbo – AM5 – DDR5	t
107	core i5 10600k	Intel	CPU	NaN	Procesador Core i5 10600K 10TH 6N 12H – Intel	t
108	rx 9070 gaming	AMD	GPU	NaN	Tarjeta de video Gigabyte Radeon™ RX 9070 GAMING OC 16G GDDR6X	t
109	rtx5060 8g	NVIDIA	GPU	NaN	Tarjeta de video MSI GeForce RTX5060 8G Cyclone OC 1 HDMI	t
110	rtx5050 8g	NVIDIA	GPU	NaN	Tarjeta de video MSI GeForce RTX5050 8G Shadow 2X OC 1	t
111	core i3 12100f	Intel	CPU	NaN	Procesador Core i3 12100F 12va Gen – Intel	t
112	core i5 12400f	Intel	CPU	NaN	Procesador Intel Core i5 12400F 12va Gen – Intel	t
113	core i9 12900kf	Intel	CPU	NaN	Procesador Core i9 12900KF 12va 16N 24H – Intel	t
114	ryzen 5 5600xt	AMD	CPU	NaN	Procesador Ryzen 5 5600XT 6N+12H – Amd	t
115	ryzen 7 5700	AMD	CPU	NaN	Procesador Ryzen 7 5700, 8N+16H – AMD	t
116	rx 7600 gaming	AMD	GPU	NaN	TARJETA DE VIDEO GIGABYTE RADEON RX 7600 GAMING OC 8G GDDR6 – WINDFORCE/OC EDITION – DP/HDMI – BLACK (GV-R76GAMING OC-8GD G11)	t
117	ryzen 7 5800xt	AMD	CPU	NaN	Procesador Ryzen 7 5800XT, 8N+16H – AMD	t
118	core i9 12900ks	Intel	CPU	NaN	Procesador Core i9 12900KS 12va 16N 24H – Intel	t
119	ryzen 9 7900x	AMD	CPU	NaN	Procesador Ryzen 9 7900X, AM5 12N 24H – AMD	t
120	ryzen 5 3400g	AMD	CPU	NaN	Procesador Ryzen 5 3400G 4N + 8H – AMD	t
121	rx 7600 xt	AMD	GPU	NaN	TARJETA DE VIDEO GIGABYTE AMD RADEON RX 7600 XT – 16GB GDDR6 GAMING OC – WINDFORCE – RAYTRACING – 3 FANS – HDMI/DP (GV-R76XTGAMING OC-16GD)	t
122	core i7 12700f	Intel	CPU	NaN	Procesador Core i7 12700F 12va Gen – Intel	t
123	core i7-10700k	Intel	CPU	NaN	Procesador Intel Core i7-10700K	t
124	ryzen 9 9950x3d2	AMD	CPU	NaN	Procesador AMD Ryzen 9 9950x3D2 Dual Edition | 16-Cores/32-Hilos | AM5 | Gráficos integrados	t
125	ryzen 5 9600	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 9600 – AM5 – 6 CORES – 12 THREAD – TURBO 5.2GHZ – 65W	t
126	ryzen 5 5500x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 5500X3D 3.0GHZ BASE – 6 CORES – 12HILOS – 96MB L3-CACHE – 105W	t
127	core i7-9700f	Intel	CPU	NaN	Procesador Intel Core i7-9700F 3GHZ 12MB CACHE LGA1151	t
128	core i5-13600kf	Intel	CPU	NaN	Procesador Intel Core i5-13600KF 14-Cores/20-Hilos (6P+8E) Base 3.5GHz Turbo 5.1GHz – Caché 24MB – LGA1700 13th Gen no graphics	t
129	gtx 1650	NVIDIA	GPU	NaN	Tarjeta Gráfica Nvidia Gtx 1650 4GB Gddr6 – Arktek	t
130	core i7-9750h	Intel	CPU	NaN	PROCESADOR INTEL CORE i7-9750H – SRF6U PARA LAPTOP	t
131	core i7-13700f	Intel	CPU	NaN	PROCESADOR INTEL CORE i7-13700F – 13TH – LGA 1700 – 2.10GHZ HASTA 5.20GHZ – 24M – 65W – 16 CORES (BX8071513700F)	t
132	core i7-13700	Intel	CPU	NaN	PROCESADOR INTEL CORE i7-13700 – 13TH – LGA 1700 – 2.10GHZ HASTA 5.20GHZ – 30M – 8 CORES – 16 NUCLEOS	t
133	core i5-13400f	Intel	CPU	NaN	PROCESADOR INTEL CORE i5-13400F – 2.50GHZ BASE – 65W – 10 NUCLEOS (BX8071513400F)	t
134	core i5-13400	Intel	CPU	NaN	PROCESADOR INTEL CORE i5-13400 4.6GHz – 20MB – LGA1700 – 13th GEN	t
135	core i5-12400	Intel	CPU	NaN	PROCESADOR INTEL CORE i5-12400 4.4GHz – 18MB – LGA1700 – 12th GEN – TRAY (SIN CAJA)	t
136	core i3-14100	Intel	CPU	NaN	PROCESADOR INTEL CORE i3-14100 – 3.5GHZ – 14TH – LGA1700 – 4 CORES	t
137	core i3-13100	Intel	CPU	NaN	PROCESADOR INTEL CORE i3-13100 – 3.40GHZ – 13TH – LGA1700 – 4 CORES – 12MB CACHE	t
138	gtx 1050ti	NVIDIA	GPU	NaN	Tarjeta Gráfica Nvidia GTX 1050TI 4gb Gddr5 – Arktek	t
139	core ultra 5 250k	Intel	CPU	NaN	Procesador Intel Core Ultra 5 250K Plus | Turbo 5.3GHz | 18-Cores | LGA1851	t
140	rtx 5070 12g	NVIDIA	GPU	NaN	Msi RTX 5070 12g Shadow 3X OC Tarjeta de Video	t
141	rtx 5070	NVIDIA	GPU	NaN	Mtec PC Rainbow Beast Ryzen 7 9700X 16GB 1TB RTX 5070	t
142	rtx 4050 16gb	NVIDIA	GPU	NaN	MSI Thin 15 B13VE Intel i5-13420H RTX 4050 16GB	t
143	core ultra 5 225h	Intel	CPU	NaN	LAPTOP ASUS EXPERTBOOK INTEL CORE ULTRA 5 225H-16GB-512GB SSD-16" WUXGA-WF6E-TPM-3Y-MOUSE-GREY-FRE	t
144	rtx 4050 6gb	NVIDIA	GPU	NaN	ASUS V16 Core 5 120H RTX 4050 6GB 16GB RAM	t
145	rtx 5060 ti	NVIDIA	GPU	NaN	Zotac Gaming GeForce RTX 5060 Ti Twin Edge OC 16GB	t
146	rtx 5070 ti	NVIDIA	GPU	NaN	Zotac Gaming Geforce RTX 5070 Ti Solid SFF OC 16GB	t
147	core ultra 7 255h	Intel	CPU	NaN	NUC ASUS INTEL CORE ULTRA 7 255H DDR5 5600MHZ M.2 WIFI7 BT5.4 HDMI-THUNDERBOLT-RJ45-VESA	t
148	rtx 5050	NVIDIA	GPU	NaN	Mtec PC Flexi Lite Core Ultra 5 500GB 16GB RTX 5050	t
149	rtx 5060 ti 8gb	NVIDIA	GPU	NaN	Asus Dual RTX 5060 Ti 8GB OC Edition Tarjeta de Video	t
150	ryzen 7 7700x	AMD	CPU	NaN	Amd Ryzen 7 7700X 4.5Ghz Am5 8 Núcleos 16 hilos	t
151	ryzen 9 270 16gb	AMD	CPU	NaN	Asus Vivobook S16 M3607HA Ryzen 9 270 16Gb 1TB 16″ Cool Silver	t
152	core ultra 5 500gb	Intel	CPU	NaN	Mtec PC Flexi Lite Core Ultra 5 500GB 16GB RTX 5050	t
153	rtx 5060 ti 16g	NVIDIA	GPU	NaN	Msi RTX 5060 Ti 16G Ventus 2X OC Plus Tarjeta Video	t
154	rtx 4050	NVIDIA	GPU	NaN	Lenovo LOQ 15ARP10E AMD R7 7735HS 16GB 512GB RTX 4050 15.6″	t
155	rtx 5070 ti g	NVIDIA	GPU	NaN	Tarjeta de Video Gigabyte NVIDIA GeForce RTX 5070 Ti GAMING OC, 16GB 256-bit GDDR7, PCI Express x16 5.0	t
156	teclado inalambrico trust gxt sento black (20062)	Varios	Periferico	Teclado	Teclado Inalambrico Trust GXT Sento – Black (20062)	f
157	monitor asus tuf vg289q	Asus	Monitor	NaN	Monitor Asus TUF VG289Q	f
158	monitor gaming msi g2712f 27 fhd ips 180 hz 1ms 300 nits dp/hdmi black	Msi	Monitor	IPS	MONITOR GAMING MSI G2712F 27″ FHD IPS – 180 HZ – 1MS – 300 NITS – DP/HDMI – BLACK	f
159	monitor teros te-2123s 21.45 fhd ips 1ms 100hz hdmi/vga black	Varios	Monitor	IPS	MONITOR TEROS TE-2123S – 21.45″ FHD IPS – 1MS – 100HZ – HDMI/VGA – BLACK	f
160	monitor asus proart pa247cv 23.8 full hd ips 100% srgb 75hz 5ms dp/hdmi/usb-c black (90lm03y1-b013b0)	Asus	Monitor	IPS	Monitor ASUS PROART PA247CV 23.8″ FULL HD – IPS – 100% sRGB – 75HZ – 5MS – DP/HDMI/USB-C – BLACK (90LM03Y1-B013B0)	f
161	monitor teros te-2711s 27 fhd 100hz 1ms ips hdmi	Varios	Monitor	IPS	MONITOR TEROS TE-2711S 27″ FHD – 100HZ – 1MS – IPS – HDMI	f
162	teclado logitech g515 tkl tactical teclas pbt tactile lightsync rgb grafite (920-012868)	Logitech	Periferico	Teclado	TECLADO LOGITECH G515 TKL – TACTICAL – TECLAS PBT – TACTILE – LIGHTSYNC RGB – GRAFITE (920-012868)	f
163	teclado logitech k120	Logitech	Periferico	Teclado	Teclado Logitech K120	f
164	monitor teros te-2401s 23.8 curvo r3000 va fhd 5ms 100hz hdmi/vga black	Varios	Monitor	VA	MONITOR TEROS TE-2401S – 23.8″ CURVO R3000 VA – FHD – 5MS – 100HZ – HDMI/VGA – BLACK	f
165	repuesto teclado + palmrest + touchpad 5cb0l02103 compatible with lenovo n22 chromebook	Varios	Periferico	Teclado	Repuesto Teclado + Palmrest + Touchpad 5CB0L02103 Compatible with Lenovo N22 Chromebook	f
166	logitech mk200: combo de combo de teclado y mouse usb 920-002716	Logitech	Periferico	Teclado	Logitech MK200: Combo de Combo de teclado y mouse USB – 920-002716	f
167	logitech mk120: combo de combo de teclado y mouse (920-004428)	Logitech	Periferico	Teclado	Logitech MK120: Combo de Combo de teclado y mouse – (920-004428)	f
168	logitech mk320: combo de teclado y mouse inalambricos (920-002836)	Logitech	Periferico	Teclado	Logitech MK320: Combo de teclado y mouse inalámbricos – (920-002836)	f
169	combo marvo cm370pm pink: teclado, mouse, audifonos y pad	Varios	Periferico	Teclado	Combo Marvo CM370PM Pink: Teclado, Mouse, Audifonos y Pad	f
170	laptop asus rog strix g16 g614pm-rv038 | ryzen r9 8940hx | 32gb | 1tb | rtx 5060 8gb | 16 165hz (+mochila+mouse)	Asus	Periferico	Mouse	Laptop ASUS ROG STRIX G16 G614PM-RV038 | RYZEN R9 8940HX | 32GB | 1TB | RTX 5060 8GB | 16″ 165HZ (+Mochila+Mouse)	f
171	teclado mecanico razer blackwidow v4 tenkeyless hyperspeed wireless/usb-c razer chromatm rgb abs doubleshot swtich tactile and quiet black (rz03-05480600-r	Razer	Periferico	Teclado	TECLADO MECANICO RAZER BLACKWIDOW V4 TENKEYLESS HYPERSPEED – WIRELESS/USB-C – RAZER CHROMA™ RGB – ABS DOUBLESHOT – SWTICH TACTILE AND QUIET – BLACK (RZ03-05480600-R311)	f
172	teclado asus rog strix scope ii 96 wireless bluetooth/wired/rf 2.4ghz teclas abs switch rog nx snow lubed black (90mp037a-bksa00)	Asus	Periferico	Teclado	TECLADO ASUS ROG STRIX SCOPE II 96 WIRELESS – BLUETOOTH/WIRED/RF 2.4GHZ – TECLAS ABS – SWITCH ROG NX SNOW – LUBED – BLACK (90MP037A-BKSA00)	f
173	teclado logitech pebble keys 2 k380s bluetooth silencioso espanol white (920-011784)	Logitech	Periferico	Teclado	TECLADO LOGITECH PEBBLE KEYS 2 K380S – BLUETOOTH – SILENCIOSO – ESPAÑOL – WHITE (920-011784)	f
174	teclado logitech g915 tkl bluetooth mecanico lightspeed rgb (920-009495)	Logitech	Periferico	Teclado	Teclado Logitech G915 TKL Bluetooth Mecanico LightSpeed Rgb (920-009495)	f
175	teclado logitech g815 mecanico lightsync rgb gl tactile g-keys white (920-011354)	Logitech	Periferico	Teclado	TECLADO LOGITECH G815 MECANICO LIGHTSYNC RGB – GL TACTILE – G-KEYS – WHITE (920-011354)	f
176	monitor teros te-2411s gaming 24 1920x1080 1ms 200 nits 100hz hdmi/vga	Varios	Monitor	NaN	MONITOR TEROS TE-2411S GAMING 24″ 1920X1080 – 1ms – 200 NITS – 100HZ – HDMI/VGA	f
177	monitor teros te-2124s 21.45 fhd ips 100hz 5ms plano hdmi/vga black	Varios	Monitor	IPS	MONITOR TEROS TE-2124S 21.45″ FHD IPS – 100HZ – 5MS – PLANO – HDMI/VGA – BLACK	f
178	teclado mecanico redragon fizz pro wireless k616-rgb wg 60% dust proof red 430g usb-c white/gray	Redragon	Periferico	Teclado	TECLADO MECANICO REDRAGON FIZZ PRO WIRELESS K616-RGB WG – 60% – DUST PROOF RED – 430G – USB-C – WHITE/GRAY	f
179	monitor teros te-1914s 19.5 1600x900 5ms 220 nits hdmi vga	Varios	Monitor	NaN	MONITOR TEROS TE-1914S 19.5″ 1600X900 – 5MS – 220 NITS – HDMI – VGA	f
180	combo teclado + mouse logitech pop keys inalambrico bluetooth 5.1 (920-013053)	Logitech	Periferico	Teclado	COMBO TECLADO + MOUSE LOGITECH POP KEYS INALAMBRICO – BLUETOOTH 5.1 (920-013053)	f
181	teclado razer blackwidow v4 x pokemon edition razer chromatm rgb abs switch lineal es grenn/detalles tematicos pokemon (rz03-04704200-r3m1)	Razer	Periferico	Teclado	TECLADO RAZER BLACKWIDOW V4 X POKEMON EDITION – RAZER CHROMA™ RGB – ABS – SWITCH LINEAL – ES – GRENN/DETALLES TEMATICOS POKEMON (RZ03-04704200-R3M1)	f
182	teclado mecanico redragon yama k550rgb-1-sp rgb chroma 100% anti-ghosting black	Redragon	Periferico	Teclado	TECLADO MECANICO REDRAGON YAMA K550RGB-1-SP – RGB CHROMA – 100% ANTI-GHOSTING – BLACK	f
183	teclado genius kb-117 alambrico usb black	Varios	Periferico	Teclado	TECLADO GENIUS KB-117 ALAMBRICO USB – BLACK	f
184	teclado mecanico corsair galleon 100 sd integrated stream deck lcd full-color teclas pbt switch mlx black (ch-912a311-na)	Corsair	Periferico	Teclado	TECLADO MECANICO CORSAIR GALLEON 100 SD – INTEGRATED STREAM DECK – LCD FULL-COLOR – TECLAS PBT – SWITCH MLX – BLACK (CH-912A311-NA)	f
185	teclado corsair gaming k70 core rgb mecanico mlx red 100% anit-ghosting black (ch-910971e-sp)	Corsair	Periferico	Teclado	TECLADO CORSAIR GAMING K70 CORE RGB – MECANICO – MLX RED – 100% ANIT-GHOSTING – BLACK (CH-910971E-SP)	f
186	teclado msi forge gk600 tkl wireless/bt/usb 83 teclas 20 mode rgb sub pbt 100% anti-ghosting linear white/violet	Msi	Periferico	Teclado	TECLADO MSI FORGE GK600 TKL WIRELESS/BT/USB – 83 TECLAS – 20 MODE RGB – SUB PBT – 100% ANTI-GHOSTING – LINEAR – WHITE/VIOLET	f
187	bundle 4 en 1 alcatroz xcraft nexus wireless : teclado mouse headset mousepad black	Varios	Periferico	Teclado	BUNDLE 4 EN 1 ALCATROZ XCRAFT NEXUS WIRELESS : TECLADO – MOUSE – HEADSET – MOUSEPAD – BLACK	f
188	bundle 4 en 1 alcatroz basecamp : teclado mouse headset mousepad black	Varios	Periferico	Teclado	BUNDLE 4 EN 1 ALCATROZ BASECAMP : TECLADO – MOUSE – HEADSET – MOUSEPAD – BLACK	f
189	monitor asus tuf vg248q1b 24 fhd led panel tn 165hz 0.5ms gtg freesync premium dp 1.2/hdmi v1.4	Asus	Monitor	TN	MONITOR ASUS TUF VG248Q1B 24″ FHD LED – PANEL TN – 165HZ – 0.5MS GTG – FREESYNC PREMIUM – DP 1.2/HDMI V1.4	f
190	teclado steelseries apex 7 tkl mecanico switch red rgb linear 100% antighosting pc/mac/xbox one black	Varios	Periferico	Teclado	TECLADO STEELSERIES APEX 7 TKL – MECANICO SWITCH RED RGB LINEAR – 100% ANTIGHOSTING – PC/MAC/XBOX ONE – BLACK	f
191	monitor asus va24ehf 24 (23.8) full hd ips 100hz 1ms vrr adaptive-sync hdmi(v1.4)	Asus	Monitor	IPS	MONITOR ASUS VA24EHF 24″ (23.8″) Full HD – IPS – 100Hz 1ms – VRR Adaptive-Sync – HDMI(v1.4)	f
192	monitor asus vy27uq 27 4k (3840 x 2160) non-glare ips dhr-10 adaptive sync eye care dp/hdmi black	Asus	Monitor	IPS	MONITOR ASUS VY27UQ – 27″ 4K (3840 x 2160) – NON-GLARE – IPS – DHR-10 – ADAPTIVE SYNC – EYE CARE – DP/HDMI – BLACK	f
193	monitor corsair xeneon 32uhd144-a 32 uhd ips 144hz hdr600 non-glare 100% adobe rgb 1ms amd freesync premium black (cm-9020006-na)	Corsair	Monitor	IPS	MONITOR CORSAIR XENEON 32UHD144-A – 32″ UHD IPS – 144HZ – HDR600 – NON-GLARE – 100% ADOBE RGB – 1MS – AMD FREESYNC PREMIUM – BLACK (CM-9020006-NA)	f
194	monitor env 1eenv1711 24 fhd panel va 300 nits 16ms vga/hdmi	Varios	Monitor	VA	MONITOR ENV 1EENV1711 – 24″ FHD – PANEL VA – 300 NITS – 16MS – VGA/HDMI	f
195	monitor env 1esm1695 21.5 full hd 19201080 va 230 nits 75hz 6.5ms vga/hdmi vesa	Varios	Monitor	VA	MONITOR ENV 1ESM1695 – 21.5″ FULL HD 1920×1080 – VA – 230 NITS – 75HZ – 6.5MS – VGA/HDMI – VESA	f
196	teclado meetion mt-mk20 lina inverse mecanico switch blue anti-ghosting black/red	Varios	Periferico	Teclado	TECLADO MEETION MT-MK20 LINA INVERSE – MECANICO – SWITCH BLUE – ANTI-GHOSTING – BLACK/RED	f
197	teclado hp pavillon 15-bs black	Varios	Periferico	Teclado	TECLADO HP PAVILLON 15-BS BLACK	f
198	combo teclado y mouse logitech mk850 wireless / 920-008219 920008659	Logitech	Periferico	Teclado	Combo Teclado y Mouse Logitech MK850 Wireless / 920-008219 – 920008659	f
199	monitor gigabyte gs27q 27 ss ips 2k qhd 2560x1440 non-glare 100% srgb 1ms mprt 170hz hdr hdmi 2.0/dp 1.4 black	Gigabyte	Monitor	IPS	MONITOR GIGABYTE GS27Q – 27″ SS IPS – 2K QHD 2560X1440 – NON-GLARE – 100% SRGB – 1MS MPRT – 170HZ – HDR – HDMI 2.0/DP 1.4 – BLACK	f
200	monitor gigabyte gs34wqc 34 va 1500r wqhd 3440x1440 non-glare 120% srgb 1ms mprt 135hz hdr hdmi 2.0/dp 1.4 black	Gigabyte	Monitor	VA	MONITOR GIGABYTE GS34WQC – 34″ VA 1500R – WQHD 3440X1440 – NON-GLARE – 120% SRGB – 1MS MPRT – 135HZ – HDR – HDMI 2.0/DP 1.4 – BLACK	f
201	monitor gigabyte m32qc-sa 31.5 qhd 165hz hdr400 1ms mprt hdmi 94% dci-p3/123% srgb 2.0/dp 1.2	Gigabyte	Monitor	NaN	MONITOR GIGABYTE M32QC-SA 31.5″ QHD – 165HZ – HDR400 – 1MS MPRT – HDMI – 94% DCI-P3/123% sRGB – 2.0/DP 1.2	f
202	monitor lg 27qn600-b 27 ips 2k qhd 25601440 srgb >99% 75hz 5ms hdr freesync- hdmi/dp	Lg	Monitor	IPS	MONITOR LG 27QN600-B 27″ IPS 2K QHD 2560×1440 – SRGB >99% – 75HZ – 5ms – HDR – FREESYNC- HDMI/DP	f
203	monitor lg 32mn600p-b 31.5 ips full hd amd freesync	Lg	Monitor	IPS	MONITOR LG 32MN600P-B 31.5″ IPS FULL HD AMD FREESYNC	f
204	monitor lg ultragear 27gr75q-b 27 qhd 2560x1440 165hz ips 1ms gtg srgb 99% anti-glare hdr10 hdmi 2.2/dp 1.4 black	Lg	Monitor	IPS	MONITOR LG ULTRAGEAR 27GR75Q-B 27″ QHD 2560X1440 – 165HZ – IPS 1MS GTG – SRGB 99% – ANTI-GLARE – HDR10 – HDMI 2.2/DP 1.4 – BLACK	f
205	combo teclado y mouse genius slimstar c126 wired black	Varios	Periferico	Teclado	COMBO TECLADO Y MOUSE GENIUS SLIMSTAR C126 WIRED – BLACK	f
206	teclado dyi glorious gmmk-tkl-rgb sin switch sin keycaps black	Varios	Periferico	Teclado	Teclado DYI Glorious GMMK-TKL-RGB – Sin Switch – Sin KeyCaps – Black	f
207	monitor msi optix g274rw 27 fhd ips 170hz 1ms (mprt) hdmi/dp white	Msi	Monitor	IPS	MONITOR MSI OPTIX G274RW – 27″ FHD IPS – 170HZ – 1MS (MPRT) – HDMI/DP – WHITE	f
208	monitor samsung ur55 28 4k uhd ips hdr10 4ms 60hz hdmi/dp (lu28r550uqnxza)	Samsung	Monitor	IPS	MONITOR SAMSUNG UR55 – 28″ 4K UHD IPS HDR10 – 4MS – 60HZ – HDMI/DP (LU28R550UQNXZA)	f
209	teclado steelseries apex 9 mini 60% optical switches rgb double shot pbt black	Varios	Periferico	Teclado	TECLADO STEELSERIES APEX 9 MINI 60% – OPTICAL SWITCHES RGB – DOUBLE SHOT PBT – BLACK	f
210	monitor gigabyte gs27qa 27 ips 2k qhd | 180hz | plano	Gigabyte	Monitor	IPS	Monitor Gigabyte GS27QA 27″ IPS 2K QHD | 180Hz | Plano	f
211	teclado steelseries apex 7 mecanico switch red linear rgb 100% antighosting pc/mac/xbox one black	Varios	Periferico	Teclado	TECLADO STEELSERIES APEX 7 – MECANICO SWITCH RED LINEAR RGB – 100% ANTIGHOSTING – PC/MAC/XBOX ONE – BLACK	f
212	procesador hpe dl380 gen9 intel xeon e5-2640v3 kit (719049-b)	Intel	CPU	NaN	Procesador HPE DL380 Gen9 Intel Xeon E5-2640v3 Kit – (719049-B)	f
213	mouse logitech g pro 2 lightspeed rgb wireless 44000dpi >888 ips 1ms 80g black (910-007246)	Logitech	Periferico	Mouse	MOUSE LOGITECH G PRO 2 LIGHTSPEED RGB WIRELESS – 44000DPI – >888 IPS – 1MS – 80G – BLACK (910-007246)	f
214	mouse logitech gaming g pro x superlight 2 lightspeed wireless/usb connectivity 32000dpi 0.5 response time 5 botones white (910-006636)	Logitech	Periferico	Mouse	MOUSE LOGITECH GAMING G PRO X SUPERLIGHT 2 LIGHTSPEED WIRELESS/USB CONNECTIVITY – 32000DPI – 0.5 RESPONSE TIME – 5 BOTONES – WHITE (910-006636)	f
215	mouse logitech g pro lightspeed rgb inalambrico 25600dpi black (910-005271)	Logitech	Periferico	Mouse	MOUSE LOGITECH G PRO LIGHTSPEED RGB Inalambrico – 25600DPI – BLACK (910-005271)	f
216	mouse logitech m240 wireless bluetooth 4000 dpi silent grafito (910-007113)	Logitech	Periferico	Mouse	MOUSE LOGITECH M240 WIRELESS BLUETOOTH – 4000 DPI – SILENT – GRAFITO (910-007113)	f
217	laptop asus rog strix g16 g614pm-rv039 | ryzen r9 8940hx |16gb | 1tb | rtx 5060 8gb | 16 165hz (+mochila+mouse)	Asus	Periferico	Mouse	Laptop ASUS ROG STRIX G16 G614PM-RV039 | RYZEN R9 8940HX |16GB | 1TB | RTX 5060 8GB | 16″ 165HZ (+Mochila+Mouse)	f
218	notebook asus x1605za-mb915 intel core i7-12700h 16gb ram 512g ssd 16 wuxga sin s.o + mochila/mouse black	Asus	Periferico	Mouse	NOTEBOOK ASUS X1605ZA-MB915 – INTEL CORE i7-12700H – 16GB RAM – 512G SSD – 16″ WUXGA – SIN S.O + MOCHILA/MOUSE – BLACK	f
219	notebook asus vivobook x1605va-mb649 intel core i9-13900h 16gb ram 1tb ssd 16 wuxga sin s.o mouse/mochila black	Asus	Periferico	Mouse	NOTEBOOK ASUS VIVOBOOK X1605VA-MB649 INTEL CORE i9-13900H – 16GB RAM – 1TB SSD – 16″ WUXGA – SIN S.O – MOUSE/MOCHILA – BLACK	f
220	ia workstation amd threadripper + dual geforce rtx 5090 + 128gb ram ddr5	AMD	CPU	NaN	IA Workstation AMD ThreadRipper + Dual GeForce RTX 5090 + 128GB RAM DDR5	f
221	pc desktop workstation intel ultra 7 265kf | tuf b860 | 32gb ddr5 | 1tb ssd | rtx 5050 8gb | wifi | case solido	Intel	CPU	NaN	PC Desktop Workstation Intel Ultra 7 265KF | TUF B860 | 32GB DDR5 | 1TB SSD | RTX 5050 8GB | WiFi | Case Sólido	f
222	pc desktop workstation intel ultra 7 270k+ | tuf b860 wifi7 | 32gb ddr5 | 1tb ssd | case solido	Intel	CPU	NaN	PC Desktop Workstation Intel Ultra 7 270K+ | TUF B860 WiFi7 | 32GB DDR5 | 1TB SSD | Case Sólido	f
223	pc desktop servidor intel ultra 9 285k | 32gb ddr5 | raid 2x1tb ssd | torre	Intel	CPU	NaN	PC Desktop Servidor Intel Ultra 9 285K | 32GB DDR5 | RAID 2x1TB SSD | Torre	f
224	notebook asus vivobook x1605va-mb2030 intel core i9-13900h 16gb ram 1tb ssd 16 wuxga sin s.o silver mochila + mouse	Asus	Periferico	Mouse	NOTEBOOK ASUS VIVOBOOK X1605VA-MB2030 – INTEL CORE i9-13900H – 16GB RAM – 1TB SSD – 16″ WUXGA – SIN S.O – SILVER – MOCHILA + MOUSE	f
225	notebook asus vivobook x1504va-bq3132 intel core i5 120u 16gb ram (8gb on board) 512gb ssd 15.6 fhd wv sin s.o cool silver + mochila y mouse	Asus	Periferico	Mouse	NOTEBOOK ASUS VIVOBOOK X1504VA-BQ3132 – INTEL CORE i5 120U – 16GB RAM (8GB ON BOARD) – 512GB SSD – 15.6″ FHD WV – SIN S.O – COOL SILVER + MOCHILA Y MOUSE	f
226	notebook asus vivobook x1502va-nj973 intel core i5-13420h ram 16gb (8gb on board + 8gb ddr4) 512gb ssd 15.6 fhd s.o freedos cool silver mochila+mouse	Asus	Periferico	Mouse	NOTEBOOK ASUS VIVOBOOK X1502VA-NJ973 – INTEL CORE i5-13420H – RAM 16GB (8GB On Board + 8GB DDR4) – 512GB SSD – 15.6″ FHD – S.O FREEDOS – COOL SILVER – MOCHILA+MOUSE	f
227	notebook asus vivobook pro n6506mv-ma058 intel core ultra 9 185h 1tb ssd 24gb ram (8gb onboard) 15.6 oled 2880x1620 geforce rtx 4060 8gb sin s.o kb es 2s-c	Asus	Periferico	Mouse	NOTEBOOK ASUS VIVOBOOK PRO N6506MV-MA058 – INTEL CORE ULTRA 9 185H – 1TB SSD – 24GB RAM (8GB ONBOARD) – 15.6″ OLED 2880X1620 – GEFORCE RTX 4060 8GB – SIN S.O – KB ES – 2S-COOL SILVER + MOUSE/MOCHILA (90NB12Y2-M002T0)	f
228	teclado mecanico razer blackwidow v4 x 75% razer chromatm rgb abs orange lineal black (rz03-05000200-r3u1)	Razer	Periferico	Teclado	TECLADO MECANICO RAZER BLACKWIDOW V4 X 75% – RAZER CHROMA™ RGB – ABS – ORANGE LINEAL – BLACK (RZ03-05000200-R3U1)	f
229	laptop asus vivobook m1502ya-bq828 | ryzen 7-7730u | 16gb ram | 512gb ssd | 15.6 fhd | silver (+mochila+mouse)	Asus	Periferico	Mouse	Laptop Asus VivoBook M1502YA-BQ828 | RYZEN 7-7730U | 16GB RAM | 512GB SSD | 15.6″ FHD | SILVER (+MOCHILA+MOUSE)	f
230	mouse logitech pebble m350 wireless usb bluetooth silencioso almond milk (910-006658)	Logitech	Periferico	Mouse	MOUSE LOGITECH PEBBLE M350 WIRELESS USB BLUETOOTH SILENCIOSO – ALMOND MILK (910-006658)	f
231	audifonos gaming cougar omnes essential wireless mic omnidirectional 53mm black (3hw50g53b.0001)	Varios	Periferico	Headset	AUDIFONOS GAMING COUGAR OMNES ESSENTIAL – WIRELESS – MIC OMNIDIRECTIONAL – 53MM – BLACK (3HW50G53B.0001)	f
232	headsets corsair hs60 haptic	Corsair	Periferico	Headset	Headsets Corsair HS60 HAPTIC	f
233	almohadillas de repuesto para audifonos logitech g733 black	Logitech	Periferico	Headset	ALMOHADILLAS DE REPUESTO PARA AUDIFONOS LOGITECH G733 – BLACK	f
234	audifonos primus gaming edition star wars mandalorian arcus 210 tws wireless omnidireccional usb type c 5 rms black (pwh-s210ml)	Varios	Periferico	Headset	AUDIFONOS PRIMUS GAMING EDITION STAR WARS MANDALORIAN ARCUS 210 TWS – WIRELESS – OMNIDIRECCIONAL – USB TYPE C – 5 RMS – BLACK (PWH-S210ML)	f
235	stand para audifonos cougar bunker s	Varios	Periferico	Headset	Stand para audifonos Cougar Bunker S	f
236	combo quasad: teclado, mouse, audifonos y pad	Varios	Periferico	Teclado	Combo Quasad: Teclado, Mouse, Audifonos y Pad	f
237	headsets logitech h111	Logitech	Periferico	Headset	Headsets Logitech H111	f
238	headsets cooler master ch321	Varios	Periferico	Headset	Headsets Cooler Master CH321	f
239	headsets hp h500gs	Varios	Periferico	Headset	Headsets HP H500GS	f
240	headsets inalambricos corsair virtuoso rgb wireless white (ca-9011224-na)	Corsair	Periferico	Headset	Headsets Inalambricos Corsair Virtuoso RGB Wireless White – (CA-9011224-NA)	f
241	headsets inalambricos corsair void rgb elite wireless white (ca-9011202-na)	Corsair	Periferico	Headset	Headsets Inalambricos Corsair VOID RGB Elite Wireless White – (CA-9011202-NA)	f
242	headsets corsair void rgb elite premium black	Corsair	Periferico	Headset	Headsets Corsair VOID RGB Elite Premium Black	f
243	mouse inalambrico asus rog spatha x (90mp0220-bmua00)	Asus	Periferico	Mouse	Mouse Inalambrico Asus ROG Spatha X – (90MP0220-BMUA00)	f
244	laptop asus vivobook m1607ka-mb110 | ryzen ai 7 350 | 16gb ram | 1tb ssd | 16.0 | blue	AMD	CPU	NaN	Laptop ASUS VIVOBOOK M1607KA-MB110 | RYZEN AI 7 350 | 16GB RAM | 1TB SSD | 16.0″ | BLUE	f
245	mouse cooler master mm711 blue	Varios	Periferico	Mouse	Mouse Cooler Master MM711 Blue	f
246	kit de teclado y mouse logitech mk250 compact wireless/bluetooth black (920-013513)	Logitech	Periferico	Teclado	KIT DE TECLADO Y MOUSE LOGITECH MK250 COMPACT – WIRELESS/BLUETOOTH – BLACK (920-013513)	f
247	teclado mecanico redragon k621 horus tkl wireless bluetooth 5.0 rgb chroma 100% anti-ghosting black (k621-rgb sp-red)	Redragon	Periferico	Teclado	TECLADO MECANICO REDRAGON K621 HORUS TKL – WIRELESS – BLUETOOTH 5.0 – RGB CHROMA – 100% ANTI-GHOSTING – BLACK (K621-RGB SP-RED)	f
248	teclado mecanico gaming marvo kg962-white-r 60% switch red anti-ghosting cable type c desmontable white	Varios	Periferico	Teclado	TECLADO MECANICO GAMING MARVO KG962-WHITE-R – 60% SWITCH RED – ANTI-GHOSTING – CABLE TYPE C DESMONTABLE – WHITE	f
249	teclado redragon shiva k512rgb-sp membrana rgb reposamunecas magnetico black	Redragon	Periferico	Teclado	TECLADO REDRAGON SHIVA K512RGB-SP – MEMBRANA – RGB – REPOSAMUÑECAS MAGNETICO – BLACK	f
250	teclado redragon kumara k552w-rgb sps-red mecanico tkl us dust-proof red white	Redragon	Periferico	Teclado	TECLADO REDRAGON KUMARA K552W-RGB SPS-RED – MECANICO TKL – US – DUST-PROOF RED – WHITE	f
251	teclado primus gaming ballista90t edition star wars mandalorian mechanical anti-ghosting linear y silent switch red (pks-s092ml-s)	Varios	Periferico	Teclado	TECLADO PRIMUS GAMING BALLISTA90T EDITION STAR WARS MANDALORIAN – MECHANICAL – ANTI-GHOSTING – LINEAR Y SILENT – SWITCH RED (PKS-S092ML-S)	f
252	teclado perzonalizable corsair elgato stream deck+ 8 teclas lcd usb-c black (10gbd9901)	Corsair	Periferico	Teclado	TECLADO PERZONALIZABLE CORSAIR ELGATO STREAM DECK+ 8 TECLAS LCD – USB-C – BLACK (10GBD9901)	f
253	teclado mecanico redragon horus tkl k621w-rgb-sp wireless bluetooth/dongle rf usb	Redragon	Periferico	Teclado	TECLADO MECANICO REDRAGON HORUS TKL K621W-RGB-SP WIRELESS – BLUETOOTH/DONGLE RF USB	f
254	teclado mecanico redragon deimos k599-krs tkl 70% wireless/wired rgb chroma switch linear 45 gr black	Redragon	Periferico	Teclado	TECLADO MECANICO REDRAGON DEIMOS K599-KRS – TKL 70% – WIRELESS/WIRED – RGB CHROMA – SWITCH LINEAR – 45 GR – BLACK	f
255	teclado mecanico hyperx origins 60% rgb switch linear 100% anti-ghosting compatible ps5tm, ps4tm, xbox series x|stm, xbox onetm black (4p5n4aa)	Hyperx	Periferico	Teclado	TECLADO MECANICO HYPERX ORIGINS 60% RGB – SWITCH LINEAR – 100% ANTI-GHOSTING – COMPATIBLE PS5™, PS4™, XBOX SERIES X|S™, XBOX ONE™ – BLACK (4P5N4AA)	f
256	teclado mecanico hyperx alloy elite 2 rgb switch rojo 100 % anti-ghost compatible ps5tm, ps4tm, xbox series x|stm, xbox onetm black (4p5n3ai#ac8)	Hyperx	Periferico	Teclado	TECLADO MECANICO HYPERX ALLOY ELITE 2 – RGB SWITCH ROJO – 100 % ANTI-GHOST – COMPATIBLE PS5™, PS4™, XBOX SERIES X|S™, XBOX ONE™ – BLACK (4P5N3AI#AC8)	f
257	teclado mecanico horus k618-rgb-sp wireless rgb chroma fps bluetooth 5.0 100% anti-ghosting black	Varios	Periferico	Teclado	TECLADO MECANICO HORUS K618-RGB-SP – WIRELESS – RGB CHROMA FPS – BLUETOOTH 5.0 – 100% ANTI-GHOSTING – BLACK	f
258	teclado mecanico gaming cougar luxlim low profile switch red usb black	Varios	Periferico	Teclado	TECLADO MECANICO GAMING COUGAR LUXLIM – LOW PROFILE – SWITCH RED – USB – BLACK	f
259	monitor asus gaming rog swift oled pg27aqdm 26.5 2560x1440 woled non-glare 135% srgb dci-p3 99% 0.03ms gtg hdr10 240hz dp 1.4 dsc/hdmi 2.0 black	Asus	Monitor	OLED	MONITOR ASUS GAMING ROG SWIFT OLED PG27AQDM – 26.5″ 2560X1440 – WOLED – NON-GLARE – 135% SRGB – DCI-P3 99% – 0.03MS GTG – HDR10 – 240HZ – DP 1.4 DSC/HDMI 2.0 – BLACK	f
260	combo teclado y mouse genius q8000 wireless 12 fn keys plug and play black	Varios	Periferico	Teclado	COMBO TECLADO Y MOUSE GENIUS Q8000 WIRELESS – 12 FN KEYS – PLUG AND PLAY – BLACK	f
261	mouse msi forge gm300 7200dpi 7 botones rgb black	Msi	Periferico	Mouse	MOUSE MSI FORGE GM300 – 7200DPI – 7 BOTONES – RGB – BLACK	f
262	mouse lenovo 300 usb 1600dpi black	Varios	Periferico	Mouse	MOUSE LENOVO 300 USB – 1600DPI – BLACK	f
263	mouse lenovo essential usb diseno ambidextro 1600dpi black (4y50r20863)	Varios	Periferico	Mouse	MOUSE LENOVO ESSENTIAL USB – DISEÑO AMBIDEXTRO – 1600DPI – BLACK (4Y50R20863)	f
264	mouse razer cobra chromatm rgb gengar edition 58g 8500dpi 6 botones programables 300ips black (rz01-04650700-r3m1)	Razer	Periferico	Mouse	MOUSE RAZER COBRA CHROMA™ RGB GENGAR EDITION – 58G – 8500DPI – 6 BOTONES PROGRAMABLES – 300IPS – BLACK (RZ01-04650700-R3M1)	f
265	combo mousepad goliathus mobile + mouse razer abyssus lite (rz83-02730100-b3m1)	Razer	Periferico	Mouse	COMBO MOUSEPAD GOLIATHUS MOBILE + MOUSE RAZER ABYSSUS LITE (RZ83-02730100-B3M1)	f
266	mouse logitech mx master 3s bluetooth edition ergonomico 7 botones 8000dpi grafito (910-007502)	Logitech	Periferico	Mouse	MOUSE LOGITECH MX MASTER 3S BLUETOOTH EDITION – ERGONOMICO – 7 BOTONES – 8000DPI – GRAFITO (910-007502)	f
267	mouse logitech m110 silent wired full size black (910-006756)	Logitech	Periferico	Mouse	MOUSE LOGITECH M110 SILENT – WIRED – FULL SIZE – BLACK (910-006756)	f
268	pc/torre cpu ryzen 7-8700g, a620, ssd 500gb, 16gb ddr5	AMD	CPU	NaN	PC/Torre CPU Ryzen 7-8700G, A620, SSD 500GB, 16GB DDR5	f
269	mouse klip xtreme optical liteglider usb + ps/2 adapter (kmo-102)	Varios	Periferico	Mouse	MOUSE KLIP XTREME OPTICAL LITEGLIDER – USB + PS/2 ADAPTER (KMO-102)	f
270	mouse pad havit mp839	Varios	Periferico	Mouse	Mouse Pad Havit MP839	f
271	mouse glorious model d matte white (gd-white)	Varios	Periferico	Mouse	Mouse Glorious Model D – Matte White (GD-White)	f
272	mouse pad glorious xl white (gw-xl)	Varios	Periferico	Mouse	Mouse Pad Glorious XL – White (GW-XL)	f
273	mouse pad asus rog balteus rgb (90mp0110-b0ua00)	Asus	Periferico	Mouse	Mouse Pad Asus ROG Balteus RGB – (90MP0110-B0UA00)	f
274	mouse glorious model d (d minus) matte white (glo-ms-dm-mw)	Varios	Periferico	Mouse	Mouse Glorious Model D – (D Minus) Matte White – (GLO-MS-DM-MW)	f
275	monitor touch sat 1053fph 15 1024 x 768px multi-touch 3 puntos hdmi/vga/usb	Varios	Monitor	NaN	MONITOR TOUCH SAT 1053FPH – 15″ 1024 x 768PX – MULTI-TOUCH 3 PUNTOS – HDMI/VGA/USB	f
276	monitor gigabyte m27up ice sa1 27 uhd (3840x2160p) ss ips 160hz/320-hz fhd 1ms gtg hdmi/dp speaker hdr400 non-glare white	Gigabyte	Monitor	IPS	MONITOR GIGABYTE M27UP ICE SA1 – 27″ UHD (3840X2160P) SS IPS – 160HZ/320-HZ FHD – 1MS GTG – HDMI/DP – SPEAKER – HDR400 – NON-GLARE – WHITE	f
277	tarjeta de video asus geforce gt710 2gb gddr5 hdmi/d-sub/dvi-d (gt710-sl-2gd5-brk-evo)	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS GEFORCE GT710 – 2GB GDDR5 – HDMI/D-SUB/DVI-D (GT710-SL-2GD5-BRK-EVO)	f
278	soporte para dos monitores kmm-510 con regleta integrada y puertos usb	Varios	Monitor	NaN	SOPORTE PARA DOS MONITORES KMM-510 CON REGLETA INTEGRADA Y PUERTOS USB	f
279	stand marvo para monitor dz-01 rgb 4 port usb touch black	Varios	Monitor	NaN	STAND MARVO PARA MONITOR DZ-01 – RGB – 4 PORT USB – TOUCH – BLACK	f
280	laptop msi thin 15 b13udx-3085xec | core i5-13420h | 8gb ram | 512gb ssd | rtx3050 6gb | 15.6 144hz (9s7-16r831-3085)	Msi	RAM	NaN	Laptop MSI Thin 15 B13UDX-3085XEC | CORE i5-13420H | 8GB RAM | 512GB SSD | RTX3050 6GB | 15.6″ 144HZ (9S7-16R831-3085)	f
281	laptop hp 15-fd0276la | core i7-1355u | 16gb ram | 512gb ssd | 15.6	Varios	RAM	NaN	LAPTOP HP 15-FD0276LA | Core i7-1355U | 16GB RAM | 512GB SSD | 15.6″	f
282	laptop asus vivobook f1605va-ws74us | negro | core i7-1355u | ram 16gb | ssd 512gb | 16 wuxga w11	Asus	RAM	NaN	Laptop ASUS VivoBook F1605VA-WS74US | Negro | CORE i7-1355U | RAM 16GB | SSD 512GB | 16″ WUXGA – W11	f
283	servidor nas qnap ts-473a-8g cpu amd v1500b 4-core 8gb ddr4 4 bahias 2x 2.5gbe	Varios	RAM	DDR4	Servidor NAS QNAP TS-473A-8G – CPU AMD v1500B 4-Core – 8GB DDR4 – 4 BAHÍAS – 2x 2.5GbE	f
284	monitor asus proart pa329crv 32 | plano ips 4k | usb-c	Asus	Monitor	IPS	Monitor Asus ProArt PA329CRV 32″ | Plano IPS 4K | USB-C	f
285	audifono gamer inal p/ pc c/ mic logitech g435	Logitech	Periferico	Headset	Audifono Gamer Inal P/ Pc C/ Mic – Logitech G435	f
286	laptop asus gaming v16 v3607vp-rp030 | ultra 7 240h | 1tb | 32gb ddr5 |rtx 5070 8g | 16 wuxga	Asus	RAM	DDR5	Laptop Asus Gaming V16 V3607VP-RP030 | ULTRA 7 240H | 1TB | 32GB DDR5 |RTX 5070 8G | 16″ WUXGA	f
287	torre cpu pc amd ryzen 5 5600g | 16gb ddr4 | ssd 500gb | fuente + case	Varios	RAM	DDR4	Torre CPU PC AMD Ryzen 5 5600G | 16GB DDR4 | SSD 500GB | Fuente + Case	f
288	laptop gigabyte gaming a16 | ryzen 7 260 | 16gb ddr5 | 1tb | rtx 5070 8gb | 16 fhd+ (9rga6ab7whkhjk0la3m0)	Gigabyte	RAM	DDR5	Laptop Gigabyte Gaming A16 | Ryzen 7 260 | 16GB DDR5 | 1TB | RTX 5070 8GB | 16″ FHD+ (9RGA6AB7WHKHJK0LA3M0)	f
289	laptop asus tuf a16 fa608uh-rv063 | ryzen 7 260 | 16gb ram | 1tb ssd | rtx 5050 8gb | 16.0	Asus	RAM	NaN	Laptop ASUS TUF A16 FA608UH-RV063 | RYZEN 7 260 | 16GB RAM | 1TB SSD | RTX 5050 8GB | 16.0″	f
290	soporte huanuo 2 brazos vertical para monitores de 13 a 32 (hnhm2)	Varios	Monitor	NaN	SOPORTE HUANUO 2 BRAZOS VERTICAL para monitores DE 13 A 32″ (HNHM2)	f
291	soporte brazo para 2 monitores teros te-7114 hasta 32 soporta 12kg	Varios	Monitor	NaN	SOPORTE BRAZO PARA 2 MONITORES TEROS TE-7114 – HASTA 32″ – SOPORTA 12KG	f
292	simulador racing + pedestal para monitor (qfrs01-01a)	Varios	Monitor	NaN	SIMULADOR RACING + PEDESTAL PARA MONITOR (QFRS01-01A)	f
293	monitor acer k202q 19.5 hd (1600x900) 75hz 5ms 200 nits hdmi/vga black (um.ie0aa.004)	Acer	Monitor	NaN	MONITOR ACER K202Q – 19.5″ HD (1600X900) – 75HZ – 5MS – 200 NITS – HDMI/VGA – BLACK (UM.IE0AA.004)	f
294	monitor teros te-1916s 19.5 1600x900 5ms 75hz hdmi/vga	Varios	Monitor	NaN	MONITOR TEROS TE-1916S 19.5″ 1600X900 – 5MS – 75HZ – HDMI/VGA	f
295	monitor msi gaming mag 275qf 27 wqhd (2560x1440) ips 180hz 0.5ms gtg hdmi/dp black (9s6-3ce21m-014)	Msi	Monitor	IPS	MONITOR MSI GAMING MAG 275QF – 27″ WQHD (2560X1440) IPS – 180HZ – 0.5MS GTG – HDMI/DP – BLACK (9S6-3CE21M-014)	f
296	monitor lg 29u511a-b ultrawide 29 ips 25601080 hdmi 100hz srgb 99% 5ms (gtg)	Lg	Monitor	IPS	Monitor LG 29U511A-B ULTRAWIDE 29″ – IPS – 2560×1080 – HDMI – 100HZ – sRGB 99% – 5MS (GTG)	f
297	monitor portatil env 15.6 fhd ips ultrafino usb c black	Varios	Monitor	IPS	MONITOR PORTATIL ENV 15.6″ FHD IPS – ULTRAFINO – USB C – BLACK	f
298	monitor teros te-2415s 24 gaming plano ips | fhd | 120hz 1ms | dp hdmi vga	Varios	Monitor	IPS	MONITOR TEROS TE-2415S 24″ GAMING PLANO IPS | FHD | 120HZ 1ms | DP – HDMI – VGA	f
299	monitor empresarial asus va279qgs 27 ips fhd (1920x1080) 120hz 1ms hdmi/dp/vga/usb black	Asus	Monitor	IPS	MONITOR EMPRESARIAL ASUS VA279QGS – 27″ IPS FHD (1920X1080) – 120HZ – 1MS – HDMI/DP/VGA/USB – BLACK	f
300	monitor portatil acer pm1 15.6 fhd 6ms ultrafino mini hdmi/usb c black (pm161q)	Acer	Monitor	NaN	MONITOR PORTATIL ACER PM1 – 15.6″ FHD – 6MS – ULTRAFINO – MINI HDMI/USB C – BLACK (PM161Q)	f
301	ram kingston fury beast rgb 16gb ddr5 5600mt/s black	Kingston	RAM	DDR5	Ram Kingston Fury Beast RGB 16GB DDR5 5600MT/s – Black	f
302	laptop lenovo loq amd ryzen 7 7735hs 16gb ram 512gb ssd geforce rtx4050 15.6 fhd 144hz w11h luna gray (83d0000lec)	Varios	RAM	NaN	Laptop Lenovo LOQ AMD RYZEN 7 7735HS – 16GB RAM – 512GB SSD – GEFORCE RTX4050 – 15.6″ FHD 144HZ – W11H – LUNA GRAY (83D0000LEC)	f
303	laptop lenovo ideapad 3 15irh10 | i5-13420h | ram 8gb | ssd 512gb | 15.3 | gris (83k1007plm)	Varios	RAM	NaN	Laptop Lenovo IdeaPad 3 15IRH10 | i5-13420H | RAM 8GB | SSD 512GB | 15.3″ | Gris (83K1007PLM)	f
304	monitor msi mag 274qf x24 27 wqhd (2560x1440) fast ips 0.5ms 240hz hdmi/dp black (9s6-3ce41h-020)	Msi	Monitor	IPS	MONITOR MSI MAG 274QF X24 – 27″ WQHD (2560X1440) – FAST IPS – 0.5MS – 240HZ – HDMI/DP – BLACK (9S6-3CE41H-020)	f
305	monitor samsung gaming odyssey g3 27 fhd 180hz dp hdmi black	Samsung	Monitor	NaN	Monitor Samsung Gaming Odyssey G3 27 – FHD – 180HZ – Dp Hdmi – Black	f
306	mini pc asus rog nuc 15 | ultra 7 255hx | 32gb ddr5 | 1tb ssd | rtx 5060 8gb | win11h	Asus	RAM	DDR5	Mini PC ASUS ROG NUC 15 | Ultra 7 255HX | 32GB DDR5 | 1TB SSD | RTX 5060 8GB | Win11H	f
307	pc asus rog g700tf-7265kf036x core ultra 7 265kf | rtx 5070 12gb | 32gb ddr5 | 1tb ssd | win 11 pro	Asus	RAM	DDR5	PC ASUS ROG G700TF-7265KF036X Core Ultra 7 265KF | RTX 5070 12GB | 32GB DDR5 | 1TB SSD | Win 11 Pro	f
308	pc/torre cpu core i9-14900k, z790, ssd 1tb, 32gb ddr5 + rtx 4070 ti super 16gb	Varios	RAM	DDR5	PC/Torre CPU Core i9-14900K, Z790, SSD 1TB, 32GB DDR5 + RTX 4070 TI SUPER 16GB	f
309	memoria ram ddr4 corsair vengeance lpx 8gb 3000mhz (cmk8gx4m1d3000c16)	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance LPX 8GB 3000MHz – (CMK8GX4M1D3000C16)	f
310	monitor asus tuf vg259qm5a | 24.5 ips full hd 240hz 0.3ms | 99% srgb | g-sync/freesync	Asus	Monitor	IPS	Monitor Asus TUF VG259QM5A | 24.5″ IPS Full HD 240Hz 0.3ms | 99% SRGB | G-Sync/FreeSync	f
311	monitor asus rog strix xg27acmes | 27 2k 255hz 0.3ms | g-sync | hdr	Asus	Monitor	NaN	Monitor Asus ROG STRIX XG27ACMES | 27″ 2K 255Hz 0.3ms | G-SYNC | HDR	f
312	monitor lg ultragear 24g411a-b 24 fhd (1920x1080) 144hz ips 1ms gtg srgb 99% anti-glare hdr10 hdmi/dp black	Lg	Monitor	IPS	MONITOR LG ULTRAGEAR 24G411A-B 24″ FHD (1920X1080) – 144HZ – IPS – 1MS GTG – SRGB 99% – ANTI-GLARE – HDR10 – HDMI/DP – BLACK	f
313	memoria ram ddr4 hp v6 8gb 3200mhz (7eh67aa#abm)	Varios	RAM	DDR4	Memoria RAM DDR4 HP V6 8GB 3200Mhz – (7EH67AA#ABM)	f
314	memoria ram ddr4 hyperx fury rgb 3000mhz (hx430c15fb3/8)	Hyperx	RAM	DDR4	Memoria RAM DDR4 HyperX Fury RGB 3000Mhz – (HX430C15FB3/8)	f
315	memoria ram ddr4 hyperx fury rgb 16gb 3000mhz (hx430c15fb3a/16)	Hyperx	RAM	DDR4	Memoria RAM DDR4 HyperX Fury RGB 16GB 3000Mhz – (HX430C15FB3A/16)	f
316	memoria ram ddr4 so-dimm kingston value 8gb 2666mhz (kvr26s19s6/8)	Kingston	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Kingston Value 8GB 2666Mhz – (KVR26S19S6/8)	f
317	memoria ram ddr4 hp v6 red 8gb 2666mhz (7eh61aa#abm)	Varios	RAM	DDR4	Memoria RAM DDR4 HP V6 Red 8GB 2666Mhz – (7EH61AA#ABM)	f
318	memoria ram ddr4 hyperx predator rgb 8gb 3200mhz (hx432c16pb3a/8)	Hyperx	RAM	DDR4	Memoria RAM DDR4 HyperX PRedATOR RGB 8GB 3200MHz – (HX432C16PB3A/8)	f
319	memoria ram ddr4 hyperx fury rgb 8gb 2666mhz (hx426c16fb3a/8)	Hyperx	RAM	DDR4	Memoria RAM DDR4 HyperX Fury RGB 8GB 2666MHz – (HX426C16FB3A/8)	f
320	memoria ram ddr4 kingston 16gb 2666mhz (kvr26n19d8/16)	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston 16GB 2666Mhz – (KVR26N19D8/16)	f
321	memoria ram ddr5 corsair vengeance 16gb ddr5 4800mhz black (cmk32gx5m2a4800c40)	Corsair	RAM	DDR5	Memoria RAM DDR5 Corsair Vengeance 16GB DDR5 4800MHZ Black – (CMK32GX5M2A4800C40)	f
322	memoria ram ddr4 corsair vengeance lpx 16gb 3000mhz (cmk16gx4m1b3000c15)	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance LPX 16GB 3000MHz – (CMK16GX4M1B3000C15)	f
323	memoria ram ddr4 corsair vengeance lpx 16gb 3600mhz (cmk16gx4m1z3600c18)	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance LPX 16GB 3600Mhz – (CMK16GX4M1Z3600C18)	f
324	memoria ram ddr4 corsair vengeance lpx 8gb 3600mhz (cmk8gx4m1z3600c18)	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance LPX 8GB 3600Mhz – (CMK8GX4M1Z3600C18)	f
325	memoria ram ddr5 kingston fury beast 16gb ddr5 4800mhz cl38 black (kf548c38bb-16)	Kingston	RAM	DDR5	Memoria RAM DDR5 Kingston Fury Beast 16GB DDR5 4800MHZ CL38 BLACK – (KF548C38BB-16)	f
326	memoria ram ddr5 kingston fury beast 16gb ddr5 4800mhz cl38 black (kf548c38bbk2/32)	Kingston	RAM	DDR5	Memoria RAM DDR5 Kingston Fury Beast 16GB DDR5 4800MHz CL38 BLACK – (KF548C38BBK2/32)	f
327	memoria ram ddr4 so-dimm kingston fury impact 8gb 3200mhz (kf432s20ib/8)	Kingston	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Kingston Fury Impact 8GB 3200MHZ – (KF432S20IB/8)	f
328	memoria ram ddr4 corsair vengeance rgb pro 16gb 3200mhz (cmw16gx4m1z3200c16)	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance RGB PRO 16GB 3200Mhz – (CMW16GX4M1Z3200C16)	f
329	memoria ram ddr4 kingston 16gb 3200mhz (kvr32n22d8/16)	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston 16GB 3200MHz – (KVR32N22D8/16)	f
330	memoria ram ddr4 so-dimm kingston 16gb 3200mhz (kvr32s22d8/16)	Kingston	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Kingston 16GB 3200Mhz – (KVR32S22D8/16)	f
331	memoria ram ddr3 kingston 8gb 1600mhz ecc 1.5v para servidor kvr16r11d4/8hc	Kingston	RAM	DDR3	Memoria RAM DDR3 Kingston 8GB 1600MHZ ECC 1.5v para Servidor – KVR16R11D4/8HC	f
332	memoria ram ddr4 so-dimm kingston 8gb 3200mhz (kvr32s22s8/8)	Kingston	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Kingston 8GB 3200MHz – (KVR32S22S8/8)	f
333	memoria ram ddr4 xpg spectrix d50 rgb 8gb 3000mhz (ax4u30008g16a-st50)	Xpg	RAM	DDR4	Memoria RAM DDR4 XPG Spectrix D50 RGB 8GB 3000Mhz – (AX4U30008G16A-ST50)	f
334	memoria ram ddr4 kingston fury 16gb 3200mhz (hx432c16fb4/16)	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston Fury 16GB 3200Mhz – (HX432C16FB4/16)	f
335	memoria ram ddr4 kingston fury 8gb 2666mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston Fury 8GB 2666Mhz	f
336	memoria ram kingston 8gb ddr3l 1600mhz so-dimm (kvr16ls11/8)	Kingston	RAM	DDR3	Memoria Ram Kingston 8GB DDR3L 1600MHz So-Dimm (KVR16LS11/8)	f
337	pc/torre cpu core i7-14700kf, tuf z790, ssd 1tb, 32gb ddr5 + rtx 5070 12gb	Varios	RAM	DDR5	PC/Torre CPU Core i7-14700KF, TUF Z790, SSD 1TB, 32GB DDR5 + RTX 5070 12GB	f
338	monitor xiaomi g24i 23.8 fhd (1920x1080) 180hz 1ms gtg hdmi/dp black (p24fca-rggl)	Varios	Monitor	NaN	MONITOR XIAOMI G24i – 23.8″ FHD (1920X1080) – 180HZ – 1MS GTG – HDMI/DP – BLACK (P24FCA-RGGL)	f
339	monitor gigabyte mo27q28g oled | 27 2k | 280hz	Gigabyte	Monitor	OLED	Monitor Gigabyte MO27Q28G OLED | 27″ 2K | 280Hz	f
340	monitor gigabyte gs32q 32 ss-ips qhd | 165hz | plano	Gigabyte	Monitor	IPS	Monitor Gigabyte GS32Q 32″» SS-IPS QHD | 165Hz | Plano	f
341	monitor xtratech xtm19 19.5 hd+ 1600900 entradas hdmi y vga	Varios	Monitor	NaN	Monitor XTRATECH XTM19 19.5″ HD+ 1600×900 – Entradas HDMI y VGA	f
342	soporte para monitor klip xtreme kmm-400 hasta 27	Varios	Monitor	NaN	Soporte para monitor Klip Xtreme KMM-400 – Hasta 27″	f
343	soporte klip xtreme kmm-301 para monitor y laptop	Varios	Monitor	NaN	Soporte Klip Xtreme KMM-301 PARA MONITOR Y LAPTOP	f
344	monitor e-sports benq zowie xl2411p 24	Benq	Monitor	NaN	Monitor E-Sports BenQ Zowie XL2411P – 24″	f
345	procesador intel core ultra 5 250k plus | turbo 5.3ghz | 18-cores | lga1851	Lg	Monitor	NaN	Procesador Intel Core Ultra 5 250K Plus | Turbo 5.3GHz | 18-Cores | LGA1851	f
346	case corsair frame 4000d lcd rs argb con pantalla tactil xeon edge 14.5 | negro	Corsair	Monitor	NaN	Case Corsair FRAME 4000D LCD RS ARGB con Pantalla Tactil Xeon Edge 14.5″ | Negro	f
347	tarjeta de video asus gt 710 2gb (gt710-4h-sl-2gd5)	Asus	GPU	NaN	Tarjeta de video Asus GT 710 2GB – (GT710-4H-SL-2GD5)	f
348	tarjeta de video gigabyte gt 1030 2gb (gv-n1030d5-2gl)	Gigabyte	GPU	NaN	Tarjeta de video Gigabyte GT 1030 – 2GB – (GV-N1030D5-2GL)	f
349	procesador amd ryzen 5 8400f | 6-cores | 4.7 ghz | 65w | am5 | sin graficos	Varios	Monitor	NaN	Procesador AMD Ryzen 5 8400F | 6-CORES | 4.7 GHZ | 65W | AM5 | SIN GRAFICOS	f
350	procesador amd ryzen 7 9850x3d 8-cores/16-hilos 4.7ghz | am5	Varios	Monitor	NaN	PROCESADOR AMD RYZEN 7 9850X3D 8-CORES/16-HILOS 4.7GHz | AM5	f
351	monitor lg ultragear 27g411a-b 27 fhd ips (1920x1080p) 1ms mbr hdr10 144hz oc hdmi/dp	Lg	Monitor	IPS	MONITOR LG ULTRAGEAR 27G411A-B – 27″ FHD IPS (1920X1080P) – 1MS MBR – HDR10 – 144HZ OC – HDMI/DP	f
352	soporte brazo klip xtreme kmm-410 con mecanismo de resorte para 2 monitores 13-32 4.4/17.6lb vesa	Varios	Monitor	NaN	SOPORTE BRAZO KLIP XTREME KMM-410 – CON MECANISMO DE RESORTE – PARA 2 MONITORES 13″-32″ – 4.4/17.6LB – VESA	f
353	monitor portatil asus zenscreen mb166c | 15.6 fhd ips | usb-c/dp	Asus	Monitor	IPS	Monitor Portatil Asus ZenScreen MB166C | 15.6″ FHD IPS | USB-C/DP	f
354	docking station anker 8 en 1 dual monitor usb-c hdmi/ethernet/power 85w/usb-3.0	Varios	Monitor	NaN	DOCKING STATION ANKER 8 EN 1 – DUAL MONITOR – USB-C – HDMI/ETHERNET/POWER 85W/USB-3.0	f
355	monitor samsung gaming essential s3 s36gd 27 fhd (1920x1080) 100hz 4ms d-sub/hdmi black (s27d366gan)	Samsung	Monitor	NaN	MONITOR SAMSUNG GAMING ESSENTIAL S3 S36GD – 27″ FHD (1920X1080) – 100HZ – 4MS – D-SUB/HDMI – BLACK (S27D366GAN)	f
356	monitor gaming zowie xl2731k 27 fhd 165hz dyac 320 nits tn hdmi2.0/dp 1.2 (9h.lkclb-qbl)	Varios	Monitor	TN	MONITOR GAMING ZOWIE XL2731K – 27″ FHD – 165HZ DYAC – 320 NITS – TN – HDMI2.0/DP 1.2 (9H.LKCLB-QBL)	f
357	monitor teros te-2787g 27 fhd curvo 180hz 2ms dp/hdmi	Varios	Monitor	NaN	MONITOR TEROS TE-2787G 27″ FHD CURVO – 180HZ – 2MS – DP/HDMI	f
358	monitor gaming msi mag 275cqf e18 27 wqhd 2k(2560x1440) curvo 180hz 0.5ms (gtg) hdr ready hdmi 2.0b/dp 1.4a black (9s6-3ce91h-004)	Msi	Monitor	NaN	MONITOR GAMING MSI MAG 275CQF E18 – 27″ WQHD 2K(2560X1440) – CURVO 180HZ – 0.5MS (GTG) – HDR READY – HDMI 2.0b/DP 1.4a – BLACK (9S6-3CE91H-004)	f
359	monitor lg ultragear 27gs65f-b 27 fhd ips 180hz 1ms hdr10 g-sync/freesync black	Lg	Monitor	IPS	MONITOR LG ULTRAGEAR 27GS65F-B – 27” FHD IPS – 180HZ – 1MS – HDR10 – G-SYNC/FREESYNC – BLACK	f
360	tarjeta capturadora de video blackmagic design decklink duo 2 4ch sdi tarjeta de reproduccion y captura bmd-bdlkduo2	Varios	GPU	NaN	Tarjeta capturadora de video Blackmagic Design DeckLink Duo 2 4ch SDI Tarjeta de reproducción y captura BMD-BDLKDUO2	f
361	tarjeta de video gigabyte gt 710 2gb (gv-n710d3-2gl rev2.0)	Gigabyte	GPU	NaN	Tarjeta de video Gigabyte GT 710 2GB – (GV-N710D3-2GL REV2.0)	f
362	monitor gigabyte gs24f14 24 ips fhd 144hz 1ms	Gigabyte	Monitor	IPS	Monitor Gigabyte GS24F14 24″ IPS FHD 144Hz 1ms	f
363	monitor indurama vortix ultra 32 | curvo va fhd 180hz (32mimnavu)	Varios	Monitor	VA	Monitor Indurama Vortix Ultra 32″ | Curvo VA FHD 180Hz (32MIMNAVU)	f
364	monitor asus vp227he 21.45 fhd 75hz non-glare va 5ms gtg hdmi v1.4/vga black	Asus	Monitor	VA	MONITOR ASUS VP227HE – 21.45″ FHD – 75HZ – NON-GLARE – VA – 5MS GTG – HDMI v1.4/VGA – BLACK	f
365	monitor asus tuf gaming vg279q1a 27 fhd 1920x1080p panel ips non-glare 1ms mprt 165hz freesync premium dp 1.2/hdmi v1.4	Asus	Monitor	IPS	MONITOR ASUS TUF GAMING VG279Q1A – 27″ FHD 1920X1080P – PANEL IPS – NON-GLARE – 1MS MPRT – 165HZ – FREESYNC PREMIUM – DP 1.2/HDMI V1.4	f
366	monitor asus tuf gaming vg249q1a 23.8 fhd 19201080 panel ips non-glare 1ms mprt 165hz freesync premium dp 1.2/hdmi v1.4	Asus	Monitor	IPS	MONITOR ASUS TUF GAMING VG249Q1A – 23.8″ FHD 1920×1080 – PANEL IPS – NON-GLARE – 1MS MPRT – 165HZ – FREESYNC PREMIUM – DP 1.2/HDMI V1.4	f
367	monitor asus tuf gaming vg27wq1b curvo 27 165hz 1ms wqhd (25601440) (90lm0671-b011b0)	Asus	Monitor	NaN	Monitor ASUS TUF Gaming VG27WQ1B CURVO 27″ 165Hz 1ms WQHD (2560×1440) (90LM0671-B011B0)	f
368	monitor asus tuf vg32vq1b 32 curvo wqhd (2560x1440p) 165hz 1ms speakers dp/hdmi black	Asus	Monitor	NaN	MONITOR ASUS TUF VG32VQ1B 32″ CURVO WQHD (2560x1440P) – 165HZ – 1MS – SPEAKERS – DP/HDMI – BLACK	f
369	monitor asus tuf gaming vg34vql3a 34 curvo wqhd (3440x1440p) 180 hz 1ms hdmi/dp black	Asus	Monitor	NaN	MONITOR ASUS TUF GAMING VG34VQL3A 34″ CURVO – WQHD (3440X1440P) – 180 HZ – 1MS – HDMI/DP – BLACK	f
370	monitor asus rog strix gaming xg27acs 27 qhd ips non-glare 180hz 1ms gtg hdr hdmi/dp/usb-c black	Asus	Monitor	IPS	MONITOR ASUS ROG STRIX GAMING XG27ACS – 27″ QHD IPS – NON-GLARE – 180HZ – 1MS GTG – HDR – HDMI/DP/USB-C – BLACK	f
371	soporte/brazo para monitores klip xtreme kpm-310	Varios	Monitor	NaN	Soporte/Brazo para monitores Klip Xtreme KPM-310	f
372	monitor asus proart pa279crv 27 4k | 99% dci-p3 | 99% adobe rgb | hdr400	Asus	Monitor	NaN	Monitor Asus ProArt PA279CRV 27″ 4K | 99% DCI-P3 | 99% ADOBE RGB | HDR400	f
373	monitor gigabyte m27q2 ice 27 ips 2k qhd | oc 210hz | plano | blanco	Gigabyte	Monitor	IPS	Monitor Gigabyte M27Q2 ICE 27″ IPS 2K QHD | OC 210Hz | Plano | Blanco	f
374	monitor gigabyte m28u 28 ss ips 4k200hz 1ms	Gigabyte	Monitor	IPS	Monitor Gigabyte M28U 28″ SS IPS 4K200Hz 1ms	f
375	monitor gigabyte gs25f2 24.5 ss ips fhd 200hz 1ms	Gigabyte	Monitor	IPS	Monitor Gigabyte GS25F2 24.5″ SS IPS FHD 200Hz 1ms	f
376	ram kingston fury beast rgb 32gb ddr5 5600mt/s black	Kingston	RAM	DDR5	Ram Kingston Fury Beast RGB 32GB DDR5 5600MT/s – Black	f
377	memoria ram ddr4 corsair vengeance rgb rs 8gb 3200mhz cl16 black (cmg8gx4m1e3200c16)	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance RGB RS 8GB 3200MHZ CL16 BLACK – (CMG8GX4M1E3200C16)	f
468	lg ergo 32uk580-b monitor 31.5 pulgadas 4k uhd	Lg	Monitor	NaN	Lg Ergo 32UK580-B Monitor 31.5 Pulgadas 4K UHD	f
378	memoria ram kingston fury beast 16gb ddr5-5600 black (kf556c40bb-16)	Kingston	RAM	DDR5	Memoria RAM Kingston Fury Beast 16GB DDR5-5600 BLACK (KF556C40BB-16)	f
379	memoria ram ddr4 kingston fury beast 16gb rgb 3600mhz (kf436c18bba/16)	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston Fury Beast 16GB RGB 3600MHZ – (KF436C18BBA/16)	f
380	memoria ram ddr5 kingston fury beast 16gb 5200mhz (kf552c40bb-16)	Kingston	RAM	DDR5	Memoria RAM DDR5 Kingston Fury Beast 16GB 5200MHZ – (KF552C40BB-16)	f
381	memoria ram ddr3 kingston 8gb 1600mhz (kvr16n11/8)	Kingston	RAM	DDR3	Memoria RAM DDR3 Kingston 8GB 1600MHz – (KVR16N11/8)	f
382	memoria ram ddr4 so-dimm kingston fury impact 32gb 3200mhz (kf432s20ib/32)	Kingston	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Kingston Fury Impact 32GB 3200Mhz – (KF432S20IB/32)	f
383	memoria ram ddr4 kingston fury 8gb 3200mhz (kvr32n22s8/8 kvr32n22s6/8)	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston Fury 8GB 3200Mhz – (KVR32N22S8/8 – KVR32N22S6/8)	f
384	memoria ram kingston fury beast 32gb ddr5-5600 black (kf556c40bb-32)	Kingston	RAM	DDR5	Memoria RAM Kingston Fury Beast 32GB DDR5-5600 BLACK (KF556C40BB-32)	f
385	memoria ram ddr4 corsair vengeance lpx 8gb 3200mhz (cmk8gx4m1z3200c16)	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance LPX 8GB 3200Mhz – (CMK8GX4M1Z3200C16)	f
386	memoria ram kingston fury beast 8gb ddr5-5600 black (kf556c40bb-8)	Kingston	RAM	DDR5	Memoria RAM Kingston Fury Beast 8GB DDR5-5600 BLACK (KF556C40BB-8)	f
387	monitor gigabyte gs27fa 27 ss ips fhd 180hz 1ms	Gigabyte	Monitor	IPS	Monitor Gigabyte GS27FA 27″ SS IPS FHD 180Hz 1ms	f
388	monitor gigabyte gs25f2a 24.5 ips fhd 240hz	Gigabyte	Monitor	IPS	Monitor Gigabyte GS25F2A 24.5″ IPS FHD 240Hz	f
389	tarjeta de video profesional asus turbo amd radeon ai pro r9700 32gb gddr6 (turbo-ai-pro-r9700-32g)	AMD	GPU	NaN	TARJETA DE VIDEO PROFESIONAL ASUS TURBO AMD RADEON AI PRO R9700 32GB GDDR6 (TURBO-AI-PRO-R9700-32G)	f
390	tarjeta de video msi n210 1gb (912-v809-3634)	Msi	GPU	NaN	Tarjeta de video MSI N210 1GB – (912-V809-3634)	f
391	tarjeta de video gigabyte gt 1030 2gb (gv-n1030d4-2gl)	Gigabyte	GPU	NaN	Tarjeta de video Gigabyte GT 1030 2GB – (GV-N1030D4-2GL)	f
392	tarjeta de video biostar g210 1gb (vn2103nhg6-sbarl-bs2)	Varios	GPU	NaN	Tarjeta de video Biostar G210 1GB – (VN2103NHG6-SBARL-BS2)	f
393	monitor msi mpg-491cqp-qd-oled 49 ultrawide curvo	Msi	Monitor	OLED	Monitor MSI MPG-491CQP-QD-OLED 49″ UltraWide Curvo	f
394	monitor indurama vortix nova 27 | ips fhd 120hz	Varios	Monitor	IPS	Monitor Indurama Vortix Nova 27″ | IPS FHD 120Hz	f
395	monitor indurama vortix nova 25 full hd 120hz | hdmi+dp (25mimnavn )	Varios	Monitor	VA	Monitor Indurama Vortix Nova 25″ Full HD 120Hz | HDMI+DP (25MIMNAVN )	f
396	tarjeta de video afox rx-550 4gb gddr5 hdmi/dp/dvi-d	Varios	GPU	NaN	TARJETA DE VIDEO AFOX RX-550 4GB – GDDR5 – HDMI/DP/DVI-D	f
397	tarjeta de video asus geforce gt730 2gb gddr5 auto extreme 0db silent 4 hdmi (gt730-4h-sl-2gd5)	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS GEFORCE GT730 2GB GDDR5 – AUTO EXTREME – 0DB SILENT – 4 HDMI (GT730-4H-SL-2GD5)	f
398	monitor asus va249hg 24 full hd 120hz | eyecare | hdmi y vga	Asus	Monitor	VA	Monitor Asus VA249HG 24″ Full HD 120Hz | EyeCare | HDMI y VGA	f
399	monitor asus proart pa248qfv 24 ips wuxga | 100hz | hdr	Asus	Monitor	IPS	Monitor ASUS ProArt PA248QFV 24″ IPS WUXGA | 100HZ | HDR	f
400	monitor asus va279hg 27 full hd 120hz | eyecare | hdmi y vga	Asus	Monitor	VA	Monitor Asus VA279HG 27″ Full HD 120Hz | EyeCare | HDMI y VGA	f
401	monitor lg 20u401a-b 19.5 | 1600900 | hdmi y vga	Lg	Monitor	NaN	Monitor LG 20U401A-B 19.5″ | 1600×900 | HDMI y VGA	f
402	monitor indurama vortix core 22 (21.5) full hd 100hz | vga/hdmi (22mimnavc)	Varios	Monitor	NaN	Monitor Indurama Vortix Core 22 (21.5″) Full HD 100HZ | VGA/HDMI (22MIMNAVC)	f
403	monitor samsung ls24a608ucn 24 wqhd 2560x1440 ultra-thin 5ms 75hz hdmi/dp	Samsung	Monitor	NaN	MONITOR SAMSUNG LS24A608UCN – 24″ WQHD 2560X1440 – ULTRA-THIN – 5MS – 75HZ – HDMI/DP	f
404	laptop hp victus 15-fb3019la | ryzen 7 7445h | 8gb ddr5 ampliable | 512gb | 15.6 | rtx3050 6gb (bt4f6la#abm)	Varios	RAM	DDR5	Laptop HP Victus 15-FB3019LA | RYZEN 7 7445H | 8GB DDR5 Ampliable | 512GB | 15.6″ | RTX3050 6GB (BT4F6LA#ABM)	f
405	unidad estado solido ssd 2.5 480gb sata iii hp s650	Varios	SSD	SATA	Unidad Estado Solido Ssd 2.5″ 480GB Sata III – HP S650	f
406	audifono gamer p/ pc c/ mic logitech g335 mint	Logitech	Periferico	Headset	Audifono Gamer P/ Pc C/ Mic – Logitech G335 MINT	f
407	mouse pad klip xtreme 22.5x19.5 cm con almohadilla gel - negro	Varios	Periferico	Mouse	MOUSE PAD KLIP XTREME 22.5x19.5 cm CON ALMOHADILLA GEL - NEGRO	f
408	laptop asus expertbook b5 intel ultra 7 255h-16gb-ssd1tb-16" wqxga-wf7-tpm-3y-gris-mouse-w11p	Asus	Periferico	Mouse	LAPTOP ASUS EXPERTBOOK B5 INTEL ULTRA 7 255H-16GB-SSD1TB-16" WQXGA-WF7-TPM-3Y-GRIS-MOUSE-W11P	f
409	mouse primus inalambrico gamer conexion dual usb bateria recargable	Varios	Periferico	Mouse	MOUSE PRIMUS INALAMBRICO GAMER CONEXION DUAL USB BATERIA RECARGABLE	f
410	mouse logitech inalambrico m650 bluetooth usb silence - grafito	Logitech	Periferico	Mouse	MOUSE LOGITECH INALAMBRICO M650 BLUETOOTH USB SILENCE - GRAFITO	f
411	mouse xtech alambrico usb negro ergonomico	Varios	Periferico	Mouse	MOUSE XTECH ALAMBRICO USB NEGRO ERGONOMICO	f
412	mouse xtech alambrico 3 botones usb - negro	Varios	Periferico	Mouse	MOUSE XTECH ALAMBRICO 3 BOTONES USB - NEGRO	f
413	mouse xtech inalambrico 1200dpi usb negro	Varios	Periferico	Mouse	MOUSE XTECH INALAMBRICO 1200dpi USB NEGRO	f
414	mouse pad xtech 22x18 cm negro	Varios	Periferico	Mouse	MOUSE PAD XTECH 22x18 cm NEGRO	f
415	mouse klip xtreme inalambrico usb - azul	Varios	Periferico	Mouse	MOUSE KLIP XTREME INALAMBRICO USB - AZUL	f
416	mouse logitech inalambrico m170 gris	Logitech	Periferico	Mouse	MOUSE LOGITECH INALAMBRICO M170 GRIS	f
417	mouse klip xtreme inalambrico ergonomico 6 bot. nano usb - azul	Varios	Periferico	Mouse	MOUSE KLIP XTREME INALAMBRICO ERGONOMICO 6 BOT. NANO USB - AZUL	f
418	laptop asus vivobook 15 ci5-120u 1.4ghz-8gb-512gb ssd-quiet blue-15.6"fhd-w11+mouse	Asus	Periferico	Mouse	LAPTOP ASUS VIVOBOOK 15 CI5-120U 1.4GHZ-8GB-512GB SSD-QUIET BLUE-15.6"FHD-W11+MOUSE	f
419	redragon flekact pro k708gf rgb pro teclado	Redragon	Periferico	Teclado	Redragon Flekact Pro K708GF RGB PRO Teclado	f
420	mouse logitech m196 inalambrico bluetooth - grafito 1000 dpi	Logitech	Periferico	Mouse	MOUSE LOGITECH M196 INALAMBRICO BLUETOOTH - GRAFITO 1000 DPI	f
421	mouse klip xtreme inalambrico bluetooth 6 botones - negro	Varios	Periferico	Mouse	MOUSE KLIP XTREME INALAMBRICO BLUETOOTH 6 BOTONES - NEGRO	f
422	audifono + microfono primus gamer on-ear bluetooth arcus360bt - negro	Varios	Periferico	Headset	AUDIFONO + MICROFONO PRIMUS GAMER ON-EAR BLUETOOTH ARCUS360BT - NEGRO	f
423	audifono + microfono xtech on ear tipo diadema 2 conectores 3.5mm	Varios	Periferico	Headset	AUDIFONO + MICROFONO XTECH ON EAR TIPO DIADEMA 2 conectores 3.5mm	f
424	audifono + microfono logitech alambrico gamer g335 - 3.5mm negro	Logitech	Periferico	Headset	AUDIFONO + MICROFONO LOGITECH ALAMBRICO GAMER G335 - 3.5mm NEGRO	f
425	hp victus amd ryzen 7-7445hs rtx 4050 16gb	AMD	CPU	NaN	HP Victus AMD Ryzen 7-7445HS RTX 4050 16GB	f
426	msi thin 15 b13ve intel i5-13420h rtx 4050 16gb	Intel	CPU	NaN	MSI Thin 15 B13VE Intel i5-13420H RTX 4050 16GB	f
427	gamdias aura gc12 case gamer 6 fans argb	AMD	CPU	NaN	Gamdias Aura GC12 Case Gamer 6 Fans Argb	f
428	gamdias kratos m1 600b fuente de poder 600w 80+ bronze	AMD	CPU	NaN	Gamdias Kratos M1 600B Fuente de Poder 600W 80+ Bronze	f
429	gamdias atlas m3m case gamer vidrio templado 3 fans	AMD	CPU	NaN	Gamdias Atlas M3M Case Gamer Vidrio Templado 3 Fans	f
430	mouse pad avanti con almohadilla negro	Varios	Periferico	Mouse	MOUSE PAD AVANTI CON ALMOHADILLA NEGRO	f
431	mouse ezmi alambrico ez gamer iluminacion rgb 6 bot. 7200 dpi usb - negro	Varios	Periferico	Mouse	MOUSE EZMI ALAMBRICO EZ GAMER ILUMINACION RGB 6 BOT. 7200 DPI USB - NEGRO	f
432	laptop asus expertbook b3 intel ultra 7 155h-16gb-1tb ssd-16" wuxga-wf6e-tpm-3y-mouse-grey-w11p	Asus	Periferico	Mouse	LAPTOP ASUS EXPERTBOOK B3 INTEL ULTRA 7 155H-16GB-1TB SSD-16" WUXGA-WF6E-TPM-3Y-MOUSE-GREY-W11P	f
433	mouse logitech ergonomic lift left vertical bluetooth 4000 dpi grafito - mano izquierda	Logitech	Periferico	Mouse	MOUSE LOGITECH ERGONOMIC LIFT LEFT VERTICAL BLUETOOTH 4000 DPI GRAFITO - MANO IZQUIERDA	f
434	teclado + mouse logitech inalambrico mk270 unifying	Logitech	Periferico	Teclado	TECLADO + MOUSE LOGITECH INALAMBRICO MK270 UNIFYING	f
435	teclado klip xtreme inalambrico keyglider bluetooth y 2.4ghz - panel tactil	Varios	Periferico	Teclado	TECLADO KLIP XTREME INALAMBRICO KEYGLIDER BLUETOOTH Y 2.4GHz - PANEL TACTIL	f
436	teclado + mouse klip xtreme inalambrico keyroll usb	Varios	Periferico	Teclado	TECLADO + MOUSE KLIP XTREME INALAMBRICO KEYROLL USB	f
437	teclado xtratech alambrico usb espanol	Varios	Periferico	Teclado	TECLADO XTRATECH ALAMBRICO USB ESPAÑOL	f
438	teclado klip xtreme inalambrico ergonomico transcend usb negro	Varios	Periferico	Teclado	TECLADO KLIP XTREME INALAMBRICO ERGONOMICO TRANSCEND USB NEGRO	f
439	teclado + mouse ezmi inalambrico - negro	Varios	Periferico	Teclado	TECLADO + MOUSE EZMI INALAMBRICO - NEGRO	f
440	teclado + mouse targus inalambrico - negro	Varios	Periferico	Teclado	TECLADO + MOUSE TARGUS INALAMBRICO - NEGRO	f
441	teclado + mouse manhattan inalambrico - negro	Varios	Periferico	Teclado	TECLADO + MOUSE MANHATTAN INALAMBRICO - NEGRO	f
442	case combo speedmind mouse teclado / fuente 750w usb	Varios	Periferico	Teclado	CASE COMBO SPEEDMIND MOUSE TECLADO / FUENTE 750W USB	f
443	estuche para tablet rippa 10" teclado y lapiz incluido - negro	Varios	Periferico	Teclado	ESTUCHE PARA TABLET RIPPA 10" TECLADO Y LAPIZ INCLUIDO - NEGRO	f
444	teclado logitech inalambrico k270 usb negro	Logitech	Periferico	Teclado	TECLADO LOGITECH INALAMBRICO K270 USB NEGRO	f
445	teclado logitech inalambrico gamer g915 tkl lightspeed mecanico bluetooth / rgb / blanco	Logitech	Periferico	Teclado	TECLADO LOGITECH INALAMBRICO GAMER G915 TKL LIGHTSPEED MECANICO BLUETOOTH / RGB / BLANCO	f
446	teclado + mouse xtech alambrico usb - negro	Varios	Periferico	Teclado	TECLADO + MOUSE XTECH ALAMBRICO USB - NEGRO	f
447	laptop asus tuf gaming a15 amd r7-7445hs 3.2ghz-16gb-512gb ssd-tg rtx3050 4gb-black-15.6"fhd-w11 mochila + mouse	Asus	Periferico	Mouse	LAPTOP ASUS TUF GAMING A15 AMD R7-7445HS 3.2GHZ-16GB-512GB SSD-TG RTX3050 4GB-BLACK-15.6"FHD-W11 MOCHILA + MOUSE	f
448	laptop asus vivobook go 15 amd r5-40(7520u) 2.8ghz-16gb-512gb ssd-green-15.6"fhd+mouse+w11	Asus	Periferico	Mouse	LAPTOP ASUS VIVOBOOK GO 15 AMD R5-40(7520U) 2.8GHZ-16GB-512GB SSD-GREEN-15.6"FHD+MOUSE+W11	f
449	laptop asus vivobook go 15 amd r5-40 2.8ghz-16gb-512gb ssd-silver-15.6"fhd+mouse+w11	Asus	Periferico	Mouse	LAPTOP ASUS VIVOBOOK GO 15 AMD R5-40 2.8GHZ-16GB-512GB SSD-SILVER-15.6"FHD+MOUSE+W11	f
450	laptop asus vivobook 15 ci7-150u 1.8ghz-16gb-512gb ssd-blue-15.6"fhd+mouse-w11	Asus	Periferico	Mouse	LAPTOP ASUS VIVOBOOK 15 CI7-150U 1.8GHZ-16GB-512GB SSD-BLUE-15.6"FHD+MOUSE-W11	f
451	laptop asus expertbook intel core ultra 5 225h-16gb-512gb ssd-16" wuxga-wf6e-tpm-3y-mouse-grey-fre	Asus	Periferico	Mouse	LAPTOP ASUS EXPERTBOOK INTEL CORE ULTRA 5 225H-16GB-512GB SSD-16" WUXGA-WF6E-TPM-3Y-MOUSE-GREY-FRE	f
452	mouse xtech inalambrico xtm-309 de 3 botones 1600 dpi	Varios	Periferico	Mouse	MOUSE XTECH INALAMBRICO XTM-309 DE 3 BOTONES 1600 DPI	f
453	mouse pad xtech disney stich amarillo	Varios	Periferico	Mouse	MOUSE PAD XTECH DISNEY STICH AMARILLO	f
454	mouse xtech inalambrico disney stich usb + mouse pad con almohadilla	Varios	Periferico	Mouse	MOUSE XTECH INALAMBRICO DISNEY STICH USB + MOUSE PAD CON ALMOHADILLA	f
455	lenovo loq 15arp10e amd r7 7735hs 16gb 512gb rtx 4050 15.6	AMD	CPU	NaN	Lenovo LOQ 15ARP10E AMD R7 7735HS 16GB 512GB RTX 4050 15.6″	f
456	asus v16 core 5 120h rtx 4050 6gb 16gb ram	Intel	CPU	NaN	ASUS V16 Core 5 120H RTX 4050 6GB 16GB RAM	f
457	asus prime b850m-a mainboard ddr5 matx amd	AMD	CPU	NaN	ASUS Prime B850M-A Mainboard DDR5 mATX AMD	f
458	msi mag 32c6x 32 monitor curvo fhd 250hz 1ms	Msi	Monitor	NaN	Msi MAG 32C6X 32″ Monitor Curvo FHD 250Hz 1Ms	f
459	thunderobot zq25f180 monitor 24.5 180hz qhd ips	Varios	Monitor	IPS	Thunderobot ZQ25F180 Monitor 24.5″ 180Hz QHD IPS	f
460	asus tuf vg279qm5a 27 monitor gamer fhd 240hz ips	Asus	Monitor	IPS	Asus TUF VG279QM5A 27″ Monitor Gamer FHD 240Hz IPS	f
461	armaggeddon pixxel+ xf27hd monitor 27 ips 120hz	Varios	Monitor	IPS	Armaggeddon Pixxel+ XF27HD Monitor 27″ IPS 120Hz	f
462	asus tuf vg249q5r 23.8 monitor gamer fhd 200hz ips	Asus	Monitor	IPS	Asus TUF VG249Q5R 23.8″ Monitor Gamer FHD 200Hz IPS	f
463	msi pro mp243l e14 monitor 24 144hz ips 1ms	Msi	Monitor	IPS	Msi Pro MP243L E14 Monitor 24″ 144Hz IPS 1ms	f
464	teros te-2786g 27 monitor gamer 200hz 1ms ips	Varios	Monitor	IPS	Teros TE-2786G 27″ Monitor Gamer 200Hz 1ms IPS	f
465	klip xtreme kmm-510 soporte articulado dos monitores con regleta	Varios	Monitor	NaN	Klip Xtreme KMM-510 Soporte Articulado Dos Monitores con regleta	f
466	asrock pg27q15r2a 27 monitor curvo va qhd 1440p 165hz	Varios	Monitor	VA	Asrock PG27Q15R2A 27″ Monitor Curvo VA QHD 1440P 165Hz	f
467	cooler master ga241 23.8 monitor fhd 100hz 1ms	Varios	Monitor	NaN	Cooler Master GA241 23.8″ Monitor FHD 100Hz 1ms	f
469	ge 97894 cable extension monitor vga 3.04m	Varios	Monitor	NaN	Ge 97894 Cable Extensión Monitor Vga 3.04m	f
470	msi mpg 491cqp 49 qd-oled 144hz 0.3ms	Msi	Monitor	OLED	MSI MPG 491CQP 49″ QD-OLED 144Hz 0.3ms	f
471	oraimo osw-831n rose gold amoled 1.32	Varios	Monitor	OLED	Oraimo OSW-831N Rose Gold AMOLED 1.32¨	f
472	oraimo osw-830 black smartwatch amoled	Varios	Monitor	OLED	Oraimo OSW-830 Black Smartwatch Amoled	f
473	asus rog strix xg27aqdmes 27 240hz oled qhd	Asus	Monitor	OLED	ASUS ROG STRIX XG27AQDMES 27″ 240Hz OLED QHD	f
474	cougar poseidon vistek argb 240 pantalla lcd	Varios	Monitor	NaN	Cougar Poseidon Vistek ARGB 240 Pantalla LCD	f
475	cougar poseidon vistek pro argb 240mm pantalla lcd wh	Varios	Monitor	NaN	Cougar Poseidon Vistek Pro ARGB 240mm Pantalla LCD Wh	f
476	cougar poseidon vistek argb 360 pantalla lcd wh	Varios	Monitor	NaN	Cougar Poseidon Vistek ARGB 360 Pantalla LCD Wh	f
477	cougar poseidon vistek pro argb 360 pantalla lcd bk	Varios	Monitor	NaN	Cougar Poseidon Vistek Pro ARGB 360 Pantalla LCD Bk	f
478	gamdias hermes e8 usb red switch teclado mecanico	Varios	Periferico	Teclado	Gamdias Hermes E8 USB Red Switch Teclado Mecánico	f
479	gamdias hermes e7 usb red switch teclado mecanico	Varios	Periferico	Teclado	Gamdias Hermes E7 USB Red Switch Teclado Mecánico	f
480	msi mag 272f x24 monitor 27 ips full hd 240hz 0.5ms	Msi	Monitor	IPS	Msi Mag 272F X24 Monitor 27″ IPS Full HD 240Hz 0.5ms	f
481	asus proart pa27jcv 27 pulgadas ips 5k monitor	Asus	Monitor	IPS	ASUS ProArt PA27JCV 27″ Pulgadas IPS 5K Monitor	f
482	msi b550m-a pro motherboard amd am4 ddr4	AMD	CPU	NaN	MSI B550M-A PRO Motherboard AMD AM4 DDR4	f
483	teros te-2767g 27 monitor curvo qhd 2k 180hz 1ms	Varios	Monitor	NaN	Teros TE-2767G 27″ Monitor Curvo QHD 2K 180Hz 1ms	f
484	asus tuf gaming x870-plus wifi amd am5 mainboard	AMD	CPU	NaN	Asus TUF Gaming X870-PLUS WIFI AMD AM5 Mainboard	f
485	asus prime h810m-e lga1851 ddr5 intel	Intel	CPU	NaN	ASUS Prime H810M-E LGA1851 DDR5 Intel	f
486	asus prime b760m-a ddr5 mainboard intel lga1700 matx	Intel	CPU	NaN	Asus Prime B760M-A DDR5 Mainboard Intel LGA1700 mATX	f
487	asus tuf gaming b850m-plus wifi am5 amd	AMD	CPU	NaN	Asus TUF Gaming B850M-Plus WIFI AM5 AMD	f
488	asus tuf z890 plus wifi intel core ultra lga1851	Intel	CPU	NaN	Asus TUF Z890 PLUS WIFI Intel Core Ultra LGA1851	f
489	msi pro h810m-b mainboard ddr5 intel lga1851	Intel	CPU	NaN	MSI Pro H810M-B Mainboard DDR5 Intel LGA1851	f
490	asus prime b860m-a motherboard lga1851 intel	Intel	CPU	NaN	Asus Prime B860M-A Motherboard LGA1851 Intel	f
491	mtec pc rainbow lite ryzen 7 16gb 1tb rtx 5060 ti	AMD	CPU	NaN	Mtec PC Rainbow Lite Ryzen 7 16GB 1TB RTX 5060 Ti	f
492	mtec pc digital beast ryzen 7 16gb 1tb rtx 5070	AMD	CPU	NaN	Mtec PC Digital Beast Ryzen 7 16GB 1TB RTX 5070	f
493	tp-link tapo d210 video portero wifi vision nocturna	Varios	GPU	NaN	Tp-link Tapo D210 Video Portero WiFi Visión Nocturna	f
494	adata xpg spectrix d41 16gb ddr4 rgb 3200mhz memoria ram	Adata	RAM	DDR4	Adata Xpg Spectrix D41 16gb Ddr4 Rgb 3200mhz Memoria Ram	f
495	xpg lancer rgb ddr5 16gb ram 6000mhz white	Xpg	RAM	DDR5	Xpg Lancer Rgb DDR5 16gb Ram 6000mhz White	f
496	xpg caster rgb 16gb ram ddr5 6400mhz	Xpg	RAM	DDR5	Xpg Caster RGB 16GB Ram DDR5 6400Mhz	f
497	adata sc610 1000gb disco de estado solido externo	Adata	SSD	NaN	Adata SC610 1000GB Disco de Estado sólido Externo	f
498	corsair mp600 core xt 1tb m.2 nvme gen4	Corsair	SSD	NVMe	Corsair MP600 Core XT 1TB M.2 Nvme Gen4	f
499	xiaomi barra de luz para monitor	Varios	Monitor	NaN	Xiaomi Barra de Luz para Monitor	f
500	boetec slim 2477 monitor curvo 24 200hz 1ms	Varios	Monitor	NaN	Boetec Slim 2477 Monitor Curvo 24″ 200Hz 1ms	f
501	asus tuf vg259qm5a 24.5 monitor gamer fhd 240hz ips	Asus	Monitor	IPS	Asus TUF VG259QM5A 24.5″ Monitor Gamer FHD 240Hz IPS	f
502	gigabyte gs27qa monitor 27 qhd ss ips 180hz 1ms	Gigabyte	Monitor	IPS	Gigabyte GS27QA Monitor 27″ QHD SS IPS 180Hz 1ms	f
503	teclado + mouse logitech inalambrico mk220	Logitech	Periferico	Teclado	TECLADO + MOUSE LOGITECH INALAMBRICO MK220	f
504	teclado + mouse logitech alambrico mk120 usb	Logitech	Periferico	Teclado	TECLADO + MOUSE LOGITECH ALAMBRICO MK120 USB	f
505	teclado + mouse logitech alambrico mk200 usb	Logitech	Periferico	Teclado	TECLADO + MOUSE LOGITECH ALAMBRICO MK200 USB	f
506	mouse quasad qm-850 wireless 1600dpi recargable red/negro	Varios	Periferico	Mouse	Mouse QUASAD QM-850 wireless 1600dpi recargable Red/Negro	f
507	mouse genius optico dx-110, alambrico, usb, 1000dpi, negro	Varios	Periferico	Mouse	Mouse Genius Óptico DX-110, Alámbrico, USB, 1000DPI, Negro	f
508	procesador lenovo servidor sr550/sr590/sr650 intel xeon silver 4208 8c 85w 2.1ghz	Intel	CPU	NaN	PROCESADOR LENOVO SERVIDOR SR550/SR590/SR650 Intel Xeon Silver 4208 8C 85W 2.1GHz	f
509	procesador lenovo servidor sr530/sr570/sr630 intel xeon silver 4214 12c 85w 2.2ghz	Intel	CPU	NaN	PROCESADOR LENOVO SERVIDOR SR530/SR570/SR630 Intel Xeon Silver 4214 12C 85W 2.2GHz	f
510	cooler kit lenovo thinksystem del procesador	Varios	CPU	NaN	COOLER KIT LENOVO THINKSYSTEM DEL PROCESADOR	f
511	cooler kit lenovo thinksystem del procesador sr570	Varios	CPU	NaN	COOLER KIT LENOVO THINKSYSTEM DEL PROCESADOR SR570	f
512	laptop lenovo yoga pro 7 14asp9 ryzen ai 9-365 2.0ghz-32gb-1tb ssd- grey-14.5"oled 2.8k wqxga+w11	AMD	CPU	NaN	LAPTOP LENOVO YOGA PRO 7 14ASP9 RYZEN AI 9-365 2.0GHZ-32GB-1TB SSD- GREY-14.5"OLED 2.8K WQXGA+W11	f
513	laptop lenovo ip 5 2 in 1 14ahp9 amd r7-8845hs 3.8ghz-16gb-512gb ssd-14" wuxga-touch-grey-w11	AMD	CPU	NaN	LAPTOP LENOVO IP 5 2 IN 1 14AHP9 AMD R7-8845HS 3.8GHZ-16GB-512GB SSD-14" WUXGA-TOUCH-GREY-W11	f
514	laptop asus zenbook duo core ultra x7 358h 1.9ghz-32gb-1tb ssd-gray-14"3k touch-w11+forro	Intel	CPU	NaN	LAPTOP ASUS ZENBOOK DUO CORE ULTRA X7 358H 1.9GHZ-32GB-1TB SSD-GRAY-14"3K TOUCH-W11+FORRO	f
515	nuc asus intel core 3 processor 100u ddr5 5600mhz m.2 wifi7 bt5.4 hdmi-thunderbolt rj45-vesa	Intel	CPU	NaN	NUC ASUS INTEL CORE 3 PROCESSOR 100U DDR5 5600MHZ M.2 WIFI7 BT5.4 HDMI-THUNDERBOLT RJ45-VESA	f
516	laptop asus vivobook 16 amd r7 ai 350 2.0ghz-16gb-1tb-quiet blue-16"wuxga-w11+moch+mo+office365	AMD	CPU	NaN	LAPTOP ASUS VIVOBOOK 16 AMD R7 AI 350 2.0GHZ-16GB-1TB-QUIET BLUE-16"WUXGA-W11+MOCH+MO+OFFICE365	f
517	laptop asus vivobook s16 amd r9-270 (16tops) 4.0ghz-16gb-1tb ssd-mate gray-16"wuxga-w11+moc+ofi365	AMD	CPU	NaN	LAPTOP ASUS VIVOBOOK S16 AMD R9-270 (16TOPS) 4.0GHZ-16GB-1TB SSD-MATE GRAY-16"WUXGA-W11+MOC+OFI365	f
559	tablet lenovo idea tab 5g 11" 8gb+128gb incluye lapiz lenovo + folio teclado gris	Varios	Periferico	Teclado	TABLET LENOVO IDEA TAB 5G 11" 8GB+128GB INCLUYE LAPIZ LENOVO + FOLIO TECLADO GRIS	f
518	tarjeta de video asus dual geforce rtxtm 3050 oc 6gb gddr6x dos ventiladores pcie 4.0/dvi/hdmi/dp	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL GeForce RTX™ 3050 OC 6GB GDDR6X DOS VENTILADORES PCIe 4.0/DVI/HDMI/DP	f
519	tarjeta tplink pcie x1 wifi 300mbps 2 antenas desmontables	Varios	GPU	NaN	TARJETA TPLINK PCIe x1 WIFI 300Mbps 2 ANTENAS DESMONTABLES	f
520	celular infinix smart 20 4gb+4 virtual ram 128gb azul	Varios	RAM	NaN	CELULAR INFINIX SMART 20 4GB+4 VIRTUAL RAM 128GB AZUL	f
521	tablet itel vista tab 11 10.1" lte 12gb ram (4gb+8gb extendida) + 128gb- gris	Varios	RAM	NaN	TABLET ITEL VISTA TAB 11 10.1" LTE 12GB RAM (4GB+8GB EXTENDIDA) + 128GB- GRIS	f
522	televisor-tv indurama 50" led 4k uhd smart - google tv 5.0	Varios	RAM	NaN	TELEVISOR-TV INDURAMA 50" LED 4K UHD SMART - GOOGLE TV 5.0	f
523	televisor-tv indurama 65" led 4k uhd smart - google tv 5.0	Varios	RAM	NaN	TELEVISOR-TV INDURAMA 65" LED 4K UHD SMART - GOOGLE TV 5.0	f
524	televisor-tv indurama 43" led 4k uhd 43tikj5uhd - google tv 5.0	Varios	RAM	NaN	TELEVISOR-TV INDURAMA 43" LED 4K UHD 43TIKJ5UHD - GOOGLE TV 5.0	f
525	televisor-tv indurama 58" led 4k uhd smart 58tikgf5uhd google tv 5.0	Varios	RAM	NaN	TELEVISOR-TV INDURAMA 58" LED 4K UHD SMART 58TIKGF5UHD GOOGLE TV 5.0	f
526	mouse gamer lightspeed logitech g pro, inalambrico, optico, 25.600dpi	Logitech	Periferico	Mouse	Mouse Gamer LIGHTSPEED Logitech G Pro, Inalámbrico, Óptico, 25.600DPI	f
527	upgrade kit mouse logitech g pro wireless teclado pro x 60 tkl wireless	Logitech	Periferico	Teclado	UPGRADE KIT Mouse Logitech G Pro Wireless – Teclado Pro X 60 Tkl Wireless	f
528	televisor-tv indurama 43" led 4k uhd smart - google tv	Varios	RAM	NaN	TELEVISOR-TV INDURAMA 43" LED 4K UHD SMART - GOOGLE TV	f
529	teclado gamer corsair k70 core rgb, teclado mecanico, switch cherry mlx red, alambrico, negro (espanol)	Corsair	Periferico	Teclado	Teclado Gamer Corsair K70 Core RGB, Teclado Mecánico, Switch Cherry MLX Red, Alámbrico, Negro (Español)	f
530	tarjeta de video gigabyte amd radeon rx 9070 gaming oc, 16gb 256-bit gddr6, pci express 5.0	AMD	CPU	NaN	Tarjeta de Video Gigabyte AMD Radeon RX 9070 GAMING OC, 16GB 256-bit GDDR6, PCI Express 5.0	f
531	mainbaord asus prime b860m-a socket 1851 intel	Intel	CPU	NaN	Mainbaord Asus Prime B860m-a socket 1851 intel	f
532	memoria ram kingston 16gb ddr5 5600mhz dimm cl46 (kvr56u46bs8- 16)	Kingston	RAM	DDR5	Memoria RAM KINGSTON 16GB DDR5 5600MHz – DIMM – CL46 (KVR56U46BS8- 16)	f
533	memoria ram kingston valueram 32gb *ddr5* 6400mhz cl52 cudimm (kvr64a52bd8-32) para pc	Kingston	RAM	DDR5	Memoria RAM KINGSTON VALUERAM 32GB *DDR5* 6400MHZ – CL52 – CUDIMM (KVR64A52BD8-32) para PC	f
534	memoria ram mushkin ddr4, 3200mhz, 16gb pc	Varios	RAM	DDR4	Memoria RAM Mushkin DDR4, 3200MHz, 16GB PC	f
535	monitor gamer lg ultragear g4 lcd 23.8, 19201080 full hd, g-sync/freesync, 144hz, hdmi/displayport, negro modelo 24g411a-b	Lg	Monitor	NaN	Monitor Gamer LG UltraGear G4 LCD 23.8″, 1920×1080 Full HD, G-Sync/FreeSync, 144Hz, HDMI/DisplayPort, Negro Modelo 24G411A-B	f
536	monitor teros te-1914s 19.5 1600900 5ms 220 nits hdmi vga parlantes	Varios	Monitor	NaN	Monitor Teros Te-1914s 19.5″ 1600×900 5ms 220 Nits – Hdmi – Vga – Parlantes	f
537	monitor gamer curvo gigabyte gs34wqca lcd 34, 34401440 ultra wide quad hd, freesync, 120hz, hdmi/displayport, negro	Gigabyte	Monitor	NaN	Monitor Gamer Curvo Gigabyte GS34WQCA LCD 34″, 3440×1440 Ultra Wide Quad HD, FreeSync, 120Hz, HDMI/DisplayPort, Negro	f
538	monitor gamer gigabyte gs27fa led 27, 19201080 full hd, 180hz, hdmi/displayport, negro	Gigabyte	Monitor	NaN	Monitor Gamer Gigabyte GS27FA LED 27″, 1920×1080 Full HD, 180Hz, HDMI/DisplayPort, Negro	f
539	monitor indurama 32 vortix ultra va fhd 1080p	Varios	Monitor	VA	MONITOR Indurama 32″ VORTIX Ultra VA FHD 1080p	f
540	monitor indurama 27 vortix nova ips fhd 1080p 120hz hdmi displayport	Varios	Monitor	IPS	MONITOR Indurama 27″ VORTIX NOVA IPS FHD 1080p 120Hz HDMI DISPLAYPORT	f
541	monitor lg 19.5 hd+ 1600900 led tn 75hz 5ms (gtg) hdmi/vga negro modelo 20u401a	Lg	Monitor	TN	MONITOR LG 19.5″ HD+ 1600×900 – LED TN – 75Hz – 5ms (GTG) – HDMI/VGA – NEGRO Modelo 20u401a	f
542	monitor rca w2427sg 23.8 fhd (1920x1080) 100hz 14ms hdmi/vga	Varios	Monitor	NaN	MONITOR RCA W2427SG 23.8″ FHD (1920X1080) 100HZ – 14MS – HDMI/VGA	f
543	cpu para juegos amd ryzen 5 5500 rtx 3050 6gb sin monitor	Varios	Monitor	NaN	CPU para juegos AMD RYZEN 5 5500 RTX 3050 6GB sin monitor	f
544	cpu para juegos amd ryzen 5 5600g rtx 3050 sin monitor	Varios	Monitor	NaN	CPU para juegos AMD RYZEN 5 5600G RTX 3050 sin monitor	f
545	cpu para juegos amd ryzen 5 5500 rtx 3060 12gb sin monitor	Varios	Monitor	NaN	CPU para juegos AMD RYZEN 5 5500 RTX 3060 12GB sin monitor	f
546	cpu para juegos amd ryzen 7 5700g rtx 3060 12gb ram 32gb sin monitor	Varios	Monitor	NaN	CPU para juegos AMD RYZEN 7 5700G RTX 3060 12GB RAM 32GB sin monitor	f
547	teclado primus gaming ballista61t abs 61 teclas retroiluminado switch red lineal es white (pks-060w-s)	Varios	Periferico	Teclado	TECLADO PRIMUS GAMING BALLISTA61T – ABS – 61 TECLAS – RETROILUMINADO – SWITCH RED LINEAL – ES – WHITE (PKS-060W-S)	f
548	teclado quasad usb espanol multimedia modelo qk-440c	Varios	Periferico	Teclado	Teclado Quasad USB Español Multimedia Modelo QK-440C	f
549	case quasad generico c3156 teclado mouse parlantes	Varios	Periferico	Teclado	Case Quasad GENERICO C3156 TECLADO MOUSE PARLANTES	f
550	combo kit 4 en 1 marvo cm-370 teclado mouse headset mousepad	Varios	Periferico	Teclado	Combo Kit 4 en 1 Marvo CM-370 Teclado Mouse headset mousepad	f
551	memoria sodimm hiksemi 16gb ddr4 3200mhz	Varios	RAM	DDR4	MEMORIA SODIMM HIKSEMI 16GB DDR4 3200MHz	f
552	televisor-tv indurama 65" led 4k uhd smart - google tv	Varios	RAM	NaN	TELEVISOR-TV INDURAMA 65" LED 4K UHD SMART - GOOGLE TV	f
553	teclado + mouse klip xtreme alambrico ergonomico usb	Varios	Periferico	Teclado	TECLADO + MOUSE KLIP XTREME ALAMBRICO ERGONOMICO USB	f
554	monitor lg 27" led gamer ultragear ips 1080p 180hz hdmi-dp pivote	Lg	Monitor	IPS	MONITOR LG 27" LED GAMER ULTRAGEAR IPS 1080p 180Hz HDMI-DP PIVOTE	f
555	soporte de pared xtech articulado 23" a 42" televisor-tv y monitor	Varios	Monitor	NaN	SOPORTE DE PARED XTECH ARTICULADO 23" A 42" TELEVISOR-TV Y MONITOR	f
556	convertidor tufsen usb 3.0 a vga monitor	Varios	Monitor	NaN	CONVERTIDOR TUFSEN USB 3.0 A VGA MONITOR	f
557	soporte de pared xtech fijo 26" a 70" televisor-tv y monitor	Varios	Monitor	NaN	SOPORTE DE PARED XTECH FIJO 26" A 70" TELEVISOR-TV Y MONITOR	f
558	teclado lenovo ideapad 330-14ikb gray win8 (without frame)	Varios	Periferico	Teclado	TECLADO LENOVO IDEAPAD 330-14IKB GRAY WIN8 (WITHOUT FRAME)	f
698	mousepad ergonomico klip xtreme kmp-100b	Varios	Periferico	Mouse	MOUSEPAD ERGONOMICO KLIP XTREME KMP-100B	f
560	tablet lenovo yoga tab plus 12,7" gen 3 wifi 16+256gb (incluye teclado + tab pen pro )	Varios	Periferico	Teclado	TABLET LENOVO YOGA TAB PLUS 12,7" GEN 3 WIFI 16+256GB (INCLUYE TECLADO + TAB PEN PRO )	f
561	teclado hp pavilion x360 14m-dw0023dx 14m-dw1023dx 14m-dw1033dx	Varios	Periferico	Teclado	TECLADO HP PAVILION X360 14M-DW0023DX 14M-DW1023DX 14M-DW1033DX	f
562	tablet lenovo idea tab 5g 11" 8gb+256gb incluye lapiz lenovo + folio teclado	Varios	Periferico	Teclado	TABLET LENOVO IDEA TAB 5G 11" 8GB+256GB INCLUYE LAPIZ LENOVO + FOLIO TECLADO	f
563	teclado + mouse xtech inalambrico con mouse pad xl y hub usb 3.0 4 puertos	Varios	Periferico	Teclado	TECLADO + MOUSE XTECH INALAMBRICO CON MOUSE PAD XL Y HUB USB 3.0 4 PUERTOS	f
564	teclado xtech alambrico usb multimedia	Varios	Periferico	Teclado	TECLADO XTECH ALAMBRICO USB MULTIMEDIA	f
565	tablet lenovo idea tab pro 12.7" 8gb+256gb gris + teclado + lenovo tab pen plus + moto buds	Varios	Periferico	Teclado	TABLET LENOVO IDEA TAB PRO 12.7" 8GB+256GB GRIS + TECLADO + LENOVO TAB PEN PLUS + MOTO BUDS	f
566	teclado primus alambrico gamer ballista usb-c trenzado desmontable negro	Varios	Periferico	Teclado	TECLADO PRIMUS ALAMBRICO GAMER BALLISTA USB-C TRENZADO DESMONTABLE NEGRO	f
567	tablet lenovo idea tab pro 12.7" 8gb 256gb usb-c luna grey + teclado lenovo + tab pen plus	Varios	Periferico	Teclado	TABLET LENOVO IDEA TAB PRO 12.7" 8GB 256GB USB-C LUNA GREY + TECLADO LENOVO + TAB PEN PLUS	f
568	repuesto teclado/palmrest para laptop xtratech xct15q11	Varios	Periferico	Teclado	REPUESTO TECLADO/PALMREST PARA LAPTOP XTRATECH XCT15Q11	f
569	repuesto teclado/palmrest para laptop xtratech xct14q82	Varios	Periferico	Teclado	REPUESTO TECLADO/PALMREST PARA LAPTOP XTRATECH XCT14Q82	f
570	repuesto teclado/palmrest laptop xtratech xct14q11	Varios	Periferico	Teclado	REPUESTO TECLADO/PALMREST LAPTOP XTRATECH XCT14Q11	f
571	teclado ezmi alambrico gamer retroiluminado usb - negro	Varios	Periferico	Teclado	TECLADO EZMI ALAMBRICO GAMER RETROILUMINADO USB - NEGRO	f
572	teclado ezmi alambrico usb - negro	Varios	Periferico	Teclado	TECLADO EZMI ALAMBRICO USB - NEGRO	f
573	teclado asus g713 g713q g713qe g713qm black us (rgb blacklit win8)	Asus	Periferico	Teclado	TECLADO ASUS G713 G713Q G713QE G713QM BLACK US (RGB BLACKLIT WIN8)	f
574	teclado primus alambrico gamer usb 105 teclas 1000hz anti-ghosting	Varios	Periferico	Teclado	TECLADO PRIMUS ALAMBRICO GAMER USB 105 TECLAS 1000Hz ANTI-GHOSTING	f
575	teclado logitech alambrico gamer g213 prodigy usb - ingles	Logitech	Periferico	Teclado	TECLADO LOGITECH ALAMBRICO GAMER G213 PRODIGY USB - INGLES	f
576	monitor lg 24" (23.8) led ips 1080p hdmix2	Lg	Monitor	IPS	MONITOR LG 24" (23.8) LED IPS 1080p HDMIx2	f
577	monitor xtratech 21.5" fhd lcd 19201080 hdmi - vga- 100hz	Varios	Monitor	NaN	MONITOR XTRATECH 21.5" FHD LCD 1920×1080 HDMI - VGA- 100Hz	f
578	televisor-tv indurama 58" led 4k uhd smart - google tv	Varios	RAM	NaN	TELEVISOR-TV INDURAMA 58" LED 4K UHD SMART - GOOGLE TV	f
579	monitor indurama 22" vortix core va fhd 1080p 100hz	Varios	Monitor	VA	MONITOR INDURAMA 22" VORTIX CORE VA FHD 1080p 100Hz	f
580	disco solido ssd ext adata 1tb - 2000 mb/s- se880- usb 3.2 gen2 x2	Adata	SSD	NaN	DISCO SOLIDO SSD EXT ADATA 1TB - 2000 MB/s- SE880- USB 3.2 Gen2 x2	f
581	disco solido ssd int m.2 adata 1tb 2280 legend 710 pcle gen3 x4	Adata	SSD	NVMe	DISCO SOLIDO SSD INT M.2 ADATA 1TB 2280 LEGEND 710 PCle Gen3 x4	f
582	disco solido ssd int m.2 adata 512gb 2280 legend 710 pcle gen3 x4	Adata	SSD	NVMe	DISCO SOLIDO SSD INT M.2 ADATA 512GB 2280 LEGEND 710 PCle Gen3 x4	f
583	disco solido ssd int adata 1tb su-650 sata 6gb-s 2.5inc 3d-nand	Adata	SSD	SATA	DISCO SOLIDO SSD INT ADATA 1TB SU-650 SATA 6Gb-s 2.5Inc 3D-NAND	f
584	disco solido ssd int m.2 hiksemi wave 512gb 2280 nvme pcie sata 3.0	Varios	SSD	NVMe	DISCO SOLIDO SSD INT M.2 HIKSEMI WAVE 512GB 2280 NVME PCIe SATA 3.0	f
585	disco solido ssd int m.2 hiksemi wave 1tb 2280 nvme pcie	Varios	SSD	NVMe	DISCO SOLIDO SSD INT M.2 HIKSEMI WAVE 1TB 2280 NVME PCIe	f
586	disco solido ssd int hiksemi wave 512gb series 2.5" sata 3.0	Varios	SSD	SATA	DISCO SOLIDO SSD INT HIKSEMI WAVE 512GB SERIES 2.5" SATA 3.0	f
587	laptop acer gaming nitro lite ci5-13420h 2.1ghz-16gb-512gb ssd-tg gtx3050 6gb-black-16"fhd-w11	Acer	SSD	NaN	LAPTOP ACER GAMING NITRO LITE CI5-13420H 2.1GHZ-16GB-512GB SSD-TG GTX3050 6GB-BLACK-16"FHD-W11	f
588	disco lenovo m.2 5300 240gb sata 6gbps non hs ssd/sr250v2,st550,sr530,sr550,sr570,sr630,sr650,650 v2	Varios	SSD	NVMe	DISCO LENOVO M.2 5300 240GB SATA 6GBPS Non HS SSD/SR250V2,ST550,SR530,SR550,SR570,SR630,SR650,650 V2	f
589	nuc asus intel core ultra 7 255h ddr5 5600mhz m.2 wifi7 bt5.4 hdmi-thunderbolt-rj45-vesa	Asus	SSD	NVMe	NUC ASUS INTEL CORE ULTRA 7 255H DDR5 5600MHZ M.2 WIFI7 BT5.4 HDMI-THUNDERBOLT-RJ45-VESA	f
590	camara smart wifi vta mozart - baby monitor	Varios	Monitor	NaN	CAMARA SMART WIFI VTA MOZART - BABY MONITOR	f
591	monitor xtratech 19.5" led 1600x900 hdmi vga 60 hz parlantes integrados	Varios	Monitor	NaN	MONITOR XTRATECH 19.5" LED 1600X900 HDMI VGA 60 Hz PARLANTES INTEGRADOS	f
592	monitor xtratech 24" full hd 1920x1080 100hz vga hdmi	Varios	Monitor	NaN	MONITOR XTRATECH 24" FULL HD 1920X1080 100Hz VGA HDMI	f
593	barra de luz primus nimbus2l inteligente wifi 2 en 1 para monitor	Varios	Monitor	NaN	BARRA DE LUZ PRIMUS NIMBUS2L INTELIGENTE WIFI 2 EN 1 PARA MONITOR	f
594	soporte de pared avanti articulado 26" a 55" televisor-tv y monitor	Varios	Monitor	VA	SOPORTE DE PARED AVANTI ARTICULADO 26" A 55" TELEVISOR-TV Y MONITOR	f
595	soporte de pared avanti articulado 32" a 60" televisor-tv y monitor	Varios	Monitor	VA	SOPORTE DE PARED AVANTI ARTICULADO 32" A 60" TELEVISOR-TV Y MONITOR	f
596	soporte de pared avanti fijo 32" a 80" televisor-tv y monitor	Varios	Monitor	VA	SOPORTE DE PARED AVANTI FIJO 32" A 80" TELEVISOR-TV Y MONITOR	f
597	soporte de pared avanti fijo 26" a 63" televisor-tv y monitor	Varios	Monitor	VA	SOPORTE DE PARED AVANTI FIJO 26" A 63" TELEVISOR-TV Y MONITOR	f
598	monitor indurama 25" vortix nova ips fhd 1080p 120hz	Varios	Monitor	IPS	MONITOR INDURAMA 25" VORTIX NOVA IPS FHD 1080p 120Hz	f
599	monitor indurama 27" vortix nova ips fhd 1080p 120hz	Varios	Monitor	IPS	MONITOR INDURAMA 27" VORTIX NOVA IPS FHD 1080p 120Hz	f
600	monitor indurama 32" gamer curvo vortix ultra va fhd 1080p 180hz	Varios	Monitor	VA	MONITOR INDURAMA 32" GAMER CURVO VORTIX ULTRA VA FHD 1080p 180Hz	f
601	redragon horus k618 rgb white teclado mecanico	Redragon	Periferico	Teclado	Redragon Horus K618 RGB White Teclado Mecánico	f
602	redragon kumara k552 teclado mecanico	Redragon	Periferico	Teclado	Redragon Kumara K552 Teclado Mecánico	f
603	audifono inalambrico bt 5.3 c/ estuche genius m910bt	Varios	Periferico	Headset	Audifono Inalambrico BT 5.3 C/ Estuche – Genius M910BT	f
604	unidad estado solido ssd 2.5 sata iii 128gb indilinx ind-s325s	Varios	SSD	SATA	Unidad Estado Sólido Ssd 2.5″ Sata III 128Gb – Indilinx IND-S325S	f
605	laptop 15.6 fhd, core i5 12va, ram 8gb, ssd 256gb lenovo 15iah8	Varios	RAM	NaN	Laptop 15.6″ Fhd, Core i5 12va, Ram 8Gb, Ssd 256Gb – Lenovo 15IAH8	f
606	lector de memorias interno para mainboard universal	Varios	RAM	NaN	Lector de Memorias Interno para Mainboard – Universal	f
607	cpu intel core i5 12va 14va, ram 16gb, ssd 512gb, perifericos	Varios	SSD	NaN	Cpu Intel Core i5 12va 14va, Ram 16Gb, Ssd 512Gb, Periféricos	f
608	laptop 15.6 fhd, ryzen 7 5825u, ram 24gb, ssd 1tb asus m1502ya	Asus	SSD	NaN	Laptop 15.6″ Fhd, Ryzen 7 5825U, Ram 24GB, Ssd 1TB – Asus M1502YA	f
609	cpu amd atlhon 3000g, 2gb graficos, ram 8gb, ssd 256gb	Varios	SSD	NaN	Cpu Amd Atlhon 3000g, 2Gb Gráficos, Ram 8GB, SSD 256GB	f
610	unidad estado solido ssd sata iii 512gb dato ds700	Varios	SSD	SATA	Unidad Estado Sólido SSD Sata III 512Gb – Dato DS700	f
611	laptop 15.6 ryzen 5 7520u, ram 16gb, ssd 512gb hp 15-fc0256la	Varios	SSD	NaN	Laptop 15.6″ Ryzen 5 7520u, Ram 16GB, Ssd 512Gb – HP 15-FC0256LA	f
612	unidad estado solido ssd 2.5 240gb sata iii adata su650	Adata	SSD	SATA	Unidad Estado Solido Ssd 2.5″ 240GB Sata III – Adata SU650	f
613	unidad estado solido ssd 2.5 sata iii 256gb indilinx ind-s325s	Varios	SSD	SATA	Unidad Estado Sólido Ssd 2.5″ Sata III 256GB – Indilinx IND-S325S	f
614	unidad estado solido ssd 2.5 sata iii 960gb msi s270	Msi	SSD	SATA	Unidad Estado Sólido SSD 2.5″ Sata III 960GB – Msi S270	f
615	redragon ucal pro k673 anime teclado 75% wireless	Redragon	Periferico	Teclado	Redragon Ucal Pro K673 Anime Teclado 75% Wireless	f
616	laptop 15,6 fhd, i5 12va, ram 16gb ddr5, ssd 512gb celeste lenovo 15iah8	Varios	SSD	NaN	Laptop 15,6″ Fhd, i5 12va, Ram 16GB Ddr5, Ssd 512Gb Celeste – Lenovo 15IAH8	f
617	laptop 15 fhd 144hz, ryzen 7 7735hs, ram 16gb ddr5, ssd 512gb, rtx 3050 msi thin a15 b7uc	Msi	SSD	NaN	Laptop 15″ Fhd 144Hz, Ryzen 7 7735HS, Ram 16Gb Ddr5, Ssd 512Gb, Rtx 3050 – Msi Thin A15 B7UC	f
618	laptop 15.6 fhd, core i5 13420h, ram 8gb ddr5, ssd 512gb lenovo v15 g5	Varios	SSD	NaN	Laptop 15.6″ Fhd, Core i5 13420H, Ram 8Gb Ddr5, Ssd 512Gb – Lenovo V15 G5	f
619	monitor 25 fhd, ips, adaptive sync, 1ms, 200hz gigabyte gs25f2	Gigabyte	Monitor	IPS	Monitor 25″ Fhd, IPS, Adaptive Sync, 1ms, 200Hz – Gigabyte GS25F2	f
620	monitor 27 2k, ips, adaptive sync, 1ms, 180hz gigabyte gs27qa	Gigabyte	Monitor	IPS	Monitor 27″ 2K, IPS, Adaptive Sync, 1ms, 180Hz – Gigabyte GS27QA	f
621	monitor 27 fhd, ips, adaptive sync, 144hz, 1ms lg 27g411a-b	Lg	Monitor	IPS	Monitor 27″ Fhd, Ips, Adaptive Sync, 144hz, 1ms – LG 27G411A-B	f
622	monitor 20 hd+, 1440900, hdmi, vga one j019	Varios	Monitor	NaN	Monitor 20″ HD+, 1440×900, Hdmi, Vga – One J019	f
623	monitor 34 34401440, 120hz, 1ms, adaptive sync, ultrawide gigabyte gs34wqca	Gigabyte	Monitor	NaN	Monitor 34″ 3440×1440, 120Hz, 1ms, Adaptive Sync, UltraWide – Gigabyte GS34WQCA	f
624	monitor 25 fhd ips 120hz, dp, hdmi indurama vortix nova	Varios	Monitor	IPS	Monitor 25″ FHD Ips 120Hz, DP, Hdmi – Indurama Vortix Nova	f
625	monitor 25 fhd, ips, adaptive sync, 1ms, 240hz gigabyte gs25f2a	Gigabyte	Monitor	IPS	Monitor 25″ Fhd, IPS, Adaptive Sync, 1ms, 240Hz – Gigabyte GS25F2A	f
626	ram ddr4, 16gb, 3200, so-dimm kingston	Kingston	RAM	DDR4	Ram Ddr4, 16Gb, 3200, So-Dimm – Kingston	f
627	ram gamer ddr5, 16gb, 5600, dimm, cl40, rgb kingston fury	Kingston	RAM	DDR5	Ram Gamer Ddr5, 16Gb, 5600, Dimm, Cl40, RGB – Kingston Fury	f
628	mouse inalambrico logitech mx ergo s	Logitech	Periferico	Mouse	MOUSE INALAMBRICO LOGITECH MX ERGO S	f
629	audifono inalambrico jbl tour one m3 black	Varios	Periferico	Headset	AUDIFONO INALAMBRICO JBL TOUR ONE M3 BLACK	f
630	audifono inalambrico jbl tune 780nc black	Varios	Periferico	Headset	AUDIFONO INALAMBRICO JBL TUNE 780NC BLACK	f
631	audifono inalambrico lightspeed logitech g pro x	Logitech	Periferico	Headset	AUDIFONO INALAMBRICO LIGHTSPEED LOGITECH G PRO X	f
632	procesador amd ryzen 7-7800x3d 4.2ghz hasta 5ghz cache 96mb no inc.	AMD	CPU	NaN	Procesador AMD ryzen 7-7800X3D 4.2GHz hasta 5GHz cache 96MB no inc.	f
633	procesador amd ryzen 9-7900x 4.7ghz hasta 5.6ghz cache 64mb no inc.	AMD	CPU	NaN	Procesador AMD ryzen 9-7900X 4.7GHz hasta 5.6GHz cache 64MB no inc.	f
634	procesador amd ryzen 7-7700x 4.5ghz hasta 5.4ghz cache 32mb no incluye	AMD	CPU	NaN	Procesador AMD ryzen 7-7700X 4.5GHz hasta 5.4GHz cache 32MB no incluye	f
635	procesador athlon 3000g graficos vega 3 amd	AMD	CPU	NaN	Procesador Athlon 3000G Graficos Vega 3 – AMD	f
636	procesador ultra 5 225 series 2 10n+10h intel	Intel	CPU	NaN	Procesador Ultra 5 225 Series 2 10N+10H – Intel	f
637	procesador ultra 7 265kf series 2 20n+20h intel	Intel	CPU	NaN	Procesador Ultra 7 265KF Series 2 20N+20H – Intel	f
638	procesador ultra 7 265k series 2 20n+20h intel	Intel	CPU	NaN	Procesador Ultra 7 265K Series 2 20N+20H – Intel	f
639	tarjeta de video msi geforce gt710 2gd3h 2gb low profile ddr3	NVIDIA	GPU	NaN	Tarjeta de video MSI GeForce GT710 2GD3H 2GB low profile DDR3	f
640	adap. wifi pci e 300mbps tarjeta de red d-link dwa-548	Varios	GPU	NaN	Adap. Wifi PCI E 300Mbps Tarjeta de Red – D-Link DWA-548	f
641	memoria ram acer ud100 8gb ddr4 3200mhz cl22 para pc	Acer	RAM	DDR4	Memoria ram Acer UD100 8GB DDR4 3200MHz CL22 para pc	f
642	memoria ram kingston 8gb ddr4 3200mhz cl22 para pc	Kingston	RAM	DDR4	Memoria ram Kingston 8GB DDR4 3200MHz CL22 para pc	f
643	memoria ram patriot 8gb ddr4 3200mhz cl22 para pc	Varios	RAM	DDR4	Memoria ram Patriot 8GB DDR4 3200MHz CL22 para pc	f
644	memoria ram acer 16gb ddr4 3200mhz cl22 para pc	Acer	RAM	DDR4	Memoria ram Acer 16GB DDR4 3200MHz CL22 para pc	f
645	memoria ram adata 8gb ddr5 5600mhz cl45 para pc 1.1v	Adata	RAM	DDR5	Memoria ram Adata 8gb DDR5 5600Mhz CL45 para pc 1.1v	f
646	memoria ram kingston 16gb ddr4 3200mhz cl22 para notebook	Kingston	RAM	DDR4	Memoria ram Kingston 16GB DDR4 3200Mhz CL22 para notebook	f
647	monitor 24 fhd, ips, adaptive sync, 1ms, 144hz gigabyte gs24f14	Gigabyte	Monitor	IPS	Monitor 24″ Fhd, IPS, Adaptive Sync, 1ms, 144Hz – Gigabyte GS24F14	f
648	monitor 24 fhd, ips, adaptive sync, 120hz, 1ms asus va249hg	Asus	Monitor	IPS	Monitor 24″ Fhd, Ips, Adaptive Sync, 120hz, 1ms – Asus VA249HG	f
649	monitor 22 fhd, 120hz, adaptive sync, hdmi, dp armaggeddon pixxel pf22hd super wh	Varios	Monitor	NaN	Monitor 22″ Fhd, 120Hz, Adaptive Sync, Hdmi, Dp – Armaggeddon Pixxel PF22HD Super WH	f
650	teclado mecanico 60% gamer rgb marvo kg933 bk sw red	Varios	Periferico	Teclado	Teclado Mecanico 60% Gamer Rgb – Marvo KG933 BK SW RED	f
651	teclado estandar espanol multimedia quasad qk-440c	Varios	Periferico	Teclado	Teclado Estándar Español Multimedia – Quasad QK-440C	f
652	teclado inalambrico c/ touchpad logitech k400 plus	Logitech	Periferico	Teclado	Teclado Inalámbrico C/ Touchpad – Logitech K400 Plus	f
653	teclado gamer multimedia rgb marvo k602	Varios	Periferico	Teclado	Teclado Gamer Multimedia Rgb – Marvo K602	f
654	teclado multimedia usb cable wh genius slimstar 126	Varios	Periferico	Teclado	Teclado Multimedia Usb Cable WH – Genius Slimstar 126	f
655	teclado gamer mecanico rgb 100% evil pc kb-772eg	Varios	Periferico	Teclado	Teclado Gamer Mecanico Rgb 100% – Evil PC KB-772EG	f
656	teclado mecanico gamer 80% rgb marvo kg901 krone 87	Varios	Periferico	Teclado	Teclado Mecanico Gamer 80% Rgb – Marvo KG901 Krone 87	f
657	teclado gamer mecanico rgb 100% quasad qkm-g80	Varios	Periferico	Teclado	Teclado Gamer Mecanico Rgb 100% – Quasad QKM-G80	f
658	combo gamer teclado, mouse, audif, pad env 9182 ge08	Varios	Periferico	Teclado	Combo Gamer Teclado, Mouse, Audif, Pad – Env 9182 GE08	f
659	combo teclado mecanico + mouse calidad rgb cougar combat	Varios	Periferico	Teclado	Combo Teclado Mecanico + Mouse Calidad Rgb – Cougar Combat	f
660	combo teclado + mouse inalambrico recargable quasad qc-4583	Varios	Periferico	Teclado	Combo Teclado + Mouse Inalámbrico Recargable – Quasad QC-4583	f
661	combo gamer teclado + mouse c/ cable usb msi gk100	Msi	Periferico	Teclado	Combo Gamer Teclado + Mouse C/ Cable USB – MSI GK100	f
662	mouse gamer p/pc rgb evil pc ms-225eg	Varios	Periferico	Mouse	Mouse Gamer P/Pc Rgb – Evil PC MS-225EG	f
663	mouse gamer alambrico usb p/pc rgb corsair katar pro	Corsair	Periferico	Mouse	Mouse Gamer Alambrico Usb P/Pc RGB – Corsair Katar Pro	f
664	mouse gamer p/pc rgb 6 botones genius m-700	Varios	Periferico	Mouse	Mouse Gamer P/Pc Rgb 6 Botones – Genius M-700	f
665	mouse gamer programable rgb logitech g502 hero	Logitech	Periferico	Mouse	Mouse Gamer Programable Rgb – Logitech G502 Hero	f
666	mouse inalambrico usb colores logitech m170	Logitech	Periferico	Mouse	Mouse Inalambrico Usb Colores – Logitech M170	f
667	mouse c/ cable usb genius micro traveler	Varios	Periferico	Mouse	Mouse C/ Cable Usb – Genius Micro Traveler	f
668	mouse inalambrico usb blue genius nx-7007	Varios	Periferico	Mouse	Mouse Inalambrico Usb Blue – Genius NX-7007	f
669	mouse gamer p/pc rgb msi gm08	Msi	Periferico	Mouse	Mouse Gamer P/Pc Rgb – MSI GM08	f
670	mouse inalambrico gamer programable logitech g305	Logitech	Periferico	Mouse	Mouse Inalámbrico Gamer Programable – Logitech G305	f
671	mousepad antideslizante xtech xta-180	Varios	Periferico	Mouse	MousePad Antideslizante – XTech XTA-180	f
672	teclado mecanico gamer rgb 60% primus ballista61t	Varios	Periferico	Teclado	Teclado Mecanico Gamer Rgb 60% – Primus BALLISTA61T	f
673	teclado mecanico gamer 60% sw rojo xtrike me gk-996	Varios	Periferico	Teclado	Teclado Mecanico Gamer 60% Sw Rojo – Xtrike Me GK-996	f
674	monitor msi gamer mag 272qp qd-oled x50 26.5 qd-oled wqhd 500hz	Msi	Monitor	OLED	Monitor MSI gamer MAG 272QP QD-OLED X50 26.5″ QD-Oled WQHD 500Hz	f
675	teclado mecanico gamer 60% rgb xtrike me gk-916	Varios	Periferico	Teclado	Teclado Mecanico Gamer 60% Rgb – Xtrike Me GK-916	f
676	monitor asrock gamer pg27ffx2a 27 inch led ips fhd (1920 x	Varios	Monitor	IPS	Monitor Asrock gamer PG27FFX2A 27 inch LED IPS FHD (1920 x	f
677	monitor benq gamer zowie xl2731k 27 inch fhd 165hz 1ms hdmi-displayport	Benq	Monitor	NaN	Monitor BenQ gamer Zowie XL2731K 27 inch FHD 165Hz 1ms HDMI-DisplayPort	f
678	monitor 25 fhd, ips, adaptive sync, 0.5ms, 240hz msi mag 245f x24	Msi	Monitor	IPS	Monitor 25″ Fhd, IPS, Adaptive Sync, 0.5ms, 240Hz – Msi Mag 245F X24	f
679	monitor 24 fhd, 100hz, hdmi, vga xtratech xtm24	Varios	Monitor	NaN	Monitor 24″ FHD, 100Hz, Hdmi, Vga – Xtratech XTM24	f
680	monitor 24 fhd, ips, 200hz, 1 ms, adaptive sync xiaomi g24i 2026	Varios	Monitor	IPS	Monitor 24″ Fhd, Ips, 200hz, 1 ms, Adaptive Sync – Xiaomi G24i 2026	f
681	monitor 24 fhd, ips, adaptive sync, 144hz, 1ms lg 24g411a-b	Lg	Monitor	IPS	Monitor 24″ Fhd, Ips, Adaptive Sync, 144hz, 1ms – LG 24G411A-B	f
682	monitor 27 2k 2560 x 1440, curvo, adaptive sync, 1ms, 165hz samsung odyssey g5 g55c	Samsung	Monitor	NaN	Monitor 27″ 2K 2560 x 1440, Curvo, Adaptive Sync, 1ms, 165Hz – Samsung Odyssey G5 G55C	f
683	monitor 20 hd+ 1600900, 75hz, hdmi lg 20u401a-b	Lg	Monitor	NaN	Monitor 20″ HD+ 1600×900, 75Hz, Hdmi – LG 20U401A-B	f
684	monitor 25 fhd, adaptive sync, 240hz, 0.3ms asus tuf vg259qm5a	Asus	Monitor	NaN	Monitor 25″ FHD, Adaptive Sync, 240Hz, 0.3ms – Asus Tuf VG259QM5A	f
685	monitor 24 fhd gamer, 200hz, 1ms, rgb, dp, hdmi env 1887	Varios	Monitor	NaN	Monitor 24″ Fhd Gamer, 200hz, 1ms, Rgb, Dp, Hdmi – ENV 1887	f
686	monitor 24 fhd ips, 180hz, 1ms env 3524	Varios	Monitor	IPS	Monitor 24″ Fhd Ips, 180hz, 1ms – ENV 3524	f
687	monitor 24 fhd ips, 120hz, adaptive sync, hdmi, dp armaggeddon pixxel xf24hd	Varios	Monitor	IPS	Monitor 24″ Fhd Ips, 120Hz, Adaptive Sync, Hdmi, Dp – Armaggeddon Pixxel XF24HD	f
688	monitor gamer 25 fhd, ips, 100hz, 1ms, adaptive sync asrock cl25ff	Varios	Monitor	IPS	Monitor Gamer 25″ Fhd, Ips, 100Hz, 1ms, Adaptive Sync – Asrock CL25FF	f
689	monitor 27 fhd, ips, adaptive sync, 180hz, 1ms gigabyte gs27fa	Gigabyte	Monitor	IPS	Monitor 27″ Fhd, Ips, Adaptive Sync, 180Hz, 1ms – Gigabyte GS27FA	f
690	monitor 27 fhd, curvo, adaptive sync, 280hz, 0.5ms msi 276cxf	Msi	Monitor	NaN	Monitor 27″ Fhd, Curvo, Adaptive Sync, 280Hz, 0.5ms – Msi 276CXF	f
691	monitor 24 fhd, ips, adaptive sync, 100hz, 1ms asus vz24ehf	Asus	Monitor	IPS	Monitor 24″ Fhd, Ips, Adaptive Sync, 100hz, 1ms – Asus VZ24EHF	f
692	monitor 20 1600900, 75hz, hdmi, vga xtratech xtm19	Varios	Monitor	NaN	Monitor 20″ 1600×900, 75Hz, Hdmi, Vga – Xtratech XTM19	f
693	monitor 27 fhd, ips, adaptive sync, 180hz, 1ms msi g2712f	Msi	Monitor	IPS	Monitor 27″ Fhd, Ips, Adaptive Sync, 180Hz, 1ms – Msi G2712F	f
694	teclado mecanico gamer 80% sw rojo xtrike me gk-989	Varios	Periferico	Teclado	Teclado Mecanico Gamer 80% Sw Rojo – Xtrike Me GK-989	f
695	teclado gamer usb c/ cable rgb xtrike me kb-309	Varios	Periferico	Teclado	Teclado Gamer Usb C/ Cable RGB – Xtrike Me KB-309	f
696	teclado mecanico gamer 80% sw rojo xtrike me gk-997	Varios	Periferico	Teclado	Teclado Mecanico Gamer 80% Sw Rojo – Xtrike Me GK-997	f
697	laptop asus rog scar 18 g835l + audifonos + mouse + mochila	Asus	Periferico	Mouse	LAPTOP ASUS ROG SCAR 18 G835L + AUDÍFONOS + MOUSE + MOCHILA	f
699	mouse redragon azzmach m618 black	Redragon	Periferico	Mouse	MOUSE REDRAGON AZZMACH M618 BLACK	f
700	msi cubi 5 intel i5 1235u ddr4 +wifi +bluetooh	Intel	CPU	NaN	MSI CUBI 5 INTEL I5 1235U DDR4 +WIFI +BLUETOOH	f
701	tarjeta de red pcie x1 tp-link tl-wn881nd	Varios	GPU	NaN	TARJETA DE RED PCIE X1 TP-LINK TL-WN881ND	f
702	8gb ram so-dimm ddr5 kingston kcp 5600mts cl46	Kingston	RAM	DDR5	8GB RAM SO-DIMM DDR5 KINGSTON KCP 5600MTS CL46	f
703	32gb ram so-dimm ddr5 kingston fury impact 5600mts cl40	Kingston	RAM	DDR5	32GB RAM SO-DIMM DDR5 KINGSTON FURY IMPACT 5600MTS CL40	f
704	16gb ram so-dimm ddr5 kingston fury impact 5600mts cl40	Kingston	RAM	DDR5	16GB RAM SO-DIMM DDR5 KINGSTON FURY IMPACT 5600MTS CL40	f
705	16gb ram ddr4 corsair vengeance lpx 3200mhz cl16	Corsair	RAM	DDR4	16GB RAM DDR4 CORSAIR VENGEANCE LPX 3200MHZ CL16	f
706	16gb ram ddr5 xpg lancer blade black 6000mts cl48	Xpg	RAM	DDR5	16GB RAM DDR5 XPG LANCER BLADE BLACK 6000MTS CL48	f
707	8gb so-dimm ddr4 kingston 3200mhz cl22	Kingston	RAM	DDR4	8GB SO-DIMM DDR4 KINGSTON 3200MHZ CL22	f
708	msi cubi 5 intel i3 1215u ddr4 +wifi +bluetooth	Msi	RAM	DDR4	MSI CUBI 5 INTEL I3 1215U DDR4 +WIFI +BLUETOOTH	f
709	msi cubi 5 intel i7 1255u ddr4 +wifi +bluetooth	Msi	RAM	DDR4	MSI CUBI 5 INTEL I7 1255U DDR4 +WIFI +BLUETOOTH	f
710	monitor ultrawide curvo samsung odyssey oled g9 g91sd	Samsung	Monitor	OLED	MONITOR ULTRAWIDE CURVO SAMSUNG ODYSSEY OLED G9 G91SD	f
711	monitor ultrawide curvo samsung viewfinity s6 s65uc	Samsung	Monitor	NaN	MONITOR ULTRAWIDE CURVO SAMSUNG VIEWFINITY S6 S65UC	f
712	monitor portatil viewsonic va1653	Viewsonic	Monitor	VA	MONITOR PORTATIL VIEWSONIC VA1653	f
713	monitor lg ultragear 27g411a	Lg	Monitor	NaN	MONITOR LG ULTRAGEAR 27G411A	f
714	monitor indurama vortixnova 25	Varios	Monitor	VA	MONITOR INDURAMA VORTIXNOVA 25	f
715	monitor samsung odyssey g6 g60f	Samsung	Monitor	NaN	MONITOR SAMSUNG ODYSSEY G6 G60F	f
716	monitor msi mpg 321urx qd-oled	Msi	Monitor	OLED	MONITOR MSI MPG 321URX QD-OLED	f
717	monitor curvo teros te-2767g	Varios	Monitor	NaN	MONITOR CURVO TEROS TE-2767G	f
718	monitor curvo teros te-3219g	Varios	Monitor	NaN	MONITOR CURVO TEROS TE-3219G	f
719	monitor acer k202q bi	Acer	Monitor	NaN	MONITOR ACER K202Q BI	f
720	monitor lg ultragear 24g411a	Lg	Monitor	NaN	MONITOR LG ULTRAGEAR 24G411A	f
721	monitor indurama vortixnova 27	Varios	Monitor	VA	MONITOR INDURAMA VORTIXNOVA 27	f
722	procesador intel i7 14700 5.4ghz 20+28 lga1700 14va	Intel	CPU	NaN	PROCESADOR INTEL I7 14700 5.4GHZ 20+28 LGA1700 14VA	f
723	redragon olaf k648gg rgb teclado gamer wireless 94 teclas	Redragon	Periferico	Teclado	Redragon Olaf K648GG RGB Teclado Gamer Wireless 94 Teclas	f
724	redragon eisa k686ak rgb pro teclado gamer 90%	Redragon	Periferico	Teclado	Redragon Eisa K686AK RGB PRO Teclado Gamer 90%	f
725	redragon fizz pro k616 rgb teclado wireless blanco	Redragon	Periferico	Teclado	Redragon FIZZ PRO K616 RGB Teclado Wireless Blanco	f
726	alcatroz x-craft xc3000 combo teclado + mouse	Varios	Periferico	Teclado	Alcatroz X-Craft XC3000 Combo Teclado + Mouse	f
727	armaggeddon mka-7c black teclado mecanico linear	Varios	Periferico	Teclado	Armaggeddon MKA-7C Black Teclado Mecánico Linear	f
728	genius scorpion km-gx6 teclado+mouse combo gamer	Varios	Periferico	Teclado	Genius Scorpion KM-GX6 Teclado+Mouse Combo Gamer	f
729	genius km-160 combo teclado + mouse usb	Varios	Periferico	Teclado	Genius KM-160 Combo Teclado + Mouse USB	f
730	thunderobot kg3089c teclado negro mecanico blue switch	Varios	Periferico	Teclado	Thunderobot KG3089C Teclado Negro Mecánico Blue Switch	f
731	redragon kumlun l p006 mousepad large speed	Redragon	Periferico	Mouse	Redragon Kumlun L P006 Mousepad Large Speed	f
732	redragon aatrox m811 rgb mmo mouse 15 botones	Redragon	Periferico	Mouse	Redragon Aatrox M811 Rgb MMO Mouse 15 Botones	f
733	razer deathadder v2 x hyperspeed mouse inalambrico	Razer	Periferico	Mouse	Razer DeathAdder V2 X HyperSpeed Mouse Inalámbrico	f
734	redragon pisces p016 mouse pad 33x26cm	Redragon	Periferico	Mouse	Redragon Pisces P016 Mouse Pad 33x26cm	f
735	redragon k1ng m916 ultra mouse 8k hz 30k dpi	Redragon	Periferico	Mouse	Redragon K1ng M916 Ultra Mouse 8K Hz 30K Dpi	f
736	combo gamer redragon mouse y mousepad m601wl-ba negro y rojo	Redragon	Periferico	Mouse	Combo gamer Redragon Mouse y MousePad M601WL-BA Negro y Rojo	f
737	logitech mx vertical mouse ergonomico vertical	Logitech	Periferico	Mouse	Logitech MX Vertical Mouse Ergonómico Vertical	f
738	machenike gm704 liuliya mousepad large	Varios	Periferico	Mouse	Machenike GM704 Liuliya MousePad Large	f
739	pirmus arena mousepad medium pmp-01m	Varios	Periferico	Mouse	Pirmus Arena Mousepad Medium PMP-01M	f
740	hyperx pulsefire core rgb mouse gamer	Hyperx	Periferico	Mouse	Hyperx Pulsefire Core RGB Mouse Gamer	f
741	cougar airblader tournament mouse gamer 20k dpi white	Varios	Periferico	Mouse	Cougar AirBlader Tournament Mouse Gamer 20k Dpi White	f
742	redragon hylas h260 rgb auriculares gamer	Redragon	Periferico	Headset	Redragon Hylas H260 RGB Auriculares Gamer	f
743	armaggeddon cosmic iii lite bk auriculares inalambrico	Varios	Periferico	Headset	Armaggeddon Cosmic III Lite BK Auriculares Inalámbrico	f
744	monitor msi g242l e14	Msi	Monitor	NaN	MONITOR MSI G242L E14	f
745	monitor asus tuf vg259qm5a	Asus	Monitor	NaN	MONITOR ASUS TUF VG259QM5A	f
746	mouse inalambrico corsair m75 white	Corsair	Periferico	Mouse	MOUSE INALAMBRICO CORSAIR M75 WHITE	f
747	teclado y mouse inalambrico logitech advanced mk540	Logitech	Periferico	Teclado	TECLADO Y MOUSE INALAMBRICO LOGITECH ADVANCED MK540	f
748	kit redragon s147 teclado +audifono +mouse +mousepad	Redragon	Periferico	Teclado	KIT REDRAGON S147 TECLADO +AUDIFONO +MOUSE +MOUSEPAD	f
749	teclado asus rog falchion ace hfx magnetic switch	Asus	Periferico	Teclado	TECLADO ASUS ROG FALCHION ACE HFX MAGNETIC SWITCH	f
750	teclado corsair galleon 100 sd mlx switch	Corsair	Periferico	Teclado	TECLADO CORSAIR GALLEON 100 SD MLX SWITCH	f
751	teclado corsair vanguard 96 mlx switch	Corsair	Periferico	Teclado	TECLADO CORSAIR VANGUARD 96 MLX SWITCH	f
752	teclado inalambrico corsair k70 core tkl mlx switch	Corsair	Periferico	Teclado	TECLADO INALAMBRICO CORSAIR K70 CORE TKL MLX SWITCH	f
753	teclado corsair k70 pro tkl mgx switch	Corsair	Periferico	Teclado	TECLADO CORSAIR K70 PRO TKL MGX SWITCH	f
754	teclado optico corsair k65 pro mini opx switch	Corsair	Periferico	Teclado	TECLADO OPTICO CORSAIR K65 PRO MINI OPX SWITCH	f
755	teclado inalambrico redragon flekact pro k708mc switch suluo	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON FLEKACT PRO K708MC SWITCH SULUO	f
756	teclado inalambrico redragon cyrus pro k681mg green switch rpc	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON CYRUS PRO K681MG GREEN SWITCH RPC	f
757	teclado inalambrico redragon veigar k643wgc switch red	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON VEIGAR K643WGC SWITCH RED	f
758	teclado redragon ironguard k722 black switch dragon chant	Redragon	Periferico	Teclado	TECLADO REDRAGON IRONGUARD K722 BLACK SWITCH DRAGON CHANT	f
759	teclado y mouse inalambrico meetion mini5000	Varios	Periferico	Teclado	TECLADO Y MOUSE INALAMBRICO MEETION MINI5000	f
760	teclado inalambrico meetion wk310 black	Varios	Periferico	Teclado	TECLADO INALAMBRICO MEETION WK310 BLACK	f
761	teclado inalambrico meetion wk330 black	Varios	Periferico	Teclado	TECLADO INALAMBRICO MEETION WK330 BLACK	f
762	mouse inalambrico razer viper v3 hyperspeed	Razer	Periferico	Mouse	MOUSE INALAMBRICO RAZER VIPER V3 HYPERSPEED	f
763	mouse inalambrico logitech g g502 x plus lightspeed	Logitech	Periferico	Mouse	MOUSE INALAMBRICO LOGITECH G G502 X PLUS LIGHTSPEED	f
764	mouse inalambrico logitech pro x superlight 2 se	Logitech	Periferico	Mouse	MOUSE INALAMBRICO LOGITECH PRO X SUPERLIGHT 2 SE	f
765	mouse inalambrico razer basilisk v3 pro 35k phantom green edition	Razer	Periferico	Mouse	MOUSE INALAMBRICO RAZER BASILISK V3 PRO 35K PHANTOM GREEN EDITION	f
766	mouse inalambrico razer cobra hyperspeed	Razer	Periferico	Mouse	MOUSE INALAMBRICO RAZER COBRA HYPERSPEED	f
767	mouse inalambrico logitech mx master 4	Logitech	Periferico	Mouse	MOUSE INALAMBRICO LOGITECH MX MASTER 4	f
768	mouse inalambrico corsair scimitar elite se carbon	Corsair	Periferico	Mouse	MOUSE INALAMBRICO CORSAIR SCIMITAR ELITE SE CARBON	f
769	teclado razer huntsman v3 x tenkeyless optical purple switch	Razer	Periferico	Teclado	TECLADO RAZER HUNTSMAN V3 X TENKEYLESS OPTICAL PURPLE SWITCH	f
770	teclado redradon castor magnetic k631	Varios	Periferico	Teclado	TECLADO REDRADON CASTOR MAGNETIC K631	f
771	monitor asus rog strix xg27aqdmes oled	Asus	Monitor	OLED	MONITOR ASUS ROG STRIX XG27AQDMES OLED	f
772	teclado inalambrico redragon terraflare pro k762wb white-black manbo switch	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON TERRAFLARE PRO K762WB WHITE-BLACK MANBO SWITCH	f
773	monitor asus zenscreen ms32uc google tv	Asus	Monitor	NaN	MONITOR ASUS ZENSCREEN MS32UC GOOGLE TV	f
774	monitor ultrawide lg 34u511a	Lg	Monitor	NaN	MONITOR ULTRAWIDE LG 34U511A	f
775	monitor asus proart pa248qfv	Asus	Monitor	NaN	MONITOR ASUS PROART PA248QFV	f
776	monitor asus proart pa278qgv	Asus	Monitor	NaN	MONITOR ASUS PROART PA278QGV	f
777	monitor gigabyte mo27q28g woled	Gigabyte	Monitor	OLED	MONITOR GIGABYTE MO27Q28G WOLED	f
778	monitor gigabyte m27q2 qd ice	Gigabyte	Monitor	NaN	MONITOR GIGABYTE M27Q2 QD ICE	f
779	monitor gigabyte gs25f2a	Gigabyte	Monitor	NaN	MONITOR GIGABYTE GS25F2A	f
780	soporte neumatico doble monitor klip xtreme kmm-410	Varios	Monitor	NaN	SOPORTE NEUMATICO DOBLE MONITOR KLIP XTREME KMM-410	f
781	monitor curvo teros te-3412g	Varios	Monitor	NaN	MONITOR CURVO TEROS TE-3412G	f
782	monitor portatil asus zenscreen mb169ck	Asus	Monitor	NaN	MONITOR PORTATIL ASUS ZENSCREEN MB169CK	f
783	monitor teros te-2786g	Varios	Monitor	NaN	MONITOR TEROS TE-2786G	f
784	monitor teros te-2714s	Varios	Monitor	NaN	MONITOR TEROS TE-2714S	f
785	monitor inteligente para bebe nexxt nhc-b100 2k	Varios	Monitor	NaN	MONITOR INTELIGENTE PARA BEBE NEXXT NHC-B100 2K	f
786	monitor gigabyte gs25f2	Gigabyte	Monitor	NaN	MONITOR GIGABYTE GS25F2	f
787	monitor asrock pg27fft1a	Varios	Monitor	NaN	MONITOR ASROCK PG27FFT1A	f
788	monitor asrock pg25fft	Varios	Monitor	NaN	MONITOR ASROCK PG25FFT	f
789	monitor curvo samsung odyssey g5 g55c	Samsung	Monitor	NaN	MONITOR CURVO SAMSUNG ODYSSEY G5 G55C	f
790	monitor asus proart pa279crv	Asus	Monitor	NaN	MONITOR ASUS PROART PA279CRV	f
791	teclado inalambrico multi plataforma logitech k780	Logitech	Periferico	Teclado	TECLADO INALAMBRICO MULTI PLATAFORMA LOGITECH K780	f
792	teclado logitech g pro x tkl rapid magnetic switch	Logitech	Periferico	Teclado	TECLADO LOGITECH G PRO X TKL RAPID MAGNETIC SWITCH	f
793	teclado inalambrico redragon behemoth pro k724 black rpc switch	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON BEHEMOTH PRO K724 BLACK RPC SWITCH	f
794	headset audifono logitech astro a20 inalambricos xbox one, green/black (939-001557)	Logitech	Periferico	Headset	Headset Audifono Logitech ASTRO A20 Inalambricos Xbox One, Green/Black (939-001557)	f
\.


--
-- Data for Name: dim_tiempo; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dim_tiempo (id_tiempo, fecha, semana_iso, mes, trimestre, anio, nombre_dia) FROM stdin;
20260101	2026-01-01	1	1	1	2026	Jueves
20260102	2026-01-02	1	1	1	2026	Viernes
20260103	2026-01-03	1	1	1	2026	Sabado
20260104	2026-01-04	1	1	1	2026	Domingo
20260105	2026-01-05	2	1	1	2026	Lunes
20260106	2026-01-06	2	1	1	2026	Martes
20260107	2026-01-07	2	1	1	2026	Miercoles
20260108	2026-01-08	2	1	1	2026	Jueves
20260109	2026-01-09	2	1	1	2026	Viernes
20260110	2026-01-10	2	1	1	2026	Sabado
20260111	2026-01-11	2	1	1	2026	Domingo
20260112	2026-01-12	3	1	1	2026	Lunes
20260113	2026-01-13	3	1	1	2026	Martes
20260114	2026-01-14	3	1	1	2026	Miercoles
20260115	2026-01-15	3	1	1	2026	Jueves
20260116	2026-01-16	3	1	1	2026	Viernes
20260117	2026-01-17	3	1	1	2026	Sabado
20260118	2026-01-18	3	1	1	2026	Domingo
20260119	2026-01-19	4	1	1	2026	Lunes
20260120	2026-01-20	4	1	1	2026	Martes
20260121	2026-01-21	4	1	1	2026	Miercoles
20260122	2026-01-22	4	1	1	2026	Jueves
20260123	2026-01-23	4	1	1	2026	Viernes
20260124	2026-01-24	4	1	1	2026	Sabado
20260125	2026-01-25	4	1	1	2026	Domingo
20260126	2026-01-26	5	1	1	2026	Lunes
20260127	2026-01-27	5	1	1	2026	Martes
20260128	2026-01-28	5	1	1	2026	Miercoles
20260129	2026-01-29	5	1	1	2026	Jueves
20260130	2026-01-30	5	1	1	2026	Viernes
20260131	2026-01-31	5	1	1	2026	Sabado
20260201	2026-02-01	5	2	1	2026	Domingo
20260202	2026-02-02	6	2	1	2026	Lunes
20260203	2026-02-03	6	2	1	2026	Martes
20260204	2026-02-04	6	2	1	2026	Miercoles
20260205	2026-02-05	6	2	1	2026	Jueves
20260206	2026-02-06	6	2	1	2026	Viernes
20260207	2026-02-07	6	2	1	2026	Sabado
20260208	2026-02-08	6	2	1	2026	Domingo
20260209	2026-02-09	7	2	1	2026	Lunes
20260210	2026-02-10	7	2	1	2026	Martes
20260211	2026-02-11	7	2	1	2026	Miercoles
20260212	2026-02-12	7	2	1	2026	Jueves
20260213	2026-02-13	7	2	1	2026	Viernes
20260214	2026-02-14	7	2	1	2026	Sabado
20260215	2026-02-15	7	2	1	2026	Domingo
20260216	2026-02-16	8	2	1	2026	Lunes
20260217	2026-02-17	8	2	1	2026	Martes
20260218	2026-02-18	8	2	1	2026	Miercoles
20260219	2026-02-19	8	2	1	2026	Jueves
20260220	2026-02-20	8	2	1	2026	Viernes
20260221	2026-02-21	8	2	1	2026	Sabado
20260222	2026-02-22	8	2	1	2026	Domingo
20260223	2026-02-23	9	2	1	2026	Lunes
20260224	2026-02-24	9	2	1	2026	Martes
20260225	2026-02-25	9	2	1	2026	Miercoles
20260226	2026-02-26	9	2	1	2026	Jueves
20260227	2026-02-27	9	2	1	2026	Viernes
20260228	2026-02-28	9	2	1	2026	Sabado
20260301	2026-03-01	9	3	1	2026	Domingo
20260302	2026-03-02	10	3	1	2026	Lunes
20260303	2026-03-03	10	3	1	2026	Martes
20260304	2026-03-04	10	3	1	2026	Miercoles
20260305	2026-03-05	10	3	1	2026	Jueves
20260306	2026-03-06	10	3	1	2026	Viernes
20260307	2026-03-07	10	3	1	2026	Sabado
20260308	2026-03-08	10	3	1	2026	Domingo
20260309	2026-03-09	11	3	1	2026	Lunes
20260310	2026-03-10	11	3	1	2026	Martes
20260311	2026-03-11	11	3	1	2026	Miercoles
20260312	2026-03-12	11	3	1	2026	Jueves
20260313	2026-03-13	11	3	1	2026	Viernes
20260314	2026-03-14	11	3	1	2026	Sabado
20260315	2026-03-15	11	3	1	2026	Domingo
20260316	2026-03-16	12	3	1	2026	Lunes
20260317	2026-03-17	12	3	1	2026	Martes
20260318	2026-03-18	12	3	1	2026	Miercoles
20260319	2026-03-19	12	3	1	2026	Jueves
20260320	2026-03-20	12	3	1	2026	Viernes
20260321	2026-03-21	12	3	1	2026	Sabado
20260322	2026-03-22	12	3	1	2026	Domingo
20260323	2026-03-23	13	3	1	2026	Lunes
20260324	2026-03-24	13	3	1	2026	Martes
20260325	2026-03-25	13	3	1	2026	Miercoles
20260326	2026-03-26	13	3	1	2026	Jueves
20260327	2026-03-27	13	3	1	2026	Viernes
20260328	2026-03-28	13	3	1	2026	Sabado
20260329	2026-03-29	13	3	1	2026	Domingo
20260330	2026-03-30	14	3	1	2026	Lunes
20260331	2026-03-31	14	3	1	2026	Martes
20260401	2026-04-01	14	4	2	2026	Miercoles
20260402	2026-04-02	14	4	2	2026	Jueves
20260403	2026-04-03	14	4	2	2026	Viernes
20260404	2026-04-04	14	4	2	2026	Sabado
20260405	2026-04-05	14	4	2	2026	Domingo
20260406	2026-04-06	15	4	2	2026	Lunes
20260407	2026-04-07	15	4	2	2026	Martes
20260408	2026-04-08	15	4	2	2026	Miercoles
20260409	2026-04-09	15	4	2	2026	Jueves
20260410	2026-04-10	15	4	2	2026	Viernes
20260411	2026-04-11	15	4	2	2026	Sabado
20260412	2026-04-12	15	4	2	2026	Domingo
20260413	2026-04-13	16	4	2	2026	Lunes
20260414	2026-04-14	16	4	2	2026	Martes
20260415	2026-04-15	16	4	2	2026	Miercoles
20260416	2026-04-16	16	4	2	2026	Jueves
20260417	2026-04-17	16	4	2	2026	Viernes
20260418	2026-04-18	16	4	2	2026	Sabado
20260419	2026-04-19	16	4	2	2026	Domingo
20260420	2026-04-20	17	4	2	2026	Lunes
20260421	2026-04-21	17	4	2	2026	Martes
20260422	2026-04-22	17	4	2	2026	Miercoles
20260423	2026-04-23	17	4	2	2026	Jueves
20260424	2026-04-24	17	4	2	2026	Viernes
20260425	2026-04-25	17	4	2	2026	Sabado
20260426	2026-04-26	17	4	2	2026	Domingo
20260427	2026-04-27	18	4	2	2026	Lunes
20260428	2026-04-28	18	4	2	2026	Martes
20260429	2026-04-29	18	4	2	2026	Miercoles
20260430	2026-04-30	18	4	2	2026	Jueves
20260501	2026-05-01	18	5	2	2026	Viernes
20260502	2026-05-02	18	5	2	2026	Sabado
20260503	2026-05-03	18	5	2	2026	Domingo
20260504	2026-05-04	19	5	2	2026	Lunes
20260505	2026-05-05	19	5	2	2026	Martes
20260506	2026-05-06	19	5	2	2026	Miercoles
20260507	2026-05-07	19	5	2	2026	Jueves
20260508	2026-05-08	19	5	2	2026	Viernes
20260509	2026-05-09	19	5	2	2026	Sabado
20260510	2026-05-10	19	5	2	2026	Domingo
20260511	2026-05-11	20	5	2	2026	Lunes
20260512	2026-05-12	20	5	2	2026	Martes
20260513	2026-05-13	20	5	2	2026	Miercoles
20260514	2026-05-14	20	5	2	2026	Jueves
20260515	2026-05-15	20	5	2	2026	Viernes
20260516	2026-05-16	20	5	2	2026	Sabado
20260517	2026-05-17	20	5	2	2026	Domingo
20260518	2026-05-18	21	5	2	2026	Lunes
20260519	2026-05-19	21	5	2	2026	Martes
20260520	2026-05-20	21	5	2	2026	Miercoles
20260521	2026-05-21	21	5	2	2026	Jueves
20260522	2026-05-22	21	5	2	2026	Viernes
20260523	2026-05-23	21	5	2	2026	Sabado
20260524	2026-05-24	21	5	2	2026	Domingo
20260525	2026-05-25	22	5	2	2026	Lunes
20260526	2026-05-26	22	5	2	2026	Martes
20260527	2026-05-27	22	5	2	2026	Miercoles
20260528	2026-05-28	22	5	2	2026	Jueves
20260529	2026-05-29	22	5	2	2026	Viernes
20260530	2026-05-30	22	5	2	2026	Sabado
20260531	2026-05-31	22	5	2	2026	Domingo
20260601	2026-06-01	23	6	2	2026	Lunes
20260602	2026-06-02	23	6	2	2026	Martes
20260603	2026-06-03	23	6	2	2026	Miercoles
20260604	2026-06-04	23	6	2	2026	Jueves
20260605	2026-06-05	23	6	2	2026	Viernes
20260606	2026-06-06	23	6	2	2026	Sabado
20260607	2026-06-07	23	6	2	2026	Domingo
20260608	2026-06-08	24	6	2	2026	Lunes
20260609	2026-06-09	24	6	2	2026	Martes
20260610	2026-06-10	24	6	2	2026	Miercoles
20260611	2026-06-11	24	6	2	2026	Jueves
20260612	2026-06-12	24	6	2	2026	Viernes
20260613	2026-06-13	24	6	2	2026	Sabado
20260614	2026-06-14	24	6	2	2026	Domingo
20260615	2026-06-15	25	6	2	2026	Lunes
20260616	2026-06-16	25	6	2	2026	Martes
20260617	2026-06-17	25	6	2	2026	Miercoles
20260618	2026-06-18	25	6	2	2026	Jueves
20260619	2026-06-19	25	6	2	2026	Viernes
20260620	2026-06-20	25	6	2	2026	Sabado
20260621	2026-06-21	25	6	2	2026	Domingo
20260622	2026-06-22	26	6	2	2026	Lunes
20260623	2026-06-23	26	6	2	2026	Martes
20260624	2026-06-24	26	6	2	2026	Miercoles
20260625	2026-06-25	26	6	2	2026	Jueves
20260626	2026-06-26	26	6	2	2026	Viernes
20260627	2026-06-27	26	6	2	2026	Sabado
20260628	2026-06-28	26	6	2	2026	Domingo
20260629	2026-06-29	27	6	2	2026	Lunes
20260630	2026-06-30	27	6	2	2026	Martes
20260701	2026-07-01	27	7	3	2026	Miercoles
20260702	2026-07-02	27	7	3	2026	Jueves
20260703	2026-07-03	27	7	3	2026	Viernes
20260704	2026-07-04	27	7	3	2026	Sabado
20260705	2026-07-05	27	7	3	2026	Domingo
20260706	2026-07-06	28	7	3	2026	Lunes
20260707	2026-07-07	28	7	3	2026	Martes
20260708	2026-07-08	28	7	3	2026	Miercoles
20260709	2026-07-09	28	7	3	2026	Jueves
20260710	2026-07-10	28	7	3	2026	Viernes
20260711	2026-07-11	28	7	3	2026	Sabado
20260712	2026-07-12	28	7	3	2026	Domingo
20260713	2026-07-13	29	7	3	2026	Lunes
20260714	2026-07-14	29	7	3	2026	Martes
20260715	2026-07-15	29	7	3	2026	Miercoles
20260716	2026-07-16	29	7	3	2026	Jueves
20260717	2026-07-17	29	7	3	2026	Viernes
20260718	2026-07-18	29	7	3	2026	Sabado
20260719	2026-07-19	29	7	3	2026	Domingo
20260720	2026-07-20	30	7	3	2026	Lunes
20260721	2026-07-21	30	7	3	2026	Martes
20260722	2026-07-22	30	7	3	2026	Miercoles
20260723	2026-07-23	30	7	3	2026	Jueves
20260724	2026-07-24	30	7	3	2026	Viernes
20260725	2026-07-25	30	7	3	2026	Sabado
20260726	2026-07-26	30	7	3	2026	Domingo
20260727	2026-07-27	31	7	3	2026	Lunes
20260728	2026-07-28	31	7	3	2026	Martes
20260729	2026-07-29	31	7	3	2026	Miercoles
20260730	2026-07-30	31	7	3	2026	Jueves
20260731	2026-07-31	31	7	3	2026	Viernes
20260801	2026-08-01	31	8	3	2026	Sabado
20260802	2026-08-02	31	8	3	2026	Domingo
20260803	2026-08-03	32	8	3	2026	Lunes
20260804	2026-08-04	32	8	3	2026	Martes
20260805	2026-08-05	32	8	3	2026	Miercoles
20260806	2026-08-06	32	8	3	2026	Jueves
20260807	2026-08-07	32	8	3	2026	Viernes
20260808	2026-08-08	32	8	3	2026	Sabado
20260809	2026-08-09	32	8	3	2026	Domingo
20260810	2026-08-10	33	8	3	2026	Lunes
20260811	2026-08-11	33	8	3	2026	Martes
20260812	2026-08-12	33	8	3	2026	Miercoles
20260813	2026-08-13	33	8	3	2026	Jueves
20260814	2026-08-14	33	8	3	2026	Viernes
20260815	2026-08-15	33	8	3	2026	Sabado
20260816	2026-08-16	33	8	3	2026	Domingo
20260817	2026-08-17	34	8	3	2026	Lunes
20260818	2026-08-18	34	8	3	2026	Martes
20260819	2026-08-19	34	8	3	2026	Miercoles
20260820	2026-08-20	34	8	3	2026	Jueves
20260821	2026-08-21	34	8	3	2026	Viernes
20260822	2026-08-22	34	8	3	2026	Sabado
20260823	2026-08-23	34	8	3	2026	Domingo
20260824	2026-08-24	35	8	3	2026	Lunes
20260825	2026-08-25	35	8	3	2026	Martes
20260826	2026-08-26	35	8	3	2026	Miercoles
20260827	2026-08-27	35	8	3	2026	Jueves
20260828	2026-08-28	35	8	3	2026	Viernes
20260829	2026-08-29	35	8	3	2026	Sabado
20260830	2026-08-30	35	8	3	2026	Domingo
20260831	2026-08-31	36	8	3	2026	Lunes
20260901	2026-09-01	36	9	3	2026	Martes
20260902	2026-09-02	36	9	3	2026	Miercoles
20260903	2026-09-03	36	9	3	2026	Jueves
20260904	2026-09-04	36	9	3	2026	Viernes
20260905	2026-09-05	36	9	3	2026	Sabado
20260906	2026-09-06	36	9	3	2026	Domingo
20260907	2026-09-07	37	9	3	2026	Lunes
20260908	2026-09-08	37	9	3	2026	Martes
20260909	2026-09-09	37	9	3	2026	Miercoles
20260910	2026-09-10	37	9	3	2026	Jueves
20260911	2026-09-11	37	9	3	2026	Viernes
20260912	2026-09-12	37	9	3	2026	Sabado
20260913	2026-09-13	37	9	3	2026	Domingo
20260914	2026-09-14	38	9	3	2026	Lunes
20260915	2026-09-15	38	9	3	2026	Martes
20260916	2026-09-16	38	9	3	2026	Miercoles
20260917	2026-09-17	38	9	3	2026	Jueves
20260918	2026-09-18	38	9	3	2026	Viernes
20260919	2026-09-19	38	9	3	2026	Sabado
20260920	2026-09-20	38	9	3	2026	Domingo
20260921	2026-09-21	39	9	3	2026	Lunes
20260922	2026-09-22	39	9	3	2026	Martes
20260923	2026-09-23	39	9	3	2026	Miercoles
20260924	2026-09-24	39	9	3	2026	Jueves
20260925	2026-09-25	39	9	3	2026	Viernes
20260926	2026-09-26	39	9	3	2026	Sabado
20260927	2026-09-27	39	9	3	2026	Domingo
20260928	2026-09-28	40	9	3	2026	Lunes
20260929	2026-09-29	40	9	3	2026	Martes
20260930	2026-09-30	40	9	3	2026	Miercoles
20261001	2026-10-01	40	10	4	2026	Jueves
20261002	2026-10-02	40	10	4	2026	Viernes
20261003	2026-10-03	40	10	4	2026	Sabado
20261004	2026-10-04	40	10	4	2026	Domingo
20261005	2026-10-05	41	10	4	2026	Lunes
20261006	2026-10-06	41	10	4	2026	Martes
20261007	2026-10-07	41	10	4	2026	Miercoles
20261008	2026-10-08	41	10	4	2026	Jueves
20261009	2026-10-09	41	10	4	2026	Viernes
20261010	2026-10-10	41	10	4	2026	Sabado
20261011	2026-10-11	41	10	4	2026	Domingo
20261012	2026-10-12	42	10	4	2026	Lunes
20261013	2026-10-13	42	10	4	2026	Martes
20261014	2026-10-14	42	10	4	2026	Miercoles
20261015	2026-10-15	42	10	4	2026	Jueves
20261016	2026-10-16	42	10	4	2026	Viernes
20261017	2026-10-17	42	10	4	2026	Sabado
20261018	2026-10-18	42	10	4	2026	Domingo
20261019	2026-10-19	43	10	4	2026	Lunes
20261020	2026-10-20	43	10	4	2026	Martes
20261021	2026-10-21	43	10	4	2026	Miercoles
20261022	2026-10-22	43	10	4	2026	Jueves
20261023	2026-10-23	43	10	4	2026	Viernes
20261024	2026-10-24	43	10	4	2026	Sabado
20261025	2026-10-25	43	10	4	2026	Domingo
20261026	2026-10-26	44	10	4	2026	Lunes
20261027	2026-10-27	44	10	4	2026	Martes
20261028	2026-10-28	44	10	4	2026	Miercoles
20261029	2026-10-29	44	10	4	2026	Jueves
20261030	2026-10-30	44	10	4	2026	Viernes
20261031	2026-10-31	44	10	4	2026	Sabado
20261101	2026-11-01	44	11	4	2026	Domingo
20261102	2026-11-02	45	11	4	2026	Lunes
20261103	2026-11-03	45	11	4	2026	Martes
20261104	2026-11-04	45	11	4	2026	Miercoles
20261105	2026-11-05	45	11	4	2026	Jueves
20261106	2026-11-06	45	11	4	2026	Viernes
20261107	2026-11-07	45	11	4	2026	Sabado
20261108	2026-11-08	45	11	4	2026	Domingo
20261109	2026-11-09	46	11	4	2026	Lunes
20261110	2026-11-10	46	11	4	2026	Martes
20261111	2026-11-11	46	11	4	2026	Miercoles
20261112	2026-11-12	46	11	4	2026	Jueves
20261113	2026-11-13	46	11	4	2026	Viernes
20261114	2026-11-14	46	11	4	2026	Sabado
20261115	2026-11-15	46	11	4	2026	Domingo
20261116	2026-11-16	47	11	4	2026	Lunes
20261117	2026-11-17	47	11	4	2026	Martes
20261118	2026-11-18	47	11	4	2026	Miercoles
20261119	2026-11-19	47	11	4	2026	Jueves
20261120	2026-11-20	47	11	4	2026	Viernes
20261121	2026-11-21	47	11	4	2026	Sabado
20261122	2026-11-22	47	11	4	2026	Domingo
20261123	2026-11-23	48	11	4	2026	Lunes
20261124	2026-11-24	48	11	4	2026	Martes
20261125	2026-11-25	48	11	4	2026	Miercoles
20261126	2026-11-26	48	11	4	2026	Jueves
20261127	2026-11-27	48	11	4	2026	Viernes
20261128	2026-11-28	48	11	4	2026	Sabado
20261129	2026-11-29	48	11	4	2026	Domingo
20261130	2026-11-30	49	11	4	2026	Lunes
20261201	2026-12-01	49	12	4	2026	Martes
20261202	2026-12-02	49	12	4	2026	Miercoles
20261203	2026-12-03	49	12	4	2026	Jueves
20261204	2026-12-04	49	12	4	2026	Viernes
20261205	2026-12-05	49	12	4	2026	Sabado
20261206	2026-12-06	49	12	4	2026	Domingo
20261207	2026-12-07	50	12	4	2026	Lunes
20261208	2026-12-08	50	12	4	2026	Martes
20261209	2026-12-09	50	12	4	2026	Miercoles
20261210	2026-12-10	50	12	4	2026	Jueves
20261211	2026-12-11	50	12	4	2026	Viernes
20261212	2026-12-12	50	12	4	2026	Sabado
20261213	2026-12-13	50	12	4	2026	Domingo
20261214	2026-12-14	51	12	4	2026	Lunes
20261215	2026-12-15	51	12	4	2026	Martes
20261216	2026-12-16	51	12	4	2026	Miercoles
20261217	2026-12-17	51	12	4	2026	Jueves
20261218	2026-12-18	51	12	4	2026	Viernes
20261219	2026-12-19	51	12	4	2026	Sabado
20261220	2026-12-20	51	12	4	2026	Domingo
20261221	2026-12-21	52	12	4	2026	Lunes
20261222	2026-12-22	52	12	4	2026	Martes
20261223	2026-12-23	52	12	4	2026	Miercoles
20261224	2026-12-24	52	12	4	2026	Jueves
20261225	2026-12-25	52	12	4	2026	Viernes
20261226	2026-12-26	52	12	4	2026	Sabado
20261227	2026-12-27	52	12	4	2026	Domingo
20261228	2026-12-28	53	12	4	2026	Lunes
20261229	2026-12-29	53	12	4	2026	Martes
20261230	2026-12-30	53	12	4	2026	Miercoles
20261231	2026-12-31	53	12	4	2026	Jueves
\.


--
-- Data for Name: dim_tienda; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dim_tienda (id_tienda, nombre_tienda, pais, moneda_nativa, tipo_tienda, url_base) FROM stdin;
1	CompuGamer	Ecuador	USD	Tienda especializada	https://compugamer.com.ec
2	Computron	Ecuador	USD	Tienda especializada	https://www.computron.com.ec
3	MTEC	Ecuador	USD	Tienda especializada	https://mtec-ec.com
4	NomadaWare	Ecuador	USD	Tienda especializada	https://nomadaware.com.ec
5	TecnoGame	Ecuador	USD	Tienda especializada	https://tecnogame.ec
6	Tecnosmart	Ecuador	USD	Tienda especializada	https://www.tecnosmart.com.ec
\.


--
-- Data for Name: fact_precios; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.fact_precios (id_hecho, id_producto, id_tienda, id_tiempo, id_fuente, precio_original, moneda_original, tasa_cambio_usd, precio_usd, stock_disponible, fecha_extraccion, url_producto) FROM stdin;
1	1	1	20260630	1	425.0000	USD	1.000000	425.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/ulltra7265/
2	103	1	20260630	1	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/procesador-amd-ryzen-5-5600gt-con-amd-radeon-graphics-socket-am4-4-60ghz-6-nucleos-16mb-cache-incluye-disipador/
3	49	1	20260630	1	315.0000	USD	1.000000	315.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/procesador-amd-ryzen-7-8700g-con-amd-radeon-graphics-socket-am5-5-10ghz-8-nucleos-24mb-cache-incluye-disipador/
4	55	1	20260630	1	325.0000	USD	1.000000	325.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/procesador-amd-ryzen-7-8700f-socket-am5-5ghz-8-nucleos-16mb-cache-incluye-disipador/
5	91	1	20260630	1	245.0000	USD	1.000000	245.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/procesador-intel-core-i5-14400-con-intel-uhd-graphics-730-lga-1700-4-70ghz-10-nucleos-20mb-cache-incluye-disipador-14va-generacion-raptor-lake/
6	50	1	20260630	1	179.0000	USD	1.000000	179.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/procesador-amd-ryzen-5-8500g-con-amd-radeon-graphics-socket-am5-5ghz-6-nucleos-16mb-cache-incluye-disipador/
7	34	1	20260630	1	950.0000	USD	1.000000	950.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/ultra9285k/
8	86	1	20260630	1	575.0000	USD	1.000000	575.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/ultra7265k/
9	105	1	20260630	1	435.0000	USD	1.000000	435.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/ultra5245/
10	530	1	20260630	1	900.0000	USD	1.000000	900.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/tarjeta-de-video-gigabyte-amd-radeon-rx-9070-gaming-oc-16gb-256-bit-gddr6-pci-express-5-0/
11	531	1	20260630	1	190.0000	USD	1.000000	190.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/mainbaord-asus-prime-b860m-a-socket-1851-intel/
12	155	1	20260630	1	1590.0000	USD	1.000000	1590.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/rtx5070ti16gbgigabyte/
13	108	1	20260630	1	900.0000	USD	1.000000	900.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/tarjeta-de-video-gigabyte-amd-radeon-rx-9070-gaming-oc-16gb-256-bit-gddr6-pci-express-5-0/
14	148	1	20260630	1	395.0000	USD	1.000000	395.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/tarjeta-de-video-asus-nvidia-geforce-rtx-5050-oc-edition-8gb-128-bit-gddr6-pci-express-5-0/
15	16	1	20260630	1	480.0000	USD	1.000000	480.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/dual50608gb/
16	532	1	20260630	1	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/memoria-ram-kingston-16gb-ddr5-5600mhz-dimm-cl46-kcp556us8-16-kvr56u46bs8-16/
17	533	1	20260630	1	290.0000	USD	1.000000	290.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/32gbddr5cudimm/
18	534	1	20260630	1	189.0000	USD	1.000000	189.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/memoria-ram-mushkin-ddr4-3200mhz-16gb-pc16gbddr4-memoriaram16gbddr4/
19	535	1	20260630	1	195.0000	USD	1.000000	195.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor-gamer-lg-ultragear-g4-lcd-23-8-1920x1080-full-hd-g-sync-freesync-144hz-hdmi-displayport-negro-modelo-24g411a-b/
20	536	1	20260630	1	110.0000	USD	1.000000	110.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor-teros-te-1914s-19-5-1600x900-5ms-220-nits-hdmi-vga-parlantes/
21	537	1	20260630	1	490.0000	USD	1.000000	490.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor-gamer-curvo-gigabyte-gs34wqca-lcd-34-3440x1440-ultra-wide-quad-hd-freesync-120hz-hdmi-displayport-negro/
22	538	1	20260630	1	280.0000	USD	1.000000	280.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/gs27fa/
23	539	1	20260630	1	380.0000	USD	1.000000	380.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor-indurama-32-vortix-ultra-va-fhd-1080p/
24	540	1	20260630	1	179.0000	USD	1.000000	179.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor-indurama-27-vortix-nova-ips-fhd-1080p-120hz/
25	541	1	20260630	1	99.0000	USD	1.000000	99.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor20u401a/
26	542	1	20260630	1	159.0000	USD	1.000000	159.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/w2427sg/
27	543	1	20260630	1	800.0000	USD	1.000000	800.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/cpur535006gb/
28	544	1	20260630	1	750.0000	USD	1.000000	750.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/cpu5600g30506gb/
29	545	1	20260630	1	900.0000	USD	1.000000	900.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/r5306012gb/
30	546	1	20260630	1	990.0000	USD	1.000000	990.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/retro-glass-jug-330-ml/
31	547	1	20260630	1	39.0000	USD	1.000000	39.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/teclado-primus-gaming-ballista61t-abs-61-teclas-retroiluminado-switch-red-lineal-es-white-pks-060w-s/
32	548	1	20260630	1	8.0000	USD	1.000000	8.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/qk-440c/
33	549	1	20260630	1	49.0000	USD	1.000000	49.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/case-quasad-generico-c3156-teclado-mouse-parlantes/
34	550	1	20260630	1	25.0000	USD	1.000000	25.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/cm-370/
35	529	1	20260630	1	89.0000	USD	1.000000	89.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/k70core/
36	527	1	20260630	1	325.0000	USD	1.000000	325.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/upgrade-kit-mouse-logitech-g-pro-wireless-teclado-pro-x-60-tkl-wireless/
37	506	1	20260630	1	9.0000	USD	1.000000	9.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/qm-850/
38	526	1	20260630	1	129.0000	USD	1.000000	129.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/logitechgpro/
39	507	1	20260630	1	5.0000	USD	1.000000	5.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/dx-110/
40	50	2	20260630	2	248.9900	USD	1.000000	248.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
41	103	2	20260630	2	229.9900	USD	1.000000	229.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
42	508	2	20260630	2	951.9900	USD	1.000000	951.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/servidores/componentes-servidores/
43	509	2	20260630	2	1762.9900	USD	1.000000	1762.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/servidores/componentes-servidores/
44	510	2	20260630	2	55.9900	USD	1.000000	55.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/servidores/componentes-servidores/
45	511	2	20260630	2	125.9900	USD	1.000000	125.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/servidores/componentes-servidores/
46	448	2	20260630	2	879.9900	USD	1.000000	879.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
47	449	2	20260630	2	869.9900	USD	1.000000	869.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
48	512	2	20260630	2	2429.9900	USD	1.000000	2429.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
49	513	2	20260630	2	1279.9900	USD	1.000000	1279.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
50	147	2	20260630	2	899.9900	USD	1.000000	899.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
51	514	2	20260630	2	5299.9900	USD	1.000000	5299.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
52	515	2	20260630	2	519.9900	USD	1.000000	519.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
53	516	2	20260630	2	1289.9900	USD	1.000000	1289.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
54	517	2	20260630	2	1339.9900	USD	1.000000	1339.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
55	143	2	20260630	2	1149.9900	USD	1.000000	1149.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/corporativo/
56	518	2	20260630	2	299.9900	USD	1.000000	299.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
57	519	2	20260630	2	14.9900	USD	1.000000	14.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/redes/adaptadores/
58	520	2	20260630	2	159.9900	USD	1.000000	159.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/celulares-y-tablets/celulares/
59	521	2	20260630	2	224.9900	USD	1.000000	224.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/celulares-y-tablets/
60	522	2	20260630	2	419.9900	USD	1.000000	419.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/televisores/
61	523	2	20260630	2	689.9900	USD	1.000000	689.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/televisores/
62	524	2	20260630	2	309.9900	USD	1.000000	309.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/televisores/
63	525	2	20260630	2	509.9900	USD	1.000000	509.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/televisores/
64	551	2	20260630	2	259.9900	USD	1.000000	259.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
65	528	2	20260630	2	319.9900	USD	1.000000	319.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/televisores/
66	552	2	20260630	2	674.9900	USD	1.000000	674.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/televisores/
67	578	2	20260630	2	499.9900	USD	1.000000	499.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/televisores/
68	580	2	20260630	2	274.9900	USD	1.000000	274.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/almacenamiento/
69	581	2	20260630	2	329.9900	USD	1.000000	329.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
70	582	2	20260630	2	124.9900	USD	1.000000	124.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
71	583	2	20260630	2	258.9900	USD	1.000000	258.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
72	584	2	20260630	2	169.9900	USD	1.000000	169.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
73	585	2	20260630	2	319.9900	USD	1.000000	319.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
74	586	2	20260630	2	139.9900	USD	1.000000	139.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
75	587	2	20260630	2	1149.9900	USD	1.000000	1149.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
76	588	2	20260630	2	369.9900	USD	1.000000	369.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/servidores/componentes-servidores/
77	589	2	20260630	2	899.9900	USD	1.000000	899.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
78	590	2	20260630	2	56.9900	USD	1.000000	56.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/smart-home/
79	591	2	20260630	2	89.9900	USD	1.000000	89.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
80	592	2	20260630	2	159.9900	USD	1.000000	159.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
81	593	2	20260630	2	58.9900	USD	1.000000	58.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
82	594	2	20260630	2	16.9900	USD	1.000000	16.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/accesorios-tv-y-video/
83	595	2	20260630	2	25.9900	USD	1.000000	25.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/accesorios-tv-y-video/
84	596	2	20260630	2	12.9900	USD	1.000000	12.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/accesorios-tv-y-video/
85	597	2	20260630	2	9.9900	USD	1.000000	9.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/accesorios-tv-y-video/
86	598	2	20260630	2	174.9900	USD	1.000000	174.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
87	599	2	20260630	2	197.9900	USD	1.000000	197.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
88	600	2	20260630	2	499.9900	USD	1.000000	499.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
89	579	2	20260630	2	138.9900	USD	1.000000	138.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
90	577	2	20260630	2	229.9900	USD	1.000000	229.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
91	554	2	20260630	2	439.9900	USD	1.000000	439.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
92	576	2	20260630	2	279.9900	USD	1.000000	279.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
93	555	2	20260630	2	6.9900	USD	1.000000	6.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/accesorios-tv-y-video/
94	556	2	20260630	2	23.9900	USD	1.000000	23.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
95	557	2	20260630	2	8.9900	USD	1.000000	8.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/tv-y-video/accesorios-tv-y-video/
96	558	2	20260630	2	99.9900	USD	1.000000	99.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
97	559	2	20260630	2	459.9900	USD	1.000000	459.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/celulares-y-tablets/
98	560	2	20260630	2	1099.9900	USD	1.000000	1099.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/celulares-y-tablets/
99	561	2	20260630	2	102.9900	USD	1.000000	102.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
100	562	2	20260630	2	598.9900	USD	1.000000	598.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/celulares-y-tablets/
101	563	2	20260630	2	32.9900	USD	1.000000	32.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
102	564	2	20260630	2	8.9900	USD	1.000000	8.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
103	565	2	20260630	2	649.9900	USD	1.000000	649.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/celulares-y-tablets/
104	566	2	20260630	2	39.9900	USD	1.000000	39.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
105	567	2	20260630	2	759.9900	USD	1.000000	759.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/celulares-y-tablets/
106	568	2	20260630	2	59.8000	USD	1.000000	59.8000	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
107	569	2	20260630	2	60.0000	USD	1.000000	60.0000	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
108	570	2	20260630	2	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
109	571	2	20260630	2	19.9900	USD	1.000000	19.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
110	572	2	20260630	2	7.9900	USD	1.000000	7.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
111	573	2	20260630	2	119.9900	USD	1.000000	119.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
112	574	2	20260630	2	49.9900	USD	1.000000	49.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
113	575	2	20260630	2	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
114	553	2	20260630	2	18.9900	USD	1.000000	18.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
115	505	2	20260630	2	26.9900	USD	1.000000	26.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
116	504	2	20260630	2	20.9900	USD	1.000000	20.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
117	503	2	20260630	2	35.9900	USD	1.000000	35.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
118	434	2	20260630	2	33.9900	USD	1.000000	33.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
119	435	2	20260630	2	28.9900	USD	1.000000	28.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
120	436	2	20260630	2	27.9900	USD	1.000000	27.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
121	437	2	20260630	2	6.9900	USD	1.000000	6.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
122	438	2	20260630	2	45.9900	USD	1.000000	45.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
123	439	2	20260630	2	16.9900	USD	1.000000	16.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
124	440	2	20260630	2	25.9900	USD	1.000000	25.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
125	441	2	20260630	2	31.9900	USD	1.000000	31.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
126	442	2	20260630	2	80.9900	USD	1.000000	80.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/cases/
127	443	2	20260630	2	17.9900	USD	1.000000	17.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
128	444	2	20260630	2	21.9900	USD	1.000000	21.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
129	445	2	20260630	2	259.9900	USD	1.000000	259.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
130	446	2	20260630	2	9.9900	USD	1.000000	9.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
131	447	2	20260630	2	1249.9900	USD	1.000000	1249.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
132	448	2	20260630	2	879.9900	USD	1.000000	879.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
133	449	2	20260630	2	869.9900	USD	1.000000	869.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
134	450	2	20260630	2	1199.9900	USD	1.000000	1199.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
135	451	2	20260630	2	1149.9900	USD	1.000000	1149.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/corporativo/
136	452	2	20260630	2	5.9900	USD	1.000000	5.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
137	453	2	20260630	2	2.9900	USD	1.000000	2.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
138	454	2	20260630	2	12.9900	USD	1.000000	12.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
139	433	2	20260630	2	79.9900	USD	1.000000	79.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
140	432	2	20260630	2	1559.9900	USD	1.000000	1559.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/corporativo/
141	431	2	20260630	2	14.9800	USD	1.000000	14.9800	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
142	430	2	20260630	2	4.4900	USD	1.000000	4.4900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
143	408	2	20260630	2	1798.9900	USD	1.000000	1798.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/corporativo/
144	409	2	20260630	2	37.9900	USD	1.000000	37.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
145	410	2	20260630	2	54.9900	USD	1.000000	54.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
146	411	2	20260630	2	3.4900	USD	1.000000	3.4900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
147	412	2	20260630	2	3.9900	USD	1.000000	3.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
148	413	2	20260630	2	6.4900	USD	1.000000	6.4900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
149	414	2	20260630	2	0.9900	USD	1.000000	0.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
150	415	2	20260630	2	13.0000	USD	1.000000	13.0000	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
151	416	2	20260630	2	10.9900	USD	1.000000	10.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
152	417	2	20260630	2	11.9900	USD	1.000000	11.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
153	407	2	20260630	2	8.0000	USD	1.000000	8.0000	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
154	418	2	20260630	2	699.9900	USD	1.000000	699.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
155	420	2	20260630	2	13.9900	USD	1.000000	13.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
156	421	2	20260630	2	15.9900	USD	1.000000	15.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
157	422	2	20260630	2	65.9900	USD	1.000000	65.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
158	423	2	20260630	2	4.9900	USD	1.000000	4.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/audio/audifonos/
159	424	2	20260630	2	89.9900	USD	1.000000	89.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
160	54	3	20260630	3	220.0000	USD	1.000000	220.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/intel-core-ultra-5-225f-procesador-10-nuc-hasta-4-9ghz-copia/
161	42	3	20260630	3	540.0000	USD	1.000000	540.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-9-9900x-procesador-4-4ghz-12-nucleos-24-hilos/
162	34	3	20260630	3	835.0000	USD	1.000000	835.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/intel-core-ultra-9-285k-procesador-24-nucleos-24-3-2-5-7ghz/
163	55	3	20260630	3	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-7-8700f-procesador-8-nuc-16h-4-1-5-ghz/
164	35	3	20260630	3	430.0000	USD	1.000000	430.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-7-9700x-3-8-5-5ghz-8-nucleos-16-hilos/
165	49	3	20260630	3	350.0000	USD	1.000000	350.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-7-8700g-procesador-8-nucleos-16-hilos-4-2ghz-5-1ghz/
166	1	3	20260630	3	470.0000	USD	1.000000	470.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/intel-core-ultra-7-265-procesador-20-nucleos-hasta-5-3ghz/
167	48	3	20260630	3	245.0000	USD	1.000000	245.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-5-8600g-procesador-6-nucleos-12-hilos-4-3ghz-5-0ghz/
168	50	3	20260630	3	194.0000	USD	1.000000	194.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-5-8500g-procesador-3-5ghz-6-nucleos-12-hilos-am5/
169	425	3	20260630	3	1320.0000	USD	1.000000	1320.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/hp-victus-amd-ryzen-7-7445hs-rtx-4050-16gb/
170	426	3	20260630	3	1065.0000	USD	1.000000	1065.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-thin-15-b13ve-intel-i5-13420h-rtx-4050-16gb/
171	427	3	20260630	3	70.0000	USD	1.000000	70.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gamdias-aura-gc12-case-gamer-6-fans-argb/
172	428	3	20260630	3	60.0000	USD	1.000000	60.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gamdias-kratos-m1-600b-fuente-de-poder-600w-80-bronze/
173	429	3	20260630	3	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gamdias-atlas-m3m-case-gamer-vidrio-templado-3-fans/
174	455	3	20260630	3	1185.0000	USD	1.000000	1185.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/lenovo-loq-15arp10e-amd-r7-7735hs-16gb-512b-rtx-4050-15-6/
175	100	3	20260630	3	2998.0000	USD	1.000000	2998.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-rainbow-beast-frozen-ryzen-7-9800x3d-32gb-2tb-rtx-5070/
176	456	3	20260630	3	1070.0000	USD	1.000000	1070.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-v16-core-5-120h-rtx-4050-6gb-16gb-ram/
177	457	3	20260630	3	175.0000	USD	1.000000	175.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-prime-b850m-a-wifi-ddr5-matx-amd/
178	482	3	20260630	3	100.0000	USD	1.000000	100.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-b550m-a-pro-motherboard-amd-am4-ddr4/
179	51	3	20260630	3	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-5-9600x-3-9-5-4ghz-6-nucleos-12-hilos/
180	150	3	20260630	3	440.0000	USD	1.000000	440.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-7-7700x-4-5ghz-am5-8-nucleos-16-hilos/
181	484	3	20260630	3	380.0000	USD	1.000000	380.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-tuf-gaming-x870-plus-wifi-amd-am5-mainboard/
182	485	3	20260630	3	110.0000	USD	1.000000	110.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-prime-h810m-e-lga1851-ddr5-intel/
183	486	3	20260630	3	135.0000	USD	1.000000	135.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-prime-b760m-a-ddr5-mainboard-intel-lga1700-matx/
184	487	3	20260630	3	280.0000	USD	1.000000	280.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-tuf-gaming-b850m-plus-wifi-am5-amd-ddr5-mainboard/
185	488	3	20260630	3	400.0000	USD	1.000000	400.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-tuf-z890-plus-wifi-intel-core-ultra/
186	151	3	20260630	3	999.0000	USD	1.000000	999.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-vivobook-s16-m3607ha-ryzen-9-270-16gb-1tb-16-cool-silver/
187	489	3	20260630	3	140.0000	USD	1.000000	140.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-pro-h810m-b-mainboard-ddr5-intel-lga1851/
188	490	3	20260630	3	170.0000	USD	1.000000	170.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-prime-b860m-a-motherboard-lga1851-intel/
189	491	3	20260630	3	1960.0000	USD	1.000000	1960.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-rainbow-lite-ryzen-7-16gb-1tb-rtx-5060-ti/
190	492	3	20260630	3	2215.0000	USD	1.000000	2215.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-digital-beast-ryzen-7-16gb-1tb-rtx-5070/
191	152	3	20260630	3	1430.0000	USD	1.000000	1430.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-flexi-lite-core-ultra-5-500gb-16gb-rtx-5050/
192	152	3	20260630	3	1575.0000	USD	1.000000	1575.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-air-curve-core-ultra-5-500gb-16gb-rtx-5060/
193	99	3	20260630	3	390.0000	USD	1.000000	390.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-7-7700-3-8ghz-8-nucleos-16-hilos-procesador-am5/
194	140	3	20260630	3	900.0000	USD	1.000000	900.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-rtx-5070-12g-shadow-3x-oc-tarjeta-de-video/
195	149	3	20260630	3	540.0000	USD	1.000000	540.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-dual-rtx-5060-ti-8gb-gddr7-oc-edition-tarjeta-de-video/
196	145	3	20260630	3	790.0000	USD	1.000000	790.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-dual-rtx-5060-ti-evo-16gb-tarjeta-de-video/
197	5	3	20260630	3	415.0000	USD	1.000000	415.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-dual-rtx-5050-8gb-gddr6-oc-edition-tarjeta-de-video/
198	153	3	20260630	3	750.0000	USD	1.000000	750.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-rtx-5060-ti-16g-ventus-2x-oc-plus-tarjeta-video/
199	146	3	20260630	3	1295.0000	USD	1.000000	1295.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gigabyte-rtx-5070-ti-eagle-oc-sff-16g-tarjeta-de-video/
200	493	3	20260630	3	60.0000	USD	1.000000	60.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/video-portero-wifi-tapo-d210-vision-nocturna-color-y-deteccion-de-personas/
201	154	3	20260630	3	1185.0000	USD	1.000000	1185.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/lenovo-loq-15arp10e-amd-r7-7735hs-16gb-512b-rtx-4050-15-6/
202	142	3	20260630	3	1320.0000	USD	1.000000	1320.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/hp-victus-amd-ryzen-7-7445hs-rtx-4050-16gb/
203	141	3	20260630	3	2998.0000	USD	1.000000	2998.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-rainbow-beast-frozen-ryzen-7-9800x3d-32gb-2tb-rtx-5070/
204	5	3	20260630	3	1375.0000	USD	1.000000	1375.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-lite-hd-i5-14400-16gb-960gb-rtx-5050-8gb/
205	145	3	20260630	3	1960.0000	USD	1.000000	1960.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-rainbow-lite-ryzen-7-16gb-1tb-rtx-5060-ti/
206	141	3	20260630	3	2215.0000	USD	1.000000	2215.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-digital-beast-ryzen-7-16gb-1tb-rtx-5070/
207	148	3	20260630	3	1430.0000	USD	1.000000	1430.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-flexi-lite-core-ultra-5-500gb-16gb-rtx-5050/
208	16	3	20260630	3	1575.0000	USD	1.000000	1575.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-air-curve-core-ultra-5-500gb-16gb-rtx-5060/
209	141	3	20260630	3	2440.0000	USD	1.000000	2440.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/mtec-pc-rainbow-beast-ryzen-9700x-32gb-1tb-rtx-5070/
210	142	3	20260630	3	1065.0000	USD	1.000000	1065.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-thin-15-b13ve-intel-i5-13420h-rtx-4050-16gb/
211	144	3	20260630	3	1070.0000	USD	1.000000	1070.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-v16-core-5-120h-rtx-4050-6gb-16gb-ram/
212	141	3	20260630	3	900.0000	USD	1.000000	900.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/zotac-gaming-geforce-rtx-5070-solid-12gb/
213	145	3	20260630	3	760.0000	USD	1.000000	760.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/zotac-gaming-geforce-rtx-5060-ti-twin-edge-oc-16gb/
214	145	3	20260630	3	765.0000	USD	1.000000	765.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gigabyte-geforce-rtx-5060-ti-eagle-oc-ice-16gb/
215	146	3	20260630	3	1300.0000	USD	1.000000	1300.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/zotac-gaming-geforce-rtx-5070-ti-solid-sff-oc-16gb/
216	494	3	20260630	3	175.0000	USD	1.000000	175.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/adata-xpg-spectrix-d41-16gb-ddr4-rgb-3200mhz/
217	456	3	20260630	3	1070.0000	USD	1.000000	1070.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-v16-core-5-120h-rtx-4050-6gb-16gb-ram/
218	495	3	20260630	3	325.0000	USD	1.000000	325.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/xpg-lancer-rgb-ddr5-16gb-ram-6000mhz-white/
219	496	3	20260630	3	335.0000	USD	1.000000	335.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/xpg-caster-rgb-16gb-ddr5-6400mhz/
220	489	3	20260630	3	140.0000	USD	1.000000	140.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-pro-h810m-b-mainboard-ddr5-intel-lga1851/
221	497	3	20260630	3	210.0000	USD	1.000000	210.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/adata-sc610-1000gb-disco-de-estado-solido-externo/
222	498	3	20260630	3	200.0000	USD	1.000000	200.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/corsair-mp600-core-xt-1t-m-2-gen4/
223	499	3	20260630	3	60.0000	USD	1.000000	60.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/xiaomi-barra-de-luz-para-monitor/
224	500	3	20260630	3	145.0000	USD	1.000000	145.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/boetec-slim-2477-24-ips-200hz-1ms/
225	501	3	20260630	3	250.0000	USD	1.000000	250.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-tuf-vg259qm5a-24-5-monitor-gamer-fhd-240hz-ips/
226	502	3	20260630	3	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gigabyte-gs27qa-monitor-27-qhd-ss-ips-180hz-1ms/
227	483	3	20260630	3	295.0000	USD	1.000000	295.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/eros-te-2767g-27-curvo-qhd-2k-180hz-1ms/
228	481	3	20260630	3	955.0000	USD	1.000000	955.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-proart-pa27jcv-27-pulgadas-ips-5k-monitor/
229	458	3	20260630	3	350.0000	USD	1.000000	350.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-mag-32c6x-31-5-monitor-curvo-fhd-250hz-1ms/
230	480	3	20260630	3	305.0000	USD	1.000000	305.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-mag-272f-x24-monitor-27-ips-full-hd-240hz-0-5ms/
231	459	3	20260630	3	220.0000	USD	1.000000	220.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/thunderobot-zq25f180-monitor-24-5-180hz-qhd-ips/
232	460	3	20260630	3	290.0000	USD	1.000000	290.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-tuf-vg279qm5a-27-monitor-gamer-fhd-240hz-ips/
233	461	3	20260630	3	210.0000	USD	1.000000	210.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/armaggeddon-pixxel-xf27hd-monitor-27-ips-120hz/
234	462	3	20260630	3	240.0000	USD	1.000000	240.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-tuf-vg249q5r-23-8-monitor-gamer-fhd-200hz-ips/
235	463	3	20260630	3	225.0000	USD	1.000000	225.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-pro-mp243l-e14-monitor-24-144hz-ips-1ms/
236	464	3	20260630	3	235.0000	USD	1.000000	235.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/teros-te-2786g-27-monitor-gamer-200hz-1ms-ips/
237	465	3	20260630	3	50.0000	USD	1.000000	50.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/klip-xtreme-kmm-510-soporte-articulado-dos-monitores/
238	466	3	20260630	3	428.9900	USD	1.000000	428.9900	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asrock-pg27q15r2a-27-monitor-curvo-va-qhd-1440p-165hz/
239	467	3	20260630	3	165.0000	USD	1.000000	165.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/cooler-master-ga241-23-8-monitor-fhd-100hz-1ms/
240	468	3	20260630	3	619.9900	USD	1.000000	619.9900	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/lg-ergo-32uk580-b-monitor-31-5-pulgadas-4k-uhd/
241	469	3	20260630	3	8.9900	USD	1.000000	8.9900	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/ge-97894-cable-extension-monitor-vga-3-04m/
242	470	3	20260630	3	1605.0000	USD	1.000000	1605.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-mpg-491cqp-49-qd-oled-144hz-0-3ms/
243	471	3	20260630	3	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/oraimo-osw-831n-rose-gold-amoled-1-32%c2%a8/
244	472	3	20260630	3	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/oraimo-osw-830-black-smartwatch-amoled/
245	473	3	20260630	3	740.0000	USD	1.000000	740.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-rog-strix-xg27aqdmes-27-240hz-oled-qhd/
246	474	3	20260630	3	105.0000	USD	1.000000	105.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/cougar-poseidon-vistek-argb-240-pantalla-lcd-2/
247	475	3	20260630	3	125.0000	USD	1.000000	125.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/cougar-poseidon-vistek-pro-argb-240mm-pantalla-lcd-wh/
248	476	3	20260630	3	110.0000	USD	1.000000	110.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/cougar-poseidon-vistek-argb-360-pantalla-lcd-wh/
249	477	3	20260630	3	148.0000	USD	1.000000	148.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/cougar-poseidon-vistek-pro-argb-360-pantalla-lcd-bk/
250	478	3	20260630	3	30.0000	USD	1.000000	30.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gamdias-hermes-e8-usb-red-switch-teclado-mecanico/
251	479	3	20260630	3	40.0000	USD	1.000000	40.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gamdias-hermes-e7-usb-red-switch-teclado-mecanico/
252	601	3	20260630	3	75.0000	USD	1.000000	75.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-horus-k618-rgb-white-teclado-mecanico/
253	419	3	20260630	3	85.0000	USD	1.000000	85.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-flekact-pro-k708gf-rgb-pro-teclado-inalambrico/
254	602	3	20260630	3	50.0000	USD	1.000000	50.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-kumara-k552-teclado-mecanico/
255	615	3	20260630	3	70.0000	USD	1.000000	70.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-ucal-pro-k673-anime-teclado-75-wireless/
256	723	3	20260630	3	95.0000	USD	1.000000	95.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-olaf-k648gg-rgb-teclado-gamer-wireless-94-teclas/
257	724	3	20260630	3	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-eisa-k686ak-rgb-pro-teclado-gamer-90/
258	725	3	20260630	3	45.0000	USD	1.000000	45.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-fizz-pro-k616-rgb-teclado-wireless-blanco/
259	726	3	20260630	3	13.0000	USD	1.000000	13.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/alcatroz-x-craft-xc3000-combo-gamer/
260	727	3	20260630	3	28.0000	USD	1.000000	28.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/armaggeddon-mka-7c-psycheagle-teclado-mecanico-red-switch/
261	728	3	20260630	3	18.0000	USD	1.000000	18.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/genius-scorpion-km-gx6-tecladomouse-combo-gamer/
262	729	3	20260630	3	12.0000	USD	1.000000	12.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/genius-km-160-combo-teclado-mouse-usb/
263	730	3	20260630	3	33.0000	USD	1.000000	33.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/thunderobot-kg3089c-teclado-negro-mecanico-blue-switch/
264	731	3	20260630	3	22.0000	USD	1.000000	22.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-kumlun-l-p006-mousepad-large-speed/
265	732	3	20260630	3	25.0000	USD	1.000000	25.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-aatrox-m811-rgb-mmo-mouse-15-botones/
266	733	3	20260630	3	58.0000	USD	1.000000	58.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/razer-deathadder-v2-x-hyperspeed-mouse-inalambrico/
267	734	3	20260630	3	8.0000	USD	1.000000	8.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-pisces-p016-mouse-pad-33x26cm/
268	735	3	20260630	3	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-k1ng-m916-ultra-mouse-8k-hz-30k-dpi/
269	736	3	20260630	3	23.0000	USD	1.000000	23.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/combo-gamer-redragon-mouse-y-mousepad-m601wl-ba-negro-y-rojo/
270	737	3	20260630	3	100.0000	USD	1.000000	100.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/logitech-mx-vertical-mouse-ergonomico-vertical-2/
271	738	3	20260630	3	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/machenike-gm704-liuliya-mousepad-large/
272	739	3	20260630	3	10.0000	USD	1.000000	10.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/pirmus-arena-mousepad-medium-pmp-01m/
273	740	3	20260630	3	24.9900	USD	1.000000	24.9900	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/hyperx-pulsefire-core-rgb-mouse-gamer/
274	741	3	20260630	3	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/cougar-airblader-tournament-mouse-gamer-20k-dpi-white/
275	742	3	20260630	3	21.0000	USD	1.000000	21.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-hylas-h260-rgb-auriculares-gamer/
276	743	3	20260630	3	34.9900	USD	1.000000	34.9900	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/armaggeddon-cosmic-iii-lite-bk-auriculares-inalambrico-copia/
277	69	4	20260630	4	280.0000	USD	1.000000	280.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-intel-core-ultra-5-250kf-plus-5-3ghz-22tops-1818-lga-1851/
278	124	4	20260630	4	1290.0000	USD	1.000000	1290.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-ryzen-9-9950x3d2-5-6ghz-am5/
279	722	4	20260630	4	470.0000	USD	1.000000	470.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-intel-core-i7-14700-5-4ghz/
280	60	4	20260630	4	260.0000	USD	1.000000	260.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-intel-core-ultra-5-225/
281	59	4	20260630	4	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-5-9600-am5/
282	58	4	20260630	4	490.0000	USD	1.000000	490.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-9-5900xt-am4/
283	57	4	20260630	4	780.0000	USD	1.000000	780.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/amd-ryzen-9-9900x3d-5-5ghz-am5/
284	56	4	20260630	4	950.0000	USD	1.000000	950.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/amd-ryzen-9-9950x3d-5-7ghz-1632-am5/
285	55	4	20260630	4	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/amd-ryzen-7-8700f-5ghz-816-am5/
286	54	4	20260630	4	230.0000	USD	1.000000	230.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/intel-core-ultra-5-225f-lga-1851/
287	34	4	20260630	4	820.0000	USD	1.000000	820.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-intel-core-ultra-9-285k/
288	53	4	20260630	4	200.0000	USD	1.000000	200.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-5-8400f-612-4-7ghz/
289	52	4	20260630	4	430.0000	USD	1.000000	430.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-intel-core-ultra-7-265kf/
290	42	4	20260630	4	550.0000	USD	1.000000	550.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-9-9900x/
291	51	4	20260630	4	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-5-9600x-5-4ghz/
292	50	4	20260630	4	180.0000	USD	1.000000	180.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-ryzen-5-8500g-radeon-740m/
293	49	4	20260630	4	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/amd-ryzen-7-8700g-5-1ghz-radeon-780m/
294	48	4	20260630	4	220.0000	USD	1.000000	220.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/amd-ryzen-5-8600g-5-0ghz-radeon-760m/
295	47	4	20260630	4	390.0000	USD	1.000000	390.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-7-7700-5-3ghz-am5/
296	708	4	20260630	4	349.9900	USD	1.000000	349.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-cubi-5-intel-i3-1215u-ddr4-wifi-bluetooth/
297	700	4	20260630	4	529.9900	USD	1.000000	529.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-cubi-5-intel-i5-1235u-ddr4-wifi-bluetooh/
298	709	4	20260630	4	669.9900	USD	1.000000	669.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-cubi-5-intel-i7-1255u-ddr4-wifi-bluetooth/
299	46	4	20260630	4	2049.9900	USD	1.000000	2049.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-zotac-amp-extreme-infinity-geforce-rtx-5080-16gb-gddr7/
300	4	4	20260630	4	499.9900	USD	1.000000	499.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-gigabyte-eagle-geforce-rtx-5060-8gb-oc-gddr7/
301	4	4	20260630	4	509.9900	USD	1.000000	509.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-gigabyte-eagle-ice-geforce-rtx-5060-8gb-oc-gddr7/
302	5	4	20260630	4	419.9900	USD	1.000000	419.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-gigabyte-windforce-v2-geforce-rtx-5050-8gb-oc-gddr6/
303	45	4	20260630	4	769.9900	USD	1.000000	769.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/asus-dual-evo-geforce-rtx-5060-ti-16gb/
304	39	4	20260630	4	3989.9900	USD	1.000000	3989.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/zotac-amp-extreme-infinity-rtx-5090-32g/
305	39	4	20260630	4	6989.9900	USD	1.000000	6989.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-geforce-rtx-5090-32g-lightning-z/
306	44	4	20260630	4	1149.9900	USD	1.000000	1149.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/xfx-swift-amd-radeon-rx-9070-xt-16gb/
307	43	4	20260630	4	699.9900	USD	1.000000	699.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/xfx-swift-amd-radeon-rx-9060-xt-16gb-oc-wh/
308	43	4	20260630	4	689.9900	USD	1.000000	689.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/xfx-swift-amd-radeon-rx-9060-xt-16gb-oc/
309	46	4	20260630	4	2099.9900	USD	1.000000	2099.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-gaming-trio-white-geforce-rtx-5080-16gb-oc-gddr7/
310	4	4	20260630	4	479.9900	USD	1.000000	479.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-cyclone-geforce-rtx-5060-8gb-oc/
311	5	4	20260630	4	399.9900	USD	1.000000	399.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/zotac-rtx-5050-8gb-edge-oc-gddr6/
312	5	4	20260630	4	409.9900	USD	1.000000	409.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-asus-dual-nvidia-rtx-5050-8gb-gddr6-oc/
313	43	4	20260630	4	519.9900	USD	1.000000	519.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-asrock-steel-legend-amd-radeon-rx-9060-xt-8gb-oc-gddr6/
314	6	4	20260630	4	949.9900	USD	1.000000	949.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-asus-prime-rtx-5070-12gb-oc-gddr7/
315	4	4	20260630	4	519.9900	USD	1.000000	519.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-msi-ventus-3x-nvidia-rtx-5060-8gb-oc-gddr7/
316	45	4	20260630	4	789.9900	USD	1.000000	789.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gigabyte-eagle-ice-rtx-5060-ti-16gb-oc/
317	39	4	20260630	4	4489.9900	USD	1.000000	4489.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/asus-rog-astral-rtx-5090-32gb-oc-gddr7/
318	66	4	20260630	4	999.9900	USD	1.000000	999.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gigabyte-amd-radeon-rx-9070-16gb-oc/
319	6	4	20260630	4	1049.9900	USD	1.000000	1049.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gpu-asus-tuf-rtx-5070-12gb-oc-gddr7/
320	15	4	20260630	4	1449.9900	USD	1.000000	1449.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gpu-gigabyte-gaming-rtx-5070-ti-16gb-oc/
321	44	4	20260630	4	1189.9900	USD	1.000000	1189.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gpu-gigabyte-aorus-elite-amd-radeon-rx-9070-xt-16gb-oc/
322	46	4	20260630	4	1999.9900	USD	1.000000	1999.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gpu-gigabyte-aero-sff-rtx-5080-16gb-oc/
323	46	4	20260630	4	2389.9900	USD	1.000000	2389.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/asus-rog-astral-rtx-5080-16gb-oc-gddr7/
324	12	4	20260630	4	1249.9900	USD	1.000000	1249.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/asus-tuf-gaming-rtx-4070-ti-super-btf/
325	65	4	20260630	4	790.9000	USD	1.000000	790.9000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gpu-aorus-xtreme-radeon-rx-6900-xt-12gb/
326	701	4	20260630	4	15.0000	USD	1.000000	15.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/adaptador-tp-link-tl-wn881nd/
327	702	4	20260630	4	110.0000	USD	1.000000	110.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/8gb-so-dimm-kingston-ddr5-5600mt-s-cl46/
328	703	4	20260630	4	400.0000	USD	1.000000	400.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/32gb-so-dimm-ddr5-kingston-fury-impact/
329	704	4	20260630	4	200.0000	USD	1.000000	200.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/16gb-so-dimm-ddr5-kingston-fury-impact/
330	705	4	20260630	4	180.0000	USD	1.000000	180.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/16gb-ram-ddr4-corsair-vengeance-lpx-3200mhz-cl16/
331	706	4	20260630	4	270.0000	USD	1.000000	270.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/16gb-ddr5-xpg-lancer-blade-6000mts-cl48/
332	707	4	20260630	4	100.0000	USD	1.000000	100.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/8gb-ddr4-so-dimm-kingston-3200mhz-cl22/
333	708	4	20260630	4	349.9900	USD	1.000000	349.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-cubi-5-intel-i3-1215u-ddr4-wifi-bluetooth/
334	700	4	20260630	4	529.9900	USD	1.000000	529.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-cubi-5-intel-i5-1235u-ddr4-wifi-bluetooh/
335	709	4	20260630	4	669.9900	USD	1.000000	669.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-cubi-5-intel-i7-1255u-ddr4-wifi-bluetooth/
336	710	4	20260630	4	1349.9900	USD	1.000000	1349.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-ultrawide-curvo-samsung-odyssey-oled-g9-g91sd/
337	711	4	20260630	4	649.9900	USD	1.000000	649.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-ultrawide-curvo-samsung-viewfinity-s6-s65uc/
338	712	4	20260630	4	119.9900	USD	1.000000	119.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-portatil-viewsonic-va1653/
339	713	4	20260630	4	199.9900	USD	1.000000	199.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-lg-ultragear-27g411a/
340	714	4	20260630	4	149.9900	USD	1.000000	149.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-indurama-vortixnova-25/
341	715	4	20260630	4	519.9900	USD	1.000000	519.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-samsung-odyssey-g6-g60f/
342	716	4	20260630	4	1549.9900	USD	1.000000	1549.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-msi-mpg-321urx-qd-oled/
343	717	4	20260630	4	289.9900	USD	1.000000	289.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-curvo-teros-te-2767g/
344	718	4	20260630	4	299.9900	USD	1.000000	299.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-curvo-teros-te-3219g/
345	719	4	20260630	4	79.9900	USD	1.000000	79.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-acer-k202q-bi/
346	720	4	20260630	4	179.9900	USD	1.000000	179.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-lg-ultragear-24g411a/
347	744	4	20260630	4	209.9900	USD	1.000000	209.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-msi-g242l-e14/
348	721	4	20260630	4	169.9900	USD	1.000000	169.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-indurama-vortixnova-27/
349	745	4	20260630	4	249.9900	USD	1.000000	249.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-tuf-vg259qm5a/
350	771	4	20260630	4	749.9900	USD	1.000000	749.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-rog-strix-oled-xg27aqdmes/
351	773	4	20260630	4	949.9900	USD	1.000000	949.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-zenscreen-smart-ms32uc/
352	774	4	20260630	4	509.9900	USD	1.000000	509.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-ultrawide-lg-34u511a/
353	775	4	20260630	4	329.9900	USD	1.000000	329.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-proart-pa248qfv/
354	776	4	20260630	4	389.9900	USD	1.000000	389.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-proart-pa278qgv/
355	777	4	20260630	4	789.9900	USD	1.000000	789.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-gigabyte-mo27q28g-woled/
356	778	4	20260630	4	449.9900	USD	1.000000	449.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-gigabyte-m27q2-qd-ice/
357	779	4	20260630	4	239.9900	USD	1.000000	239.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-gigabyte-gs25f2a/
358	780	4	20260630	4	55.0000	USD	1.000000	55.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/soporte-neumatico-klip-xtreme-kmm-410/
359	781	4	20260630	4	439.9900	USD	1.000000	439.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-curvo-teros-te-3412g/
360	782	4	20260630	4	140.0000	USD	1.000000	140.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-portatil-asus-zenscreen-mb169ck/
361	783	4	20260630	4	229.9900	USD	1.000000	229.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-teros-te-2786g/
362	784	4	20260630	4	189.9900	USD	1.000000	189.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-teros-te-2714s/
363	785	4	20260630	4	45.0000	USD	1.000000	45.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-inteligente-para-bebe-nexxt-nhc-b100-2k/
364	786	4	20260630	4	219.9900	USD	1.000000	219.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-gigabyte-gs25f2/
365	787	4	20260630	4	309.9900	USD	1.000000	309.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asrock-pg27fft1a/
366	788	4	20260630	4	279.9900	USD	1.000000	279.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asrock-pg25fft-ips-180hz-1ms/
367	789	4	20260630	4	349.9900	USD	1.000000	349.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-curvo-samsung-odyssey-g5-g55c/
368	790	4	20260630	4	589.9900	USD	1.000000	589.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-proart-pa279crv/
369	791	4	20260630	4	75.0000	USD	1.000000	75.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-multi-plataforma-logitech-k780/
370	792	4	20260630	4	180.0000	USD	1.000000	180.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-logitech-g-pro-x-tkl-rapid-magnetic-switch/
371	793	4	20260630	4	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-redragon-behemoth-pro-k724-black-rpc-switch/
372	772	4	20260630	4	85.0000	USD	1.000000	85.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-redragon-terraflare-pro-k762wb-white-black-manbo-switch/
373	770	4	20260630	4	50.0000	USD	1.000000	50.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redradon-castor-magnetic-k631/
374	747	4	20260630	4	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-y-mouse-logitech-advanced-mk540/
375	769	4	20260630	4	120.0000	USD	1.000000	120.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-razer-huntsman-v3-x-tenkeyless-optical-purple-switch/
376	748	4	20260630	4	70.0000	USD	1.000000	70.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/kit-redragon-s147-4-en-1/
377	749	4	20260630	4	130.0000	USD	1.000000	130.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-asus-rog-falchion-ace-hfx-magnetic-switch/
378	750	4	20260630	4	380.0000	USD	1.000000	380.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-corsair-galleon-100-sd/
379	751	4	20260630	4	200.0000	USD	1.000000	200.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-corsair-vanguard-96-mlx-switch/
380	752	4	20260630	4	190.0000	USD	1.000000	190.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-corsair-k70-core-tkl-mlx-switch/
381	753	4	20260630	4	230.0000	USD	1.000000	230.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-corsair-k70-pro-tkl-mgx-switch/
382	754	4	20260630	4	155.0000	USD	1.000000	155.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-optico-corsair-k65-pro-mini/
383	755	4	20260630	4	90.0000	USD	1.000000	90.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-flekact-pro-k708mc/
384	756	4	20260630	4	60.0000	USD	1.000000	60.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-cyrus-pro-k681mg-green/
385	757	4	20260630	4	55.0000	USD	1.000000	55.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-veigar-k643wgc/
386	758	4	20260630	4	45.0000	USD	1.000000	45.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-ironguard-k722/
387	759	4	20260630	4	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-y-mouse-meetion-mini5000/
388	760	4	20260630	4	35.0000	USD	1.000000	35.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-meetion-wk310-black/
389	761	4	20260630	4	40.0000	USD	1.000000	40.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-meetion-wk330-black/
390	762	4	20260630	4	95.0000	USD	1.000000	95.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-razer-viper-v3-hyperspeed/
391	763	4	20260630	4	175.0000	USD	1.000000	175.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-logitech-g-g502-x-plus-lightspeed/
392	764	4	20260630	4	145.0000	USD	1.000000	145.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-logitech-g-pro-x-superlight-2-se/
393	765	4	20260630	4	160.0000	USD	1.000000	160.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-razer-basilisk-v3-pro-35k-phantom-green-edition/
394	766	4	20260630	4	110.0000	USD	1.000000	110.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-razer-cobra-hyperspeed/
395	767	4	20260630	4	150.0000	USD	1.000000	150.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-logitech-mx-master-4/
396	768	4	20260630	4	170.0000	USD	1.000000	170.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-corsair-scimitar-elite-se-carbon/
397	746	4	20260630	4	140.0000	USD	1.000000	140.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-corsair-m75-white/
398	699	4	20260630	4	15.0000	USD	1.000000	15.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-redragon-azzmach-m618-black/
399	698	4	20260630	4	10.0000	USD	1.000000	10.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mousepad-ergonomico-klipxtreme-kmp-100b/
400	697	4	20260630	4	5589.9900	USD	1.000000	5589.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/laptop-asus-rog-strix-scar-18-g835/
401	628	4	20260630	4	100.0000	USD	1.000000	100.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-logitech-mx-ergo-s/
402	629	4	20260630	4	270.0000	USD	1.000000	270.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-jbl-tour-one-m3-black/
403	630	4	20260630	4	115.0000	USD	1.000000	115.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-inalambrico-jbl-tune-780nc-black/
404	631	4	20260630	4	220.0000	USD	1.000000	220.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-logitech-g-pro-x-lightspeed/
405	632	5	20260630	5	542.1600	USD	1.000000	542.1600	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
406	36	5	20260630	5	516.9800	USD	1.000000	516.9800	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
407	35	5	20260630	5	467.1100	USD	1.000000	467.1100	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
408	34	5	20260630	5	860.1600	USD	1.000000	860.1600	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
409	33	5	20260630	5	429.0000	USD	1.000000	429.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
410	32	5	20260630	5	89.0000	USD	1.000000	89.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
411	31	5	20260630	5	857.1200	USD	1.000000	857.1200	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
412	30	5	20260630	5	490.7000	USD	1.000000	490.7000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
413	633	5	20260630	5	530.9000	USD	1.000000	530.9000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
414	28	5	20260630	5	745.9100	USD	1.000000	745.9100	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
415	634	5	20260630	5	437.9700	USD	1.000000	437.9700	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
416	67	5	20260630	5	384.5200	USD	1.000000	384.5200	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
417	42	5	20260630	5	576.4500	USD	1.000000	576.4500	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
418	68	5	20260630	5	145.0000	USD	1.000000	145.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
419	107	5	20260630	5	205.0000	USD	1.000000	205.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
420	635	5	20260630	5	69.0000	USD	1.000000	69.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
421	122	5	20260630	5	339.0000	USD	1.000000	339.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
422	636	5	20260630	5	249.0000	USD	1.000000	249.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
423	120	5	20260630	5	109.0000	USD	1.000000	109.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
424	119	5	20260630	5	459.0000	USD	1.000000	459.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
425	118	5	20260630	5	429.0000	USD	1.000000	429.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
426	98	5	20260630	5	499.0000	USD	1.000000	499.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
427	55	5	20260630	5	279.0000	USD	1.000000	279.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
428	58	5	20260630	5	389.0000	USD	1.000000	389.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
429	637	5	20260630	5	419.0000	USD	1.000000	419.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
430	51	5	20260630	5	275.0000	USD	1.000000	275.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
431	35	5	20260630	5	425.0000	USD	1.000000	425.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
432	117	5	20260630	5	299.0000	USD	1.000000	299.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
433	638	5	20260630	5	459.0000	USD	1.000000	459.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
434	115	5	20260630	5	225.0000	USD	1.000000	225.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
435	49	5	20260630	5	299.0000	USD	1.000000	299.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
436	114	5	20260630	5	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
437	53	5	20260630	5	209.0000	USD	1.000000	209.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
438	113	5	20260630	5	399.0000	USD	1.000000	399.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
439	112	5	20260630	5	215.0000	USD	1.000000	215.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
440	111	5	20260630	5	125.0000	USD	1.000000	125.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
441	639	5	20260630	5	83.4500	USD	1.000000	83.4500	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
442	110	5	20260630	5	430.8100	USD	1.000000	430.8100	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
443	109	5	20260630	5	510.2300	USD	1.000000	510.2300	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
444	108	5	20260630	5	1065.9300	USD	1.000000	1065.9300	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
445	44	5	20260630	5	1235.4400	USD	1.000000	1235.4400	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
446	4	5	20260630	5	499.0000	USD	1.000000	499.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
447	121	5	20260630	5	549.0000	USD	1.000000	549.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
448	129	5	20260630	5	248.0000	USD	1.000000	248.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=tarjeta+de+video&post_type=product#
449	138	5	20260630	5	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=tarjeta+de+video&post_type=product#
450	640	5	20260630	5	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=tarjeta+de+video&post_type=product#
451	43	5	20260630	5	469.0000	USD	1.000000	469.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=tarjeta+de+video&post_type=product#
452	641	5	20260630	5	144.1700	USD	1.000000	144.1700	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
453	642	5	20260630	5	107.5400	USD	1.000000	107.5400	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
454	643	5	20260630	5	128.8200	USD	1.000000	128.8200	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
455	644	5	20260630	5	260.1800	USD	1.000000	260.1800	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
456	645	5	20260630	5	182.7700	USD	1.000000	182.7700	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
457	646	5	20260630	5	197.1700	USD	1.000000	197.1700	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
458	607	5	20260630	5	695.0000	USD	1.000000	695.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
459	608	5	20260630	5	859.0000	USD	1.000000	859.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=memoria+ram&post_type=product#
460	609	5	20260630	5	371.0000	USD	1.000000	371.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=memoria+ram&post_type=product#
461	611	5	20260630	5	679.0000	USD	1.000000	679.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=memoria+ram&post_type=product#
462	627	5	20260630	5	289.0000	USD	1.000000	289.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=memoria+ram&post_type=product#
463	626	5	20260630	5	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=memoria+ram&post_type=product#
464	605	5	20260630	5	575.0000	USD	1.000000	575.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=memoria+ram&post_type=product#
465	606	5	20260630	5	7.0000	USD	1.000000	7.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=memoria+ram&post_type=product#
466	607	5	20260630	5	695.0000	USD	1.000000	695.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=disco+solido+ssd&post_type=product#
467	608	5	20260630	5	859.0000	USD	1.000000	859.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=disco+solido+ssd&post_type=product#
468	609	5	20260630	5	371.0000	USD	1.000000	371.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=disco+solido+ssd&post_type=product#
469	610	5	20260630	5	109.0000	USD	1.000000	109.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
470	611	5	20260630	5	679.0000	USD	1.000000	679.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
471	405	5	20260630	5	116.0000	USD	1.000000	116.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
472	605	5	20260630	5	575.0000	USD	1.000000	575.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
473	612	5	20260630	5	85.0000	USD	1.000000	85.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
474	613	5	20260630	5	84.0000	USD	1.000000	84.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
475	604	5	20260630	5	49.0000	USD	1.000000	49.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
476	614	5	20260630	5	189.0000	USD	1.000000	189.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
477	616	5	20260630	5	729.0000	USD	1.000000	729.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
478	617	5	20260630	5	1149.0000	USD	1.000000	1149.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
479	618	5	20260630	5	659.0000	USD	1.000000	659.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
480	619	5	20260630	5	235.0000	USD	1.000000	235.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
481	620	5	20260630	5	319.0000	USD	1.000000	319.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
482	621	5	20260630	5	215.0000	USD	1.000000	215.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
483	622	5	20260630	5	69.0000	USD	1.000000	69.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
484	623	5	20260630	5	549.0000	USD	1.000000	549.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
485	624	5	20260630	5	155.0000	USD	1.000000	155.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
486	625	5	20260630	5	259.0000	USD	1.000000	259.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
487	647	5	20260630	5	209.0000	USD	1.000000	209.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
488	648	5	20260630	5	265.0000	USD	1.000000	265.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
489	649	5	20260630	5	159.0000	USD	1.000000	159.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
490	674	5	20260630	5	1194.2600	USD	1.000000	1194.2600	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
491	676	5	20260630	5	928.0000	USD	1.000000	928.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
492	677	5	20260630	5	609.0700	USD	1.000000	609.0700	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
493	678	5	20260630	5	269.0000	USD	1.000000	269.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
494	679	5	20260630	5	149.0000	USD	1.000000	149.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
495	680	5	20260630	5	255.0000	USD	1.000000	255.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
496	681	5	20260630	5	194.0000	USD	1.000000	194.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
497	682	5	20260630	5	355.0000	USD	1.000000	355.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
498	683	5	20260630	5	98.0000	USD	1.000000	98.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
499	684	5	20260630	5	275.0000	USD	1.000000	275.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
500	685	5	20260630	5	195.0000	USD	1.000000	195.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
501	686	5	20260630	5	185.0000	USD	1.000000	185.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
502	687	5	20260630	5	178.0000	USD	1.000000	178.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
503	688	5	20260630	5	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
504	689	5	20260630	5	249.0000	USD	1.000000	249.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
505	690	5	20260630	5	329.0000	USD	1.000000	329.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
506	691	5	20260630	5	219.0000	USD	1.000000	219.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
507	692	5	20260630	5	83.0000	USD	1.000000	83.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
508	693	5	20260630	5	289.0000	USD	1.000000	289.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
509	694	5	20260630	5	24.0000	USD	1.000000	24.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
510	695	5	20260630	5	13.0000	USD	1.000000	13.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
511	696	5	20260630	5	27.0000	USD	1.000000	27.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
512	675	5	20260630	5	23.0000	USD	1.000000	23.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
513	673	5	20260630	5	25.0000	USD	1.000000	25.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
514	650	5	20260630	5	32.0000	USD	1.000000	32.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
515	672	5	20260630	5	42.0000	USD	1.000000	42.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
516	651	5	20260630	5	9.0000	USD	1.000000	9.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
517	652	5	20260630	5	44.0000	USD	1.000000	44.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
518	653	5	20260630	5	15.0000	USD	1.000000	15.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
519	654	5	20260630	5	12.0000	USD	1.000000	12.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
520	655	5	20260630	5	30.0000	USD	1.000000	30.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
521	656	5	20260630	5	40.0000	USD	1.000000	40.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
522	657	5	20260630	5	29.0000	USD	1.000000	29.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
523	658	5	20260630	5	21.0000	USD	1.000000	21.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
524	659	5	20260630	5	59.0000	USD	1.000000	59.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
525	660	5	20260630	5	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
526	661	5	20260630	5	26.0000	USD	1.000000	26.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=teclado&post_type=product#
527	662	5	20260630	5	10.0000	USD	1.000000	10.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
528	663	5	20260630	5	28.0000	USD	1.000000	28.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
529	664	5	20260630	5	14.0000	USD	1.000000	14.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
530	665	5	20260630	5	55.0000	USD	1.000000	55.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
531	666	5	20260630	5	14.5000	USD	1.000000	14.5000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
532	667	5	20260630	5	8.5000	USD	1.000000	8.5000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
533	668	5	20260630	5	11.0000	USD	1.000000	11.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
534	669	5	20260630	5	16.0000	USD	1.000000	16.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=mouse&post_type=product#
535	670	5	20260630	5	48.0000	USD	1.000000	48.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=mouse&post_type=product#
536	671	5	20260630	5	2.5000	USD	1.000000	2.5000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=mouse&post_type=product#
537	603	5	20260630	5	18.0000	USD	1.000000	18.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=audifonos&post_type=product#
538	406	5	20260630	5	75.0000	USD	1.000000	75.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=audifonos&post_type=product#
539	285	5	20260630	5	79.0000	USD	1.000000	79.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=audifonos&post_type=product#
540	139	6	20260630	6	337.9900	USD	1.000000	337.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-5-250k-plus-turbo-5-3ghz-18-cores-lga1851/
541	32	6	20260630	6	95.9900	USD	1.000000	95.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-3-3200g-con-graficos-radeon-vega-8/
542	90	6	20260630	6	502.9900	USD	1.000000	502.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-7-270k-plus-24-cores-3-7ghz-base-36mb-lga1851-125w-base/
543	91	6	20260630	6	305.9900	USD	1.000000	305.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-14400-2-5ghz-14th-lga1700-uhd770-10-cores-20mb-cache/
544	92	6	20260630	6	175.9900	USD	1.000000	175.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i3-13100f-3-40ghz-13th-lga1700-4-cores-12mb-cache/
545	93	6	20260630	6	619.9900	USD	1.000000	619.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-14700k-20-cores-28-hilos-8p12e-base-3-4ghz-turbo-5-4ghz-cache-33mb-graficos-intel-lga1700-14th-gen/
546	94	6	20260630	6	115.9900	USD	1.000000	115.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-180/
547	36	6	20260630	6	514.9900	USD	1.000000	514.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-138/
548	95	6	20260630	6	567.9900	USD	1.000000	567.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-137/
549	52	6	20260630	6	369.9900	USD	1.000000	369.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-7-265kf-base-3-9-ghz-30mb-lga1851-20-cores-8p12e-250w/
550	60	6	20260630	6	272.9900	USD	1.000000	272.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-5-225-20mb-4-9ghz-lga1851-10-cores-65w-intel-graphics/
551	96	6	20260630	6	886.9900	USD	1.000000	886.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-9-9950x-4-3ghz-turbo-5-7ghz-16-cores-32-hilos-am5-170w/
552	35	6	20260630	6	490.9900	USD	1.000000	490.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-9700x-amd-am5-zen-5-65w-8-cores-16-thread/
553	49	6	20260630	6	353.9900	USD	1.000000	353.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-8700g-4-2ghz-base-8-cores-16-hilos-am5-65w-with-radeon-graphics/
554	98	6	20260630	6	599.9900	USD	1.000000	599.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-7800x3d-8-cores-base-4-2ghz-am5-cache-8mb/
555	99	6	20260630	6	434.9900	USD	1.000000	434.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-7700-3-8ghz-base-8-cores-16-hilos-8mb-am5-65w-100000592box/
556	53	6	20260630	6	220.9900	USD	1.000000	220.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-8400f-6-cores-4-7-ghz-turbo-65w-am5-sin-graficos/
557	68	6	20260630	6	151.9900	USD	1.000000	151.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-3-5300g-am4-16mb-64w-8-thread/
558	100	6	20260630	6	748.9900	USD	1.000000	748.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-9850x3d-4-7ghz-8-cores-16-hilos-96mb-am5-120w/
559	50	6	20260630	6	204.9900	USD	1.000000	204.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-8500g-base-3-5ghz-65w-am5-graficos-amd-radeon-740m-100-100000931box/
560	101	6	20260630	6	300.9900	USD	1.000000	300.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-5700x-3-4ghz-4-6ghz-8-core-16-threads/
561	102	6	20260630	6	179.9900	USD	1.000000	179.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i3-14100f-3-5-ghz-14th-lga1700-4-cores/
562	48	6	20260630	6	248.9900	USD	1.000000	248.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-8600g-4-3ghz-base-6-cores-12-hilos-am5-65w-with-radeon-graphics/
563	103	6	20260630	6	216.9900	USD	1.000000	216.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-5600gt-3-6ghz-turbo-4-6ghz-am4-6-core-12-threads-graficos-radeon-vega-integrados/
564	104	6	20260630	6	486.9900	USD	1.000000	486.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-12700/
565	97	6	20260630	6	151.9900	USD	1.000000	151.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-5500/
566	89	6	20260630	6	115.9900	USD	1.000000	115.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-4790k-4ghz-turbo-4-4ghz-lga1150-h/
567	212	6	20260630	6	143.9900	USD	1.000000	143.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-hpe-dl380-gen9-intel-xeon-e5-2640v3-kit-719049-b/
568	88	6	20260630	6	288.9900	USD	1.000000	288.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-10600kf-4-1ghz-12mb-cache-lga-1200/
569	87	6	20260630	6	280.9900	USD	1.000000	280.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-5700g-3-8ghz-turbo-4-6ghz-am4-8-core-16-threads-graficos-radeon-vega-integrados/
570	70	6	20260630	6	2344.9900	USD	1.000000	2344.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-gigabyte-a16-r7-260-rtx5070/
571	223	6	20260630	6	2359.0000	USD	1.000000	2359.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-desktop-servidor-intel-ultra-9-285k-8-32gb-ddr5-raid-2x1tb-ssd/
572	222	6	20260630	6	1629.0000	USD	1.000000	1629.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-desktop-workstation-intel-ultra-7-270k-plus-tuf-b860-32gb-ddr5-1tb-ssd-wifi-case-solido-copia/
573	221	6	20260630	6	1919.0000	USD	1.000000	1919.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-u7-265kf-tuf-b860-32gb-1tb-rtx5050-wifi-case-solido/
574	220	6	20260630	6	19999.0000	USD	1.000000	19999.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ia-workstation-9960x-dual-rtx-5090-128gb/
575	71	6	20260630	6	952.9900	USD	1.000000	952.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/lenovo-ip-15arp10-ryzen-7-83k700g8us/
576	72	6	20260630	6	1154.9900	USD	1.000000	1154.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-acer-aspire-a15-51m-99w4/
577	73	6	20260630	6	892.9900	USD	1.000000	892.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-lenovo-83k100qclm/
578	74	6	20260630	6	1335.9900	USD	1.000000	1335.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-lenovo-log-q-amd-ryzen-7-7735hs-16gb-ram-512gb-ssd-geforce-rtx4050-15-6-fhd-144hz-w11h-luna-gray-83d0000lec/
579	70	6	20260630	6	1805.9900	USD	1.000000	1805.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-asus-tuf-a16-fa608uh-rv063/
580	75	6	20260630	6	987.9900	USD	1.000000	987.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-msi-thin-15-b13udx-3085xec/
581	76	6	20260630	6	1351.9900	USD	1.000000	1351.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-hp-victus-15-fb3022la-amd-ryzen-7-7445h-16gb-ram-512ssd-geforce-rtx4050-6gb-win-11-black/
582	70	6	20260630	6	1915.9900	USD	1.000000	1915.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-gigabyte-gaming-a16-ryzen-7-260-16gb-ddr5-512gb-ssd-16-fhd-nvidia-rtx-5050-8gb-efi-shell-black/
583	76	6	20260630	6	1154.9900	USD	1.000000	1154.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-gaming-hp-victus-15-fb3019la-amd-ryzen-7-7445h-8gb-ram-512ssd-15-6-fhd-geforce-rtx3050-6g-s-o-freedos-black-bt4f6laabm/
584	244	6	20260630	6	897.9900	USD	1.000000	897.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-vivobook-m1607ka-mb110-amd-ryzen-ai-7-350-16gb-ram-on-board-1tb-ssd-16-0-wuxga-wv-sin-s-o-kb-es-1b-quiet-blue/
585	170	6	20260630	6	2566.9900	USD	1.000000	2566.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-rog-strix-g16-g614pm-rv038-amd-ryzen-r9-8940hx-32gb-16gb-ddr5-5200-x2-1tssd-geforce-rtx5060-8gb-16-0-wuxga-ips-165hz-3ms-sin-s-o/
586	77	6	20260630	6	776.9900	USD	1.000000	776.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-hp-15-fd0276la-core-i7-1355u-16gb-ram-512gb-ssd-15-6/
587	77	6	20260630	6	826.9900	USD	1.000000	826.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-asus-vivobook-f1605va-ws74us-negro-core-i7-1355u-ram-16gb-ssd-512gb-16-wuxga-w11/
588	78	6	20260630	6	821.9900	USD	1.000000	821.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-dell-inspiron-dc15255-a117blk-pus-amd-ryzen-7-7730u-16gb-ram-512gb-ssd-15-6-fhd-touch-win-11-home-s-carbon-black-g8mk9/
589	79	6	20260630	6	685.9900	USD	1.000000	685.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-dell-15-dc15250-5315blk-pus-intel-core-i5-1334u-8gb-ram-512gb-ssd-15-6-fhd-touch-s-o-win-11-home-s-teclado-en-carbon-black-1xvhg/
590	52	6	20260630	6	3599.0000	USD	1.000000	3599.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/19683/
591	56	6	20260630	6	6499.0000	USD	1.000000	6499.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-pba-ryzen-9-9950x3d-x870-rtx-5090-32gb-ram-64gb-ssd-2tb-poweredbyasus/
592	80	6	20260630	6	629.0000	USD	1.000000	629.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/torre-cpu-pc-amd-ryzen-5-5600g-16gb-ddr4-ssd-500gb-fuente-case/
593	81	6	20260630	6	3490.0000	USD	1.000000	3490.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-torre-cpu-core-i9-14900k-z790-ssd-1tb-32gb-ddr5-rtx-4070-ti-super-16gb/
594	268	6	20260630	6	949.0000	USD	1.000000	949.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-torre-cpu-ryzen-7-8700g-a620-256gb-16gb/
595	82	6	20260630	6	2999.0000	USD	1.000000	2999.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-intel-core-i7-z790-1tb-32gb-ddr5-rtx-4070-ti-super-16gb/
596	81	6	20260630	6	627.9900	USD	1.000000	627.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i9-14900k-24-cores-32-hilos-8p16e-base-3-2ghz-turbo-6ghz-cache-36mb-lga1700-14th-gen/
597	83	6	20260630	6	752.9900	USD	1.000000	752.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-182/
598	84	6	20260630	6	377.9900	USD	1.000000	377.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-131/
599	34	6	20260630	6	853.9900	USD	1.000000	853.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-9-285k-24-cores-36mb-lga1851-graphics/
600	85	6	20260630	6	873.9900	USD	1.000000	873.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-9-285-24-cores-36mb-lga1851/
601	86	6	20260630	6	450.9900	USD	1.000000	450.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-7-265k-30mb-lga1851-20-cores-8p12e-graphics/
602	105	6	20260630	6	466.9900	USD	1.000000	466.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-5-245k-base-4-2ghz-26mb-159w-lga1851/
603	54	6	20260630	6	276.9900	USD	1.000000	276.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-5-225f-20mb-4-9ghz-lga1851-10-cores-65w-no-graphics/
604	106	6	20260630	6	688.9900	USD	1.000000	688.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-9800x3d-8-nucleos-16-hilos-4-7ghz-base-5-2ghz-turbo-am5-ddr5/
605	55	6	20260630	6	325.9900	USD	1.000000	325.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-8700f-turbo-5-00-ghz-8-cores-16-hilos-am5-65w-sin-graficos-incluye-cooler/
606	51	6	20260630	6	333.9900	USD	1.000000	333.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-9600x-am5-6-cores-12-thread-38mb-65w/
607	50	6	20260630	6	179.9900	USD	1.000000	179.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-8500g-base-3-5ghz-65w-am5-graficos-amd-radeon-740m-tray/
608	114	6	20260630	6	216.9900	USD	1.000000	216.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-5600xt-3-7-ghz-base-hasta-4-7ghz-65w-am4/
609	124	6	20260630	6	1370.9900	USD	1.000000	1370.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-9-9950x3d2-dual-edition-16-cores-32-hilos-am5-graficos-integrados/
610	56	6	20260630	6	999.9900	USD	1.000000	999.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-9-9950x3d-4-3ghz-turbo-5-7ghz-16-cores-32-hilos-am5-170w/
611	57	6	20260630	6	769.9900	USD	1.000000	769.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-9-9900x3d-4-4ghz-12-cores-24hilos-128mb-l3-cache-120w/
612	125	6	20260630	6	317.9900	USD	1.000000	317.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-9600-am5-6-cores-12-thread-turbo-5-2ghz-65w/
613	126	6	20260630	6	244.9900	USD	1.000000	244.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-5500x3d-3-0ghz-base-6-cores-12hilos-96mb-l3-cache-105w/
614	127	6	20260630	6	365.9900	USD	1.000000	365.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-9700f-3ghz-12mb-cache-lga1151/
615	82	6	20260630	6	494.9900	USD	1.000000	494.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-14700kf-20-cores-28-hilos-8p12e-base-3-4ghz-turbo-5-4ghz-cache-33mb-lga1700-14th-gen-no-graphics/
616	123	6	20260630	6	575.9900	USD	1.000000	575.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-10700k/
617	128	6	20260630	6	462.9900	USD	1.000000	462.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-13600kf-14-cores-20-hilos-6p8e-base-3-5ghz-turbo-5-1ghz-cache-24mb-lga1700-13th-gen-no-graphics/
618	130	6	20260630	6	151.9900	USD	1.000000	151.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-9750h-srf6u-para-laptop/
619	131	6	20260630	6	535.9900	USD	1.000000	535.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-13700f-13th-lga-1700-2-10ghz-hasta-5-20ghz-24m-65w-16-cores-bx8071513700f/
620	132	6	20260630	6	583.9900	USD	1.000000	583.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-13700-13th-lga-1700-2-10ghz-hasta-5-20ghz-30m-8-cores-16-nucleos/
621	133	6	20260630	6	309.9900	USD	1.000000	309.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-13400f-2-50ghz-base-65w-10-nucleos-bx8071513400f/
622	134	6	20260630	6	284.9900	USD	1.000000	284.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-13400-4-6ghz-20mb-lga1700-13th-gen/
623	135	6	20260630	6	204.9900	USD	1.000000	204.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-12400-4-4ghz-18mb-lga1700-12th-gen-tray-sin-caja/
624	136	6	20260630	6	175.9900	USD	1.000000	175.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i3-14100-3-5ghz-14th-lga1700-4-cores/
625	137	6	20260630	6	220.9900	USD	1.000000	220.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i3-13100-3-40ghz-13th-lga1700-4-cores-12mb-cache/
626	119	6	20260630	6	543.9900	USD	1.000000	543.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-9-7900x-4-7ghz-base-12-cores-24-hilos-am5-170w/
627	5	6	20260630	6	473.9900	USD	1.000000	473.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-5050-8gb-gddr6-oc-edition-windforce-2x-hdmi-dp-gv-n5050wf2ocv2-8gdg10/
628	116	6	20260630	6	366.9900	USD	1.000000	366.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gigabyte-gv-r76gaming-oc-8gd-g11/
629	16	6	20260630	6	553.9900	USD	1.000000	553.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gigabyte-gv-n5060wf2maxoc/
630	121	6	20260630	6	513.9900	USD	1.000000	513.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-amd-radeon-rx-7600-xt-16gb-gddr6-gaming-oc-windforce-raytracing-3-fans-hdmi-dp-gv-r76xtgaming-oc-16gd/
631	43	6	20260630	6	776.9900	USD	1.000000	776.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-amd-radeon-rx-9060-xt-16gb-gddr6-gaming-oc-windforce-3-fans-hdmi-dp-gv-r9060xtgaming-oc-16gd/
632	27	6	20260630	6	320.9900	USD	1.000000	320.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-msi-ventus-2x-rtx-3050-6gb-gddr6-oc-hdmi-dp-pcie-4-0-ray-tracing-dlss-912-v812-060/
633	29	6	20260630	6	519.9900	USD	1.000000	519.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-msi-geforce-rtx-5060-8g-ventus-3x-oc-edition-8gb-gddr7-hdmi-2-1b-dp-v2-1b-912-v537-036/
634	37	6	20260630	6	1499.9900	USD	1.000000	1499.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-5070ti-gaming-oc-16gb-gddr7-dp-2-1b-hdmi-2-1b-black-gv-n507tgaming-oc-16gd/
635	26	6	20260630	6	427.9900	USD	1.000000	427.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-aorus-extreme-amd-radeon-rx-6900xt-16gb-gddr6-4k-uhd-pci-e-4-0-waterblock-dp-1-4-with-dsc-hdmi-2-1-vrr-aorus-robot-xtreme-gv-r69xtaorusx-wb-16gd/
636	6	6	20260630	6	997.9900	USD	1.000000	997.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-prime-geforce-rtx-5070-12gb-gddr7-oc-edition-hdmi-2-1b-dp-2-1b-pci-e-5-0-black-prime-rtx5070-o12g/
637	277	6	20260630	6	63.9900	USD	1.000000	63.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-geforce-gt710-2gb-gddr5-hdmi-d-sub-dvi-d-gt710-sl-2gd5-brk-evo/
638	6	6	20260630	6	981.9900	USD	1.000000	981.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-5070-12gb-gddr7-oc-edition-hdmi-dp-black-dual-rtx5070-o12g/
639	5	6	20260630	6	443.9900	USD	1.000000	443.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-5050-8gb-gddr6-oc-edition-hdmi-dp-black-dual-rtx5050-o8g/
640	27	6	20260630	6	311.9900	USD	1.000000	311.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-3050-6gb-gddr6-oc-edition-dp-hdmi-dvi-d-dual-rtx3050-o6g/
641	16	6	20260630	6	550.9900	USD	1.000000	550.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-5060-eagle-max-oc-8gb-gddr7-oc-edition-windforce-dp-2-1b-hdmi-2-1b-black-gv-n5060eaglemax-oc-8gd/
642	38	6	20260630	6	853.9900	USD	1.000000	853.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-5060ti-16gb-gddr7-oc-edition-pcie-5-0-hdmi-dp-dual-rtx5060ti-o16g-evo/
643	38	6	20260630	6	730.9900	USD	1.000000	730.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-5060ti-16gb-gddr7-oc-edition-pcie-5-0-hdmi-dp-dual-rtx5060ti-o16g/
644	4	6	20260630	6	556.9900	USD	1.000000	556.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-5060-8gb-gddr7-oc-edition-dp-hdmi-dual-rtx5060-o8g/
645	39	6	20260630	6	4518.9900	USD	1.000000	4518.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/asus-rog-astral-rtx5090-o32g-gaming/
646	27	6	20260630	6	336.9900	USD	1.000000	336.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-3050-6gb-gddr6-oc-edition-windforce-hdmi-dp-gv-n3050wf2oc-6gd/
647	40	6	20260630	6	280.9900	USD	1.000000	280.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-phoenix-geforce-gtx-1630-4gb-gddr6-auto-extreme-hdmi-dp-dvi-d-ph-gtx1630-4g/
648	361	6	20260630	6	88.9900	USD	1.000000	88.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-gt-710-2gb-gv-n710d3-2gl-rev2-0/
649	360	6	20260630	6	727.9900	USD	1.000000	727.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-capturadora-de-video-blackmagic-design-decklink-duo-2-4ch-sdi-tarjeta-de-reproduccion-y-captura-bmd-bdlkduo2/
650	41	6	20260630	6	987.9900	USD	1.000000	987.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-msi-thin-15-b13udx-3085xec/
651	4	6	20260630	6	2566.9900	USD	1.000000	2566.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-rog-strix-g16-g614pm-rv038-amd-ryzen-r9-8940hx-32gb-16gb-ddr5-5200-x2-1tssd-geforce-rtx5060-8gb-16-0-wuxga-ips-165hz-3ms-sin-s-o/
652	25	6	20260630	6	3490.0000	USD	1.000000	3490.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-torre-cpu-core-i9-14900k-z790-ssd-1tb-32gb-ddr5-rtx-4070-ti-super-16gb/
653	6	6	20260630	6	2999.0000	USD	1.000000	2999.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-intel-core-i7-z790-1tb-32gb-ddr5-rtx-4070-ti-super-16gb/
654	8	6	20260630	6	19999.0000	USD	1.000000	19999.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ia-workstation-9960x-dual-rtx-5090-128gb/
655	3	6	20260630	6	1335.9900	USD	1.000000	1335.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-lenovo-log-q-amd-ryzen-7-7735hs-16gb-ram-512gb-ssd-geforce-rtx4050-15-6-fhd-144hz-w11h-luna-gray-83d0000lec/
656	4	6	20260630	6	2699.0000	USD	1.000000	2699.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mini-pc-asus-rog-nuc-15-ultra-7-255hx-32gb-ddr5-1tb-ssd-rtx-5060-8gb-win11h/
657	5	6	20260630	6	1805.9900	USD	1.000000	1805.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-asus-tuf-a16-fa608uh-rv063/
658	6	6	20260630	6	3599.0000	USD	1.000000	3599.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/19683/
659	7	6	20260630	6	2166.9900	USD	1.000000	2166.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/msi-geforce-rtx-5080-16g-inspire-3x/
660	8	6	20260630	6	3503.9900	USD	1.000000	3503.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gigabyte-gv-n5090wf3oc-32gd/
661	348	6	20260630	6	140.9900	USD	1.000000	140.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gpu-gigabyte-geforce-gt-1030/
662	347	6	20260630	6	94.9900	USD	1.000000	94.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gpu-asus-geforce-gt-710/
663	4	6	20260630	6	486.9900	USD	1.000000	486.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-msi-shadow-2x-geforce-rtx-5060-8gb-gddr7-oc-edition-gddr7-hdmi-dp-black-912-v537-038/
664	9	6	20260630	6	838.9900	USD	1.000000	838.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-msi-geforce-rtx-5060ti-16g-ventus-2x-oc-plus-16gb-gddr7-dp-hdmi-2-fan-hdmi-dp-black-912-v537-017/
665	10	6	20260630	6	2117.9900	USD	1.000000	2117.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-5080-gaming-oc-16gb-gddr7-hdmi-2-1b-dp-1-4b-gv-n5080gaming-oc-16gd/
666	11	6	20260630	6	850.9900	USD	1.000000	850.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-5060ti-eagle-max-oc-16gb-gddr7-oc-edition-dp-2-1b-hdmi-2-1b-black-gv-n5060tieaglemax-oc-16gd/
667	2	6	20260630	6	478.9900	USD	1.000000	478.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-4060-8gb-gddr6-windforce-oc-edition-hdmi-2-1a-dp-1-4a-gv-n4060wf2oc-8gd/
668	12	6	20260630	6	1404.9900	USD	1.000000	1404.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-geforce-rtx-4070-ti-super-btf-white-edition-16gb-gddr6x-hdmi-dp-tuf-rtx4070s-o16g-bft-white/
669	13	6	20260630	6	660.9900	USD	1.000000	660.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-proart-geforce-rtx-4060ti-16gb-gddr6-advanced-edtion-hdmi-2-1a-dp-1-4a-black-proart-rtx4060ti-a-16g/
670	14	6	20260630	6	917.9900	USD	1.000000	917.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-4070-super-12gb-gddr6x-oc-edition-hdmi-dp-dual-rtx4070s-o12g/
671	15	6	20260630	6	1404.9900	USD	1.000000	1404.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-prime-rtx-5070-ti-16gb-gddr7-prime-rtx5070ti-o16g/
672	389	6	20260630	6	2999.9900	USD	1.000000	2999.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-profesional-asus-turbo-amd-radeon-ai-pro-r9700-32gb-gddr6-turbo-ai-pro-r9700-32g/
673	16	6	20260630	6	525.9900	USD	1.000000	525.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-aorus-elite-geforce-rtx-5060-8gb-gddr7-3-ventiladores-black-gv-n5060aorus-e-8gd/
674	4	6	20260630	6	513.9900	USD	1.000000	513.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-prime-geforce-rtx-5060-8gb-gddr7-oc-edition-hdmi-dp-prime-rtx5060-o8g/
675	17	6	20260630	6	3478.9900	USD	1.000000	3478.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-gaming-rtx5090-32gb-gddr7-pcie-5-0-dp-hdmi-black-tuf-rtx5090-32g-gaming/
676	18	6	20260630	6	614.9900	USD	1.000000	614.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-4060-ti-oc-edition-8gb-gddr6-hdmi-dp-dual-rtx4060ti-o8g/
677	19	6	20260630	6	305.9900	USD	1.000000	305.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-msi-geforce-rtx-3050-8gb-gddr6-ventus-2x-xs-dp-hdmi-dvi-d-912-v809-4266/
678	20	6	20260630	6	2380.9900	USD	1.000000	2380.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-4090-gaming-oc-edition-24gb-gddr6x-dp-1-4-hdmi-2-1-pci-e-4-0-gv-n4090gaming-oc-24gd/
679	21	6	20260630	6	2068.9900	USD	1.000000	2068.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-aorus-master-geforce-rtx-4080-16gb-gddr6x-rev-1-0-oc-edition-windforce-dlss-ray-tracing-reflex-studio-dp-hdmi-gv-n4080aorus-m-16gd/
680	22	6	20260630	6	1199.9900	USD	1.000000	1199.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-gaming-geforce-rtx-4070ti-12gb-gddr6x-hdmi-2-1a-dp-1-4a-argb-black-tuf-rtx4070ti-12g-gaming/
681	23	6	20260630	6	1104.9900	USD	1.000000	1104.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-gaming-geforce-rtx-4070-ti-12gb-gddr6x-oc-edition-tuf-rtx4070ti-o12g-gaming/
682	24	6	20260630	6	3054.9900	USD	1.000000	3054.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-rog-strix-geforce-rtx-4090-24gb-gddr6x-oc-edition-rog-strix-rtx4090-o24g-gaming/
683	14	6	20260630	6	929.9900	USD	1.000000	929.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-4070-super-evo-oc-12gb-gddr6x-dp-hdmi-black-90yv0kc0-m0na00/
684	2	6	20260630	6	498.9900	USD	1.000000	498.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-4060-8gb-gddr6-oc-edition-gpu-tweak-iii-dlss-3-hdmi-dp-dual-rtx4060-o8g-white/
685	2	6	20260630	6	455.9900	USD	1.000000	455.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-4060-8gb-gddr6-oc-edition-gpu-tweak-iii-dlss-3-hdmi-dp-dual-rtx4060-o8g-evo/
686	19	6	20260630	6	476.9900	USD	1.000000	476.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-eagle-geforce-rtx-3050-8gb-oc-hdmi-2-1-dp-1-4a-gv-n3050eagle-oc-8gd/
687	21	6	20260630	6	2166.9900	USD	1.000000	2166.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-gaming-geforce-rtx-4080-16gb-gddr6x-oc-edition-dlss-reflex-ray-tracing-dp-1-4a-hdmi-2-1a-tuf-rtx4080-o16g-gaming/
688	21	6	20260630	6	2396.9900	USD	1.000000	2396.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-rog-strix-gaming-geforce-rtx-4080-16gb-gddr6x-oc-edition-dlss-ray-tracing-reflex-dp-1-4a-hdmi-2-1a-rog-strix-rtx4080-o16g-gaming/
689	397	6	20260630	6	121.9900	USD	1.000000	121.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-geforce-gt730-2gb-gddr5-auto-extreme-0db-silent-4-hdmi-gt730-4h-sl-2gd5/
690	396	6	20260630	6	222.9900	USD	1.000000	222.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-afox-rx-550-4gb-gddr5-hdmi-dp-dvi-d/
691	61	6	20260630	6	476.9900	USD	1.000000	476.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-windforce-rtx-3050-oc-8gb-gv-n3050gaming-oc-8gd/
692	61	6	20260630	6	727.9900	USD	1.000000	727.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-rog-strix-rtx-3050-oc-8gb-rog-strix-rtx3050-o8g-gaming/
693	61	6	20260630	6	645.9900	USD	1.000000	645.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-zotac-geforce-rtx-3050-8gb-gddr6-twin-edge-dp-1-4a-hdmi-2-1-zt-a30500e-10m/
694	392	6	20260630	6	45.9900	USD	1.000000	45.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-biostar-g210-1gb-ddr3-hdmi-dvi-vga-vn2103nhg6-sbarl-bs2/
695	19	6	20260630	6	449.9900	USD	1.000000	449.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-3050-dual-gddr6-oc-edition-dp-hdmi-dual-rtx3050-o8g/
696	391	6	20260630	6	100.9900	USD	1.000000	100.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-gt-1030-2gb-ddr4-low-profile-gv-n1030d4-2gl/
697	62	6	20260630	6	721.9900	USD	1.000000	721.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-radeon-rx-580-8gb-oc-edition-dual-rx580-o8g/
698	390	6	20260630	6	39.9900	USD	1.000000	39.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gpu-msi-geforce-n210/
699	4	6	20260630	6	1885.9900	USD	1.000000	1885.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-asus-rog-strix-g16-g614pm-rv039-ryzen-r9-8940hx-16gb-1tb-rtx-5060-8gb-16-165hz-mochilamouse/
700	63	6	20260630	6	1450.9900	USD	1.000000	1450.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-rx-6700xt-12gb-oc-edition-gddr6-90yv0g80-m0aa00/
701	64	6	20260630	6	987.9900	USD	1.000000	987.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-tuf-gaming-a15-fa506nc-hn016-ryzen-5-7535hs-16gb-ddr5-512gb-ssd-geforce-rtx-3050-4g-15-6-fhd-wv-sin-s-o-graphite-black/
702	386	6	20260630	6	225.9900	USD	1.000000	225.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-8gb-ddr5-5600mt-s-cl40-black-kf556c40bb-8/
703	385	6	20260630	6	156.9900	USD	1.000000	156.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-corsair-vengeance-lpx-8gb-a-3200mhz/
704	384	6	20260630	6	475.9900	USD	1.000000	475.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-193/
705	383	6	20260630	6	164.9900	USD	1.000000	164.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-ddr4-kingston-fury-8gb-3200mhz-kvr32n22s8-8-kvr32n22s6-8/
706	382	6	20260630	6	281.9900	USD	1.000000	281.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-ddr4-so-dimm-kingston-fury-impact-32gb-3200mhz-kf432s20ib-32/
707	381	6	20260630	6	47.9900	USD	1.000000	47.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-8gb-ddr3-1600mhz-dimm-valueram-kvr16n11-8/
708	380	6	20260630	6	318.9900	USD	1.000000	318.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-ddr5-5200mhz-cl40-kf552c40bb-16/
709	379	6	20260630	6	253.9900	USD	1.000000	253.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-rgb-ddr4-3600mhz-cl18-black-kf436c18bba-16/
710	378	6	20260630	6	326.9900	USD	1.000000	326.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-ddrr5-5600mhz-cl40-black-kf556c40bb-16/
711	377	6	20260630	6	269.9900	USD	1.000000	269.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-corsair-vengeance-rgb-rs-8gb-3200mhz-ddr4-cl16-black-cmg8gx4m1e3200c16/
712	220	6	20260630	6	19999.0000	USD	1.000000	19999.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ia-workstation-9960x-dual-rtx-5090-128gb/
713	376	6	20260630	6	463.9900	USD	1.000000	463.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-rgb-32gb-ddr5-5600mt-s-cl40-dimm-kf556c40bba-32/
714	303	6	20260630	6	957.9900	USD	1.000000	957.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-lenovo-ideapad-3-15irh10-intel-core-i5-13420h-8gb-ram-on-board-512gb-ssd-15-3-wuxga-1920x1200-luna-gray-83k1007plm/
715	302	6	20260630	6	1335.9900	USD	1.000000	1335.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-lenovo-log-q-amd-ryzen-7-7735hs-16gb-ram-512gb-ssd-geforce-rtx4050-15-6-fhd-144hz-w11h-luna-gray-83d0000lec/
716	301	6	20260630	6	306.9900	USD	1.000000	306.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-194/
717	289	6	20260630	6	1805.9900	USD	1.000000	1805.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-asus-tuf-a16-fa608uh-rv063/
718	280	6	20260630	6	987.9900	USD	1.000000	987.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-msi-thin-15-b13udx-3085xec/
719	244	6	20260630	6	897.9900	USD	1.000000	897.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-vivobook-m1607ka-mb110-amd-ryzen-ai-7-350-16gb-ram-on-board-1tb-ssd-16-0-wuxga-wv-sin-s-o-kb-es-1b-quiet-blue/
720	281	6	20260630	6	776.9900	USD	1.000000	776.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-hp-15-fd0276la-core-i7-1355u-16gb-ram-512gb-ssd-15-6/
721	282	6	20260630	6	826.9900	USD	1.000000	826.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-asus-vivobook-f1605va-ws74us-negro-core-i7-1355u-ram-16gb-ssd-512gb-16-wuxga-w11/
722	223	6	20260630	6	2359.0000	USD	1.000000	2359.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-desktop-servidor-intel-ultra-9-285k-8-32gb-ddr5-raid-2x1tb-ssd/
723	283	6	20260630	6	1419.9900	USD	1.000000	1419.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/nas-qnap-ts-473a-8g/
724	404	6	20260630	6	1154.9900	USD	1.000000	1154.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-gaming-hp-victus-15-fb3019la-amd-ryzen-7-7445h-8gb-ram-512ssd-15-6-fhd-geforce-rtx3050-6g-s-o-freedos-black-bt4f6laabm/
725	286	6	20260630	6	2147.9900	USD	1.000000	2147.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-v16-v3607vp-rp030-intel-core-ultra-7-240h-1tb-ssd-32gb-ram-geforce-rtx-5070-8g-gddr7-16-wuxga-1920x1200-sin-s-o-black-mochila-y-mouse/
726	287	6	20260630	6	629.0000	USD	1.000000	629.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/torre-cpu-pc-amd-ryzen-5-5600g-16gb-ddr4-ssd-500gb-fuente-case/
727	288	6	20260630	6	2344.9900	USD	1.000000	2344.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-gigabyte-a16-r7-260-rtx5070/
728	222	6	20260630	6	1629.0000	USD	1.000000	1629.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-desktop-workstation-intel-ultra-7-270k-plus-tuf-b860-32gb-ddr5-1tb-ssd-wifi-case-solido-copia/
729	221	6	20260630	6	1919.0000	USD	1.000000	1919.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-u7-265kf-tuf-b860-32gb-1tb-rtx5050-wifi-case-solido/
730	306	6	20260630	6	2699.0000	USD	1.000000	2699.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mini-pc-asus-rog-nuc-15-ultra-7-255hx-32gb-ddr5-1tb-ssd-rtx-5060-8gb-win11h/
731	307	6	20260630	6	3599.0000	USD	1.000000	3599.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/19683/
732	308	6	20260630	6	3490.0000	USD	1.000000	3490.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-torre-cpu-core-i9-14900k-z790-ssd-1tb-32gb-ddr5-rtx-4070-ti-super-16gb/
733	268	6	20260630	6	949.0000	USD	1.000000	949.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-torre-cpu-ryzen-7-8700g-a620-256gb-16gb/
734	337	6	20260630	6	2999.0000	USD	1.000000	2999.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-intel-core-i7-z790-1tb-32gb-ddr5-rtx-4070-ti-super-16gb/
735	336	6	20260630	6	51.9900	USD	1.000000	51.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-kingston-8gb-ddr3l-1600mhz-so-dimm-kvr16ls11-8/
736	335	6	20260630	6	72.9900	USD	1.000000	72.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-ddr4-kingston-fury-8gb-2666mhz/
737	334	6	20260630	6	152.9900	USD	1.000000	152.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-ddr4-kingston-fury-16gb-3200mhz-hx432c16fb4-16/
738	333	6	20260630	6	120.9900	USD	1.000000	120.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-ddr4-xpg-spectrix-d50-rgb-8gb-3000mhz-ax4u30008g16a-st50/
739	332	6	20260630	6	76.9900	USD	1.000000	76.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-8gb-ddr4-3200mhz-so-dimm-cl22-kvr32s22s8-8/
740	331	6	20260630	6	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-8gb-ddr3-1600mhz-ecc-1-5v-para-servidor-kvr16r11d4-8hc/
741	330	6	20260630	6	128.9900	USD	1.000000	128.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-kingston-16gb-a-3200mhz-so-dimm/
742	329	6	20260630	6	132.9900	USD	1.000000	132.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-16gb-ddr4-3200mhz-dimm-cl22-kvr32n22d8-16/
743	328	6	20260630	6	221.9900	USD	1.000000	221.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-corsair-vengeance-rgb-pro-16gb-a-3200mhz/
744	327	6	20260630	6	39.9900	USD	1.000000	39.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-impact-8gb-ddr4-3200mhz-so-dimm-cl20-kf432s20ib-8/
745	326	6	20260630	6	108.9900	USD	1.000000	108.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-ddr5-4800mhz-cl38-black-kf548c38bbk2-32/
746	325	6	20260630	6	261.9900	USD	1.000000	261.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-ddr5-4800mhz-cl38-black-kf548c38bb-16/
747	324	6	20260630	6	67.9900	USD	1.000000	67.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-corsair-vengeance-lpx-8gb-a-3600mhz/
748	323	6	20260630	6	116.9900	USD	1.000000	116.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-corsair-vengeance-lpx-16gb-a-3600mhz/
749	309	6	20260630	6	43.9900	USD	1.000000	43.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-corsair-vengeance-lpx-ddr4-8gb-3000mhz-cmk8gx4m1d3000c16/
750	322	6	20260630	6	148.9900	USD	1.000000	148.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-corsair-vengeance-lpx-ddr4-16gb-3000mhz-cmk16gx4m1b3000c15/
751	321	6	20260630	6	314.9900	USD	1.000000	314.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-corsair-vengeance-16gb-ddr5-4800mhz-cl40-black-cmk32gx5m2a4800c40/
752	320	6	20260630	6	63.9900	USD	1.000000	63.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-16gb-ddr4-2666mhz-dimm-valueram-kvr26n19d8-16/
753	319	6	20260630	6	96.9900	USD	1.000000	96.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-hyperx-fury-rgb-8gb-ddr4-2666mhz-hx426c16fb3a-8/
754	318	6	20260630	6	104.9900	USD	1.000000	104.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ssd-corsair-force-mp510-240gb-nvme-pcie/
755	317	6	20260630	6	92.9900	USD	1.000000	92.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ssd-adata-su630-480gb-2-5/
756	316	6	20260630	6	35.9900	USD	1.000000	35.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-kingston-value-8gb-a-2666mhz-so-dimm/
757	315	6	20260630	6	209.9900	USD	1.000000	209.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hyperx-fury-rgb-16gb-a-3000mhz/
758	314	6	20260630	6	112.9900	USD	1.000000	112.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hyperx-fury-rgb-a-3000mhz/
759	313	6	20260630	6	80.9900	USD	1.000000	80.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hp-v6-8gb-a-3200mhz/
760	223	6	20260630	6	2359.0000	USD	1.000000	2359.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/pc-desktop-servidor-intel-ultra-9-285k-8-32gb-ddr5-raid-2x1tb-ssd/
761	312	6	20260630	6	176.9900	USD	1.000000	176.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-ultragear-24g411a-b/
762	311	6	20260630	6	465.9900	USD	1.000000	465.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-rog-strix-xg27acmes/
763	310	6	20260630	6	281.9900	USD	1.000000	281.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-tuf-vg259qm5a/
764	354	6	20260630	6	71.9900	USD	1.000000	71.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/docking-station-anker-8-en-1-dual-monitor-usb-c-hdmi-ethernet-power-85w-usb-3-0/
765	210	6	20260630	6	316.9900	USD	1.000000	316.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs27qa/
929	232	6	20260630	6	191.9900	USD	1.000000	191.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-corsair-hs60-haptic/
766	279	6	20260630	6	28.9900	USD	1.000000	28.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/stand-marvo-para-monitor-dz-01-rgb-4-port-usb-touch-black/
767	278	6	20260630	6	53.9900	USD	1.000000	53.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-para-dos-monitores-kmm-510-con-regleta-integrada-y-puertos-usb/
768	290	6	20260630	6	109.9900	USD	1.000000	109.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-huanuo-2-brazos-vertical-para-monitores-de-13-a-32-hnhm2/
769	291	6	20260630	6	79.9900	USD	1.000000	79.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-brazo-para-2-monitores-teros-te-7114-hasta-32-soporta-12kg/
770	292	6	20260630	6	349.9900	USD	1.000000	349.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/simulador-racing-pedestal-para-monitor-qfrs01-01a/
771	293	6	20260630	6	86.9900	USD	1.000000	86.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-acer-k202q-19-5/
772	294	6	20260630	6	78.9900	USD	1.000000	78.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-1916s-19-5-1600x900-5ms-75hz-hdmi-vga/
773	295	6	20260630	6	346.9900	USD	1.000000	346.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-msi-gaming-mag-275qf-27-wqhd-2560x1440-ips-180hz-0-5ms-gtg-hdmi-dp-black-9s6-3ce21m-014/
774	296	6	20260630	6	352.9900	USD	1.000000	352.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-29u511a-b-ultrawide-29-ips-2560x1080-hdmi-100hz-srgb-99-5ms-gtg/
775	297	6	20260630	6	72.9900	USD	1.000000	72.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-portatil-env-15-6-fhd-ips-ultrafino-usb-c-black/
776	298	6	20260630	6	191.9900	USD	1.000000	191.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2415s-24-gaming-plano-ips-fhd-120hz-1ms-dp-hdmi-vga/
777	299	6	20260630	6	310.9900	USD	1.000000	310.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-empresarial-asus-va279qgs-27-ips-fhd-1920x1080-120hz-1ms-hdmi-dp-vga-usb-black/
778	300	6	20260630	6	132.9900	USD	1.000000	132.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-portatil-acer-pm1-15-6-fhd-6ms-ultrafino-mini-hdmi-usb-c-black-pm161q/
779	304	6	20260630	6	396.9900	USD	1.000000	396.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-msi-mag-274qf-x24-27-wqhd-2560x1440-fast-ips-0-5ms-240hz-hdmi-dp-black-9s6-3ce41h-020/
780	305	6	20260630	6	342.9900	USD	1.000000	342.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-samsung-gaming-odyssey-g3-27-fhd-180hz-dp-hdmi-black/
781	338	6	20260630	6	259.9900	USD	1.000000	259.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-xiaomi-g24i-23-8-fhd-1920x1080-180hz-1ms-gtg-hdmi-dp-black-p24fca-rggl/
782	339	6	20260630	6	840.9900	USD	1.000000	840.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-mo27q28g-ga1-27-woled-2560x1440p-280hz-anti-reflection-0-03ms-gtg-hdr-true-black-500-hdmi-dp/
783	340	6	20260630	6	428.9900	USD	1.000000	428.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs32q-32-qhd-2560x1440-ss-ips-165hz-non-glare-ods-low-blue-light-hdmi-dp/
784	373	6	20260630	6	467.9900	USD	1.000000	467.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-m27q2-ice-sa1-27-qhd-2560x1440p-ss-ips-1ms-gtg-200hz-oc-210hz-hdr400-non-glare-hdmi-dp-white/
785	375	6	20260630	6	239.9900	USD	1.000000	239.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs25f2-25-24-5-fhd-1920x1080-200hz-non-glare-speaker-osd-low-blue-light-dci-p3-hdmi-dp/
786	387	6	20260630	6	269.9900	USD	1.000000	269.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs27fa-27-fhd-1920x1080-ss-ips-180hz-non-glare-ods-low-blue-light-hdmi-1dp/
787	374	6	20260630	6	965.9900	USD	1.000000	965.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-m28u-sa-28-superspeed-ips-4k-uhd-2ms-mprt-144hz-hdmi-2-1-dp-1-4-usb-c-black/
788	388	6	20260630	6	267.9900	USD	1.000000	267.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs25f2a/
789	393	6	20260630	6	1762.9900	USD	1.000000	1762.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-msi-mpg-491cqp-qd-oled-49/
790	394	6	20260630	6	170.9900	USD	1.000000	170.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-indurama-vortix-nova-27-fhd-ips-120hz-5ms-hdmidp-black-27mmnavn/
791	395	6	20260630	6	156.9900	USD	1.000000	156.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-indurama-vortix-nova-25/
792	398	6	20260630	6	235.9900	USD	1.000000	235.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-va249hg-eye-care-23-8-fhd-1920x1080-120hz-99-srgb-1ms-mprt-hdmi-vga-black/
793	399	6	20260630	6	368.9900	USD	1.000000	368.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-proart-pa248qfv-24-ips-wuxga-1920x1080-100hz-hdr-10-dp-hdmi-usb-black/
794	400	6	20260630	6	253.9900	USD	1.000000	253.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-va279hg/
795	401	6	20260630	6	94.9900	USD	1.000000	94.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-20u401a-b-19-5-1600x900-hdmi-vga/
796	402	6	20260630	6	136.9900	USD	1.000000	136.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-indurama-vortix-core-22/
797	403	6	20260630	6	566.9900	USD	1.000000	566.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-samsung-ls24a608ucn-24-wqhd-2560x1440-ultra-thin-5ms-75hz-hdmi-dp/
798	372	6	20260630	6	638.9900	USD	1.000000	638.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-proart-pa279crv-27-4k-uhd-3840x2160-99-dci-p3-99-adobe-rgb-dispalyhdr-400-dp-hdmi-type-c-usb-3-2/
799	356	6	20260630	6	497.9900	USD	1.000000	497.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gaming-zowie-xl2731k-27-fhd-165hz-dyac-320-nits-tn-hdmi2-0-dp-1-2-9h-lkclb-qbl/
800	371	6	20260630	6	44.9900	USD	1.000000	44.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-brazo-para-monitores-klip-xtreme-kpm-310/
801	342	6	20260630	6	43.9900	USD	1.000000	43.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-klip-xtreme-kmm-400-para-monitores-13-27/
802	343	6	20260630	6	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-klip-xtreme-kmm-301-para-monitor-y-laptop/
803	344	6	20260630	6	350.9900	USD	1.000000	350.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-22mn430h-b/
804	345	6	20260630	6	337.9900	USD	1.000000	337.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-5-250k-plus-turbo-5-3ghz-18-cores-lga1851/
805	302	6	20260630	6	1335.9900	USD	1.000000	1335.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-lenovo-log-q-amd-ryzen-7-7735hs-16gb-ram-512gb-ssd-geforce-rtx4050-15-6-fhd-144hz-w11h-luna-gray-83d0000lec/
806	346	6	20260630	6	382.9900	USD	1.000000	382.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/case-corsair-4000d-lcd-blaci/
807	349	6	20260630	6	220.9900	USD	1.000000	220.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-8400f-6-cores-4-7-ghz-turbo-65w-am5-sin-graficos/
808	350	6	20260630	6	748.9900	USD	1.000000	748.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-9850x3d-4-7ghz-8-cores-16-hilos-96mb-am5-120w/
809	351	6	20260630	6	213.9900	USD	1.000000	213.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-ultragear-27g411a/
810	352	6	20260630	6	45.9900	USD	1.000000	45.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-brazo-klip-xtreme-kmm-410-con-mecanismo-de-resorte-para-2-monitores-13-32-4-4-17-6lb-vesa/
811	353	6	20260630	6	209.9900	USD	1.000000	209.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-zenscreen-mb166c/
812	276	6	20260630	6	620.9900	USD	1.000000	620.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-m27up-ice/
813	341	6	20260630	6	76.9900	USD	1.000000	76.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-xtratech-xtm19-19-5-hd-1600x900-entradas-hdmi-y-vga/
814	355	6	20260630	6	247.9900	USD	1.000000	247.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-samsung-gaming-essential-s3-s36gd-27-fhd-1920x1080-100hz-4ms-d-sub-hdmi-black-s27d366gan/
815	357	6	20260630	6	245.9900	USD	1.000000	245.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2787g-27-fhd-curvo-180hz-2ms-dp-hdmi/
816	358	6	20260630	6	354.9900	USD	1.000000	354.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gaming-msi-mag-275cqf-e18-27-wqhd-2k2560x1440-curvo-180hz-0-5ms-gtg-hdr-ready-hdmi-2-0b-dp-1-4a-black-9s6-3ce91h-004/
817	359	6	20260630	6	400.9900	USD	1.000000	400.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-ultragear-27gs65f-b-27-fhd-ips-180hz-1ms-hdr10-g-sync-freesync-black/
818	362	6	20260630	6	211.9900	USD	1.000000	211.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs24f14-24-ips-fhd-144hz-1ms/
819	363	6	20260630	6	394.9900	USD	1.000000	394.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-indurama-vortix-ultra-32/
820	364	6	20260630	6	227.9900	USD	1.000000	227.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-vp227he-21-45-fhd-75hz-non-glare-va-5ms-gtg-hdmi-v1-4-vga-black/
821	365	6	20260630	6	356.9900	USD	1.000000	356.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-tuf-gaming-vg279q1a-27-fhd-1920x1080p-panel-ips-non-glare-1ms-mprt-165hz-freesync-premium-dp-1-2-hdmi-v1-4/
822	366	6	20260630	6	334.9900	USD	1.000000	334.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-256/
823	367	6	20260630	6	443.9900	USD	1.000000	443.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-167/
824	368	6	20260630	6	574.9900	USD	1.000000	574.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-88/
825	369	6	20260630	6	846.9900	USD	1.000000	846.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-87/
826	370	6	20260630	6	441.9900	USD	1.000000	441.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-84/
827	284	6	20260630	6	903.9900	USD	1.000000	903.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-pa329cvr/
828	259	6	20260630	6	1508.9900	USD	1.000000	1508.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-82/
829	275	6	20260630	6	336.9900	USD	1.000000	336.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-touch-sat-1053fph-15-1024-x-768px-multi-touch-3-puntos-hdmi-vga-usb/
830	159	6	20260630	6	199.9900	USD	1.000000	199.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2123s-21-45-fhd-ips-1ms-100hz-hdmi-vga-black/
831	158	6	20260630	6	320.9900	USD	1.000000	320.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gaming-msi-g2712f-27-fhd-ips-180-hz-1ms-300-nits-dp-hdmi-black/
832	157	6	20260630	6	602.9900	USD	1.000000	602.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-tuf-vg289q/
833	160	6	20260630	6	499.9900	USD	1.000000	499.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-proart-pa247cv-23-8-full-hd-ips-100-srgb-75hz-5ms-dp-hdmi-usb-c-black-90lm03y1-b013b0/
834	161	6	20260630	6	257.9900	USD	1.000000	257.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2711s-27-fhd-100hz-1ms-ips-hdmi/
835	176	6	20260630	6	217.9900	USD	1.000000	217.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2411s-gaming-24-1920x1080-1ms-200-nits-100hz-hdmi-vga/
836	164	6	20260630	6	215.9900	USD	1.000000	215.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2401s-23-8-curvo-r3000-va-fhd-5ms-100hz-hdmi-vga-black/
837	177	6	20260630	6	207.9900	USD	1.000000	207.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2124s-21-45-fhd-ips-100hz-5ms-plano-hdmi-vga-black/
838	179	6	20260630	6	69.9900	USD	1.000000	69.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-1914s-19-5-1600x900-5ms-220-nits-hdmi-vga/
839	208	6	20260630	6	590.9900	USD	1.000000	590.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-samsung-ur55-28-uhd-ips-hdr10-4ms-60hz-hdmi-dp-lu28r550uqnxza/
840	207	6	20260630	6	538.9900	USD	1.000000	538.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-msi-optix-g274rw-27-fhd-ips-170hz-1ms-mprt-hdmi-dp-white/
841	204	6	20260630	6	459.9900	USD	1.000000	459.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-ultragear-27gr75q-b-27-qhd-2560x1440-165hz-ips-1ms-gtg-srgb-99-anti-glare-hdr10-hdmi-2-2-dp-1-4-black/
842	203	6	20260630	6	324.9900	USD	1.000000	324.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-32mn600p-b-31-5-ips-full-hd-amd-freesync/
843	202	6	20260630	6	437.9900	USD	1.000000	437.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-27qn600-b-27-ips-2k-qhd-2560x1440-srgb-99-75hz-5ms-hdr-freesync-hdmi-dp/
844	201	6	20260630	6	646.9900	USD	1.000000	646.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-m32qc-sa-31-5-qhd-165hz-hdr400-1ms-mprt-hdmi-94-dci-p3-123-srgb-2-0-dp-1-2/
845	200	6	20260630	6	727.9900	USD	1.000000	727.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs34wqc-34-va-1500r-wqhd-3440x1440-non-glare-120-srgb-1ms-mprt-135hz-hdr-hdmi-2-0-dp-1-4-black/
846	199	6	20260630	6	469.9900	USD	1.000000	469.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs27q-27-ss-ips-2k-qhd-2560x1440-non-glare-100-srgb-1ms-mprt-170hz-hdr-hdmi-2-0-dp-1-4-black/
847	195	6	20260630	6	126.9900	USD	1.000000	126.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-env-1esm1695-21-5-full-hd-1920x1080-va-230-nits-75hz-6-5ms-vga-hdmi-vesa/
848	194	6	20260630	6	158.9900	USD	1.000000	158.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-env-1eenv1711-24-fhd-panel-va-300-nits-16ms-vga-hdmi/
849	193	6	20260630	6	1310.9900	USD	1.000000	1310.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-corsair-xeneon-32uhd144-a-32-uhd-ips-144hz-hdr600-non-glare-100-adobe-rgb-1ms-amd-freesync-premium-black-cm-9020006-na/
850	192	6	20260630	6	536.9900	USD	1.000000	536.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-vy27uq-27-4k-3840-x-2160-non-glare-ips-dhr-10-adaptive-sync-eye-care-dp-hdmi-black/
851	191	6	20260630	6	241.9900	USD	1.000000	241.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-va24ehf-24-23-8-full-hd-ips-100hz-1ms-vrr-adaptive-sync-hdmiv1-4/
852	189	6	20260630	6	338.9900	USD	1.000000	338.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-tuf-vg248q1b-24-fhd-led-panel-tn-165hz-0-5ms-gtg-freesync-premium-dp-1-2-hdmi-v1-4/
853	188	6	20260630	6	31.9900	USD	1.000000	31.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/bundle-4-en-1-alcatroz-basecamp-teclado-mouse-headset-mousepad-black/
854	187	6	20260630	6	41.9900	USD	1.000000	41.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/bundle-4-en-1-alcatroz-xcraft-nexus-wireless-teclado-mouse-headset-mousepad-black/
855	186	6	20260630	6	92.9900	USD	1.000000	92.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-msi-forge-gk600-tkl-white-violet/
856	184	6	20260630	6	471.9900	USD	1.000000	471.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-corsair-galleon-100-sd-integrated-stream-deck-lcd-full-color-teclas-pbt-switch-mlx-black-ch-912a311-na/
857	181	6	20260630	6	174.9900	USD	1.000000	174.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-razer-blackwidow-v4-x-pokemon-edition-razer-chroma-rgb-abs-switch-lineal-es-grenn-detalles-tematicos-pokemon-rz03-04704200-r3m1/
858	162	6	20260630	6	144.9900	USD	1.000000	144.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-logitech-g515-tkl-tactical-teclas-pbt-tactile-lightsync-rgb-grafite-920-012868/
859	178	6	20260630	6	47.9900	USD	1.000000	47.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-241/
860	180	6	20260630	6	84.9900	USD	1.000000	84.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-239/
861	182	6	20260630	6	86.9900	USD	1.000000	86.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-redragon-yama-k550rgb-1-sp-rgb-chroma-100-anti-ghosting-black/
862	183	6	20260630	6	7.9900	USD	1.000000	7.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-genius-kb-117-alambrico-usb-black/
863	185	6	20260630	6	90.9900	USD	1.000000	90.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-corsair-gaming-k70-core-rgb-mecanico-mlx-red-100-anit-ghosting-black-ch-910971e-sp/
864	196	6	20260630	6	69.9900	USD	1.000000	69.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-meetion-mt-mk20-lina-inverse-mecanico-switch-blue-anti-ghosting-black-red/
865	197	6	20260630	6	45.9900	USD	1.000000	45.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-hp-pavillon-15-bs-black/
866	198	6	20260630	6	114.9900	USD	1.000000	114.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-teclado-y-mouse-logitech-mk850-wireless-920-008219-920008659/
867	205	6	20260630	6	11.9900	USD	1.000000	11.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-teclado-y-mouse-genius-slimstar-c126-wired-black/
868	206	6	20260630	6	96.9900	USD	1.000000	96.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-dyi-glorious-gmmk-tkl-rgb-sin-switch-sin-keycaps-black/
869	156	6	20260630	6	51.9900	USD	1.000000	51.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-inalambrico-trust-gxt-sento-black-20062/
870	163	6	20260630	6	15.9900	USD	1.000000	15.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-logitech-k120/
871	165	6	20260630	6	18.9900	USD	1.000000	18.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ssd-externo-adata-sd700-1tb/
872	166	6	20260630	6	29.9900	USD	1.000000	29.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/kit-logitech-mk200-teclado-y-mouse-usb-920-002716/
873	167	6	20260630	6	25.9900	USD	1.000000	25.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/kit-de-teclado-y-mouse-logitech-mk120-alambrico-usb-negro-920-004428/
874	168	6	20260630	6	57.9900	USD	1.000000	57.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-inalambrico-logitech-slim-mk320-teclado-y-mouse/
875	169	6	20260630	6	27.9900	USD	1.000000	27.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-marvo-cm370pm-pink-4-en-1-tecladomousemousepadaudifono/
876	170	6	20260630	6	2566.9900	USD	1.000000	2566.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-rog-strix-g16-g614pm-rv038-amd-ryzen-r9-8940hx-32gb-16gb-ddr5-5200-x2-1tssd-geforce-rtx5060-8gb-16-0-wuxga-ips-165hz-3ms-sin-s-o/
877	171	6	20260630	6	154.9900	USD	1.000000	154.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-razer-blackwidow-v4-tenkeyless-hyperspeed-wireless-usb-c-razer-chroma-rgb-abs-doubleshot-swtich-tactile-and-quiet-black-rz03-05480600-r311/
878	172	6	20260630	6	160.9900	USD	1.000000	160.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-asus-rog-strix-scope-ii-96-wireless/
879	173	6	20260630	6	39.9900	USD	1.000000	39.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-logitech-pebble-keys-2-k380s-bluetooth-silencioso-espanol-white-920-011784/
880	174	6	20260630	6	253.9900	USD	1.000000	253.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-logitech-g915-tkl-bluetooth-mecanico-lightspeed-rgb-920-009495/
881	175	6	20260630	6	215.9900	USD	1.000000	215.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-logitech-g815-mecanico-lightsync-rgb-gl-tactile-g-keys-white-920-011354/
882	209	6	20260630	6	166.9900	USD	1.000000	166.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-244/
883	190	6	20260630	6	132.9900	USD	1.000000	132.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-243/
884	211	6	20260630	6	140.9900	USD	1.000000	140.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-242/
885	228	6	20260630	6	235.9900	USD	1.000000	235.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-238/
886	246	6	20260630	6	35.9900	USD	1.000000	35.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-67/
887	247	6	20260630	6	88.9900	USD	1.000000	88.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-k621-rgb-sp-wireless-tkl-bluetooth-5-0-rgb-chroma-100-anti-ghosting-black/
888	248	6	20260630	6	37.9900	USD	1.000000	37.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-gaming-marvo-kg962-white-r-60-switch-red-anti-ghosting-cable-type-c-desmontable-white/
889	249	6	20260630	6	33.9900	USD	1.000000	33.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-redragon-shiva-k512rgb-sp-membrana-rgb-reposamunecas-magnetico-black/
890	250	6	20260630	6	49.9900	USD	1.000000	49.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-redragon-kumara-k552w-rgb-sps-red-mecanico-tkl-us-dust-proof-red-white/
891	251	6	20260630	6	74.9900	USD	1.000000	74.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-primus-gaming-ballista90t-edition-star-wars-mandalorian-mechanical-anti-ghosting-linear-y-silent-switch-red-pks-s092ml-s/
892	252	6	20260630	6	277.9900	USD	1.000000	277.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-perzonalizable-corsair-elgato-stream-deck-8-teclas-lcd-usb-c-black-10gbd9901/
893	253	6	20260630	6	78.9900	USD	1.000000	78.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-redragon-horus-tkl-k621w-rgb-sp-wireless-bluetooth-dongle-rf-usb/
894	254	6	20260630	6	67.9900	USD	1.000000	67.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-redragon-deimos-k599-krs-tkl-70-wireless-wired-rgb-chroma-switch-linear-45-gr-black/
895	255	6	20260630	6	76.9900	USD	1.000000	76.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-hyperx-origins-60-rgb-switch-linear-100-anti-ghosting-compatible-ps5-ps4-xbox-series-xs-xbox-one-black-4p5n4aa/
896	256	6	20260630	6	156.9900	USD	1.000000	156.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-hyperx-alloy-elite-2-rgb-switch-rojo-100-anti-ghost-compatible-ps5-ps4-xbox-series-xs-xbox-one-black-4p5n3aiac8/
897	257	6	20260630	6	94.9900	USD	1.000000	94.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-horus-k618-rgb-sp-wireless-rgb-chroma-fps-bluetooth-5-0-100-anti-ghosting-black/
898	258	6	20260630	6	122.9900	USD	1.000000	122.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-gaming-cougar-luxlim-low-profile-switch-red-usb-black/
899	260	6	20260630	6	17.9900	USD	1.000000	17.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-teclado-y-mouse-genius-q8000-wireless-12-fn-keys-plug-and-play-black/
900	261	6	20260630	6	13.9900	USD	1.000000	13.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-msi-forge-gm300-7200dpi-7-botones-rgb-black/
901	262	6	20260630	6	6.9900	USD	1.000000	6.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-lenovo-300-usb-1600dpi-black/
902	263	6	20260630	6	10.9900	USD	1.000000	10.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-lenovo-essential-usb-diseno-ambidextro-1600dpi-black-4y50r20863/
903	264	6	20260630	6	82.9900	USD	1.000000	82.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-razer-cobra-chroma-rgb-gengar-edition-58g-8500dpi-6-botones-programables-300ips-black-rz01-04650700-r3m1/
904	265	6	20260630	6	48.9900	USD	1.000000	48.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-mousepad-goliathus-mobile-mouse-razer-abyssus-lite-rz83-02730100-b3m1/
905	266	6	20260630	6	126.9900	USD	1.000000	126.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-mx-master-3s-bluetooth-edition-ergonomico-7-botones-8000dpi-grafito-910-007502/
906	267	6	20260630	6	9.9900	USD	1.000000	9.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-95/
907	269	6	20260630	6	8.9900	USD	1.000000	8.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-klip-xtreme-optical-liteglider-usb-ps-2-adapter-kmo-102/
908	270	6	20260630	6	4.9900	USD	1.000000	4.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-pad-havit-mp839-2502102mm/
909	271	6	20260630	6	61.9900	USD	1.000000	61.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-glorious-model-d-matte-white-gd-white/
910	272	6	20260630	6	22.9900	USD	1.000000	22.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-pad-glorious-xl-white-gw-xl/
911	273	6	20260630	6	106.9900	USD	1.000000	106.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-pad-asus-rog-balteus-rgb-370x320mm-black-90mp0110-b0ua00/
912	274	6	20260630	6	75.9900	USD	1.000000	75.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-glorious-model-d-61g-d-minus-glo-ms-dm-mw-matte-white/
913	245	6	20260630	6	80.9900	USD	1.000000	80.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-cooler-master-mm711-blue/
914	243	6	20260630	6	221.9900	USD	1.000000	221.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-asus-p707-rog-spatha-x-wireless-aura-sync-19000dpi-black-90mp0220-bmua00/
915	213	6	20260630	6	164.9900	USD	1.000000	164.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-g-pro-2-lightspeed-rgb-wireless-44000dpi-888-ips-1ms-80g-black-910-007246/
916	214	6	20260630	6	197.9900	USD	1.000000	197.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-gaming-g-pro-x-superlight-2-lightspeed-wireless-usb-connectivity-32000dpi-0-5-response-time-5-botones-white-910-006636/
917	215	6	20260630	6	130.9900	USD	1.000000	130.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-g-pro-lightspeed-rgb-inalambrico-25600dpi-black-910-005271/
918	216	6	20260630	6	19.9900	USD	1.000000	19.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-97/
919	217	6	20260630	6	1885.9900	USD	1.000000	1885.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-asus-rog-strix-g16-g614pm-rv039-ryzen-r9-8940hx-16gb-1tb-rtx-5060-8gb-16-165hz-mochilamouse/
920	218	6	20260630	6	776.9900	USD	1.000000	776.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-x1605za-mb915-intel-core-i7-12700h-16gb-ram-512g-ssd-16-wuxga-sin-s-o-mochila-mouse-black/
921	219	6	20260630	6	1088.9900	USD	1.000000	1088.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-vivobook-x1605va-mb649-intel-core-i9-13900h-16gb-ram-1tb-ssd-16-wuxga-sin-s-o-mouse-mochila-black/
922	224	6	20260630	6	1008.9900	USD	1.000000	1008.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-vivobook-x1605va-mb2030-intel-core-i9-13900h-16gb-ram-1tb-ssd-16-wuxga-sin-s-o-silver-mochila-mouse/
923	225	6	20260630	6	665.9900	USD	1.000000	665.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-vivobook-x1504va-bq3132-intel-core-i5-120u-16gb-ram-8gb-on-board-512gb-ssd-15-6-fhd-wv-sin-s-o-cool-silver-mochila-y-mouse/
924	226	6	20260630	6	634.9900	USD	1.000000	634.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-vivobook-x1502va-nj973-intel-core-i5-13420h-ram-16gb-8gb-on-board-8gb-ddr4-512gb-ssd-15-6-fhd-s-o-freedos-cool-silver-mochilamouse/
925	227	6	20260630	6	2082.9900	USD	1.000000	2082.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/notebook-asus-vivobook-pro-n6506mv-ma058-intel-core-ultra-9-185h-1tb-ssd-24gb-ram-8gb-onboard-15-6-oled-2880x1620-geforce-rtx-4060-8gb-sin-s-o-kb-es-2s-cool-silver-mouse-mochila/
926	229	6	20260630	6	766.9900	USD	1.000000	766.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/laptop-asus-m1502ya-bq828/
927	230	6	20260630	6	23.9900	USD	1.000000	23.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-pebble-m350-wireless-usb-bluetooth-silencioso-almond-milk-910-006658/
928	231	6	20260630	6	162.9900	USD	1.000000	162.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/audifonos-gaming-cougar-omnes-essential-wireless-mic-omnidirectional-53mm-black-3hw50g53b-0001/
930	233	6	20260630	6	20.9900	USD	1.000000	20.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/almohadillas-de-repuesto-para-audifonos-logitech-g733-black/
931	234	6	20260630	6	55.9900	USD	1.000000	55.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/audifonos-primus-gaming-edition-star-wars-mandalorian-arcus-210-tws-wireless-omnidireccional-usb-type-c-5-rms-black-pwh-s210ml/
932	235	6	20260630	6	40.9900	USD	1.000000	40.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/stand-cougar-bunker-s-para-audifonos/
933	236	6	20260630	6	53.9900	USD	1.000000	53.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/bundle-quasad-4-en-1-mouse-teclado-mouse-pad-headset-gaming/
934	237	6	20260630	6	24.9900	USD	1.000000	24.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-66/
935	238	6	20260630	6	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-cooler-master-ch321/
936	239	6	20260630	6	63.9900	USD	1.000000	63.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headset-hp-h500gs/
937	240	6	20260630	6	261.9900	USD	1.000000	261.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-corsair-virtuoso-rgb-wireless-white/
938	241	6	20260630	6	136.9900	USD	1.000000	136.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-corsair-void-rgb-elite-wireless-white/
939	242	6	20260630	6	128.9900	USD	1.000000	128.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-corsair-void-rgb-elite-premium-black/
940	794	6	20260630	6	189.9900	USD	1.000000	189.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-astro-a20-black-green/
\.


--
-- Name: dim_fuente dim_fuente_nombre_fuente_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_fuente
    ADD CONSTRAINT dim_fuente_nombre_fuente_key UNIQUE (nombre_fuente);


--
-- Name: dim_fuente dim_fuente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_fuente
    ADD CONSTRAINT dim_fuente_pkey PRIMARY KEY (id_fuente);


--
-- Name: dim_producto dim_producto_clave_canonica_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_producto
    ADD CONSTRAINT dim_producto_clave_canonica_key UNIQUE (clave_canonica);


--
-- Name: dim_producto dim_producto_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_producto
    ADD CONSTRAINT dim_producto_pkey PRIMARY KEY (id_producto);


--
-- Name: dim_tiempo dim_tiempo_fecha_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_tiempo
    ADD CONSTRAINT dim_tiempo_fecha_key UNIQUE (fecha);


--
-- Name: dim_tiempo dim_tiempo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_tiempo
    ADD CONSTRAINT dim_tiempo_pkey PRIMARY KEY (id_tiempo);


--
-- Name: dim_tienda dim_tienda_nombre_tienda_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_tienda
    ADD CONSTRAINT dim_tienda_nombre_tienda_key UNIQUE (nombre_tienda);


--
-- Name: dim_tienda dim_tienda_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_tienda
    ADD CONSTRAINT dim_tienda_pkey PRIMARY KEY (id_tienda);


--
-- Name: fact_precios fact_precios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_precios
    ADD CONSTRAINT fact_precios_pkey PRIMARY KEY (id_hecho);


--
-- Name: idx_dim_prod_cat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dim_prod_cat ON public.dim_producto USING btree (categoria);


--
-- Name: idx_dim_prod_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dim_prod_key ON public.dim_producto USING btree (clave_canonica);


--
-- Name: idx_fact_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fact_producto ON public.fact_precios USING btree (id_producto);


--
-- Name: idx_fact_tiempo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fact_tiempo ON public.fact_precios USING btree (id_tiempo);


--
-- Name: idx_fact_tienda; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fact_tienda ON public.fact_precios USING btree (id_tienda);


--
-- Name: fact_precios fact_precios_id_fuente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_precios
    ADD CONSTRAINT fact_precios_id_fuente_fkey FOREIGN KEY (id_fuente) REFERENCES public.dim_fuente(id_fuente);


--
-- Name: fact_precios fact_precios_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_precios
    ADD CONSTRAINT fact_precios_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.dim_producto(id_producto);


--
-- Name: fact_precios fact_precios_id_tiempo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_precios
    ADD CONSTRAINT fact_precios_id_tiempo_fkey FOREIGN KEY (id_tiempo) REFERENCES public.dim_tiempo(id_tiempo);


--
-- Name: fact_precios fact_precios_id_tienda_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_precios
    ADD CONSTRAINT fact_precios_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.dim_tienda(id_tienda);


--
-- PostgreSQL database dump complete
--

\unrestrict TYHeOSmtwqmy434WMEPBndSQxKAzBLtC7G3wyg3rIlVPtBRtOIYldJ7JhKIMHJz

