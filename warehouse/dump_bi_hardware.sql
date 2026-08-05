--
-- PostgreSQL database dump
--

\restrict CZpNII8jkezAtnDuIIIesNSIeVaSmcIacAs7BUkCmwf7UzDgt98QkBXcgQqY10U

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
2	ryzen 9 9950x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 9 9950X3D 4.3GHz – TURBO 5.7GHZ – 16-CORES – 32-HILOS – AM5 – 170W	t
3	ryzen 5 9600	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 9600 – AM5 – 6 CORES – 12 THREAD – TURBO 5.2GHZ – 65W	t
4	ryzen 5 5500x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 5500X3D 3.0GHZ BASE – 6 CORES – 12HILOS – 96MB L3-CACHE – 105W	t
5	core i7-9700f	Intel	CPU	NaN	Procesador Intel Core i7-9700F 3GHZ 12MB CACHE LGA1151	t
6	core i7-14700kf	Intel	CPU	NaN	Procesador Intel Core i7-14700KF 20-Cores/28-Hilos (8P+12E) Base 3.4GHz Turbo 5.4GHz – Caché 33MB – LGA1700 14th Gen no graphics	t
7	core i7-10700k	Intel	CPU	NaN	Procesador Intel Core i7-10700K	t
8	core i5-13600kf	Intel	CPU	NaN	Procesador Intel Core i5-13600KF 14-Cores/20-Hilos (6P+8E) Base 3.5GHz Turbo 5.1GHz – Caché 24MB – LGA1700 13th Gen no graphics	t
9	core i7-9750h	Intel	CPU	NaN	PROCESADOR INTEL CORE i7-9750H – SRF6U PARA LAPTOP	t
10	core i7-13700f	Intel	CPU	NaN	PROCESADOR INTEL CORE i7-13700F – 13TH – LGA 1700 – 2.10GHZ HASTA 5.20GHZ – 24M – 65W – 16 CORES (BX8071513700F)	t
11	core i7-13700	Intel	CPU	NaN	PROCESADOR INTEL CORE i7-13700 – 13TH – LGA 1700 – 2.10GHZ HASTA 5.20GHZ – 30M – 8 CORES – 16 NUCLEOS	t
12	core i5-13400f	Intel	CPU	NaN	PROCESADOR INTEL CORE i5-13400F – 2.50GHZ BASE – 65W – 10 NUCLEOS (BX8071513400F)	t
13	core i5-13400	Intel	CPU	NaN	PROCESADOR INTEL CORE i5-13400 4.6GHz – 20MB – LGA1700 – 13th GEN	t
14	core i5-12400	Intel	CPU	NaN	PROCESADOR INTEL CORE i5-12400 4.4GHz – 18MB – LGA1700 – 12th GEN – TRAY (SIN CAJA)	t
15	core i3-14100	Intel	CPU	NaN	PROCESADOR INTEL CORE i3-14100 – 3.5GHZ – 14TH – LGA1700 – 4 CORES	t
16	core i3-13100	Intel	CPU	NaN	PROCESADOR INTEL CORE i3-13100 – 3.40GHZ – 13TH – LGA1700 – 4 CORES – 12MB CACHE	t
17	ryzen 9 7900x	AMD	CPU	NaN	PROCESADOR AMD RYZEN 9 7900X 4.7GHz BASE – 12 CORES – 24 HILOS – AM5 – 170W	t
18	rtx 5050 8gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 5050 8GB GDDR6 – OC EDITION – WINDFORCE 2X – HDMI/DP (GV-N5050WF2OCV2-8GDG)	t
19	rx 7600 gaming	AMD	GPU	NaN	TARJETA DE VIDEO GIGABYTE RADEON RX 7600 GAMING OC 8G GDDR6 – WINDFORCE/OC EDITION – DP/HDMI – BLACK (GV-R76GAMING OC-8GD G11)	t
20	rtx 5060	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 5060 WINDFORCE MAX OC 8G – GDDR7 – PCIE 5.0 – HDMI/DP (GV-N5060WF2MAXOC)	t
21	rx 7600 xt	AMD	GPU	NaN	TARJETA DE VIDEO GIGABYTE AMD RADEON RX 7600 XT – 16GB GDDR6 GAMING OC – WINDFORCE – RAYTRACING – 3 FANS – HDMI/DP (GV-R76XTGAMING OC-16GD)	t
22	rx 9060 xt	AMD	GPU	NaN	TARJETA DE VIDEO ASUS RADEON RX 9060 XT – 16GB GDDR6 GAMING OC – WINDFORCE – 2 FANS – HDMI/DP	t
23	rtx 3050 6gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO MSI VENTUS 2X – RTX 3050 6GB GDDR6 OC- HDMI/DP – PCIe 4.0 – RAY TRACING/DLSS (912-V812-060)	t
24	rtx 5060 8g	NVIDIA	GPU	NaN	TARJETA DE VIDEO MSI GEFORCE RTX 5060 8G VENTUS 3X OC EDITION – 8GB GDDR7 – HDMI 2.1b/DP v2.1b (912-V537-036)	t
25	rtx 5070ti g	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 5070TI GAMING OC 16GB GDDR7 – DP 2.1b / HDMI 2.1b – BLACK (GV-N507TGAMING OC-16GD)	t
26	ryzen 9 9900x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 9 9900X3D 4.4GHZ – 12 CORES – 24HILOS – 128MB L3-CACHE – 120W	t
27	ryzen 9 9950x3d2	AMD	CPU	NaN	Procesador AMD Ryzen 9 9950x3D2 Dual Edition | 16-Cores/32-Hilos | AM5 | Gráficos integrados	t
28	kingston 16gb ddr5 fury	Kingston	RAM	DDR5	Memoria RAM Kingston Fury Beast 16GB DDR5-5600 BLACK (KF556C40BB-16)	t
29	ryzen 5 5600xt	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 5600XT – 3.7 GHZ BASE – HASTA 4.7GHZ – 65W – AM4	t
30	ryzen 3 5300g	AMD	CPU	NaN	PROCESADOR AMD RYZEN 3 5300G – AM4 – 16MB – 64W – 8 THREAD	t
31	ryzen 7 9850x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 9850X3D 8-CORES/16-HILOS 4.7GHz | AM5	t
32	ryzen 5 8500g	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 8500G – BASE 3.5GHZ – 65W – AM5 – GRAFICOS AMD RADEON™ 740M (100-100000931BOX)	t
33	ryzen 7 5700x	AMD	CPU	NaN	Procesador AMD Ryzen 7 5700X 3.4GHz – 4.6Ghz – 8-Core – 16 Threads – AM4	t
34	core i3-14100f	Intel	CPU	NaN	PROCESADOR INTEL CORE i3-14100F – 3.5 GHZ – 14TH – LGA1700 – 4 CORES	t
35	ryzen 5 8600g	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 8600G 4.3GHz BASE – 6 CORES – 12 HILOS – AM5 – 65W – WITH RADEON™ GRAPHICS	t
36	ryzen 5 5600gt	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 5600GT 3.6GHZ TURBO 4.6GHz AM4 6-CORE 12 THREADS – Gráficos Radeon VEGA integrados	t
37	core i7-12700	Intel	CPU	NaN	Procesador Intel Core i7-12700	t
38	ryzen 5 5500	AMD	CPU	NaN	Procesador AMD Ryzen 5 5500	t
39	core i7-4790k	Intel	CPU	NaN	Procesador Intel Core i7-4790K	t
40	core i5-10600kf	Intel	CPU	NaN	Procesador Intel Core i5-10600KF – Sin Graficos	t
41	ryzen 7 5700g	AMD	CPU	NaN	Procesador AMD Ryzen 7 5700G – Con Graficos Radeon VEGA	t
42	core i9-14900k	Intel	CPU	NaN	Procesador Intel Core i9-14900K 24-Cores/32-Hilos (8P+16E) Base 3.2GHz Turbo 6GHz – Caché 36MB – LGA1700 14th Gen	t
43	core i9-14900kf	Intel	CPU	NaN	Procesador Intel Core i9-14900KF 24-Cores/32-Hilos (8P+16E) Base 3.2GHz Turbo 6GHz – Caché 36MB – LGA1700 – Sin Gráficos – 14th Gen	t
44	core ultra 9 285k	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 9 285K – 24 CORES – 36MB – LGA1851- GRAPHICS	t
45	core ultra 9 285	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 9 285 – 24 CORES – 36MB – LGA1851	t
46	core ultra 7 265k	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 7 265K – 30MB – LGA1851 – 20-cores (8P+12E) – GRAPHICS	t
47	core ultra 5 245k	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 5 245K – BASE 4.2GHZ – 26MB – 159W – LGA1851	t
48	core ultra 5 225f	Intel	CPU	NaN	Procesador Intel Core Ultra 5 225F | LGA1851 | Sin Gráficos	t
49	ryzen 7 9800x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 9800X3D 8-Núcleos 16-Hilos 4.7GHz Base – 5.2GHz Turbo – AM5 – DDR5	t
50	ryzen 7 8700f	AMD	CPU	NaN	Procesador AMD Ryzen 7 8700F | 5.00 GHz | 8-CORES /16-HILOS | AM5 | 65W | SIN GRÁFICOS | INCLUYE COOLER	t
51	ryzen 5 9600x	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 9600X – AM5 – 6 CORES – 12 THREAD – 38MB – 65W	t
101	asrock cl25ff	Varios	Monitor	IPS	Monitor Gamer 25″ Fhd, Ips, 100Hz, 1ms, Adaptive Sync – Asrock CL25FF	t
52	rx 6900xt	AMD	GPU	NaN	TARJETA DE VIDEO GIGABYTE AORUS EXTREME AMD RADEON RX 6900XT – 16GB GDDR6 – 4K UHD – PCI-E 4.0 – WATERBLOCK – DP 1.4 WITH DSC/HDMI 2.1 VRR + AORUS ROBOT XTREME (GV-R69XTAORUSX WB-16GD)	t
53	rtx 5070 12gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS PRIME GEFORCE RTX 5070 12GB GDDR7 – OC EDITION – HDMI 2.1b/DP 2.1b – PCI-E 5.0 – BLACK (PRIME-RTX5070-O12G)	t
54	rtx 4080 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE AORUS MASTER GEFORCE RTX 4080 16GB GDDR6X REV 1.0 – OC EDITION – WINDFORCE – DLSS/RAY TRACING/REFLEX/STUDIO – DP/HDMI (GV-N4080AORUS M-16GD)	t
55	rtx 4070ti 12gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS TUF GAMING GEFORCE RTX 4070TI 12GB GDDR6X – HDMI 2.1a/ DP 1.4a – ARGB – BLACK ( TUF-RTX4070TI-12G-GAMING)	t
56	rtx 4070 ti 12gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS TUF GAMING GEFORCE RTX 4070 Ti 12GB GDDR6X – OC EDITION (TUF-RTX4070TI-O12G-GAMING)	t
57	rtx 4090 24gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS ROG STRIX GEFORCE RTX 4090 24GB GDDR6X – OC EDITION (ROG-STRIX-RTX4090-O24G-GAMING)	t
58	rtx 4070 super	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL GEFORCE RTX 4070 SUPER EVO OC 12GB GDDR6X – DP/HDMI – BLACK (90YV0KC0-M0NA00)	t
59	rtx 4060 8gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL GEFORCE RTX 4060 8GB GDDR6 OC EDITION – GPU TWEAK III – DLSS 3 – HDMI/DP (DUAL-RTX4060-O8G-WHITE)	t
60	rtx 3050 8gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE EAGLE GEFORCE RTX 3050 8GB OC HDMI 2.1/DP 1.4A (GV-N3050EAGLE OC-8GD)	t
61	rtx 3050	NVIDIA	GPU	NaN	Tarjeta de video Gigabyte Windforce RTX 3050 OC 8GB (GV-N3050GAMING OC-8GD)	t
62	rx 580 8gb	AMD	GPU	NaN	Tarjeta de video Asus Dual RX 580 8GB OC – (Dual-RX580-O8G)	t
63	rx 6700xt	AMD	GPU	NaN	GPU Asus TUF RX 6700XT OC EDITION – 12GB – (90YV0G80-M0AA00)	t
64	kingston 8gb ddr5 fury	Kingston	RAM	DDR5	Memoria RAM Kingston Fury Beast 8GB DDR5-5600 BLACK (KF556C40BB-8)	t
65	corsair 8gb ddr4 vengeance 3200mhz	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance LPX 8GB 3200Mhz – (CMK8GX4M1Z3200C16)	t
66	kingston 32gb ddr5 fury	Kingston	RAM	DDR5	Memoria RAM Kingston Fury Beast 32GB DDR5-5600 BLACK (KF556C40BB-32)	t
67	kingston 8gb ddr4 fury 3200mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston Fury 8GB 3200Mhz – (KVR32N22S8/8 – KVR32N22S6/8)	t
68	kingston 32gb ddr4 sodimm fury 3200mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Kingston Fury Impact 32GB 3200Mhz – (KF432S20IB/32)	t
69	kingston 8gb ddr3 1600mhz	Kingston	RAM	DDR3	Memoria RAM DDR3 Kingston 8GB 1600MHz – (KVR16N11/8)	t
70	kingston 16gb ddr5 fury 5200mhz	Kingston	RAM	DDR5	Memoria RAM DDR5 Kingston Fury Beast 16GB 5200MHZ – (KF552C40BB-16)	t
71	rtx 4090 g	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 4090 GAMING OC EDITION – 24GB GDDR6X DP 1.4/HDMI 2.1 – PCI-E 4.0 (GV-N4090GAMING OC-24GD)	t
72	rtx 4060 ti	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL GEFORCE RTX 4060 TI OC EDITION 8GB GDDR6 – HDMI/DP (DUAL-RTX4060TI-O8G)	t
73	rtx 5090	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 5090 WINDFORCE OC – 32GB GDDR7 – PCIE 5.0 – HDMI 2.1b/DP 2.1b (GV-N5090WF3OC-32GD)	t
74	rtx 5060ti 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL GEFORCE RTX 5060TI 16GB GDDR7 – OC EDITION – PCIE- 5.0 – HDMI/DP (DUAL-RTX5060TI-O16G-EVO)	t
75	rtx 5060 8gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL GEFORCE RTX 5060 8GB GDDR7 – OC EDITION – DP/HDMI (DUAL-RTX5060-O8G)	t
76	rtx 5090 32gb	NVIDIA	GPU	NaN	Tarjeta de video ASUS ROG ASTRAL GeForce RTX 5090 32GB GDDDR7	t
77	gtx 1630	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS PHOENIX GEFORCE GTX 1630 4GB GDDR6 – AUTO EXTREME HDMI/DP/DVI-D (PH-GTX1630-4G)	t
78	rtx 5080 16g	NVIDIA	GPU	NaN	TARJETA DE VIDEO MSI GEFORCE RTX 5080 16G INSPIRE 3X – OC EDITION – 16GB GDDR7 – HDMI 2.1b/DP v2.1b (912-V531-203)	t
79	rtx5090 32gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS TUF GAMING RTX5090 32GB GDDR7 – PCIE 5.0 – DP/HDMI – BLACK (TUF-RTX5090-32G-GAMING)	t
80	rtx 5060ti 16g	NVIDIA	GPU	NaN	TARJETA DE VIDEO MSI GEFORCE RTX 5060TI 16G VENTUS 2X OC PLUS – 16GB GDDR7 – DP/HDMI – 2 FAN – HDMI/DP – BLACK (912-V537-017)	t
81	rtx 5080 g	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 5080 GAMING OC 16GB GDDR7 – HDMI 2.1B /DP 1.4B (GV-N5080GAMING OC-16GD)	t
82	rtx 5060ti	NVIDIA	GPU	NaN	TARJETA DE VIDEO GIGABYTE GEFORCE RTX 5060TI EAGLE MAX OC 16GB GDDR7 – OC EDITION – DP 2.1b / HDMI 2.1b – BLACK (GV-N5060TIEAGLEMAX OC-16GD)	t
83	rtx 4070 ti	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS TUF GEFORCE RTX 4070 TI SUPER BTF WHITE EDITION – 16GB GDDR6X – HDMI/DP (TUF-RTX4070S-O16G-BFT-WHITE)	t
84	rtx 4060ti 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS PROART GEFORCE RTX 4060TI 16GB GDDR6 – ADVANCED EDTION – HDMI 2.1a/DP 1.4a – BLACK (PROART-RTX4060TI-A 16G)	t
85	rtx 5070 ti 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS PRIME RTX 5070 TI 16GB GDDR7 (PRIME-RTX5070TI-O16G)	t
86	ryzen 5 8400f	AMD	CPU	NaN	Procesador AMD Ryzen 5 8400F | 6-CORES | 4.7 GHZ | 65W | AM5 | SIN GRAFICOS	t
87	ryzen 7 7700 3	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 7700 3.8GHz BASE – 8 CORES – 16 HILOS – 8MB – AM5 – 65W (100000592BOX)	t
88	ryzen 7 7800x3d	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 7800X3D – 8 CORES – BASE 4.2GHZ – AM5 – CACHE 8MB	t
89	xtrikeme teclado kb-309	Varios	Periferico	Teclado	Teclado Gamer Usb C/ Cable RGB – Xtrike Me KB-309	t
90	asrock pg27ffx2a	Varios	Monitor	IPS	Monitor Asrock gamer PG27FFX2A 27 inch LED IPS FHD (1920 x	t
91	benq xl2731k	Benq	Monitor	NaN	Monitor BenQ gamer Zowie XL2731K 27 inch FHD 165Hz 1ms HDMI-DisplayPort	t
92	msi 245f	Msi	Monitor	IPS	Monitor 25″ Fhd, IPS, Adaptive Sync, 0.5ms, 240Hz – Msi Mag 245F X24	t
93	xtratech xtm24	Varios	Monitor	NaN	Monitor 24″ FHD, 100Hz, Hdmi, Vga – Xtratech XTM24	t
94	xiaomi g24i	Varios	Monitor	IPS	Monitor 24″ Fhd, Ips, 200hz, 1 ms, Adaptive Sync – Xiaomi G24i 2026	t
95	lg 24g411a-b	Lg	Monitor	IPS	Monitor 24″ Fhd, Ips, Adaptive Sync, 144hz, 1ms – LG 24G411A-B	t
96	samsung g55c	Samsung	Monitor	NaN	Monitor 27″ 2K 2560 x 1440, Curvo, Adaptive Sync, 1ms, 165Hz – Samsung Odyssey G5 G55C	t
97	lg 20u401a-b	Lg	Monitor	NaN	Monitor 20″ HD+ 1600×900, 75Hz, Hdmi – LG 20U401A-B	t
98	armaggeddon xf27qhd	Varios	Monitor	IPS	Monitor 27″ 2K Ips, 100Hz, Adaptive Sync, Hdmi, Dp – Armaggeddon XF27QHD	t
99	armaggeddon xf24hd	Varios	Monitor	IPS	Monitor 24″ Fhd Ips, 120Hz, Adaptive Sync, Hdmi, Dp – Armaggeddon Pixxel XF24HD	t
100	rca w2427sg	Varios	Monitor	NaN	Monitor 24″ Fhd, 100Hz, Hdmi, Vga – Rca W2427SG	t
260	hp audifonos h500gs	Varios	Periferico	Headset	Headsets HP H500GS	t
102	gigabyte gs27fa	Gigabyte	Monitor	IPS	Monitor 27″ Fhd, Ips, Adaptive Sync, 180Hz, 1ms – Gigabyte GS27FA	t
103	msi 276cxf	Msi	Monitor	NaN	Monitor 27″ Fhd, Curvo, Adaptive Sync, 280Hz, 0.5ms – Msi 276CXF	t
104	msi 255f	Msi	Monitor	IPS	Monitor 25″ Fhd, Rapid IPS, Adaptive Sync, 0.5ms, 200Hz – Msi 255F E20	t
105	msi 242c	Msi	Monitor	NaN	Monitor 24″ Fhd, Curvo, Adaptive Sync, 1ms, 180Hz – Msi Mag 242C	t
106	asus va279hg	Asus	Monitor	IPS	Monitor 27″ Fhd, Ips, Adaptive Sync, 120hz, 1ms – Asus VA279HG	t
107	asus vz24ehf	Asus	Monitor	IPS	Monitor 24″ Fhd, Ips, Adaptive Sync, 100hz, 1ms – Asus VZ24EHF	t
108	asus va27eye	Asus	Monitor	IPS	Monitor 27″ Fhd, Ips, Adaptive Sync – Asus VA27EYE	t
109	xtratech xtm19	Varios	Monitor	NaN	Monitor 20″ 1600×900, 75Hz, Hdmi, Vga – Xtratech XTM19	t
110	msi g2712f	Msi	Monitor	IPS	Monitor 27″ Fhd, Ips, Adaptive Sync, 180Hz, 1ms – Msi G2712F	t
111	msi mp2412	Msi	Monitor	NaN	Monitor 24″ Corporativo, Fhd, Adaptive Sync, 100hz, 1ms – Msi MP2412	t
112	msi 272qp	Msi	Monitor	OLED	Monitor MSI gamer MAG 272QP QD-OLED X50 26.5″ QD-Oled WQHD 500Hz	t
113	armaggeddon pf22hd	Varios	Monitor	NaN	Monitor 22″ Fhd, 120Hz, Adaptive Sync, Hdmi, Dp – Armaggeddon Pixxel PF22HD Super WH	t
114	asus va249hg	Asus	Monitor	IPS	Monitor 24″ Fhd, Ips, Adaptive Sync, 120hz, 1ms – Asus VA249HG	t
115	kingston 16gb ddr4 sodimm	Kingston	RAM	DDR4	Ram Ddr4, 16Gb, 3200, So-Dimm – Kingston	t
116	gtx 1650	NVIDIA	GPU	NaN	Tarjeta Gráfica Nvidia Gtx 1650 4GB Gddr6 – Arktek	t
117	gtx 1050ti	NVIDIA	GPU	NaN	Tarjeta Gráfica Nvidia GTX 1050TI 4gb Gddr5 – Arktek	t
118	acer 8gb ddr4 3200mhz	Acer	RAM	DDR4	Memoria ram Acer UD100 8GB DDR4 3200MHz CL22 para pc	t
119	kingston 8gb ddr4 3200mhz	Kingston	RAM	DDR4	Memoria ram Kingston 8GB DDR4 3200MHz CL22 para pc	t
120	patriot 8gb ddr4 3200mhz	Varios	RAM	DDR4	Memoria ram Patriot 8GB DDR4 3200MHz CL22 para pc	t
121	acer 16gb ddr4 3200mhz	Acer	RAM	DDR4	Memoria ram Acer 16GB DDR4 3200MHz CL22 para pc	t
122	adata 8gb ddr5 5600mhz	Adata	RAM	DDR5	Memoria ram Adata 8gb DDR5 5600Mhz CL45 para pc 1.1v	t
123	kingston 16gb ddr4 3200mhz	Kingston	RAM	DDR4	Memoria ram Kingston 16GB DDR4 3200Mhz CL22 para notebook	t
124	dato 512gb sata	Varios	SSD	SATA	Unidad Estado Sólido SSD Sata III 512Gb – Dato DS700	t
125	gigabyte gs24f14	Gigabyte	Monitor	IPS	Monitor 24″ Fhd, IPS, Adaptive Sync, 1ms, 144Hz – Gigabyte GS24F14	t
126	hp 480gb sata	Varios	SSD	SATA	Unidad Estado Solido Ssd 2.5″ 480GB Sata III – HP S650	t
127	adata 240gb sata	Adata	SSD	SATA	Unidad Estado Solido Ssd 2.5″ 240GB Sata III – Adata SU650	t
128	indilinx 256gb sata	Varios	SSD	SATA	Unidad Estado Sólido Ssd 2.5″ Sata III 256GB – Indilinx IND-S325S	t
129	indilinx 128gb sata	Varios	SSD	SATA	Unidad Estado Sólido Ssd 2.5″ Sata III 128Gb – Indilinx IND-S325S	t
130	msi 960gb sata	Msi	SSD	SATA	Unidad Estado Sólido SSD 2.5″ Sata III 960GB – Msi S270	t
131	gigabyte gs25f2	Gigabyte	Monitor	IPS	Monitor 25″ Fhd, IPS, Adaptive Sync, 1ms, 200Hz – Gigabyte GS25F2	t
132	gigabyte gs27qa	Gigabyte	Monitor	IPS	Monitor 27″ 2K, IPS, Adaptive Sync, 1ms, 180Hz – Gigabyte GS27QA	t
133	lg 27g411a-b	Lg	Monitor	IPS	Monitor 27″ Fhd, Ips, Adaptive Sync, 144hz, 1ms – LG 27G411A-B	t
134	gigabyte gs34wqca	Gigabyte	Monitor	NaN	Monitor 34″ 3440×1440, 120Hz, 1ms, Adaptive Sync, UltraWide – Gigabyte GS34WQCA	t
135	gigabyte gs25f2a	Gigabyte	Monitor	IPS	Monitor 25″ Fhd, IPS, Adaptive Sync, 1ms, 240Hz – Gigabyte GS25F2A	t
136	xtrikeme teclado gk-989	Varios	Periferico	Teclado	Teclado Mecanico Gamer 80% Sw Rojo – Xtrike Me GK-989	t
137	xtrikeme teclado gk-997	Varios	Periferico	Teclado	Teclado Mecanico Gamer 80% Sw Rojo – Xtrike Me GK-997	t
138	ryzen 7 8700g	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 8700G 4.2GHz BASE – 8 CORES – 16 HILOS – AM5 – 65W – WITH RADEON™ GRAPHICS	t
139	xtrikeme teclado gk-916	Varios	Periferico	Teclado	Teclado Mecanico Gamer 60% Rgb – Xtrike Me GK-916	t
140	logitech mouse g305	Logitech	Periferico	Mouse	Mouse Inalámbrico Gamer Programable – Logitech G305	t
141	logitech mouse g203	Logitech	Periferico	Mouse	Mouse Gamer Programable Rgb – Logitech Prodigy G203	t
142	jbl audifonos 510bt	Varios	Periferico	Headset	Audifono Inalámbrico Bt 5 40H – Jbl TUNE 510BT WH	t
143	genius audifonos m910bt	Varios	Periferico	Headset	Audifono Inalambrico BT 5.3 C/ Estuche – Genius M910BT	t
144	xtrikeme audifonos hp-318	Varios	Periferico	Headset	Audifono Gamer Rgb P/ Pc C/ Mic – Xtrike Me HP-318	t
145	xtrikeme audifonos gh-416	Varios	Periferico	Headset	Audifono Gamer USB P/ Pc Mic Rgb – Xtrike Me GH-416 516	t
146	marvo audifonos hg8921	Varios	Periferico	Headset	Audifono Gamer USB P/ Pc Mic Rgb – Marvo HG8921	t
147	primus audifonos arcus360bt	Varios	Periferico	Headset	Audifono Gamer Inalambrico C/ Mic Usb Bt – Primus ARCUS360BT	t
148	logitech audifonos g335	Logitech	Periferico	Headset	Audifono Gamer P/ Pc C/ Mic – Logitech G335 MINT	t
149	logitech audifonos g435	Logitech	Periferico	Headset	Audifono Gamer Inal P/ Pc C/ Mic – Logitech G435	t
150	core ultra 5 250k	Intel	CPU	NaN	Procesador Intel Core Ultra 5 250K Plus | Turbo 5.3GHz | 18-Cores | LGA1851	t
151	ryzen 3 3200g	AMD	CPU	NaN	Procesador AMD Ryzen 3 3200G – Con gráficos Radeon VEGA 8	t
152	core ultra 7 270k	Intel	CPU	NaN	Procesador Intel Core Ultra 7 270K Plus | 24-Cores | LGA1181	t
153	core i5-14400	Intel	CPU	NaN	PROCESADOR INTEL CORE i5-14400 – 2.5GHZ – 14TH – LGA1700 – UHD770 – 10 CORES – 20MB CACHE	t
154	core i3-13100f	Intel	CPU	NaN	PROCESADOR INTEL CORE i3-13100F – 3.40GHZ – 13TH – LGA1700 – 4 CORES – 12MB CACHE	t
155	core i7-14700k	Intel	CPU	NaN	Procesador Intel Core i7-14700K 20-Cores/28-Hilos (8P+12E) Base 3.4GHz Turbo 5.4GHz – Caché 33MB – Gráficos Intel – LGA1700 14th Gen	t
156	core i7-8700k	Intel	CPU	NaN	PROCESADOR INTEL CORE i7-8700K – 12MB – 3.7GHZ – LGA1151 – 6-CORES – 95W – INTEL GRAPHICS	t
157	core i7-14700f	Intel	CPU	NaN	Procesador Intel Core i7-14700F | 8-CORES / 20-THREADS | 28MB | LGA1700 | Sin Gráficos.	t
158	core i7-14700	Intel	CPU	NaN	PROCESADOR INTEL CORE i7-14700 – 3.40GHZ BASE – 33MB – LGA1700	t
159	core ultra 7 265kf	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 7 265KF – BASE 3.9 GHZ – 30MB – LGA1851 – 20-cores (8P+12E) – 250W	t
160	core ultra 5 225	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 5 225 – 20MB – 4.9GHZ – LGA1851 – 10-CORES – 65W – INTEL GRAPHICS	t
161	ryzen 9 9950x	AMD	CPU	NaN	PROCESADOR AMD RYZEN 9 9950X 4.3GHz – TURBO 5.7GHZ – 16 CORES – 32 HILOS – AM5 – 170W	t
162	ryzen 7 9700x	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 9700X – AMD AM5 – ZEN 5 – 65W – 8 CORES – 16 THREAD	t
163	msi mouse gm08	Msi	Periferico	Mouse	Mouse Gamer P/Pc Rgb – MSI GM08	t
164	genius mouse nx-8008s	Varios	Periferico	Mouse	Mouse Inalambrico Usb – Genius Nx-8008S Bk	t
165	genius mouse nx-7007	Varios	Periferico	Mouse	Mouse Inalambrico Usb Blue – Genius NX-7007	t
166	env combo g10	Varios	Periferico	Teclado	Combo Teclado, Mouse, Usb, Inalambrico – Env G10	t
167	xtrikeme teclado gk-996	Varios	Periferico	Teclado	Teclado Mecanico Gamer 60% Sw Rojo – Xtrike Me GK-996	t
168	genius teclado k12	Varios	Periferico	Teclado	Teclado Gamer Mecánico Rgb 100% – Genius Scorpion K12	t
169	marvo teclado kg933	Varios	Periferico	Teclado	Teclado Mecanico 60% Gamer Rgb – Marvo KG933 BK SW RED	t
170	primus teclado ballista61t	Varios	Periferico	Teclado	Teclado Mecanico Gamer Rgb 60% – Primus BALLISTA61T	t
171	quasad teclado qk-440c	Varios	Periferico	Teclado	Teclado Estándar Español Multimedia – Quasad QK-440C	t
172	marvo teclado k602	Varios	Periferico	Teclado	Teclado Gamer Multimedia Rgb – Marvo K602	t
173	evilpc teclado 572eg	Varios	Periferico	Teclado	Teclado Gamer Usb Multimedia – Evil Pc 572EG	t
174	evilpc teclado kb-772eg	Varios	Periferico	Teclado	Teclado Gamer Mecanico Rgb 100% – Evil PC KB-772EG	t
175	marvo teclado kg901	Varios	Periferico	Teclado	Teclado Mecanico Gamer 80% Rgb – Marvo KG901 Krone 87	t
176	quasad teclado qkm-g80	Varios	Periferico	Teclado	Teclado Gamer Mecanico Rgb 100% – Quasad QKM-G80	t
177	env combo ge08	Varios	Periferico	Teclado	Combo Gamer Teclado, Mouse, Audif, Pad – Env 9182 GE08	t
178	genius mouse nx-7005	Varios	Periferico	Mouse	Mouse Inalambrico Usb – Genius NX-7005	t
179	env combo g09	Varios	Periferico	Teclado	Combo Mouse + Teclado Gamer – Env 9183 G09	t
180	alcatroz combo xc3000	Varios	Periferico	Teclado	Combo Teclado y Mouse Gamer Usb – Alcatroz XC3000	t
181	quasad combo qc-4583	Varios	Periferico	Teclado	Combo Teclado + Mouse Inalámbrico Recargable – Quasad QC-4583	t
182	logitech combo mk120	Logitech	Periferico	Teclado	Combo Teclado Y Mouse Usb AntiSalpicaduras – Logitech MK120	t
183	msi combo gk100	Msi	Periferico	Teclado	Combo Gamer Teclado + Mouse C/ Cable USB – MSI GK100	t
184	marvo combo cm310	Varios	Periferico	Teclado	Combo Gamer Teclado, Mouse, Pad – Marvo CM310	t
185	evilpc mouse ms-225eg	Varios	Periferico	Mouse	Mouse Gamer P/Pc Rgb – Evil PC MS-225EG	t
186	genius mouse m-700	Varios	Periferico	Mouse	Mouse Gamer P/Pc Rgb 6 Botones – Genius M-700	t
187	logitech mouse g502	Logitech	Periferico	Mouse	Mouse Gamer Programable Rgb – Logitech G502 Hero	t
188	logitech mouse m170	Logitech	Periferico	Mouse	Mouse Inalambrico Usb Colores – Logitech M170	t
189	kingston 16gb ddr4 fury 3600mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston Fury Beast 16GB RGB 3600MHZ – (KF436C18BBA/16)	t
190	genius combo km-160	Varios	Periferico	Teclado	Combo Genius KM-160: Teclado, Mouse	t
191	logitech combo mk200	Logitech	Periferico	Teclado	Logitech MK200: Combo de Combo de teclado y mouse USB – 920-002716	t
192	logitech combo mk320	Logitech	Periferico	Teclado	Logitech MK320: Combo de teclado y mouse inalámbricos – (920-002836)	t
193	marvo combo cm370pm	Varios	Periferico	Teclado	Combo Marvo CM370PM Pink: Teclado, Mouse, Audifonos y Pad	t
194	logitech teclado k380s	Logitech	Periferico	Teclado	TECLADO LOGITECH PEBBLE KEYS 2 K380S – BLUETOOTH – SILENCIOSO – ESPAÑOL – WHITE (920-011784)	t
195	logitech teclado g915	Logitech	Periferico	Teclado	Teclado Logitech G915 TKL Bluetooth Mecanico LightSpeed Rgb (920-009495)	t
196	logitech teclado g815	Logitech	Periferico	Teclado	TECLADO LOGITECH G815 MECANICO LIGHTSYNC RGB – GL TACTILE – G-KEYS – WHITE (920-011354)	t
197	klipxtreme teclado kbk-250	Varios	Periferico	Teclado	Teclado Klip Xtreme Kbk-250 Ergonomico Usb Español	t
198	redragon teclado k719gf-	Redragon	Periferico	Teclado	TECLADO REDRAGON GAMER ARTEMIS PRO K719GF-RGB-PRO WIRELESS – CON PANTALLA LCD – WHITE/BLACK	t
199	logitech combo mk250	Logitech	Periferico	Teclado	KIT DE TECLADO Y MOUSE LOGITECH MK250 COMPACT – WIRELESS/BLUETOOTH – BLACK (920-013513)	t
200	xtratech combo xt-kb277	Varios	Periferico	Teclado	COMBO XTRATECH XT-KB277 TECLADO Y MOUSE INALAMBRICO	t
201	quasad combo qc-4400u	Varios	Periferico	Teclado	COMBO TECLADO – MOUSE MULT. QUASAD QC-4400U Flat Keybcaps Black	t
202	redragon teclado k686	Redragon	Periferico	Teclado	TECLADO MECANICO REDRAGON EISA K686 – WIRELESS/BLUETOOTH/USB-C – KEYCAPS PREMIUM PBT – RGB CHROMA – 100% ANTI-GHOSTING – LINEAL RED – BLACK/WHITE/RED (K686AK-RGB-PRO)	t
203	redragon teclado k621	Redragon	Periferico	Teclado	TECLADO MECANICO REDRAGON K621 HORUS TKL – WIRELESS – BLUETOOTH 5.0 – RGB CHROMA – 100% ANTI-GHOSTING – BLACK (K621-RGB SP-RED)	t
204	marvo teclado kg962-	Varios	Periferico	Teclado	TECLADO MECANICO GAMING MARVO KG962-WHITE-R – 60% SWITCH RED – ANTI-GHOSTING – CABLE TYPE C DESMONTABLE – WHITE	t
205	genius teclado kb-100	Varios	Periferico	Teclado	Teclado Genius Smart KB-100 – USB Español	t
206	genius teclado kb-116	Varios	Periferico	Teclado	Teclado Genius KB-116 – Alambrico – USB, Black	t
207	redragon teclado k512rgb-sp	Redragon	Periferico	Teclado	TECLADO REDRAGON SHIVA K512RGB-SP – MEMBRANA – RGB – REPOSAMUÑECAS MAGNETICO – BLACK	t
208	redragon teclado k552w-	Redragon	Periferico	Teclado	TECLADO REDRAGON KUMARA K552W-RGB SPS-RED – MECANICO TKL – US – DUST-PROOF RED – WHITE	t
209	primus teclado ballista90t	Varios	Periferico	Teclado	TECLADO PRIMUS GAMING BALLISTA90T EDITION STAR WARS MANDALORIAN – MECHANICAL – ANTI-GHOSTING – LINEAR Y SILENT – SWITCH RED (PKS-S092ML-S)	t
210	redragon teclado k621w-	Redragon	Periferico	Teclado	TECLADO MECANICO REDRAGON HORUS TKL K621W-RGB-SP WIRELESS – BLUETOOTH/DONGLE RF USB	t
211	redragon teclado k599-krs	Redragon	Periferico	Teclado	TECLADO MECANICO REDRAGON DEIMOS K599-KRS – TKL 70% – WIRELESS/WIRED – RGB CHROMA – SWITCH LINEAR – 45 GR – BLACK	t
212	logitech teclado k120	Logitech	Periferico	Teclado	Teclado Logitech K120	t
213	genius combo c126	Varios	Periferico	Teclado	COMBO TECLADO Y MOUSE GENIUS SLIMSTAR C126 WIRED – BLACK	t
214	logitech combo mk850	Logitech	Periferico	Teclado	Combo Teclado y Mouse Logitech MK850 Wireless / 920-008219 – 920008659	t
215	teros te-1914s	Varios	Monitor	NaN	MONITOR TEROS TE-1914S 19.5″ 1600X900 – 5MS – 220 NITS – HDMI – VGA	t
216	samsung ur55	Samsung	Monitor	IPS	MONITOR SAMSUNG UR55 – 28″ 4K UHD IPS HDR10 – 4MS – 60HZ – HDMI/DP (LU28R550UQNXZA)	t
217	msi g274rw	Msi	Monitor	IPS	MONITOR MSI OPTIX G274RW – 27″ FHD IPS – 170HZ – 1MS (MPRT) – HDMI/DP – WHITE	t
218	lg 27gr75q-b	Lg	Monitor	IPS	MONITOR LG ULTRAGEAR 27GR75Q-B 27″ QHD 2560X1440 – 165HZ – IPS 1MS GTG – SRGB 99% – ANTI-GLARE – HDR10 – HDMI 2.2/DP 1.4 – BLACK	t
219	lg 32mn600p-b	Lg	Monitor	IPS	MONITOR LG 32MN600P-B 31.5″ IPS FULL HD AMD FREESYNC	t
220	lg 27qn600-b	Lg	Monitor	IPS	MONITOR LG 27QN600-B 27″ IPS 2K QHD 2560×1440 – SRGB >99% – 75HZ – 5ms – HDR – FREESYNC- HDMI/DP	t
221	gigabyte m32qc-sa	Gigabyte	Monitor	NaN	MONITOR GIGABYTE M32QC-SA 31.5″ QHD – 165HZ – HDR400 – 1MS MPRT – HDMI – 94% DCI-P3/123% sRGB – 2.0/DP 1.2	t
222	gigabyte gs34wqc	Gigabyte	Monitor	VA	MONITOR GIGABYTE GS34WQC – 34″ VA 1500R – WQHD 3440X1440 – NON-GLARE – 120% SRGB – 1MS MPRT – 135HZ – HDR – HDMI 2.0/DP 1.4 – BLACK	t
223	gigabyte gs27q	Gigabyte	Monitor	IPS	MONITOR GIGABYTE GS27Q – 27″ SS IPS – 2K QHD 2560X1440 – NON-GLARE – 100% SRGB – 1MS MPRT – 170HZ – HDR – HDMI 2.0/DP 1.4 – BLACK	t
224	env 1esm1695	Varios	Monitor	VA	MONITOR ENV 1ESM1695 – 21.5″ FULL HD 1920×1080 – VA – 230 NITS – 75HZ – 6.5MS – VGA/HDMI – VESA	t
225	env 1eenv1711	Varios	Monitor	VA	MONITOR ENV 1EENV1711 – 24″ FHD – PANEL VA – 300 NITS – 16MS – VGA/HDMI	t
226	corsair 32uhd144-a	Corsair	Monitor	IPS	MONITOR CORSAIR XENEON 32UHD144-A – 32″ UHD IPS – 144HZ – HDR600 – NON-GLARE – 100% ADOBE RGB – 1MS – AMD FREESYNC PREMIUM – BLACK (CM-9020006-NA)	t
227	asus vy27uq	Asus	Monitor	IPS	MONITOR ASUS VY27UQ – 27″ 4K (3840 x 2160) – NON-GLARE – IPS – DHR-10 – ADAPTIVE SYNC – EYE CARE – DP/HDMI – BLACK	t
228	asus va27ehf	Asus	Monitor	IPS	MONITOR ASUS VA27EHF 27″ Full HD – IPS – 100Hz 1ms – VRR Adaptive-Sync – HDMI(v1.4)	t
229	asus va24ehf	Asus	Monitor	IPS	MONITOR ASUS VA24EHF 24″ (23.8″) Full HD – IPS – 100Hz 1ms – VRR Adaptive-Sync – HDMI(v1.4)	t
230	asus vg248q1b	Asus	Monitor	TN	MONITOR ASUS TUF VG248Q1B 24″ FHD LED – PANEL TN – 165HZ – 0.5MS GTG – FREESYNC PREMIUM – DP 1.2/HDMI V1.4	t
231	msi teclado gk600	Msi	Periferico	Teclado	TECLADO MSI FORGE GK600 TKL WIRELESS/BT/USB – 83 TECLAS – 20 MODE RGB – SUB PBT – 100% ANTI-GHOSTING – LINEAR – WHITE/VIOLET	t
232	logitech teclado g515	Logitech	Periferico	Teclado	TECLADO LOGITECH G515 TKL – TACTICAL – TECLAS PBT – TACTILE – LIGHTSYNC RGB – GRAFITE (920-012868)	t
233	redragon teclado k616-	Redragon	Periferico	Teclado	TECLADO MECANICO REDRAGON FIZZ PRO WIRELESS K616-RGB WG – 60% – DUST PROOF RED – 430G – USB-C – WHITE/GRAY	t
234	redragon teclado k550rgb-1-sp	Redragon	Periferico	Teclado	TECLADO MECANICO REDRAGON YAMA K550RGB-1-SP – RGB CHROMA – 100% ANTI-GHOSTING – BLACK	t
235	genius teclado kb-117	Varios	Periferico	Teclado	TECLADO GENIUS KB-117 ALAMBRICO USB – BLACK	t
236	corsair teclado k70	Corsair	Periferico	Teclado	TECLADO CORSAIR GAMING K70 CORE RGB – MECANICO – MLX RED – 100% ANIT-GHOSTING – BLACK (CH-910971E-SP)	t
237	meetion teclado mt-mk20	Varios	Periferico	Teclado	TECLADO MEETION MT-MK20 LINA INVERSE – MECANICO – SWITCH BLUE – ANTI-GHOSTING – BLACK/RED	t
238	marvo teclado kg962	Varios	Periferico	Teclado	TECLADO MECANICO GAMING MARVO KG962 – 60% SWITCH RED – ANTI-GHOSTING – CABLE TYPE C DESMONTABLE – BLACK	t
239	marvo teclado kg980a	Varios	Periferico	Teclado	TECLADO MARVO KG980A TKL MECHANICAL RGB – USB 2.0 – BLACK	t
240	marvo teclado kg962-b	Varios	Periferico	Teclado	TECLADO MARVO KG962-B – 60% RGB – 100% ANTI-GHOSTING – USB TYPE-C – SWITCH BLUE – BLACK	t
241	genius teclado kb-100x	Varios	Periferico	Teclado	TECLADO GENIUS KB-100X – ALAMBRICO – USB – ESPAÑOL	t
242	logitech mouse 25600dpi	Logitech	Periferico	Mouse	MOUSE LOGITECH GAMING G309 LIGHTSPEED/BLUETOOTH – BATERIA AA – 25600DPI – WHITE (910-007205)	t
243	logitech mouse m350	Logitech	Periferico	Mouse	MOUSE LOGITECH PEBBLE M350 WIRELESS USB BLUETOOTH SILENCIOSO – ALMOND MILK (910-006658)	t
244	logitech mouse m110s	Logitech	Periferico	Mouse	MOUSE LOGITECH M110S SILENT BLUE ALAMBRICO – DISENO AMBIDIESTRO – USB (910-006662)	t
245	hyperx mouse 26000dpi	Hyperx	Periferico	Mouse	MOUSE HYPERX PULSEFIRE HASTE 2 – 26000DPI – ULTRA-LIGH – WIRED – RGB – 52G – BLACK (6N0A7AA)	t
246	corsair mouse 26000dpi	Corsair	Periferico	Mouse	MOUSE CORSAIR M65 RGB ULTRA – WIRED – OPTICAL – 8 BOTONES – 26000DPI PESO AJUSTABLE – 2 ZONE RGB – BLACK (CH-9309411-NA2)	t
247	genius combo km-8101	Varios	Periferico	Teclado	COMBO TECLADO Y MOUSE GENIUS KM-8101 WIRELESS 2.4GHZ – PLUG AND PLAY – US	t
248	primus audifonos arcus110t	Varios	Periferico	Headset	AUDIFONOS PRIMUS ARCUS ARCUS110T STAR WARS EDITION DARK SIDE – 3.5MM – OMNIDIRECCIONAL – STEREO – 50MM – BLACK/RED (PHS-S110DS)	t
249	logitech audifonos g433	Logitech	Periferico	Headset	ALMOHADILLAS DE REPUESTO PARA AUDIFONOS LOGITECH G433/G935/G533/G332 – BLACK	t
250	logitech audifonos g733	Logitech	Periferico	Headset	ALMOHADILLAS DE REPUESTO PARA AUDIFONOS LOGITECH G733 + CORREA DE REPUESTO – BLACK	t
251	cougar audifonos 53mm	Varios	Periferico	Headset	AUDIFONOS GAMING COUGAR OMNES ESSENTIAL – WIRELESS – MIC OMNIDIRECTIONAL – 53MM – BLACK (3HW50G53B.0001)	t
252	corsair audifonos hs60	Corsair	Periferico	Headset	Headsets Corsair HS60 HAPTIC	t
253	primus audifonos arcus240	Varios	Periferico	Headset	AUDIFONOS PRIMUS ARCUS240 EDICION STAR WARS EDITION DEATH TROOPER – BLUETOOTH – 12MM – IPX5 – BLACK (PWH-S240DT)	t
254	marvo combo cm370	Varios	Periferico	Teclado	Combo Marvo CM370: Teclado, Mouse, Audifonos y Pad	t
255	marvo combo cm409	Varios	Periferico	Teclado	Combo Marvo CM409: Teclado, Mouse, Audifonos y Pad	t
256	logitech audifonos h111	Logitech	Periferico	Headset	Headsets Logitech H111	t
257	meetion audifonos mt-hp010	Varios	Periferico	Headset	Headsets Meetion MT-HP010	t
258	coolermaster audifonos ch321	Varios	Periferico	Headset	Headsets Cooler Master CH321	t
259	corsair audifonos st50	Corsair	Periferico	Headset	Base para headsets Corsair ST50 Premium	t
261	corsair audifonos hs45	Corsair	Periferico	Headset	Headsets Corsair HS45 Carbon	t
262	logitech audifonos a20	Logitech	Periferico	Headset	Headset Audifono Logitech ASTRO A20 Inalambricos Xbox One, Green/Black (939-001557)	t
263	logitech mouse m240	Logitech	Periferico	Mouse	MOUSE LOGITECH M240 WIRELESS BLUETOOTH – 4000 DPI – SILENT – GRAFITO (910-007113)	t
264	razer mouse 58g	Razer	Periferico	Mouse	MOUSE RAZER COBRA CHROMA™ RGB – 58G – 8500 DPI – BLACK (RZ01-04650100-R3U1)	t
265	razer mouse 30k	Razer	Periferico	Mouse	MOUSE RAZER DEATHADDER V3 ERGONOMIC – 8K HZ 30K SENSOR – 59G – BLACK (RZ01-04640100-R3U1)	t
266	gamdias mouse 3600dpi	Varios	Periferico	Mouse	MOUSE GAMDIAS AURA GS3 RGB – 6 BOTONES – 3600DPI – BLACK	t
267	genius combo q8000	Varios	Periferico	Teclado	COMBO TECLADO Y MOUSE GENIUS Q8000 WIRELESS – 12 FN KEYS – PLUG AND PLAY – BLACK	t
268	msi mouse 8000dpi	Msi	Periferico	Mouse	MOUSE MSI VERSA 300 WIRELESS – 8000DPI – BLUETOOTH – 60G – WHITE	t
269	msi mouse 12800dpi	Msi	Periferico	Mouse	MOUSE MSI FORGE GM320 RGB – 12800DPI – 7 BOTONES – SENSOR OPTICAL – USB 2.0 – BLACK	t
270	msi mouse 7200dpi	Msi	Periferico	Mouse	MOUSE MSI FORGE GM300 – 7200DPI – 7 BOTONES – RGB – BLACK	t
271	lenovo mouse 1600dpi	Varios	Periferico	Mouse	MOUSE LENOVO 300 USB – 1600DPI – BLACK	t
272	razer mouse 750ips	Razer	Periferico	Mouse	MOUSE RAZER BASILISK V3 35K – RGB – 750IPS – 70G – OPTICAL – 11 BOTONES – BLACK (RZ01-05230100-R3U1)	t
273	razer mouse 8500dpi	Razer	Periferico	Mouse	MOUSE RAZER COBRA CHROMA™ RGB GENGAR EDITION – 58G – 8500DPI – 6 BOTONES PROGRAMABLES – 300IPS – BLACK (RZ01-04650700-R3M1)	t
274	primus mouse 10000dpi	Varios	Periferico	Mouse	Mouse Primus Gladius DM100 RBG – INALÁMBRICO/ALÁMBRICO – 10000DPI – 6 BOTONES – 20G – 100IPS – WHITE/BLACK (PMO-W203)	t
275	logitech mouse 8000dpi	Logitech	Periferico	Mouse	MOUSE LOGITECH MX MASTER 3S BLUETOOTH EDITION – ERGONOMICO – 7 BOTONES – 8000DPI – GRAFITO (910-007502)	t
276	razer mouse 400hrs	Razer	Periferico	Mouse	MOUSE RAZER GAMER NAGA V2 HYPERSPEED WIRELESS – 19 BOTONES PROGRAMABLES -30K – HASTA 400HRS – HYPERSCROLL – BLACK	t
277	logitech mouse m110	Logitech	Periferico	Mouse	MOUSE LOGITECH M110 SILENT – WIRED – FULL SIZE – BLACK (910-006756)	t
278	lenovo mouse m200	Varios	Periferico	Mouse	Mouse Lenovo Legion M200 RGB – 6 botones – USB	t
279	meetion mouse mt-g3330	Varios	Periferico	Mouse	MOUSE GAMING MEETION HERA MT-G3330 RGB LED – 9 BOTONES – 8000DPI – USB – BLACK	t
280	meetion mouse mt-g3325	Varios	Periferico	Mouse	MOUSE GAMING HADES MEETION PRO MT-G3325 RGB COLORFUL – 8 BOTONES – 5000DPI – BLACK	t
281	coolermaster mouse mm711	Varios	Periferico	Mouse	Mouse Cooler Master MM711 Blue	t
282	quasad mouse qm-g10	Varios	Periferico	Mouse	Mouse Quasad QM-G10	t
283	logitech mouse m196	Logitech	Periferico	Mouse	MOUSE LOGITECH M196 BLUETOOTH – 1000 DPI – BATERÍA AA – ROSE (910-007458)	t
284	logitech mouse 44000dpi	Logitech	Periferico	Mouse	MOUSE LOGITECH G PRO 2 LIGHTSPEED RGB WIRELESS – 44000DPI – >888 IPS – 1MS – 80G – BLACK (910-007246)	t
285	logitech mouse 32000dpi	Logitech	Periferico	Mouse	MOUSE LOGITECH GAMING G PRO X SUPERLIGHT 2 LIGHTSPEED WIRELESS/USB CONNECTIVITY – 32000DPI – 0.5 RESPONSE TIME – 5 BOTONES – WHITE (910-006636)	t
286	teros te-2124s	Varios	Monitor	IPS	MONITOR TEROS TE-2124S 21.45″ FHD IPS – 100HZ – 5MS – PLANO – HDMI/VGA – BLACK	t
287	teros te-2401s	Varios	Monitor	VA	MONITOR TEROS TE-2401S – 23.8″ CURVO R3000 VA – FHD – 5MS – 100HZ – HDMI/VGA – BLACK	t
288	teros te-2411s	Varios	Monitor	NaN	MONITOR TEROS TE-2411S GAMING 24″ 1920X1080 – 1ms – 200 NITS – 100HZ – HDMI/VGA	t
289	asus vg259qm5a	Asus	Monitor	IPS	Monitor Asus TUF VG259QM5A | 24.5″ IPS Full HD 240Hz 0.3ms | 99% SRGB | G-Sync/FreeSync	t
290	corsair 16gb ddr5 vengeance 4800mhz	Corsair	RAM	DDR5	Memoria RAM DDR5 Corsair Vengeance 16GB DDR5 4800MHZ Black – (CMK32GX5M2A4800C40)	t
291	kingston 16gb ddr4 2666mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston 16GB 2666Mhz – (KVR26N19D8/16)	t
292	kingston 16gb ddr4 fury 3200mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston Fury Beast 16GB 3200MHZ – (KF432C16BB/16)	t
293	kingston 8gb ddr4 value 2666mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston Value 8GB 2666Mhz – (KVR26N19S8/8)	t
294	hyperx 8gb ddr4 fury 3733mhz	Hyperx	RAM	DDR4	Memoria RAM DDR4 HyperX Fury 8GB 3733MHz – (HX437C19FB3A/8)	t
295	hyperx 8gb ddr4 fury 2666mhz	Hyperx	RAM	DDR4	Memoria RAM DDR4 HyperX Fury RGB 8GB 2666MHz – (HX426C16FB3A/8)	t
296	kingston 8gb ddr4 fury 3600mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston Fury Beast 8GB 3600MHZ – (KF436C17BB/8)	t
297	hyperx 8gb ddr4 predator 3200mhz	Hyperx	RAM	DDR4	Memoria RAM DDR4 HyperX PRedATOR RGB 8GB 3200MHz – (HX432C16PB3A/8)	t
298	hp 8gb ddr4 2666mhz	Varios	RAM	DDR4	Memoria RAM DDR4 HP V6 Red 8GB 2666Mhz – (7EH61AA#ABM)	t
299	hp 8gb ddr4 sodimm 2666mhz	Varios	RAM	DDR4	Memoria RAM DDR4 SO-DIMM HP S1 Series 8GB 2666 Mhz – (7EH98AA#ABM)	t
300	kingston 8gb ddr4 sodimm value 2666mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Kingston Value 8GB 2666Mhz – (KVR26S19S6/8)	t
301	hyperx 16gb ddr4 fury 2666mhz	Hyperx	RAM	DDR4	Memoria RAM DDR4 HyperX Fury 16GB 2666Mhz – (HX426C16FB4/16)	t
302	hyperx 8gb ddr4 predator 3000mhz	Hyperx	RAM	DDR4	Memoria RAM DDR4 HyperX Predator RGB 8GB 3000MHz – (HX430C15PB3A/8)	t
303	hp 8gb ddr4 3200mhz	Varios	RAM	DDR4	Memoria RAM DDR4 HP V8 RGB 8GB 3200Mhz – (7EH85AA#ABM)	t
304	hyperx 16gb ddr4 sodimm 2666mhz	Hyperx	RAM	DDR4	Memoria RAM DDR4 SO-DIMM HyperX Impact 16GB 2666Mhz – (KF426S15IB1/16)	t
305	hyperx 16gb ddr4 fury 3000mhz	Hyperx	RAM	DDR4	Memoria RAM DDR4 HyperX Fury RGB 16GB 3000Mhz – (HX430C15FB3A/16)	t
306	hp 8gb ddr4 3000mhz	Varios	RAM	DDR4	Memoria RAM DDR4 HP V8 8GB 3000Mhz – (7EH82AA#ABM)	t
307	xpg 8gb ddr4 3200mhz	Adata	RAM	DDR4	Memoria RAM DDR4 Adata XPG Spectix D60G RGB 8GB 3200Mhz – (AX4U32008G16A-ST60)	t
308	corsair 4gb ddr4 sodimm vengeance 2400mhz	Corsair	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Corsair Vengeance 4GB 2400MHZ – (CMSX4GXM1A2400C16)	t
309	corsair 16gb ddr4 vengeance 3000mhz	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance LPX 16GB 3000MHZ – (CMK16GX4M1D3000C16)	t
310	corsair 16gb ddr4 vengeance 3600mhz	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance RGB PRO 16GB 3600Mhz – (CMW16GX4M1Z3600C18)	t
311	kingston 32gb ddr5 fury 5600mhz	Kingston	RAM	DDR5	Ram Kingston Fury Beast RGB 32GB DDR5 5600MT/s – Black	t
312	kingston 16gb ddr5 fury 5600mhz	Kingston	RAM	DDR5	Ram Kingston Fury Beast RGB 16GB DDR5 5600MT/s – Black	t
313	kingston 8gb sodimm 1600mhz	Kingston	RAM	DDR3	Memoria Ram Kingston 8GB DDR3L 1600MHz So-Dimm (KVR16LS11/8)	t
314	kingston 8gb ddr4 fury 2666mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 Kingston Fury 8GB 2666Mhz	t
315	xpg 8gb ddr4 spectrix 3000mhz	Xpg	RAM	DDR4	Memoria RAM DDR4 XPG Spectrix D50 RGB 8GB 3000Mhz – (AX4U30008G16A-ST50)	t
316	kingston 8gb ddr4 sodimm 3200mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Kingston 8GB 3200MHz – (KVR32S22S8/8)	t
317	kingston 16gb ddr4 sodimm 3200mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Kingston 16GB 3200Mhz – (KVR32S22D8/16)	t
318	kingston 16gb ddr4 sodimm 2666mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Kingston 16GB 2666MHz – (KVR26S19S8/16)	t
319	corsair 16gb ddr4 vengeance 3200mhz	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance RGB PRO 16GB 3200Mhz – (CMW16GX4M1Z3200C16)	t
320	kingston 8gb ddr4 sodimm fury 3200mhz	Kingston	RAM	DDR4	Memoria RAM DDR4 SO-DIMM Kingston Fury Impact 8GB 3200MHZ – (KF432S20IB/8)	t
321	kingston 16gb ddr5 fury 4800mhz	Kingston	RAM	DDR5	Memoria RAM DDR5 Kingston Fury Beast 16GB DDR5 4800MHz CL38 BLACK – (KF548C38BBK2/32)	t
322	corsair 8gb ddr4 vengeance 3600mhz	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance LPX 8GB 3600Mhz – (CMK8GX4M1Z3600C18)	t
323	corsair 8gb ddr4 vengeance 3000mhz	Corsair	RAM	DDR4	Memoria RAM DDR4 Corsair Vengeance LPX 8GB 3000MHz – (CMK8GX4M1D3000C16)	t
324	asus xg27acmes	Asus	Monitor	NaN	Monitor Asus ROG STRIX XG27ACMES | 27″ 2K 255Hz 0.3ms | G-SYNC | HDR	t
325	teros te-2711s	Varios	Monitor	IPS	MONITOR TEROS TE-2711S 27″ FHD – 100HZ – 1MS – IPS – HDMI	t
326	acer k202q	Acer	Monitor	NaN	MONITOR ACER K202Q – 19.5″ HD (1600X900) – 75HZ – 5MS – 200 NITS – HDMI/VGA – BLACK (UM.IE0AA.004)	t
327	samsung s36gd	Samsung	Monitor	NaN	MONITOR SAMSUNG GAMING ESSENTIAL S3 S36GD – 27″ FHD (1920X1080) – 100HZ – 4MS – D-SUB/HDMI – BLACK (S27D366GAN)	t
328	teros te-2787g	Varios	Monitor	NaN	MONITOR TEROS TE-2787G 27″ FHD CURVO – 180HZ – 2MS – DP/HDMI	t
329	msi 275cqf	Msi	Monitor	NaN	MONITOR GAMING MSI MAG 275CQF E18 – 27″ WQHD 2K(2560X1440) – CURVO 180HZ – 0.5MS (GTG) – HDR READY – HDMI 2.0b/DP 1.4a – BLACK (9S6-3CE91H-004)	t
330	lg 27gs65f-b	Lg	Monitor	IPS	MONITOR LG ULTRAGEAR 27GS65F-B – 27” FHD IPS – 180HZ – 1MS – HDR10 – G-SYNC/FREESYNC – BLACK	t
331	asus vp227he	Asus	Monitor	VA	MONITOR ASUS VP227HE – 21.45″ FHD – 75HZ – NON-GLARE – VA – 5MS GTG – HDMI v1.4/VGA – BLACK	t
332	asus 1920x1080p	Asus	Monitor	IPS	MONITOR ASUS TUF GAMING VG279Q1A – 27″ FHD 1920X1080P – PANEL IPS – NON-GLARE – 1MS MPRT – 165HZ – FREESYNC PREMIUM – DP 1.2/HDMI V1.4	t
333	asus vg249q1a	Asus	Monitor	IPS	MONITOR ASUS TUF GAMING VG249Q1A – 23.8″ FHD 1920×1080 – PANEL IPS – NON-GLARE – 1MS MPRT – 165HZ – FREESYNC PREMIUM – DP 1.2/HDMI V1.4	t
334	asus vg27wq1b	Asus	Monitor	NaN	Monitor ASUS TUF Gaming VG27WQ1B CURVO 27″ 165Hz 1ms WQHD (2560×1440) (90LM0671-B011B0)	t
335	asus xg27ucs	Asus	Monitor	IPS	MONITOR ASUS ROG STRIX GAMING XG27UCS 27″ UHD (3840X2160) IPS – 160HZ – 1MS – HDMI/DP – BLACK	t
336	asus vg32vq1b	Asus	Monitor	NaN	MONITOR ASUS TUF VG32VQ1B 32″ CURVO WQHD (2560x1440P) – 165HZ – 1MS – SPEAKERS – DP/HDMI – BLACK	t
337	asus vg34vql3a	Asus	Monitor	NaN	MONITOR ASUS TUF GAMING VG34VQL3A 34″ CURVO – WQHD (3440X1440P) – 180 HZ – 1MS – HDMI/DP – BLACK	t
338	asus xg27acs	Asus	Monitor	IPS	MONITOR ASUS ROG STRIX GAMING XG27ACS – 27″ QHD IPS – NON-GLARE – 180HZ – 1MS GTG – HDR – HDMI/DP/USB-C – BLACK	t
339	asus pa329crv	Asus	Monitor	IPS	Monitor Asus ProArt PA329CRV 32″ | Plano IPS 4K | USB-C	t
340	asus pg27aqdm	Asus	Monitor	OLED	MONITOR ASUS GAMING ROG SWIFT OLED PG27AQDM – 26.5″ 2560X1440 – WOLED – NON-GLARE – 135% SRGB – DCI-P3 99% – 0.03MS GTG – HDR10 – 240HZ – DP 1.4 DSC/HDMI 2.0 – BLACK	t
341	teros te-2123s	Varios	Monitor	IPS	MONITOR TEROS TE-2123S – 21.45″ FHD IPS – 1MS – 100HZ – HDMI/VGA – BLACK	t
342	lg 29wq500-b	Lg	Monitor	IPS	Monitor LG 29WQ500-B 29″ ULTRAWIDE 21:9 FULL HD 2560×1080 – IPS – 1ms – HDMI+DP	t
343	asus vg289q	Asus	Monitor	NaN	Monitor Asus TUF VG289Q	t
344	asus pa247cv	Asus	Monitor	IPS	Monitor ASUS PROART PA247CV 23.8″ FULL HD – IPS – 100% sRGB – 75HZ – 5MS – DP/HDMI/USB-C – BLACK (90LM03Y1-B013B0)	t
345	teros te-2766g	Varios	Monitor	VA	MONITOR TEROS TE-2766G – 27″ FHD CURVO R1500 – VA – 180HZ – 1MS – HDMI/VGA – BLACK	t
346	msi 346cq	Msi	Monitor	VA	MONITOR MSI MAG 346CQ – 34″ UWQHD (3440X1440) – VA – 1MS (MPRT) – CURVED 1500R – 180HZ – 16:9 – HDR READY – HDMI/DP – BLACK (9S6-3DD71M-004)	t
347	gigabyte m27up	Gigabyte	Monitor	IPS	MONITOR GIGABYTE M27UP ICE SA1 – 27″ UHD (3840X2160P) SS IPS – 160HZ/320-HZ FHD – 1MS GTG – HDMI/DP – SPEAKER – HDR400 – NON-GLARE – WHITE	t
348	asus mb166c	Asus	Monitor	IPS	Monitor Portatil Asus ZenScreen MB166C | 15.6″ FHD IPS | USB-C/DP	t
349	teros te-1916s	Varios	Monitor	NaN	MONITOR TEROS TE-1916S 19.5″ 1600X900 – 5MS – 75HZ – HDMI/VGA	t
350	msi 275qf	Msi	Monitor	IPS	MONITOR MSI GAMING MAG 275QF – 27″ WQHD (2560X1440) IPS – 180HZ – 0.5MS GTG – HDMI/DP – BLACK (9S6-3CE21M-014)	t
351	lg 29u511a-b	Lg	Monitor	IPS	Monitor LG 29U511A-B ULTRAWIDE 29″ – IPS – 2560×1080 – HDMI – 100HZ – sRGB 99% – 5MS (GTG)	t
352	teros te-2415s	Varios	Monitor	IPS	MONITOR TEROS TE-2415S 24″ GAMING PLANO IPS | FHD | 120HZ 1ms | DP – HDMI – VGA	t
353	asus va279qgs	Asus	Monitor	IPS	MONITOR EMPRESARIAL ASUS VA279QGS – 27″ IPS FHD (1920X1080) – 120HZ – 1MS – HDMI/DP/VGA/USB – BLACK	t
354	msi 274qf	Msi	Monitor	IPS	MONITOR MSI MAG 274QF X24 – 27″ WQHD (2560X1440) – FAST IPS – 0.5MS – 240HZ – HDMI/DP – BLACK (9S6-3CE41H-020)	t
355	gigabyte mo27q28g	Gigabyte	Monitor	OLED	Monitor Gigabyte MO27Q28G OLED | 27″ 2K | 280Hz	t
356	gigabyte gs32q	Gigabyte	Monitor	IPS	Monitor Gigabyte GS32Q 32″» SS-IPS QHD | 165Hz | Plano	t
357	gigabyte m27q2	Gigabyte	Monitor	IPS	Monitor Gigabyte M27Q2 ICE 27″ IPS 2K QHD | OC 210Hz | Plano | Blanco	t
358	gigabyte 4k200hz	Gigabyte	Monitor	IPS	Monitor Gigabyte M28U 28″ SS IPS 4K200Hz 1ms	t
359	msi mpg-491cqp-	Msi	Monitor	OLED	Monitor MSI MPG-491CQP-QD-OLED 49″ UltraWide Curvo	t
360	asus pa248qfv	Asus	Monitor	IPS	Monitor ASUS ProArt PA248QFV 24″ IPS WUXGA | 100HZ | HDR	t
361	samsung ls24a608ucn	Samsung	Monitor	NaN	MONITOR SAMSUNG LS24A608UCN – 24″ WQHD 2560X1440 – ULTRA-THIN – 5MS – 75HZ – HDMI/DP	t
362	asus pa279crv	Asus	Monitor	NaN	Monitor Asus ProArt PA279CRV 27″ 4K | 99% DCI-P3 | 99% ADOBE RGB | HDR400	t
363	benq xl2411p	Benq	Monitor	NaN	Monitor E-Sports BenQ Zowie XL2411P – 24″	t
364	rx 9070 xt	AMD	GPU	NaN	Tarjeta de video Gigabyte Aorus Radeon RX 9070 XT ELITE 16G	t
365	ryzen 9 9900x	AMD	CPU	NaN	PROCESADOR AMD RYZEN 9 9900X 5.6GHZ 12+24 AM5	t
366	hiksemi 16gb ddr4 sodimm 3200mhz	Varios	RAM	DDR4	MEMORIA SODIMM HIKSEMI 16GB DDR4 3200MHz	t
367	ryzen 7 7700 5	AMD	CPU	NaN	PROCESADOR AMD RYZEN 7 7700 5.3GHZ 8+16 AM5	t
368	rtx 5080 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ZOTAC AMP EXTREME INFINITY GEFORCE RTX 5080 16GB GDDR7	t
369	rtx 5060 ti 16gb	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL EVO GEFORCE RTX 5060 TI 16GB OC	t
370	ryzen 9 5900xt	AMD	CPU	NaN	PROCESADOR AMD RYZEN 9 5900XT 4.8GHZ 16+32 AM4	t
371	ryzen 5 9600 5	AMD	CPU	NaN	PROCESADOR AMD RYZEN 5 9600 5.2GHZ 6+12 AM5	t
372	adata 512gb nvme	Adata	SSD	NVMe	DISCO SOLIDO SSD INT M.2 ADATA 512GB 2280 LEGEND 710 PCle Gen3 x4	t
373	lenovo 240gb nvme	Varios	SSD	NVMe	DISCO LENOVO M.2 5300 240GB SATA 6GBPS Non HS SSD/SR250V2,ST550,SR530,SR550,SR570,SR630,SR650,650 V2	t
374	thunderobot teclado k104	Varios	Periferico	Teclado	Thunderobot K104 Teclado Mecánico Red Switch	t
375	thunderobot teclado kg3089c	Varios	Periferico	Teclado	Thunderobot KG3089C Teclado Negro Mecánico Blue Switch	t
376	redragon mouse m811	Redragon	Periferico	Mouse	Redragon Aatrox M811 Rgb MMO Mouse 15 Botones	t
377	redragon mouse m607	Redragon	Periferico	Mouse	Redragon Griffin M607 Mouse Gamer RGB 7200 DPI	t
378	redragon mouse m916	Redragon	Periferico	Mouse	Redragon K1ng M916 Ultra Mouse 8K Hz 30K Dpi	t
379	hiksemi 512gb sata	Varios	SSD	SATA	DISCO SOLIDO SSD INT HIKSEMI WAVE 512GB SERIES 2.5" SATA 3.0	t
380	genius mouse 8350s	Varios	Periferico	Mouse	Genius Ergo 8350S Mouse Vertical Wireless	t
381	rx 9070 gaming	AMD	GPU	NaN	Tarjeta de video Gigabyte Radeon™ RX 9070 GAMING OC 16G GDDR6X	t
382	cougar mouse 20k	Varios	Periferico	Mouse	Cougar AirBlader Tournament Mouse Gamer 20k Dpi White	t
383	hiksemi 512gb nvme	Varios	SSD	NVMe	DISCO SOLIDO SSD INT M.2 HIKSEMI WAVE 512GB 2280 NVME PCIe SATA 3.0	t
384	redragon audifonos h260	Redragon	Periferico	Headset	Redragon Hylas H260 RGB Auriculares Gamer	t
385	core ultra 5 250kf	Intel	CPU	NaN	PROCESADOR INTEL CORE ULTRA 5 250KF PLUS 5.3GHZ 22TOPS 18+18 LGA 1851	t
386	genius mouse 1000dpi	Varios	Periferico	Mouse	Mouse Genius Óptico DX-110, Alámbrico, USB, 1000DPI, Negro	t
387	logitech mouse 600dpi	Logitech	Periferico	Mouse	Mouse Gamer LIGHTSPEED Logitech G Pro, Inalámbrico, Óptico, 25.600DPI	t
388	kingston 16gb ddr5 sodimm fury 5600mhz	Kingston	RAM	DDR5	16GB RAM SO-DIMM DDR5 KINGSTON FURY IMPACT 5600MTS CL40	t
389	xpg 16gb ddr5 lancer 6000mhz	Xpg	RAM	DDR5	16GB RAM DDR5 XPG LANCER BLADE BLACK 6000MTS CL48	t
390	samsung g91sd	Samsung	Monitor	OLED	MONITOR ULTRAWIDE CURVO SAMSUNG ODYSSEY OLED G9 G91SD	t
391	samsung s65uc	Samsung	Monitor	NaN	MONITOR ULTRAWIDE CURVO SAMSUNG VIEWFINITY S6 S65UC	t
392	quasad mouse 1600dpi	Varios	Periferico	Mouse	Mouse QUASAD QM-850 wireless 1600dpi recargable Red/Negro	t
393	lg 27g411a	Lg	Monitor	NaN	MONITOR LG ULTRAGEAR 27G411A	t
394	samsung g60f	Samsung	Monitor	NaN	MONITOR SAMSUNG ODYSSEY G6 G60F	t
395	msi 321urx	Msi	Monitor	OLED	MONITOR MSI MPG 321URX QD-OLED	t
396	teros te-2767g	Varios	Monitor	NaN	MONITOR CURVO TEROS TE-2767G	t
397	teros te-3219g	Varios	Monitor	NaN	MONITOR CURVO TEROS TE-3219G	t
398	lg 24g411a	Lg	Monitor	NaN	MONITOR LG ULTRAGEAR 24G411A	t
399	kingston 32gb ddr5 sodimm fury 5600mhz	Kingston	RAM	DDR5	32GB RAM SO-DIMM DDR5 KINGSTON FURY IMPACT 5600MTS CL40	t
400	rx 6900 xt	AMD	GPU	NaN	TARJETA DE VIDEO GIGABYTE AORUS XTREME RADEON RX 6900 XT 16GB GDDR6	t
401	rx 9070 16gb	AMD	GPU	NaN	TARJETA DE VIDEO GIGABYTE GAMING AMD RADEON RX 9070 16GB OC GDDR6	t
402	redragon teclado k616	Redragon	Periferico	Teclado	Redragon FIZZ PRO K616 RGB Teclado Wireless Blanco	t
403	redragon teclado k530	Redragon	Periferico	Teclado	Redragon Draconic K530 OG Teclado Gamer Wireless 60%	t
404	xtech audifonos xth-241	Varios	Periferico	Headset	AUDIFONO + MICROFONO XTECH XTH-241 ON EAR USB-A	t
405	primus teclado 1000hz	Varios	Periferico	Teclado	TECLADO PRIMUS ALAMBRICO GAMER USB 105 TECLAS 1000Hz ANTI-GHOSTING	t
406	logitech teclado k250	Logitech	Periferico	Teclado	TECLADO LOGITECH INALAMBRICO K250 BLUETOOTH - NEGRO	t
407	hp teclado 15-fd	Varios	Periferico	Teclado	TECLADO HP 15-FD 15-FC GRAY	t
408	asus teclado g713qe	Asus	Periferico	Teclado	TECLADO ASUS G713 G713Q G713QE G713QM BLACK US (RGB BLACKLIT WIN8)	t
409	ryzen 7 7700x	AMD	CPU	NaN	Amd Ryzen 7 7700X 4.5Ghz Am5 8 Núcleos 16 hilos	t
410	logitech teclado g213	Logitech	Periferico	Teclado	TECLADO LOGITECH ALAMBRICO GAMER G213 PRODIGY USB - INGLES	t
411	rtx 5070 12g	NVIDIA	GPU	NaN	Msi RTX 5070 12g Shadow 3X OC Tarjeta de Video	t
412	logitech teclado k380	Logitech	Periferico	Teclado	TECLADO LOGITECH INALAMBRICO K380 PEBBLES KEY 2 - BLUETOOTH-MULTIDISPOSITIVO / NEGRO	t
413	logitech teclado k270	Logitech	Periferico	Teclado	TECLADO LOGITECH INALAMBRICO K270 USB NEGRO	t
414	lenovo mouse gy51h47350	Varios	Periferico	Mouse	MOUSE LENOVO LEGION GAMER M300S RGB GY51H47350	t
415	xtech mouse xtm-309	Varios	Periferico	Mouse	MOUSE XTECH INALAMBRICO XTM-309 DE 3 BOTONES 1600 DPI	t
416	xtech mouse xtm-318	Varios	Periferico	Mouse	MOUSE XTECH INALAMBRICO XTM-318 DE 4 BOTONES LUCES	t
417	logitech combo mk270	Logitech	Periferico	Teclado	TECLADO + MOUSE LOGITECH INALAMBRICO MK270 UNIFYING	t
418	logitech mouse m650	Logitech	Periferico	Mouse	MOUSE LOGITECH INALAMBRICO M650 BLUETOOTH USB SILENCE - GRAFITO	t
419	logitech combo mk220	Logitech	Periferico	Teclado	TECLADO + MOUSE LOGITECH INALAMBRICO MK220	t
420	xtech mouse 1200dpi	Varios	Periferico	Mouse	MOUSE XTECH INALAMBRICO 1200dpi USB NEGRO	t
421	logitech mouse m280	Logitech	Periferico	Mouse	MOUSE LOGITECH INALAMBRICO M280 2.4GHZ USB NEGRO	t
422	logitech mouse m185	Logitech	Periferico	Mouse	MOUSE LOGITECH INALAMBRICO M185 2.4GHZ USB GRIS	t
423	rtx 5060 ti 8gb	NVIDIA	GPU	NaN	Asus Dual RTX 5060 Ti 8GB OC Edition Tarjeta de Video	t
424	redragon teclado k686ak	Redragon	Periferico	Teclado	Redragon Eisa K686AK RGB PRO Teclado Gamer 90%	t
425	msi 32c6x	Msi	Monitor	NaN	Msi MAG 32C6X 32″ Monitor Curvo FHD 250Hz 1Ms	t
426	thunderobot zq25f180	Varios	Monitor	IPS	Thunderobot ZQ25F180 Monitor 24.5″ 180Hz QHD IPS	t
427	asus vg279qm5a	Asus	Monitor	IPS	Asus TUF VG279QM5A 27″ Monitor Gamer FHD 240Hz IPS	t
428	armaggeddon xf27hd	Varios	Monitor	IPS	Armaggeddon Pixxel+ XF27HD Monitor 27″ IPS 120Hz	t
429	asus vg249q5r	Asus	Monitor	IPS	Asus TUF VG249Q5R 23.8″ Monitor Gamer FHD 200Hz IPS	t
430	msi mp243l	Msi	Monitor	IPS	Msi Pro MP243L E14 Monitor 24″ 144Hz IPS 1ms	t
431	teros te-2786g	Varios	Monitor	IPS	Teros TE-2786G 27″ Monitor Gamer 200Hz 1ms IPS	t
432	asrock pg27q15r2a	Varios	Monitor	VA	Asrock PG27Q15R2A 27″ Monitor Curvo VA QHD 1440P 165Hz	t
433	coolermaster ga241	Varios	Monitor	NaN	Cooler Master GA241 23.8″ Monitor FHD 100Hz 1ms	t
434	lg 32uk580-b	Lg	Monitor	NaN	Lg Ergo 32UK580-B Monitor 31.5 Pulgadas 4K UHD	t
435	msi 491cqp	Msi	Monitor	OLED	MSI MPG 491CQP 49″ QD-OLED 144Hz 0.3ms	t
436	asus xg27aqdmes	Asus	Monitor	OLED	ASUS ROG STRIX XG27AQDMES 27″ 240Hz OLED QHD	t
437	redragon teclado k618	Redragon	Periferico	Teclado	Redragon Horus K618 RGB White Teclado Mecánico	t
438	redragon teclado k729	Redragon	Periferico	Teclado	Redragon Otiim Magnetic K729 Teclado Gamer UltraMag	t
439	redragon teclado k708gf	Redragon	Periferico	Teclado	Redragon Flekact Pro K708GF RGB PRO Teclado	t
440	redragon teclado k552	Redragon	Periferico	Teclado	Redragon Kumara K552 Teclado Mecánico	t
441	redragon teclado k673	Redragon	Periferico	Teclado	Redragon Ucal Pro K673 Anime Teclado 75% Wireless	t
442	redragon teclado k648gg	Redragon	Periferico	Teclado	Redragon Olaf K648GG RGB Teclado Gamer Wireless 94 Teclas	t
443	msi 272f	Msi	Monitor	IPS	Msi Mag 272F X24 Monitor 27″ IPS Full HD 240Hz 0.5ms	t
444	asus pa27jcv	Asus	Monitor	IPS	ASUS ProArt PA27JCV 27″ Pulgadas IPS 5K Monitor	t
445	rtx 5060 ti	NVIDIA	GPU	NaN	Asus Dual RTX 5060 Ti EVO 16GB Tarjeta de Video	t
446	teros te-2754g	Varios	Monitor	IPS	Teros TE-2754G Monitor 27″ QHD IPS 200Hz 1ms	t
447	rtx 5060 ti 16g	NVIDIA	GPU	NaN	Msi RTX 5060 Ti 16G Ventus 2X OC Plus Tarjeta Video	t
448	rtx 5070 ti	NVIDIA	GPU	NaN	Gigabyte RTX 5070 Ti Eagle Oc Sff 16G Tarjeta Video	t
449	xtratech lcd1600	Varios	Monitor	NaN	MONITOR XTRATECH 19.5" LCD1600×900 HDMI VGA 75Hz	t
450	rtx 4050	NVIDIA	GPU	NaN	Lenovo LOQ 15ARP10E AMD R7 7735HS 16GB 512GB RTX 4050 15.6″	t
451	rtx 5070	NVIDIA	GPU	NaN	Zotac Gaming GeForce RTX 5070 Solid OC 12GB	t
452	xpg 16gb ddr4 spectrix 3200mhz	Adata	RAM	DDR4	Adata Xpg Spectrix D41 16gb Ddr4 Rgb 3200mhz Memoria Ram	t
453	xpg 16gb ddr5 caster 6400mhz	Xpg	RAM	DDR5	Xpg Caster RGB 16GB Ram DDR5 6400Mhz	t
454	adata 1000gb ext	Adata	SSD	NaN	Adata SC610 1000GB Disco de Estado sólido Externo	t
455	msi g242l	Msi	Monitor	NaN	MONITOR MSI G242L E14	t
456	kingston 8gb ddr5 sodimm 5600mhz	Kingston	RAM	DDR5	8GB RAM SO-DIMM DDR5 KINGSTON KCP 5600MTS CL46	t
457	kingston 32gb ddr5 valueram 6400mhz	Kingston	RAM	DDR5	Memoria RAM KINGSTON VALUERAM 32GB *DDR5* 6400MHZ – CL52 – CUDIMM (KVR64A52BD8-32) para PC	t
458	corsair mouse m55	Corsair	Periferico	Mouse	MOUSE INALAMBRICO CORSAIR M55 CARBON	t
459	corsair mouse m75	Corsair	Periferico	Mouse	MOUSE INALAMBRICO CORSAIR M75 WHITE	t
460	mushkin 16gb ddr4 3200mhz	Varios	RAM	DDR4	Memoria RAM Mushkin DDR4, 3200MHz, 16GB PC	t
461	corsair mouse m65	Corsair	Periferico	Mouse	MOUSE INALAMBRICO CORSAIR M65 RGB ULTRA WHITE	t
462	kingston 16gb ddr5 4800mhz	Kingston	RAM	DDR5	Memoria RAM Kingston KCP548US8-16 DDR5, 4800MHz, 16GB, CL40, Verde	t
463	redragon mouse m618	Redragon	Periferico	Mouse	MOUSE REDRAGON AZZMACH M618 BLACK	t
464	crucial 16gb ddr5 5600mhz	Crucial	RAM	DDR5	Memoria RAM Crucial 16GB DDR5, 5600MHz, 16GB, PC	t
465	meetion mouse btm008	Varios	Periferico	Mouse	MOUSE INALAMBRICO MEETION BTM008	t
466	klipxtreme mouse kmw-390	Varios	Periferico	Mouse	MOUSE ERGONOMICO INALAMBRICO KLIP XTREME EVERREST KMW-390	t
467	kingston 16gb ddr5 5600mhz	Kingston	RAM	DDR5	Memoria RAM KINGSTON 16GB DDR5 5600MHz – DIMM – CL46 (KVR56U46BS8- 16)	t
468	adata 16gb ddr4 3200mhz	Adata	RAM	DDR4	Memoria RAM Adata 16GB DDR4, 3200MHz para PC	t
469	logitech mouse m575s	Logitech	Periferico	Mouse	MOUSE INALAMBRICO LOGITECH ERGO M575S	t
470	lg 20mk40l	Lg	Monitor	NaN	Monitor HD LG 19.5″ 20MK40L 75Hz LED HDMI VGA 1366 x 768	t
471	ryzen 7 5700	AMD	CPU	NaN	Procesador Ryzen 7 5700, 8N+16H – AMD	t
472	redragon mouse m995	Redragon	Periferico	Mouse	MOUSE REDRAGON FYZU ULTRA LIGHT M995	t
473	lg 20u401a	Lg	Monitor	TN	MONITOR LG 19.5″ HD+ 1600×900 – LED TN – 75Hz – 5ms (GTG) – HDMI/VGA – NEGRO Modelo 20u401a	t
474	ryzen 7 5800xt	AMD	CPU	NaN	Procesador Ryzen 7 5800XT, 8N+16H – AMD	t
475	razer mouse 35k	Razer	Periferico	Mouse	MOUSE INALAMBRICO RAZER BASILISK V3 PRO 35K PHANTOM GREEN EDITION	t
476	meetion combo c210	Varios	Periferico	Teclado	TECLADO Y MOUSE INALAMBRICO MEETION IKEY C210	t
477	meetion mouse btm001	Varios	Periferico	Mouse	MOUSE INALAMBRICO MEETION BTM001	t
478	primus audifonos arcus250	Varios	Periferico	Headset	AURICULARES PRIMUS ARCUS250 STAR WARS BB-8	t
479	primus audifonos arcus230	Varios	Periferico	Headset	AURICULAR PRIMUS GROGU ARCUS230 TWS	t
480	redragon audifonos h510	Redragon	Periferico	Headset	AUDIFONO REDRAGON ZEUS X H510 RGB WH	t
481	logitech audifonos g332	Logitech	Periferico	Headset	AUDIFONO LOGITECH G332	t
482	core i5 10600k	Intel	CPU	NaN	Procesador Core i5 10600K 10TH 6N 12H – Intel	t
483	core ultra 5 235	Intel	CPU	NaN	Procesador Intel core ultra 5 235 2.9GHz hasta 5GHz 26MB LGA1851	t
484	core i9-14900f	Intel	CPU	NaN	Procesador Intel Core I9-14900F 4.3GHz hasta 5.80GHz cache 32MB Socket LGA1700	t
485	core i7 14700f	Intel	CPU	NaN	Procesador Core i7 14700F 14va 20N+28H – Intel	t
486	core ultra 7 265f	Intel	CPU	NaN	Procesador Intel core ultra 7 265F 1.8GHz hasta 5.3GHz 36MB LGA1851	t
487	jbl audifonos 780nc	Varios	Periferico	Headset	AUDIFONO INALAMBRICO JBL TUNE 780NC BLACK	t
488	meetion combo c230	Varios	Periferico	Teclado	KIT MEETION IKEY C230 TECLADO Y MOUSE INALAMBRICO	t
489	core i7 12700f	Intel	CPU	NaN	Procesador Core i7 12700F 12va Gen – Intel	t
490	rtx 5050	NVIDIA	GPU	NaN	Tarjeta de Video ASUS NVIDIA GeForce RTX 5050 OC Edition, 8GB 128-bit GDDR6, PCI Express 5.0	t
491	core i9 12900ks	Intel	CPU	NaN	Procesador Core i9 12900KS 12va 16N 24H – Intel	t
492	rtx 5070 ti g	NVIDIA	GPU	NaN	Tarjeta de Video Gigabyte NVIDIA GeForce RTX 5070 Ti GAMING OC, 16GB 256-bit GDDR7, PCI Express x16 5.0	t
493	jbl audifonos 530bt	Varios	Periferico	Headset	AUDIFONO INALAMBRICO JBL TUNE 530BT	t
494	ryzen 5 3400g	AMD	CPU	NaN	Procesador Ryzen 5 3400G 4N + 8H – AMD	t
495	jbl audifonos 680nc	Varios	Periferico	Headset	AUDIFONO INALAMBRICO JBL TUNE 680NC	t
496	jbl audifonos 730bt	Varios	Periferico	Headset	AUDIFONO INALAMBRICO JBL TUNE 730BT	t
497	redragon teclado k681	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON CYRUS PRO K681 RGB BLANCO/VERDE	t
498	meetion teclado wk330	Varios	Periferico	Teclado	TECLADO INALAMBRICO MEETION WK330 BLACK	t
499	asrock pg27fft1a	Varios	Monitor	NaN	MONITOR ASROCK PG27FFT1A	t
500	asrock pg25fft	Varios	Monitor	NaN	MONITOR ASROCK PG25FFT	t
501	teros te-2764g	Varios	Monitor	NaN	MONITOR CURVO TEROS TE-2764G	t
502	logitech teclado k780	Logitech	Periferico	Teclado	TECLADO INALAMBRICO MULTI PLATAFORMA LOGITECH K780	t
503	redragon teclado k724	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON BEHEMOTH PRO K724 BLACK RPC SWITCH	t
504	redragon teclado k724gbg	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON BEHEMOTH PRO K724GBG BLACK-GREEN MANBO SWITCH	t
505	rtx5050 8g	NVIDIA	GPU	NaN	Tarjeta de video MSI GeForce RTX5050 8G Shadow 2X OC 1	t
506	redragon teclado k724sp	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON BEHEMOTH PRO K724SP GRADIENT MANBO SWITCH	t
507	redragon teclado k762wb	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON TERRAFLARE PRO K762WB WHITE-BLACK MANBO SWITCH	t
508	primus teclado ballista82t	Varios	Periferico	Teclado	TECLADO INALAMBRICO PRIMUS BALLISTA82T STAR WARS C-3PO	t
509	teros te-2714s	Varios	Monitor	NaN	MONITOR TEROS TE-2714S	t
510	core i3 12100f	Intel	CPU	NaN	Procesador Core i3 12100F 12va Gen – Intel	t
511	rtx5060 8g	NVIDIA	GPU	NaN	Tarjeta de video MSI GeForce RTX5060 8G Cyclone OC 1 HDMI	t
512	asus ms32uc	Asus	Monitor	NaN	MONITOR ASUS ZENSCREEN MS32UC GOOGLE TV	t
513	lg 34u511a	Lg	Monitor	NaN	MONITOR ULTRAWIDE LG 34U511A	t
514	asus pa278qgv	Asus	Monitor	NaN	MONITOR ASUS PROART PA278QGV	t
515	teros te-2417s	Varios	Monitor	NaN	MONITOR TEROS TE-2417S	t
516	corsair 34wqhd240-c	Corsair	Monitor	OLED	MONITOR CURVO CORSAIR XENEON 34WQHD240-C QD-OLED	t
517	teros te-3412g	Varios	Monitor	NaN	MONITOR CURVO TEROS TE-3412G	t
518	asus mb169ck	Asus	Monitor	NaN	MONITOR PORTATIL ASUS ZENSCREEN MB169CK	t
519	lg 34wr50qk-b	Lg	Monitor	NaN	MONITOR CURVO ULTRAWIDE LG 34WR50QK-B	t
520	redragon teclado k762wp	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON TERRAFLARE PRO K762WP WHITE-PURPLE MANBO SWITCH	t
521	logitech combo mk540	Logitech	Periferico	Teclado	TECLADO Y MOUSE INALAMBRICO LOGITECH ADVANCED MK540	t
522	redragon teclado k708wlg	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON FLEKACT PRO K708WLG BLANCO/VERDE SWITCH SULUO	t
523	redragon teclado k681wbp	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON CYRUS PRO K681WBP LILA/BLANCO SWICHT PRE-LUBED	t
524	core i5 12400f	Intel	CPU	NaN	Procesador Intel Core i5 12400F 12va Gen – Intel	t
525	redragon teclado k681mg	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON CYRUS PRO K681MG GREEN SWITCH RPC	t
526	redragon teclado k664wbp	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON GLORIA PRO K664WBP SWITCH LION	t
527	redragon teclado k643wgc	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON VEIGAR K643WGC SWITCH RED	t
528	redragon teclado k632	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON HORUS MINI PRO K632 WHITE SWITCH RED	t
529	redragon teclado k735	Redragon	Periferico	Teclado	TECLADO REDRAGON GHOSTBLADE MAGNETICO K735 BLACK SWITCH DRAGON CHANT	t
530	redragon teclado k722	Redragon	Periferico	Teclado	TECLADO REDRAGON IRONGUARD K722 BLACK SWITCH DRAGON CHANT	t
531	redragon teclado k552wgl	Redragon	Periferico	Teclado	TECLADO REDRAGON KUMARA K552WGL SWITCH RED	t
532	redragon teclado k552lgy	Redragon	Periferico	Teclado	TECLADO REDRAGON KUMARA K552LGY SWITCH RED	t
533	redragon teclado k550	Redragon	Periferico	Teclado	TECLADO REDRAGON YAMA K550 WHITE SWITCH PURPLE	t
534	meetion combo mini5000	Varios	Periferico	Teclado	TECLADO Y MOUSE INALAMBRICO MEETION MINI5000	t
535	meetion teclado wk310	Varios	Periferico	Teclado	TECLADO INALAMBRICO MEETION WK310 BLACK	t
536	redragon teclado k708gg	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON FLEKACT PRO K708GG DEGRADADO SWITCH LEOPARD	t
537	core i9-14900	Intel	CPU	NaN	Procesador Intel Core I9-14900 Raptor Lake 4.30GHz hasta 5.4GHz cache 32MB	t
538	redragon teclado k708ak	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON FLEKACT PRO K708AK SWITCH SULUO	t
539	redragon teclado k708mc	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON FLEKACT PRO K708MC SWITCH SULUO	t
540	redragon teclado k719gf	Redragon	Periferico	Teclado	TECLADO INALAMBRICO REDRAGON ARTEMIS PRO K719GF GRAFFITI SWITCH HI-FI	t
541	core i9 12900kf	Intel	CPU	NaN	Procesador Core i9 12900KF 12va 16N 24H – Intel	t
542	corsair teclado k65	Corsair	Periferico	Teclado	TECLADO OPTICO CORSAIR K65 PRO MINI OPX SWITCH	t
543	corsair teclado k55	Corsair	Periferico	Teclado	TECLADO CORSAIR K55 RGB PRO	t
544	teclado steelseries apex 7 mecanico switch red linear rgb 100% antighosting pc/mac/xbox one black	Varios	Periferico	Teclado	TECLADO STEELSERIES APEX 7 – MECANICO SWITCH RED LINEAR RGB – 100% ANTIGHOSTING – PC/MAC/XBOX ONE – BLACK	f
545	headsets corsair void rgb elite premium black	Corsair	Periferico	Headset	Headsets Corsair VOID RGB Elite Premium Black	f
546	teclado steelseries apex 9 mini 60% optical switches rgb double shot pbt black	Varios	Periferico	Teclado	TECLADO STEELSERIES APEX 9 MINI 60% – OPTICAL SWITCHES RGB – DOUBLE SHOT PBT – BLACK	f
547	tarjeta de video gigabyte amd radeon rx 9070 gaming oc, 16gb 256-bit gddr6, pci express 5.0	AMD	CPU	NaN	Tarjeta de Video Gigabyte AMD Radeon RX 9070 GAMING OC, 16GB 256-bit GDDR6, PCI Express 5.0	f
548	teclado steelseries apex 7 tkl mecanico switch red rgb linear 100% antighosting pc/mac/xbox one black	Varios	Periferico	Teclado	TECLADO STEELSERIES APEX 7 TKL – MECANICO SWITCH RED RGB LINEAR – 100% ANTIGHOSTING – PC/MAC/XBOX ONE – BLACK	f
549	teclado asus rog strix scope ii 96 wireless bluetooth/wired/rf 2.4ghz teclas abs switch rog nx snow lubed black (90mp037a-bksa00)	Asus	Periferico	Teclado	TECLADO ASUS ROG STRIX SCOPE II 96 WIRELESS – BLUETOOTH/WIRED/RF 2.4GHZ – TECLAS ABS – SWITCH ROG NX SNOW – LUBED – BLACK (90MP037A-BKSA00)	f
550	combo quasad: teclado, mouse, audifonos y pad	Varios	Periferico	Teclado	Combo Quasad: Teclado, Mouse, Audifonos y Pad	f
551	teclado xtratech alambrico usb espanol	Varios	Periferico	Teclado	TECLADO XTRATECH ALAMBRICO USB ESPAÑOL	f
552	teclado logitech ergonomico bluetooth wave keys con reposamunecas multidisposi blanco	Logitech	Periferico	Teclado	TECLADO LOGITECH ERGONOMICO BLUETOOTH WAVE KEYS CON REPOSAMUÑECAS MULTIDISPOSI BLANCO	f
553	teclado klip xtreme inalambrico keyglider bluetooth y 2.4ghz - panel tactil	Varios	Periferico	Teclado	TECLADO KLIP XTREME INALAMBRICO KEYGLIDER BLUETOOTH Y 2.4GHz - PANEL TACTIL	f
554	teclado mecanico razer blackwidow v4 tenkeyless hyperspeed wireless/usb-c razer chromatm rgb abs doubleshot swtich tactile and quiet black (rz03-05480600-r	Razer	Periferico	Teclado	TECLADO MECANICO RAZER BLACKWIDOW V4 TENKEYLESS HYPERSPEED – WIRELESS/USB-C – RAZER CHROMA™ RGB – ABS DOUBLESHOT – SWTICH TACTILE AND QUIET – BLACK (RZ03-05480600-R311)	f
555	teclado + mouse klip xtreme inalambrico keyroll usb	Varios	Periferico	Teclado	TECLADO + MOUSE KLIP XTREME INALAMBRICO KEYROLL USB	f
556	headsets inalambricos corsair void rgb elite wireless white (ca-9011202-na)	Corsair	Periferico	Headset	Headsets Inalambricos Corsair VOID RGB Elite Wireless White – (CA-9011202-NA)	f
557	headsets inalambricos corsair virtuoso rgb wireless white (ca-9011224-na)	Corsair	Periferico	Headset	Headsets Inalambricos Corsair Virtuoso RGB Wireless White – (CA-9011224-NA)	f
558	teclado + mouse klip xtreme alambrico ergonomico usb	Varios	Periferico	Teclado	TECLADO + MOUSE KLIP XTREME ALAMBRICO ERGONOMICO USB	f
559	teclado dyi glorious gmmk-tkl-rgb sin switch sin keycaps black	Varios	Periferico	Teclado	Teclado DYI Glorious GMMK-TKL-RGB – Sin Switch – Sin KeyCaps – Black	f
560	teclado inalambrico trust gxt sento black (20062)	Varios	Periferico	Teclado	Teclado Inalambrico Trust GXT Sento – Black (20062)	f
561	teclado mecanico horus k618-rgb-sp wireless rgb chroma fps bluetooth 5.0 100% anti-ghosting black	Varios	Periferico	Teclado	TECLADO MECANICO HORUS K618-RGB-SP – WIRELESS – RGB CHROMA FPS – BLUETOOTH 5.0 – 100% ANTI-GHOSTING – BLACK	f
562	teclado ezmi alambrico usb - negro	Varios	Periferico	Teclado	TECLADO EZMI ALAMBRICO USB - NEGRO	f
563	tarjeta tplink pcie x1 wifi 300mbps 2 antenas desmontables	Varios	GPU	NaN	TARJETA TPLINK PCIe x1 WIFI 300Mbps 2 ANTENAS DESMONTABLES	f
564	monitor indurama 32 vortix ultra va fhd 1080p	Varios	Monitor	VA	MONITOR Indurama 32″ VORTIX Ultra VA FHD 1080p	f
565	monitor indurama 27 vortix nova ips fhd 1080p 120hz hdmi displayport	Varios	Monitor	IPS	MONITOR Indurama 27″ VORTIX NOVA IPS FHD 1080p 120Hz HDMI DISPLAYPORT	f
566	teclado mecanico gaming cougar luxlim low profile switch red usb black	Varios	Periferico	Teclado	TECLADO MECANICO GAMING COUGAR LUXLIM – LOW PROFILE – SWITCH RED – USB – BLACK	f
567	mouse speedmind smmou01 compacto usb	Varios	Periferico	Mouse	Mouse Speedmind SMMOU01 Compacto USB	f
568	disco solido ssd int m.2 hiksemi wave 1tb 2280 nvme pcie	Varios	SSD	NVMe	DISCO SOLIDO SSD INT M.2 HIKSEMI WAVE 1TB 2280 NVME PCIe	f
569	monitor quasad 19.5 qm-b20 hd 1366768 60hz	Varios	Monitor	NaN	Monitor Quasad 19.5″ QM-B20 HD 1366×768 – 60Hz	f
570	disco solido ssd int adata 1tb su-650 sata 6gb-s 2.5inc 3d-nand	Adata	SSD	SATA	DISCO SOLIDO SSD INT ADATA 1TB SU-650 SATA 6Gb-s 2.5Inc 3D-NAND	f
571	mouse asus tuf gaming m4 wireless/bluetooth 12000 dpi 6 botones black (-b0ua00)	Asus	Periferico	Mouse	MOUSE ASUS TUF GAMING M4 WIRELESS/BLUETOOTH – 12000 DPI – 6 BOTONES – BLACK (-B0UA00)	f
572	disco solido ssd int m.2 adata 1tb 2280 legend 710 pcle gen3 x4	Adata	SSD	NVMe	DISCO SOLIDO SSD INT M.2 ADATA 1TB 2280 LEGEND 710 PCle Gen3 x4	f
573	disco solido ssd ext adata 1tb - 2000 mb/s- se880- usb 3.2 gen2 x2	Adata	SSD	NaN	DISCO SOLIDO SSD EXT ADATA 1TB - 2000 MB/s- SE880- USB 3.2 Gen2 x2	f
574	tarjeta de video asus dual geforce rtxtm 3050 oc 6gb gddr6x dos ventiladores pcie 4.0/dvi/hdmi/dp	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS DUAL GeForce RTX™ 3050 OC 6GB GDDR6X DOS VENTILADORES PCIe 4.0/DVI/HDMI/DP	f
575	combo teclado y mouse hp 235 alambrico usb-a black (1y4d0aa#abm)	Varios	Periferico	Teclado	COMBO TECLADO Y MOUSE HP 235 – ALAMBRICO – USB-A – BLACK (1Y4D0AA#ABM)	f
576	mouse inalambrico asus rog spatha x (90mp0220-bmua00)	Asus	Periferico	Mouse	Mouse Inalambrico Asus ROG Spatha X – (90MP0220-BMUA00)	f
577	mouse hp omen 600	Varios	Periferico	Mouse	Mouse HP Omen 600	f
578	mouse glorious model d (d minus) matte white (glo-ms-dm-mw)	Varios	Periferico	Mouse	Mouse Glorious Model D – (D Minus) Matte White – (GLO-MS-DM-MW)	f
579	mouse cougar minos xt black (3mmxtwob.0001)	Varios	Periferico	Mouse	Mouse Cougar Minos XT – Black (3MMXTWOB.0001)	f
580	mouse glorious model d matte white (gd-white)	Varios	Periferico	Mouse	Mouse Glorious Model D – Matte White (GD-White)	f
581	procesador lenovo servidor sr530/sr570/sr630 intel xeon silver 4214 12c 85w 2.2ghz	Intel	CPU	NaN	PROCESADOR LENOVO SERVIDOR SR530/SR570/SR630 Intel Xeon Silver 4214 12C 85W 2.2GHz	f
582	procesador lenovo servidor sr550/sr590/sr650 intel xeon silver 4208 8c 85w 2.1ghz	Intel	CPU	NaN	PROCESADOR LENOVO SERVIDOR SR550/SR590/SR650 Intel Xeon Silver 4208 8C 85W 2.1GHz	f
583	teclado klip xtreme inalambrico ergonomico transcend usb negro	Varios	Periferico	Teclado	TECLADO KLIP XTREME INALAMBRICO ERGONOMICO TRANSCEND USB NEGRO	f
584	mouse gaming edition star wars mandalorian 11 botones 12400dpi sensor optico cafe (pmo-s202ml)	Varios	Periferico	Mouse	MOUSE GAMING EDITION STAR WARS MANDALORIAN – 11 BOTONES – 12400DPI – SENSOR OPTICO – CAFE (PMO-S202ML)	f
585	mouse klip xtreme optical liteglider usb + ps/2 adapter (kmo-102)	Varios	Periferico	Mouse	MOUSE KLIP XTREME OPTICAL LITEGLIDER – USB + PS/2 ADAPTER (KMO-102)	f
586	teclado mecanico gaming evil 772eg rainbow 670g switch blue usb black (kb-772eg)	Varios	Periferico	Teclado	TECLADO MECANICO GAMING EVIL 772EG – RAINBOW – 670G – SWITCH BLUE – USB – BLACK (KB-772EG)	f
587	upgrade kit mouse logitech g pro wireless teclado pro x 60 tkl wireless	Logitech	Periferico	Teclado	UPGRADE KIT Mouse Logitech G Pro Wireless – Teclado Pro X 60 Tkl Wireless	f
588	teclado mecanico razer blackwidow v4 x 75% razer chromatm rgb abs orange lineal black (rz03-05000200-r3u1)	Razer	Periferico	Teclado	TECLADO MECANICO RAZER BLACKWIDOW V4 X 75% – RAZER CHROMA™ RGB – ABS – ORANGE LINEAL – BLACK (RZ03-05000200-R3U1)	f
589	audifonos klipxtreme jogbudz ii ksm-150gn bluetooth v5.0 px41 12hrs	Varios	Periferico	Headset	AUDIFONOS KLIPXTREME JOGBUDZ II KSM-150GN – BLUETOOTH® V5.0 – PX41 – 12HRS	f
590	teclado ezmi alambrico gamer retroiluminado usb - negro	Varios	Periferico	Teclado	TECLADO EZMI ALAMBRICO GAMER RETROILUMINADO USB - NEGRO	f
591	teclado primus alambrico gamer ballista usb-c trenzado desmontable negro	Varios	Periferico	Teclado	TECLADO PRIMUS ALAMBRICO GAMER BALLISTA USB-C TRENZADO DESMONTABLE NEGRO	f
592	teclado xtech alambrico usb multimedia	Varios	Periferico	Teclado	TECLADO XTECH ALAMBRICO USB MULTIMEDIA	f
593	combo teclado y mouse unno tekno klass usb black espanol	Varios	Periferico	Teclado	COMBO TECLADO Y MOUSE UNNO TEKNO KLASS USB BLACK – ESPAÑOL	f
594	teclado dell xps 7590 black (backlit small enter)	Varios	Periferico	Teclado	TECLADO DELL XPS 7590 BLACK (BACKLIT SMALL ENTER)	f
595	stand para audifonos cougar bunker s	Varios	Periferico	Headset	Stand para audifonos Cougar Bunker S	f
596	mainbaord asus prime b860m-a socket 1851 intel	Intel	CPU	NaN	Mainbaord Asus Prime B860m-a socket 1851 intel	f
597	monitor lg 24" (23.8) led ips 1080p hdmix2	Lg	Monitor	IPS	MONITOR LG 24" (23.8) LED IPS 1080p HDMIx2	f
598	monitor lg 27" led gamer ultragear ips 1080p 180hz hdmi-dp pivote	Lg	Monitor	IPS	MONITOR LG 27" LED GAMER ULTRAGEAR IPS 1080p 180Hz HDMI-DP PIVOTE	f
599	microfono hyperx quadcast soporte antivibracion usb conector de audifonos incorporado ajuste de control de ganancia para pc/ps4- black/red (4p5p6aa)	Hyperx	Periferico	Headset	MICROFONO HYPERX QUADCAST – SOPORTE ANTIVIBRACION – USB – CONECTOR DE AUDIFONOS INCORPORADO – AJUSTE DE CONTROL DE GANANCIA – PARA PC/PS4- BLACK/RED (4P5P6AA)	f
600	monitor xtratech 21.5" fhd lcd 19201080 hdmi - vga- 100hz	Varios	Monitor	NaN	MONITOR XTRATECH 21.5" FHD LCD 1920×1080 HDMI - VGA- 100Hz	f
601	teclado mecanico hyperx alloy elite 2 rgb switch rojo 100 % anti-ghost compatible ps5tm, ps4tm, xbox series x|stm, xbox onetm black (4p5n3ai#ac8)	Hyperx	Periferico	Teclado	TECLADO MECANICO HYPERX ALLOY ELITE 2 – RGB SWITCH ROJO – 100 % ANTI-GHOST – COMPATIBLE PS5™, PS4™, XBOX SERIES X|S™, XBOX ONE™ – BLACK (4P5N3AI#AC8)	f
602	monitor indurama 22" vortix core va fhd 1080p 100hz	Varios	Monitor	VA	MONITOR INDURAMA 22" VORTIX CORE VA FHD 1080p 100Hz	f
603	monitor indurama 32" gamer curvo vortix ultra va fhd 1080p 180hz	Varios	Monitor	VA	MONITOR INDURAMA 32" GAMER CURVO VORTIX ULTRA VA FHD 1080p 180Hz	f
604	monitor indurama 27" vortix nova ips fhd 1080p 120hz	Varios	Monitor	IPS	MONITOR INDURAMA 27" VORTIX NOVA IPS FHD 1080p 120Hz	f
605	monitor indurama 25" vortix nova ips fhd 1080p 120hz	Varios	Monitor	IPS	MONITOR INDURAMA 25" VORTIX NOVA IPS FHD 1080p 120Hz	f
606	audifonos primus gaming edition star wars mandalorian arcus 210 tws wireless omnidireccional usb type c 5 rms black (pwh-s210ml)	Varios	Periferico	Headset	AUDIFONOS PRIMUS GAMING EDITION STAR WARS MANDALORIAN ARCUS 210 TWS – WIRELESS – OMNIDIRECCIONAL – USB TYPE C – 5 RMS – BLACK (PWH-S210ML)	f
607	teclado perzonalizable corsair elgato stream deck+ 8 teclas lcd usb-c black (10gbd9901)	Corsair	Periferico	Teclado	TECLADO PERZONALIZABLE CORSAIR ELGATO STREAM DECK+ 8 TECLAS LCD – USB-C – BLACK (10GBD9901)	f
608	teclado meetion mt-director wireless ergonomico black	Varios	Periferico	Teclado	TECLADO MEETION MT-DIRECTOR – WIRELESS – ERGONOMICO – BLACK	f
609	monitor xtratech 24" full hd 1920x1080 100hz vga hdmi	Varios	Monitor	NaN	MONITOR XTRATECH 24" FULL HD 1920X1080 100Hz VGA HDMI	f
610	monitor xtratech 19.5" led 1600x900 hdmi vga 60 hz parlantes integrados	Varios	Monitor	NaN	MONITOR XTRATECH 19.5" LED 1600X900 HDMI VGA 60 Hz PARLANTES INTEGRADOS	f
611	teclado mecanico hyperx origins 60% rgb switch linear 100% anti-ghosting compatible ps5tm, ps4tm, xbox series x|stm, xbox onetm black (4p5n4aa)	Hyperx	Periferico	Teclado	TECLADO MECANICO HYPERX ORIGINS 60% RGB – SWITCH LINEAR – 100% ANTI-GHOSTING – COMPATIBLE PS5™, PS4™, XBOX SERIES X|S™, XBOX ONE™ – BLACK (4P5N4AA)	f
612	combo teclado + mouse logitech pop keys inalambrico bluetooth 5.1 (920-013053)	Logitech	Periferico	Teclado	COMBO TECLADO + MOUSE LOGITECH POP KEYS INALAMBRICO – BLUETOOTH 5.1 (920-013053)	f
613	hyperx pulsefire core rgb mouse gamer	Hyperx	Periferico	Mouse	Hyperx Pulsefire Core RGB Mouse Gamer	f
614	teclado + mouse ezmi inalambrico - negro	Varios	Periferico	Teclado	TECLADO + MOUSE EZMI INALAMBRICO - NEGRO	f
615	tarjeta de video profesional asus turbo amd radeon ai pro r9700 32gb gddr6 (turbo-ai-pro-r9700-32g)	AMD	GPU	NaN	TARJETA DE VIDEO PROFESIONAL ASUS TURBO AMD RADEON AI PRO R9700 32GB GDDR6 (TURBO-AI-PRO-R9700-32G)	f
616	mouse inalambrico asus rog harpe ace aim lab edition	Asus	Periferico	Mouse	MOUSE INALAMBRICO ASUS ROG HARPE ACE AIM LAB EDITION	f
617	mouse inalambrico logitech mx master 4	Logitech	Periferico	Mouse	MOUSE INALAMBRICO LOGITECH MX MASTER 4	f
618	mouse inalambrico razer cobra hyperspeed	Razer	Periferico	Mouse	MOUSE INALAMBRICO RAZER COBRA HYPERSPEED	f
619	mouse c/ cable usb genius micro traveler	Varios	Periferico	Mouse	Mouse C/ Cable Usb – Genius Micro Traveler	f
620	mouse inalambrico logitech pro x superlight 2c	Logitech	Periferico	Mouse	MOUSE INALAMBRICO LOGITECH PRO X SUPERLIGHT 2C	f
621	mouse inalambrico logitech pro x superlight 2 se	Logitech	Periferico	Mouse	MOUSE INALAMBRICO LOGITECH PRO X SUPERLIGHT 2 SE	f
622	mouse inalambrico usb microsoft 1850	Varios	Periferico	Mouse	Mouse Inalambrico Usb – Microsoft 1850	f
623	mouse inalambrico razer viper v3 hyperspeed	Razer	Periferico	Mouse	MOUSE INALAMBRICO RAZER VIPER V3 HYPERSPEED	f
624	audifonos inalambricos bluetooth 5.4 tws xiaomi redmi buds 6 play	Varios	Periferico	Headset	Audifonos Inalambricos Bluetooth 5.4 Tws – Xiaomi Redmi Buds 6 Play	f
625	audifono c/ mic earbuds tipo c thonet & vander klein	Varios	Periferico	Headset	Audifono C/ Mic Earbuds tipo C – Thonet & Vander Klein	f
626	audifono inalambrico bt5 c/ estuche universal y90	Varios	Periferico	Headset	Audifono Inalambrico BT5 C/ Estuche – Universal Y90	f
627	teclado corsair vanguard 96 mlx switch	Corsair	Periferico	Teclado	TECLADO CORSAIR VANGUARD 96 MLX SWITCH	f
628	teclado corsair galleon 100 sd mlx switch	Corsair	Periferico	Teclado	TECLADO CORSAIR GALLEON 100 SD MLX SWITCH	f
629	teclado asus rog falchion ace hfx magnetic switch	Asus	Periferico	Teclado	TECLADO ASUS ROG FALCHION ACE HFX MAGNETIC SWITCH	f
630	teclado razer huntsman v3 x tenkeyless optical purple switch	Razer	Periferico	Teclado	TECLADO RAZER HUNTSMAN V3 X TENKEYLESS OPTICAL PURPLE SWITCH	f
631	teclado redradon castor magnetic k631	Varios	Periferico	Teclado	TECLADO REDRADON CASTOR MAGNETIC K631	f
632	procesador hpe dl380 gen9 intel xeon e5-2640v3 kit (719049-b)	Intel	CPU	NaN	Procesador HPE DL380 Gen9 Intel Xeon E5-2640v3 Kit – (719049-B)	f
633	ia workstation amd threadripper + dual geforce rtx 5090 + 128gb ram ddr5	AMD	CPU	NaN	IA Workstation AMD ThreadRipper + Dual GeForce RTX 5090 + 128GB RAM DDR5	f
634	teclado logitech g pro x tkl rapid magnetic switch	Logitech	Periferico	Teclado	TECLADO LOGITECH G PRO X TKL RAPID MAGNETIC SWITCH	f
635	monitor indurama vortixnova 27	Varios	Monitor	VA	MONITOR INDURAMA VORTIXNOVA 27	f
636	tarjeta de video asus geforce gt710 2gb gddr5 hdmi/d-sub/dvi-d (gt710-sl-2gd5-brk-evo)	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS GEFORCE GT710 – 2GB GDDR5 – HDMI/D-SUB/DVI-D (GT710-SL-2GD5-BRK-EVO)	f
637	monitor indurama vortixnova 25	Varios	Monitor	VA	MONITOR INDURAMA VORTIXNOVA 25	f
638	monitor portatil viewsonic va1653	Viewsonic	Monitor	VA	MONITOR PORTATIL VIEWSONIC VA1653	f
639	tarjeta de video gigabyte gt 710 2gb (gv-n710d3-2gl rev2.0)	Gigabyte	GPU	NaN	Tarjeta de video Gigabyte GT 710 2GB – (GV-N710D3-2GL REV2.0)	f
640	tarjeta capturadora de video blackmagic design decklink duo 2 4ch sdi tarjeta de reproduccion y captura bmd-bdlkduo2	Varios	GPU	NaN	Tarjeta capturadora de video Blackmagic Design DeckLink Duo 2 4ch SDI Tarjeta de reproducción y captura BMD-BDLKDUO2	f
641	tarjeta de red pcie x1 tp-link tl-wn881nd	Varios	GPU	NaN	TARJETA DE RED PCIE X1 TP-LINK TL-WN881ND	f
642	tarjeta de video gigabyte gt 1030 2gb (gv-n1030d5-2gl)	Gigabyte	GPU	NaN	Tarjeta de video Gigabyte GT 1030 – 2GB – (GV-N1030D5-2GL)	f
643	mouse gamer alambrico usb p/pc rgb corsair katar pro	Corsair	Periferico	Mouse	Mouse Gamer Alambrico Usb P/Pc RGB – Corsair Katar Pro	f
644	mouse inalambrico corsair scimitar elite se carbon	Corsair	Periferico	Mouse	MOUSE INALAMBRICO CORSAIR SCIMITAR ELITE SE CARBON	f
645	combo gamer teclado, mouse, audif, pad xrike me cmx-415 sp	Varios	Periferico	Teclado	Combo Gamer Teclado, Mouse, Audif, Pad – Xrike Me CMX-415 SP	f
646	monitor 24 fhd gamer, 200hz, 1ms, rgb, dp, hdmi env 1887	Varios	Monitor	NaN	Monitor 24″ Fhd Gamer, 200hz, 1ms, Rgb, Dp, Hdmi – ENV 1887	f
647	adap. wifi pci e 300mbps tarjeta de red d-link dwa-548	Varios	GPU	NaN	Adap. Wifi PCI E 300Mbps Tarjeta de Red – D-Link DWA-548	f
648	tarjeta de video msi geforce gt710 2gd3h 2gb low profile ddr3	NVIDIA	GPU	NaN	Tarjeta de video MSI GeForce GT710 2GD3H 2GB low profile DDR3	f
649	cpu amd atlhon 3000g, 2gb graficos, ram 8gb, ssd 256gb	Varios	RAM	NaN	Cpu Amd Atlhon 3000g, 2Gb Gráficos, Ram 8GB, SSD 256GB	f
650	procesador ultra 7 265k series 2 20n+20h intel	Intel	CPU	NaN	Procesador Ultra 7 265K Series 2 20N+20H – Intel	f
651	procesador ultra 7 265kf series 2 20n+20h intel	Intel	CPU	NaN	Procesador Ultra 7 265KF Series 2 20N+20H – Intel	f
652	monitor 20 hd+, 1440900, hdmi, vga one j019	Varios	Monitor	NaN	Monitor 20″ HD+, 1440×900, Hdmi, Vga – One J019	f
653	monitor 25 fhd ips 120hz, dp, hdmi indurama vortix nova	Varios	Monitor	IPS	Monitor 25″ FHD Ips 120Hz, DP, Hdmi – Indurama Vortix Nova	f
654	procesador ultra 5 225 series 2 10n+10h intel	Intel	CPU	NaN	Procesador Ultra 5 225 Series 2 10N+10H – Intel	f
655	procesador athlon 3000g graficos vega 3 amd	AMD	CPU	NaN	Procesador Athlon 3000G Graficos Vega 3 – AMD	f
656	procesador amd ryzen 7-7700x 4.5ghz hasta 5.4ghz cache 32mb no incluye	AMD	CPU	NaN	Procesador AMD ryzen 7-7700X 4.5GHz hasta 5.4GHz cache 32MB no incluye	f
657	procesador amd ryzen 9-7900x 4.7ghz hasta 5.6ghz cache 64mb no inc.	AMD	CPU	NaN	Procesador AMD ryzen 9-7900X 4.7GHz hasta 5.6GHz cache 64MB no inc.	f
658	monitor 24 fhd ips, 180hz, 1ms env 3524	Varios	Monitor	IPS	Monitor 24″ Fhd Ips, 180hz, 1ms – ENV 3524	f
659	mouse inalambrico corsair nightsabre carbon	Corsair	Periferico	Mouse	MOUSE INALAMBRICO CORSAIR NIGHTSABRE CARBON	f
660	procesador amd ryzen 7-7800x3d 4.2ghz hasta 5ghz cache 96mb no inc.	AMD	CPU	NaN	Procesador AMD ryzen 7-7800X3D 4.2GHz hasta 5GHz cache 96MB no inc.	f
661	audifono inalambrico lightspeed logitech g pro x	Logitech	Periferico	Headset	AUDIFONO INALAMBRICO LIGHTSPEED LOGITECH G PRO X	f
662	audifono jbl tune 530 3.5mm	Varios	Periferico	Headset	AUDIFONO JBL TUNE 530 3.5MM	f
663	audifono inalambrico jbl tour one m3 black	Varios	Periferico	Headset	AUDIFONO INALAMBRICO JBL TOUR ONE M3 BLACK	f
664	mouse inalambrico logitech g pro 2 lightspeed	Logitech	Periferico	Mouse	MOUSE INALAMBRICO LOGITECH G PRO 2 LIGHTSPEED	f
665	teclado y mouse inalambrico logitech pop icon	Logitech	Periferico	Teclado	TECLADO Y MOUSE INALAMBRICO LOGITECH POP ICON	f
666	mouse inalambrico logitech mx ergo s	Logitech	Periferico	Mouse	MOUSE INALAMBRICO LOGITECH MX ERGO S	f
667	teclado multimedia usb cable wh genius slimstar 126	Varios	Periferico	Teclado	Teclado Multimedia Usb Cable WH – Genius Slimstar 126	f
668	combo gamer teclado, mouse, audif, pad alcatroz x craft basecamp	Varios	Periferico	Teclado	Combo Gamer Teclado, Mouse, Audif, Pad – Alcatroz X Craft Basecamp	f
669	mouse corsair harpoon rgb pro carbon	Corsair	Periferico	Mouse	MOUSE CORSAIR HARPOON RGB PRO CARBON	f
670	mouse corsair scimitar rgb elite carbon	Corsair	Periferico	Mouse	MOUSE CORSAIR SCIMITAR RGB ELITE CARBON	f
671	combo teclado mecanico + mouse calidad rgb cougar combat	Varios	Periferico	Teclado	Combo Teclado Mecanico + Mouse Calidad Rgb – Cougar Combat	f
672	tarjeta de video asus gt 710 2gb (gt710-4h-sl-2gd5)	Asus	GPU	NaN	Tarjeta de video Asus GT 710 2GB – (GT710-4H-SL-2GD5)	f
673	tarjeta de video asus geforce gt730 2gb gddr5 auto extreme 0db silent 4 hdmi (gt730-4h-sl-2gd5)	NVIDIA	GPU	NaN	TARJETA DE VIDEO ASUS GEFORCE GT730 2GB GDDR5 – AUTO EXTREME – 0DB SILENT – 4 HDMI (GT730-4H-SL-2GD5)	f
674	teclado razer blackwidow v4 x pokemon edition razer chromatm rgb abs switch lineal es grenn/detalles tematicos pokemon (rz03-04704200-r3m1)	Razer	Periferico	Teclado	TECLADO RAZER BLACKWIDOW V4 X POKEMON EDITION – RAZER CHROMA™ RGB – ABS – SWITCH LINEAL – ES – GRENN/DETALLES TEMATICOS POKEMON (RZ03-04704200-R3M1)	f
675	tarjeta de video afox rx-550 4gb gddr5 hdmi/dp/dvi-d	Varios	GPU	NaN	TARJETA DE VIDEO AFOX RX-550 4GB – GDDR5 – HDMI/DP/DVI-D	f
676	soporte para monitor klip xtreme kmm-400 hasta 27	Varios	Monitor	NaN	Soporte para monitor Klip Xtreme KMM-400 – Hasta 27″	f
677	soporte klip xtreme kmm-301 para monitor y laptop	Varios	Monitor	NaN	Soporte Klip Xtreme KMM-301 PARA MONITOR Y LAPTOP	f
678	asus tuf z890 plus wifi intel core ultra lga1851	Intel	CPU	NaN	Asus TUF Z890 PLUS WIFI Intel Core Ultra LGA1851	f
679	asus tuf gaming b850m-plus wifi am5 amd	AMD	CPU	NaN	Asus TUF Gaming B850M-Plus WIFI AM5 AMD	f
680	asus prime h810m-e lga1851 ddr5 intel	Intel	CPU	NaN	ASUS Prime H810M-E LGA1851 DDR5 Intel	f
681	lenovo loq 15arp10e amd r7 7735hs 16gb 512gb rtx 4050 15.6	AMD	CPU	NaN	Lenovo LOQ 15ARP10E AMD R7 7735HS 16GB 512GB RTX 4050 15.6″	f
682	gamdias atlas m3m case gamer vidrio templado 3 fans	AMD	CPU	NaN	Gamdias Atlas M3M Case Gamer Vidrio Templado 3 Fans	f
683	gamdias kratos m1 600b fuente de poder 600w 80+ bronze	AMD	CPU	NaN	Gamdias Kratos M1 600B Fuente de Poder 600W 80+ Bronze	f
684	gamdias aura gc12 case gamer 6 fans argb	AMD	CPU	NaN	Gamdias Aura GC12 Case Gamer 6 Fans Argb	f
685	monitor indurama vortix ultra 32 | curvo va fhd 180hz (32mimnavu)	Varios	Monitor	VA	Monitor Indurama Vortix Ultra 32″ | Curvo VA FHD 180Hz (32MIMNAVU)	f
686	audifono + microfono xtech on ear tipo diadema 2 conectores 3.5mm	Varios	Periferico	Headset	AUDIFONO + MICROFONO XTECH ON EAR TIPO DIADEMA 2 conectores 3.5mm	f
687	monitor touch sat 1053fph 15 1024 x 768px multi-touch 3 puntos hdmi/vga/usb	Varios	Monitor	NaN	MONITOR TOUCH SAT 1053FPH – 15″ 1024 x 768PX – MULTI-TOUCH 3 PUNTOS – HDMI/VGA/USB	f
688	soporte para audifonos xtech incluye 2 puertos usb - rgb	Varios	Periferico	Headset	SOPORTE PARA AUDIFONOS XTECH INCLUYE 2 PUERTOS USB - RGB	f
689	mouse klip xtreme inalambrico bluetooth 6 botones - negro	Varios	Periferico	Mouse	MOUSE KLIP XTREME INALAMBRICO BLUETOOTH 6 BOTONES - NEGRO	f
690	mouse klip xtreme inalambrico ergonomico 6 bot. nano usb - azul	Varios	Periferico	Mouse	MOUSE KLIP XTREME INALAMBRICO ERGONOMICO 6 BOT. NANO USB - AZUL	f
691	mouse klip xtreme inalambrico ergonomico 6 bot. nano usb - negro	Varios	Periferico	Mouse	MOUSE KLIP XTREME INALAMBRICO ERGONOMICO 6 BOT. NANO USB - NEGRO	f
692	mouse klip xtreme inalambrico usb - azul	Varios	Periferico	Mouse	MOUSE KLIP XTREME INALAMBRICO USB - AZUL	f
693	mouse klip xtreme inalambrico vertical negro	Varios	Periferico	Mouse	MOUSE KLIP XTREME INALAMBRICO VERTICAL NEGRO	f
694	mouse xtech alambrico 3 botones usb - negro	Varios	Periferico	Mouse	MOUSE XTECH ALAMBRICO 3 BOTONES USB - NEGRO	f
695	mouse xtech alambrico usb negro ergonomico	Varios	Periferico	Mouse	MOUSE XTECH ALAMBRICO USB NEGRO ERGONOMICO	f
696	mouse primus inalambrico gamer conexion dual usb bateria recargable	Varios	Periferico	Mouse	MOUSE PRIMUS INALAMBRICO GAMER CONEXION DUAL USB BATERIA RECARGABLE	f
697	mouse ezmi alambrico ez gamer iluminacion rgb 6 bot. 7200 dpi usb - negro	Varios	Periferico	Mouse	MOUSE EZMI ALAMBRICO EZ GAMER ILUMINACION RGB 6 BOT. 7200 DPI USB - NEGRO	f
698	mouse logitech ergonomic lift left vertical bluetooth 4000 dpi grafito - mano izquierda	Logitech	Periferico	Mouse	MOUSE LOGITECH ERGONOMIC LIFT LEFT VERTICAL BLUETOOTH 4000 DPI GRAFITO - MANO IZQUIERDA	f
699	teclado + mouse xtech alambrico usb - negro	Varios	Periferico	Teclado	TECLADO + MOUSE XTECH ALAMBRICO USB - NEGRO	f
700	teclado + mouse manhattan inalambrico - negro	Varios	Periferico	Teclado	TECLADO + MOUSE MANHATTAN INALAMBRICO - NEGRO	f
701	teclado + mouse targus inalambrico - negro	Varios	Periferico	Teclado	TECLADO + MOUSE TARGUS INALAMBRICO - NEGRO	f
702	teclado mecanico corsair galleon 100 sd integrated stream deck lcd full-color teclas pbt switch mlx black (ch-912a311-na)	Corsair	Periferico	Teclado	TECLADO MECANICO CORSAIR GALLEON 100 SD – INTEGRATED STREAM DECK – LCD FULL-COLOR – TECLAS PBT – SWITCH MLX – BLACK (CH-912A311-NA)	f
703	soporte/brazo para monitores klip xtreme kpm-310	Varios	Monitor	NaN	Soporte/Brazo para monitores Klip Xtreme KPM-310	f
704	monitor gaming zowie xl2731k 27 fhd 165hz dyac 320 nits tn hdmi2.0/dp 1.2 (9h.lkclb-qbl)	Varios	Monitor	TN	MONITOR GAMING ZOWIE XL2731K – 27″ FHD – 165HZ DYAC – 320 NITS – TN – HDMI2.0/DP 1.2 (9H.LKCLB-QBL)	f
705	monitor indurama vortix core 22 (21.5) full hd 100hz | vga/hdmi (22mimnavc)	Varios	Monitor	NaN	Monitor Indurama Vortix Core 22 (21.5″) Full HD 100HZ | VGA/HDMI (22MIMNAVC)	f
706	gamdias hermes e7 usb red switch teclado mecanico	Varios	Periferico	Teclado	Gamdias Hermes E7 USB Red Switch Teclado Mecánico	f
707	tarjeta de video biostar g210 1gb (vn2103nhg6-sbarl-bs2)	Varios	GPU	NaN	Tarjeta de video Biostar G210 1GB – (VN2103NHG6-SBARL-BS2)	f
708	tarjeta de video gigabyte gt 1030 2gb (gv-n1030d4-2gl)	Gigabyte	GPU	NaN	Tarjeta de video Gigabyte GT 1030 2GB – (GV-N1030D4-2GL)	f
709	tarjeta de video msi n210 1gb (912-v809-3634)	Msi	GPU	NaN	Tarjeta de video MSI N210 1GB – (912-V809-3634)	f
710	procesador intel i7 14700 5.4ghz 20+28 lga1700 14va	Intel	CPU	NaN	PROCESADOR INTEL I7 14700 5.4GHZ 20+28 LGA1700 14VA	f
711	armaggeddon cosmic iii lite bk auriculares inalambrico	Varios	Periferico	Headset	Armaggeddon Cosmic III Lite BK Auriculares Inalámbrico	f
712	razer blackshark v2 x wh headset gamer	Razer	Periferico	Headset	Razer BlackShark V2 X Wh Headset Gamer	f
713	logitech mx vertical mouse ergonomico vertical	Logitech	Periferico	Mouse	Logitech MX Vertical Mouse Ergonómico Vertical	f
714	cougar minos neo mouse gamer 6.2k dpi usb	Varios	Periferico	Mouse	Cougar Minos NEO Mouse Gamer 6.2k DPI USB	f
715	razer deathadder v2 x hyperspeed mouse inalambrico	Razer	Periferico	Mouse	Razer DeathAdder V2 X HyperSpeed Mouse Inalámbrico	f
716	genius scorpion km-gx6 teclado+mouse combo gamer	Varios	Periferico	Teclado	Genius Scorpion KM-GX6 Teclado+Mouse Combo Gamer	f
717	armaggeddon mka-7c black teclado mecanico linear	Varios	Periferico	Teclado	Armaggeddon MKA-7C Black Teclado Mecánico Linear	f
718	gamdias hermes e8 usb red switch teclado mecanico	Varios	Periferico	Teclado	Gamdias Hermes E8 USB Red Switch Teclado Mecánico	f
719	monitor indurama vortix nova 25 full hd 120hz | hdmi+dp (25mimnavn )	Varios	Monitor	VA	Monitor Indurama Vortix Nova 25″ Full HD 120Hz | HDMI+DP (25MIMNAVN )	f
720	oraimo osw-831n rose gold amoled 1.32	Varios	Monitor	OLED	Oraimo OSW-831N Rose Gold AMOLED 1.32¨	f
721	klip xtreme kmm-510 soporte articulado dos monitores con regleta	Varios	Monitor	NaN	Klip Xtreme KMM-510 Soporte Articulado Dos Monitores con regleta	f
722	memoria ram ddr4 hyperx fury rgb 3000mhz (hx430c15fb3/8)	Hyperx	RAM	DDR4	Memoria RAM DDR4 HyperX Fury RGB 3000Mhz – (HX430C15FB3/8)	f
723	soporte para dos monitores kmm-510 con regleta integrada y puertos usb	Varios	Monitor	NaN	SOPORTE PARA DOS MONITORES KMM-510 CON REGLETA INTEGRADA Y PUERTOS USB	f
724	soporte huanuo 2 brazos vertical para monitores de 13 a 32 (hnhm2)	Varios	Monitor	NaN	SOPORTE HUANUO 2 BRAZOS VERTICAL para monitores DE 13 A 32″ (HNHM2)	f
725	boetec slim 2477 monitor curvo 24 200hz 1ms	Varios	Monitor	NaN	Boetec Slim 2477 Monitor Curvo 24″ 200Hz 1ms	f
726	monitor portatil env 15.6 fhd ips ultrafino usb c black	Varios	Monitor	IPS	MONITOR PORTATIL ENV 15.6″ FHD IPS – ULTRAFINO – USB C – BLACK	f
727	corsair mp600 core xt 1tb m.2 nvme gen4	Corsair	SSD	NVMe	Corsair MP600 Core XT 1TB M.2 Nvme Gen4	f
728	monitor portatil acer pm1 15.6 fhd 6ms ultrafino mini hdmi/usb c black (pm161q)	Acer	Monitor	NaN	MONITOR PORTATIL ACER PM1 – 15.6″ FHD – 6MS – ULTRAFINO – MINI HDMI/USB C – BLACK (PM161Q)	f
729	monitor samsung gaming odyssey g3 27 fhd 180hz dp hdmi black	Samsung	Monitor	NaN	Monitor Samsung Gaming Odyssey G3 27 – FHD – 180HZ – Dp Hdmi – Black	f
730	tp-link tapo d210 video portero wifi vision nocturna	Varios	GPU	NaN	Tp-link Tapo D210 Video Portero WiFi Visión Nocturna	f
731	monitor indurama vortix nova 27 | ips fhd 120hz	Varios	Monitor	IPS	Monitor Indurama Vortix Nova 27″ | IPS FHD 120Hz	f
732	headsets asus tuf gaming h3 gunmetal	Asus	Periferico	Headset	Headsets Asus TUF Gaming H3 – Gunmetal	f
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
2	36	1	20260630	1	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/procesador-amd-ryzen-5-5600gt-con-amd-radeon-graphics-socket-am4-4-60ghz-6-nucleos-16mb-cache-incluye-disipador/
3	138	1	20260630	1	315.0000	USD	1.000000	315.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/procesador-amd-ryzen-7-8700g-con-amd-radeon-graphics-socket-am5-5-10ghz-8-nucleos-24mb-cache-incluye-disipador/
4	50	1	20260630	1	325.0000	USD	1.000000	325.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/procesador-amd-ryzen-7-8700f-socket-am5-5ghz-8-nucleos-16mb-cache-incluye-disipador/
5	153	1	20260630	1	245.0000	USD	1.000000	245.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/procesador-intel-core-i5-14400-con-intel-uhd-graphics-730-lga-1700-4-70ghz-10-nucleos-20mb-cache-incluye-disipador-14va-generacion-raptor-lake/
6	32	1	20260630	1	179.0000	USD	1.000000	179.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/procesador-amd-ryzen-5-8500g-con-amd-radeon-graphics-socket-am5-5ghz-6-nucleos-16mb-cache-incluye-disipador/
7	44	1	20260630	1	950.0000	USD	1.000000	950.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/ultra9285k/
8	46	1	20260630	1	575.0000	USD	1.000000	575.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/ultra7265k/
9	47	1	20260630	1	435.0000	USD	1.000000	435.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/ultra5245/
10	547	1	20260630	1	900.0000	USD	1.000000	900.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/tarjeta-de-video-gigabyte-amd-radeon-rx-9070-gaming-oc-16gb-256-bit-gddr6-pci-express-5-0/
11	596	1	20260630	1	190.0000	USD	1.000000	190.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/mainbaord-asus-prime-b860m-a-socket-1851-intel/
12	492	1	20260630	1	1590.0000	USD	1.000000	1590.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/rtx5070ti16gbgigabyte/
13	381	1	20260630	1	900.0000	USD	1.000000	900.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/tarjeta-de-video-gigabyte-amd-radeon-rx-9070-gaming-oc-16gb-256-bit-gddr6-pci-express-5-0/
14	490	1	20260630	1	395.0000	USD	1.000000	395.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/tarjeta-de-video-asus-nvidia-geforce-rtx-5050-oc-edition-8gb-128-bit-gddr6-pci-express-5-0/
15	20	1	20260630	1	480.0000	USD	1.000000	480.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/dual50608gb/
16	467	1	20260630	1	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/memoria-ram-kingston-16gb-ddr5-5600mhz-dimm-cl46-kcp556us8-16-kvr56u46bs8-16/
17	464	1	20260630	1	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/memoria-ram-crucial-16gb-ddr5-5600mhz-16gb-pc/
18	462	1	20260630	1	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/memoria-ram-kingston-kcp548us8-16-ddr5-4800mhz-16gb-cl40-verde/
19	457	1	20260630	1	290.0000	USD	1.000000	290.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/32gbddr5cudimm/
20	460	1	20260630	1	189.0000	USD	1.000000	189.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/memoria-ram-mushkin-ddr4-3200mhz-16gb-pc16gbddr4-memoriaram16gbddr4/
21	123	1	20260630	1	189.0000	USD	1.000000	189.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/16gbkins-16gb-ddr4/
22	468	1	20260630	1	189.0000	USD	1.000000	189.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/16gbadata16gb-ddr4/
23	95	1	20260630	1	195.0000	USD	1.000000	195.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor-gamer-lg-ultragear-g4-lcd-23-8-1920x1080-full-hd-g-sync-freesync-144hz-hdmi-displayport-negro-modelo-24g411a-b/
24	215	1	20260630	1	110.0000	USD	1.000000	110.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor-teros-te-1914s-19-5-1600x900-5ms-220-nits-hdmi-vga-parlantes/
25	134	1	20260630	1	490.0000	USD	1.000000	490.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor-gamer-curvo-gigabyte-gs34wqca-lcd-34-3440x1440-ultra-wide-quad-hd-freesync-120hz-hdmi-displayport-negro/
26	102	1	20260630	1	280.0000	USD	1.000000	280.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/gs27fa/
27	564	1	20260630	1	380.0000	USD	1.000000	380.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor-indurama-32-vortix-ultra-va-fhd-1080p/
28	565	1	20260630	1	179.0000	USD	1.000000	179.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor-indurama-27-vortix-nova-ips-fhd-1080p-120hz/
29	473	1	20260630	1	99.0000	USD	1.000000	99.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor20u401a/
30	470	1	20260630	1	99.0000	USD	1.000000	99.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/monitor20mk40l/
31	100	1	20260630	1	159.0000	USD	1.000000	159.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/w2427sg/
32	569	1	20260630	1	110.0000	USD	1.000000	110.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/qm-b20/
33	170	1	20260630	1	39.0000	USD	1.000000	39.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/teclado-primus-gaming-ballista61t-abs-61-teclas-retroiluminado-switch-red-lineal-es-white-pks-060w-s/
34	171	1	20260630	1	8.0000	USD	1.000000	8.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/qk-440c/
35	236	1	20260630	1	89.0000	USD	1.000000	89.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/k70core/
36	235	1	20260630	1	8.0000	USD	1.000000	8.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/teclado-genius-kb-117-alambrico-usb-negro-espanol/
37	587	1	20260630	1	325.0000	USD	1.000000	325.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/upgrade-kit-mouse-logitech-g-pro-wireless-teclado-pro-x-60-tkl-wireless/
38	392	1	20260630	1	9.0000	USD	1.000000	9.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/qm-850/
39	387	1	20260630	1	129.0000	USD	1.000000	129.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/logitechgpro/
40	386	1	20260630	1	5.0000	USD	1.000000	5.0000	t	2026-06-30 00:00:00	https://www.compugamer.com.ec/gamers/producto/dx-110/
41	32	2	20260630	2	248.9900	USD	1.000000	248.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
42	36	2	20260630	2	229.9900	USD	1.000000	229.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
43	582	2	20260630	2	951.9900	USD	1.000000	951.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/servidores/componentes-servidores/
44	581	2	20260630	2	1762.9900	USD	1.000000	1762.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/servidores/componentes-servidores/
45	574	2	20260630	2	299.9900	USD	1.000000	299.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
46	563	2	20260630	2	14.9900	USD	1.000000	14.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/redes/adaptadores/
47	366	2	20260630	2	259.9900	USD	1.000000	259.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
48	573	2	20260630	2	274.9900	USD	1.000000	274.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/almacenamiento/
49	572	2	20260630	2	329.9900	USD	1.000000	329.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
50	372	2	20260630	2	124.9900	USD	1.000000	124.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
51	570	2	20260630	2	258.9900	USD	1.000000	258.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
52	383	2	20260630	2	169.9900	USD	1.000000	169.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
53	568	2	20260630	2	319.9900	USD	1.000000	319.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
54	379	2	20260630	2	139.9900	USD	1.000000	139.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/componentes/
55	373	2	20260630	2	369.9900	USD	1.000000	369.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/servidores/componentes-servidores/
56	610	2	20260630	2	89.9900	USD	1.000000	89.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
57	609	2	20260630	2	159.9900	USD	1.000000	159.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
58	605	2	20260630	2	174.9900	USD	1.000000	174.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
59	604	2	20260630	2	197.9900	USD	1.000000	197.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
60	603	2	20260630	2	499.9900	USD	1.000000	499.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
61	602	2	20260630	2	138.9900	USD	1.000000	138.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
62	600	2	20260630	2	229.9900	USD	1.000000	229.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
63	449	2	20260630	2	89.9900	USD	1.000000	89.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
64	598	2	20260630	2	439.9900	USD	1.000000	439.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
65	597	2	20260630	2	279.9900	USD	1.000000	279.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/
66	594	2	20260630	2	102.9900	USD	1.000000	102.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
67	592	2	20260630	2	8.9900	USD	1.000000	8.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
68	591	2	20260630	2	39.9900	USD	1.000000	39.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
69	590	2	20260630	2	19.9900	USD	1.000000	19.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
70	562	2	20260630	2	7.9900	USD	1.000000	7.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
71	408	2	20260630	2	119.9900	USD	1.000000	119.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
72	407	2	20260630	2	119.9900	USD	1.000000	119.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
73	406	2	20260630	2	19.9900	USD	1.000000	19.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
74	405	2	20260630	2	49.9900	USD	1.000000	49.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
75	410	2	20260630	2	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
76	558	2	20260630	2	18.9900	USD	1.000000	18.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
77	191	2	20260630	2	26.9900	USD	1.000000	26.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
78	212	2	20260630	2	7.9900	USD	1.000000	7.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
79	182	2	20260630	2	20.9900	USD	1.000000	20.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
80	419	2	20260630	2	35.9900	USD	1.000000	35.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
81	417	2	20260630	2	33.9900	USD	1.000000	33.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
82	552	2	20260630	2	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
83	553	2	20260630	2	28.9900	USD	1.000000	28.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
84	555	2	20260630	2	27.9900	USD	1.000000	27.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
85	551	2	20260630	2	6.9900	USD	1.000000	6.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
86	412	2	20260630	2	49.9900	USD	1.000000	49.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
87	583	2	20260630	2	45.9900	USD	1.000000	45.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
88	614	2	20260630	2	16.9900	USD	1.000000	16.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
89	701	2	20260630	2	25.9900	USD	1.000000	25.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
90	700	2	20260630	2	31.9900	USD	1.000000	31.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
91	413	2	20260630	2	21.9900	USD	1.000000	21.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
92	195	2	20260630	2	259.9900	USD	1.000000	259.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
93	699	2	20260630	2	9.9900	USD	1.000000	9.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
94	414	2	20260630	2	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
95	415	2	20260630	2	5.9900	USD	1.000000	5.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
96	416	2	20260630	2	6.9900	USD	1.000000	6.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
97	698	2	20260630	2	79.9900	USD	1.000000	79.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
98	697	2	20260630	2	14.9800	USD	1.000000	14.9800	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
99	696	2	20260630	2	37.9900	USD	1.000000	37.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
100	418	2	20260630	2	54.9900	USD	1.000000	54.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
101	695	2	20260630	2	3.4900	USD	1.000000	3.4900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
102	694	2	20260630	2	3.9900	USD	1.000000	3.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
103	693	2	20260630	2	20.9900	USD	1.000000	20.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
104	420	2	20260630	2	6.4900	USD	1.000000	6.4900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
105	692	2	20260630	2	13.0000	USD	1.000000	13.0000	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
106	188	2	20260630	2	10.9900	USD	1.000000	10.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
107	188	2	20260630	2	12.9900	USD	1.000000	12.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
108	691	2	20260630	2	10.9900	USD	1.000000	10.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
109	690	2	20260630	2	11.9900	USD	1.000000	11.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
110	421	2	20260630	2	20.9900	USD	1.000000	20.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
111	422	2	20260630	2	21.9900	USD	1.000000	21.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
112	283	2	20260630	2	13.9900	USD	1.000000	13.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
113	689	2	20260630	2	15.9900	USD	1.000000	15.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/accesorios/
114	688	2	20260630	2	21.9900	USD	1.000000	21.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
115	404	2	20260630	2	12.9900	USD	1.000000	12.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/audio/audifonos/
116	147	2	20260630	2	65.9900	USD	1.000000	65.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
117	147	2	20260630	2	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
118	686	2	20260630	2	4.9900	USD	1.000000	4.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/audio/audifonos/
119	148	2	20260630	2	89.9900	USD	1.000000	89.9900	t	2026-06-30 00:00:00	https://www.computron.com.ec/producto-categoria/computadoras/gamer/accesorios-gamer/
120	48	3	20260630	3	220.0000	USD	1.000000	220.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/intel-core-ultra-5-225f-procesador-10-nuc-hasta-4-9ghz-copia/
121	365	3	20260630	3	540.0000	USD	1.000000	540.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-9-9900x-procesador-4-4ghz-12-nucleos-24-hilos/
122	44	3	20260630	3	835.0000	USD	1.000000	835.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/intel-core-ultra-9-285k-procesador-24-nucleos-24-3-2-5-7ghz/
123	50	3	20260630	3	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-7-8700f-procesador-8-nuc-16h-4-1-5-ghz/
124	162	3	20260630	3	430.0000	USD	1.000000	430.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-7-9700x-3-8-5-5ghz-8-nucleos-16-hilos/
125	138	3	20260630	3	350.0000	USD	1.000000	350.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-7-8700g-procesador-8-nucleos-16-hilos-4-2ghz-5-1ghz/
126	1	3	20260630	3	470.0000	USD	1.000000	470.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/intel-core-ultra-7-265-procesador-20-nucleos-hasta-5-3ghz/
127	35	3	20260630	3	245.0000	USD	1.000000	245.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-5-8600g-procesador-6-nucleos-12-hilos-4-3ghz-5-0ghz/
128	32	3	20260630	3	194.0000	USD	1.000000	194.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-5-8500g-procesador-3-5ghz-6-nucleos-12-hilos-am5/
129	684	3	20260630	3	70.0000	USD	1.000000	70.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gamdias-aura-gc12-case-gamer-6-fans-argb/
130	683	3	20260630	3	60.0000	USD	1.000000	60.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gamdias-kratos-m1-600b-fuente-de-poder-600w-80-bronze/
131	682	3	20260630	3	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gamdias-atlas-m3m-case-gamer-vidrio-templado-3-fans/
132	681	3	20260630	3	1185.0000	USD	1.000000	1185.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/lenovo-loq-15arp10e-amd-r7-7735hs-16gb-512b-rtx-4050-15-6/
133	51	3	20260630	3	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-5-9600x-3-9-5-4ghz-6-nucleos-12-hilos/
134	409	3	20260630	3	440.0000	USD	1.000000	440.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-7-7700x-4-5ghz-am5-8-nucleos-16-hilos/
135	680	3	20260630	3	110.0000	USD	1.000000	110.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-prime-h810m-e-lga1851-ddr5-intel/
136	679	3	20260630	3	280.0000	USD	1.000000	280.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-tuf-gaming-b850m-plus-wifi-am5-amd-ddr5-mainboard/
137	678	3	20260630	3	400.0000	USD	1.000000	400.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-tuf-z890-plus-wifi-intel-core-ultra/
138	87	3	20260630	3	390.0000	USD	1.000000	390.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/amd-ryzen-7-7700-3-8ghz-8-nucleos-16-hilos-procesador-am5/
139	411	3	20260630	3	900.0000	USD	1.000000	900.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-rtx-5070-12g-shadow-3x-oc-tarjeta-de-video/
140	423	3	20260630	3	540.0000	USD	1.000000	540.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-dual-rtx-5060-ti-8gb-gddr7-oc-edition-tarjeta-de-video/
141	445	3	20260630	3	790.0000	USD	1.000000	790.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-dual-rtx-5060-ti-evo-16gb-tarjeta-de-video/
142	18	3	20260630	3	415.0000	USD	1.000000	415.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-dual-rtx-5050-8gb-gddr6-oc-edition-tarjeta-de-video/
143	447	3	20260630	3	750.0000	USD	1.000000	750.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-rtx-5060-ti-16g-ventus-2x-oc-plus-tarjeta-video/
144	448	3	20260630	3	1295.0000	USD	1.000000	1295.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gigabyte-rtx-5070-ti-eagle-oc-sff-16g-tarjeta-de-video/
145	730	3	20260630	3	60.0000	USD	1.000000	60.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/video-portero-wifi-tapo-d210-vision-nocturna-color-y-deteccion-de-personas/
523	624	5	20260630	5	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=audifonos&post_type=product#
146	450	3	20260630	3	1185.0000	USD	1.000000	1185.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/lenovo-loq-15arp10e-amd-r7-7735hs-16gb-512b-rtx-4050-15-6/
147	451	3	20260630	3	900.0000	USD	1.000000	900.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/zotac-gaming-geforce-rtx-5070-solid-12gb/
148	445	3	20260630	3	760.0000	USD	1.000000	760.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/zotac-gaming-geforce-rtx-5060-ti-twin-edge-oc-16gb/
149	445	3	20260630	3	765.0000	USD	1.000000	765.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gigabyte-geforce-rtx-5060-ti-eagle-oc-ice-16gb/
150	448	3	20260630	3	1300.0000	USD	1.000000	1300.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/zotac-gaming-geforce-rtx-5070-ti-solid-sff-oc-16gb/
151	452	3	20260630	3	175.0000	USD	1.000000	175.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/adata-xpg-spectrix-d41-16gb-ddr4-rgb-3200mhz/
152	389	3	20260630	3	325.0000	USD	1.000000	325.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/xpg-lancer-rgb-ddr5-16gb-ram-6000mhz-white/
153	453	3	20260630	3	335.0000	USD	1.000000	335.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/xpg-caster-rgb-16gb-ddr5-6400mhz/
154	454	3	20260630	3	210.0000	USD	1.000000	210.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/adata-sc610-1000gb-disco-de-estado-solido-externo/
155	727	3	20260630	3	200.0000	USD	1.000000	200.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/corsair-mp600-core-xt-1t-m-2-gen4/
156	725	3	20260630	3	145.0000	USD	1.000000	145.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/boetec-slim-2477-24-ips-200hz-1ms/
157	289	3	20260630	3	250.0000	USD	1.000000	250.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-tuf-vg259qm5a-24-5-monitor-gamer-fhd-240hz-ips/
158	132	3	20260630	3	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gigabyte-gs27qa-monitor-27-qhd-ss-ips-180hz-1ms/
159	103	3	20260630	3	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-mag-276cxf-monitor-27fhd-curvo-280hz-0-5ms/
160	396	3	20260630	3	295.0000	USD	1.000000	295.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/eros-te-2767g-27-curvo-qhd-2k-180hz-1ms/
161	446	3	20260630	3	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/teros-te-2754g-27-qhd-ips-200hz-1ms/
162	444	3	20260630	3	955.0000	USD	1.000000	955.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-proart-pa27jcv-27-pulgadas-ips-5k-monitor/
163	425	3	20260630	3	350.0000	USD	1.000000	350.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-mag-32c6x-31-5-monitor-curvo-fhd-250hz-1ms/
164	443	3	20260630	3	305.0000	USD	1.000000	305.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-mag-272f-x24-monitor-27-ips-full-hd-240hz-0-5ms/
165	426	3	20260630	3	220.0000	USD	1.000000	220.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/thunderobot-zq25f180-monitor-24-5-180hz-qhd-ips/
166	427	3	20260630	3	290.0000	USD	1.000000	290.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-tuf-vg279qm5a-27-monitor-gamer-fhd-240hz-ips/
167	428	3	20260630	3	210.0000	USD	1.000000	210.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/armaggeddon-pixxel-xf27hd-monitor-27-ips-120hz/
168	429	3	20260630	3	240.0000	USD	1.000000	240.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-tuf-vg249q5r-23-8-monitor-gamer-fhd-200hz-ips/
169	430	3	20260630	3	225.0000	USD	1.000000	225.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-pro-mp243l-e14-monitor-24-144hz-ips-1ms/
170	431	3	20260630	3	235.0000	USD	1.000000	235.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/teros-te-2786g-27-monitor-gamer-200hz-1ms-ips/
171	721	3	20260630	3	50.0000	USD	1.000000	50.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/klip-xtreme-kmm-510-soporte-articulado-dos-monitores/
172	432	3	20260630	3	428.9900	USD	1.000000	428.9900	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asrock-pg27q15r2a-27-monitor-curvo-va-qhd-1440p-165hz/
173	433	3	20260630	3	165.0000	USD	1.000000	165.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/cooler-master-ga241-23-8-monitor-fhd-100hz-1ms/
174	434	3	20260630	3	619.9900	USD	1.000000	619.9900	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/lg-ergo-32uk580-b-monitor-31-5-pulgadas-4k-uhd/
175	435	3	20260630	3	1605.0000	USD	1.000000	1605.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/msi-mpg-491cqp-49-qd-oled-144hz-0-3ms/
176	720	3	20260630	3	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/oraimo-osw-831n-rose-gold-amoled-1-32%c2%a8/
177	436	3	20260630	3	740.0000	USD	1.000000	740.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/asus-rog-strix-xg27aqdmes-27-240hz-oled-qhd/
178	718	3	20260630	3	30.0000	USD	1.000000	30.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gamdias-hermes-e8-usb-red-switch-teclado-mecanico/
179	706	3	20260630	3	40.0000	USD	1.000000	40.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/gamdias-hermes-e7-usb-red-switch-teclado-mecanico/
180	437	3	20260630	3	75.0000	USD	1.000000	75.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-horus-k618-rgb-white-teclado-mecanico/
181	438	3	20260630	3	75.0000	USD	1.000000	75.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-otiim-magnetic-k729-teclado-gamer-ultramag/
182	439	3	20260630	3	85.0000	USD	1.000000	85.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-flekact-pro-k708gf-rgb-pro-teclado-inalambrico/
183	440	3	20260630	3	50.0000	USD	1.000000	50.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-kumara-k552-teclado-mecanico/
184	441	3	20260630	3	70.0000	USD	1.000000	70.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-ucal-pro-k673-anime-teclado-75-wireless/
185	442	3	20260630	3	95.0000	USD	1.000000	95.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-olaf-k648gg-rgb-teclado-gamer-wireless-94-teclas/
186	424	3	20260630	3	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-eisa-k686ak-rgb-pro-teclado-gamer-90/
187	403	3	20260630	3	70.0000	USD	1.000000	70.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-draconic-k530-og-teclado-gamer-wireless-60/
188	402	3	20260630	3	45.0000	USD	1.000000	45.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-fizz-pro-k616-rgb-teclado-wireless-blanco/
189	180	3	20260630	3	13.0000	USD	1.000000	13.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/alcatroz-x-craft-xc3000-combo-gamer/
190	717	3	20260630	3	28.0000	USD	1.000000	28.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/armaggeddon-mka-7c-psycheagle-teclado-mecanico-red-switch/
191	716	3	20260630	3	18.0000	USD	1.000000	18.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/genius-scorpion-km-gx6-tecladomouse-combo-gamer/
192	190	3	20260630	3	12.0000	USD	1.000000	12.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/genius-km-160-combo-teclado-mouse-usb/
193	374	3	20260630	3	40.0000	USD	1.000000	40.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/thunderobot-k104-teclado-mecanico-red-switch/
194	375	3	20260630	3	33.0000	USD	1.000000	33.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/thunderobot-kg3089c-teclado-negro-mecanico-blue-switch/
195	376	3	20260630	3	25.0000	USD	1.000000	25.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-aatrox-m811-rgb-mmo-mouse-15-botones/
196	715	3	20260630	3	58.0000	USD	1.000000	58.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/razer-deathadder-v2-x-hyperspeed-mouse-inalambrico/
197	377	3	20260630	3	18.0000	USD	1.000000	18.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-griffin-m607-mouse-gamer-rgb-7200-dpi/
198	378	3	20260630	3	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-k1ng-m916-ultra-mouse-8k-hz-30k-dpi/
199	714	3	20260630	3	25.0000	USD	1.000000	25.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/cougar-minos-neo-mouse-gamer-6-2k-dpi-usb/
200	380	3	20260630	3	18.0000	USD	1.000000	18.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/genius-ergo-8350s-mouse-vertical/
201	713	3	20260630	3	100.0000	USD	1.000000	100.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/logitech-mx-vertical-mouse-ergonomico-vertical-2/
202	141	3	20260630	3	25.0000	USD	1.000000	25.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/logitech-g203-prodigy-mouse-gamer/
203	613	3	20260630	3	24.9900	USD	1.000000	24.9900	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/hyperx-pulsefire-core-rgb-mouse-gamer/
204	382	3	20260630	3	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/cougar-airblader-tournament-mouse-gamer-20k-dpi-white/
205	712	3	20260630	3	70.0000	USD	1.000000	70.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/razer-blackshark-v2-x-wh-headset-gamer/
206	384	3	20260630	3	21.0000	USD	1.000000	21.0000	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/redragon-hylas-h260-rgb-auriculares-gamer/
207	711	3	20260630	3	34.9900	USD	1.000000	34.9900	t	2026-06-30 00:00:00	https://mtec-ec.com/producto/armaggeddon-cosmic-iii-lite-bk-auriculares-inalambrico-copia/
208	385	4	20260630	4	280.0000	USD	1.000000	280.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-intel-core-ultra-5-250kf-plus-5-3ghz-22tops-1818-lga-1851/
209	27	4	20260630	4	1290.0000	USD	1.000000	1290.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-ryzen-9-9950x3d2-5-6ghz-am5/
210	710	4	20260630	4	470.0000	USD	1.000000	470.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-intel-core-i7-14700-5-4ghz/
211	160	4	20260630	4	260.0000	USD	1.000000	260.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-intel-core-ultra-5-225/
212	371	4	20260630	4	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-5-9600-am5/
213	370	4	20260630	4	490.0000	USD	1.000000	490.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-9-5900xt-am4/
214	26	4	20260630	4	780.0000	USD	1.000000	780.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/amd-ryzen-9-9900x3d-5-5ghz-am5/
215	2	4	20260630	4	950.0000	USD	1.000000	950.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/amd-ryzen-9-9950x3d-5-7ghz-1632-am5/
216	50	4	20260630	4	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/amd-ryzen-7-8700f-5ghz-816-am5/
217	48	4	20260630	4	230.0000	USD	1.000000	230.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/intel-core-ultra-5-225f-lga-1851/
218	44	4	20260630	4	820.0000	USD	1.000000	820.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-intel-core-ultra-9-285k/
219	86	4	20260630	4	200.0000	USD	1.000000	200.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-5-8400f-612-4-7ghz/
220	159	4	20260630	4	430.0000	USD	1.000000	430.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-intel-core-ultra-7-265kf/
221	365	4	20260630	4	550.0000	USD	1.000000	550.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-9-9900x/
222	51	4	20260630	4	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-5-9600x-5-4ghz/
223	32	4	20260630	4	180.0000	USD	1.000000	180.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-ryzen-5-8500g-radeon-740m/
224	138	4	20260630	4	300.0000	USD	1.000000	300.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/amd-ryzen-7-8700g-5-1ghz-radeon-780m/
225	35	4	20260630	4	220.0000	USD	1.000000	220.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/amd-ryzen-5-8600g-5-0ghz-radeon-760m/
226	367	4	20260630	4	390.0000	USD	1.000000	390.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/procesador-amd-ryzen-7-7700-5-3ghz-am5/
227	368	4	20260630	4	2049.9900	USD	1.000000	2049.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-zotac-amp-extreme-infinity-geforce-rtx-5080-16gb-gddr7/
228	75	4	20260630	4	499.9900	USD	1.000000	499.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-gigabyte-eagle-geforce-rtx-5060-8gb-oc-gddr7/
229	75	4	20260630	4	509.9900	USD	1.000000	509.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-gigabyte-eagle-ice-geforce-rtx-5060-8gb-oc-gddr7/
230	18	4	20260630	4	419.9900	USD	1.000000	419.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-gigabyte-windforce-v2-geforce-rtx-5050-8gb-oc-gddr6/
231	369	4	20260630	4	769.9900	USD	1.000000	769.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/asus-dual-evo-geforce-rtx-5060-ti-16gb/
232	76	4	20260630	4	3989.9900	USD	1.000000	3989.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/zotac-amp-extreme-infinity-rtx-5090-32g/
233	76	4	20260630	4	6989.9900	USD	1.000000	6989.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-geforce-rtx-5090-32g-lightning-z/
234	364	4	20260630	4	1149.9900	USD	1.000000	1149.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/xfx-swift-amd-radeon-rx-9070-xt-16gb/
235	22	4	20260630	4	699.9900	USD	1.000000	699.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/xfx-swift-amd-radeon-rx-9060-xt-16gb-oc-wh/
236	22	4	20260630	4	689.9900	USD	1.000000	689.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/xfx-swift-amd-radeon-rx-9060-xt-16gb-oc/
237	368	4	20260630	4	2099.9900	USD	1.000000	2099.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-gaming-trio-white-geforce-rtx-5080-16gb-oc-gddr7/
238	75	4	20260630	4	479.9900	USD	1.000000	479.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/msi-cyclone-geforce-rtx-5060-8gb-oc/
239	18	4	20260630	4	399.9900	USD	1.000000	399.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/zotac-rtx-5050-8gb-edge-oc-gddr6/
240	18	4	20260630	4	409.9900	USD	1.000000	409.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-asus-dual-nvidia-rtx-5050-8gb-gddr6-oc/
241	22	4	20260630	4	519.9900	USD	1.000000	519.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-asrock-steel-legend-amd-radeon-rx-9060-xt-8gb-oc-gddr6/
242	53	4	20260630	4	949.9900	USD	1.000000	949.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-asus-prime-rtx-5070-12gb-oc-gddr7/
243	75	4	20260630	4	519.9900	USD	1.000000	519.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/tarjeta-de-video-msi-ventus-3x-nvidia-rtx-5060-8gb-oc-gddr7/
244	369	4	20260630	4	789.9900	USD	1.000000	789.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gigabyte-eagle-ice-rtx-5060-ti-16gb-oc/
245	76	4	20260630	4	4489.9900	USD	1.000000	4489.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/asus-rog-astral-rtx-5090-32gb-oc-gddr7/
246	401	4	20260630	4	999.9900	USD	1.000000	999.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gigabyte-amd-radeon-rx-9070-16gb-oc/
247	53	4	20260630	4	1049.9900	USD	1.000000	1049.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gpu-asus-tuf-rtx-5070-12gb-oc-gddr7/
248	85	4	20260630	4	1449.9900	USD	1.000000	1449.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gpu-gigabyte-gaming-rtx-5070-ti-16gb-oc/
249	364	4	20260630	4	1189.9900	USD	1.000000	1189.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gpu-gigabyte-aorus-elite-amd-radeon-rx-9070-xt-16gb-oc/
250	368	4	20260630	4	1999.9900	USD	1.000000	1999.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gpu-gigabyte-aero-sff-rtx-5080-16gb-oc/
251	368	4	20260630	4	2389.9900	USD	1.000000	2389.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/asus-rog-astral-rtx-5080-16gb-oc-gddr7/
252	83	4	20260630	4	1249.9900	USD	1.000000	1249.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/asus-tuf-gaming-rtx-4070-ti-super-btf/
253	400	4	20260630	4	790.9000	USD	1.000000	790.9000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/gpu-aorus-xtreme-radeon-rx-6900-xt-12gb/
254	641	4	20260630	4	15.0000	USD	1.000000	15.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/adaptador-tp-link-tl-wn881nd/
255	456	4	20260630	4	110.0000	USD	1.000000	110.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/8gb-so-dimm-kingston-ddr5-5600mt-s-cl46/
256	399	4	20260630	4	400.0000	USD	1.000000	400.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/32gb-so-dimm-ddr5-kingston-fury-impact/
257	388	4	20260630	4	200.0000	USD	1.000000	200.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/16gb-so-dimm-ddr5-kingston-fury-impact/
258	319	4	20260630	4	180.0000	USD	1.000000	180.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/16gb-ram-ddr4-corsair-vengeance-lpx-3200mhz-cl16/
259	389	4	20260630	4	270.0000	USD	1.000000	270.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/16gb-ddr5-xpg-lancer-blade-6000mts-cl48/
260	316	4	20260630	4	100.0000	USD	1.000000	100.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/8gb-ddr4-so-dimm-kingston-3200mhz-cl22/
261	390	4	20260630	4	1349.9900	USD	1.000000	1349.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-ultrawide-curvo-samsung-odyssey-oled-g9-g91sd/
262	391	4	20260630	4	649.9900	USD	1.000000	649.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-ultrawide-curvo-samsung-viewfinity-s6-s65uc/
263	638	4	20260630	4	119.9900	USD	1.000000	119.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-portatil-viewsonic-va1653/
264	393	4	20260630	4	199.9900	USD	1.000000	199.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-lg-ultragear-27g411a/
265	125	4	20260630	4	199.9900	USD	1.000000	199.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-gigabyte-gs24f14/
266	637	4	20260630	4	149.9900	USD	1.000000	149.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-indurama-vortixnova-25/
267	394	4	20260630	4	519.9900	USD	1.000000	519.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-samsung-odyssey-g6-g60f/
268	395	4	20260630	4	1549.9900	USD	1.000000	1549.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-msi-mpg-321urx-qd-oled/
269	396	4	20260630	4	289.9900	USD	1.000000	289.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-curvo-teros-te-2767g/
270	397	4	20260630	4	299.9900	USD	1.000000	299.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-curvo-teros-te-3219g/
271	326	4	20260630	4	79.9900	USD	1.000000	79.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-acer-k202q-bi/
272	398	4	20260630	4	179.9900	USD	1.000000	179.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-lg-ultragear-24g411a/
273	455	4	20260630	4	209.9900	USD	1.000000	209.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-msi-g242l-e14/
274	635	4	20260630	4	169.9900	USD	1.000000	169.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-indurama-vortixnova-27/
275	289	4	20260630	4	249.9900	USD	1.000000	249.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-tuf-vg259qm5a/
276	436	4	20260630	4	749.9900	USD	1.000000	749.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-rog-strix-oled-xg27aqdmes/
277	512	4	20260630	4	949.9900	USD	1.000000	949.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-zenscreen-smart-ms32uc/
278	513	4	20260630	4	509.9900	USD	1.000000	509.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-ultrawide-lg-34u511a/
279	360	4	20260630	4	329.9900	USD	1.000000	329.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-proart-pa248qfv/
280	514	4	20260630	4	389.9900	USD	1.000000	389.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-proart-pa278qgv/
281	355	4	20260630	4	789.9900	USD	1.000000	789.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-gigabyte-mo27q28g-woled/
282	357	4	20260630	4	449.9900	USD	1.000000	449.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-gigabyte-m27q2-qd-ice/
283	135	4	20260630	4	239.9900	USD	1.000000	239.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-gigabyte-gs25f2a/
284	429	4	20260630	4	239.9900	USD	1.000000	239.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-tuf-vg249q5r/
285	427	4	20260630	4	289.9900	USD	1.000000	289.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-tuf-vg279qm5a/
286	516	4	20260630	4	1349.9900	USD	1.000000	1349.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-corsair-xeneon-34wqhd240-c-oled/
287	517	4	20260630	4	439.9900	USD	1.000000	439.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-curvo-teros-te-3412g/
288	446	4	20260630	4	299.9900	USD	1.000000	299.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-teros-te-2754g/
289	518	4	20260630	4	140.0000	USD	1.000000	140.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-portatil-asus-zenscreen-mb169ck/
290	519	4	20260630	4	519.9900	USD	1.000000	519.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-curvo-ultrawide-lg-34wr50qk-b/
291	431	4	20260630	4	229.9900	USD	1.000000	229.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-teros-te-2786g/
292	515	4	20260630	4	179.9900	USD	1.000000	179.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-teros-te-2417s/
293	509	4	20260630	4	189.9900	USD	1.000000	189.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-teros-te-2714s/
294	131	4	20260630	4	219.9900	USD	1.000000	219.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-gigabyte-gs25f2/
295	132	4	20260630	4	299.9900	USD	1.000000	299.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-gigabyte-gs27qa-2/
296	102	4	20260630	4	249.9900	USD	1.000000	249.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-gigabyte-gs27fa/
297	105	4	20260630	4	239.9900	USD	1.000000	239.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-curvo-msi-mag-242c/
298	499	4	20260630	4	309.9900	USD	1.000000	309.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asrock-pg27fft1a/
299	500	4	20260630	4	279.9900	USD	1.000000	279.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asrock-pg25fft-ips-180hz-1ms/
300	96	4	20260630	4	349.9900	USD	1.000000	349.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-curvo-samsung-odyssey-g5-g55c/
301	501	4	20260630	4	279.9900	USD	1.000000	279.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-curvo-teros-te-2764g/
302	362	4	20260630	4	589.9900	USD	1.000000	589.9900	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/monitor-asus-proart-pa279crv/
303	502	4	20260630	4	75.0000	USD	1.000000	75.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-multi-plataforma-logitech-k780/
304	634	4	20260630	4	180.0000	USD	1.000000	180.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-logitech-g-pro-x-tkl-rapid-magnetic-switch/
305	503	4	20260630	4	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-redragon-behemoth-pro-k724-black-rpc-switch/
306	504	4	20260630	4	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-redragon-behemoth-pro-k724gbg-black-green-manbo-switch/
307	506	4	20260630	4	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-redragon-behemoth-pro-k724sp-gradient-manbo-switch/
308	507	4	20260630	4	85.0000	USD	1.000000	85.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-redragon-terraflare-pro-k762wb-white-black-manbo-switch/
309	520	4	20260630	4	85.0000	USD	1.000000	85.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-redragon-terraflare-pro-k762wp-white-purple-manbo-switch/
310	631	4	20260630	4	50.0000	USD	1.000000	50.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redradon-castor-magnetic-k631/
311	521	4	20260630	4	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-y-mouse-logitech-advanced-mk540/
312	630	4	20260630	4	120.0000	USD	1.000000	120.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-razer-huntsman-v3-x-tenkeyless-optical-purple-switch/
313	629	4	20260630	4	130.0000	USD	1.000000	130.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-asus-rog-falchion-ace-hfx-magnetic-switch/
314	628	4	20260630	4	380.0000	USD	1.000000	380.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-corsair-galleon-100-sd/
315	627	4	20260630	4	200.0000	USD	1.000000	200.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-corsair-vanguard-96-mlx-switch/
316	236	4	20260630	4	190.0000	USD	1.000000	190.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-corsair-k70-core-tkl-mlx-switch/
317	236	4	20260630	4	230.0000	USD	1.000000	230.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-corsair-k70-pro-tkl-mgx-switch/
318	543	4	20260630	4	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-corsair-k55-rgb-pro/
319	542	4	20260630	4	190.0000	USD	1.000000	190.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-corsair-k65-plus-mlx-switch/
320	542	4	20260630	4	155.0000	USD	1.000000	155.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-optico-corsair-k65-pro-mini/
321	540	4	20260630	4	85.0000	USD	1.000000	85.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-artemis-pro-k719gf/
322	539	4	20260630	4	90.0000	USD	1.000000	90.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-flekact-pro-k708mc/
323	538	4	20260630	4	90.0000	USD	1.000000	90.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-flekact-pro-k708ak/
324	522	4	20260630	4	85.0000	USD	1.000000	85.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-flekact-pro-k708wlg/
325	536	4	20260630	4	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-flekact-pro-k708gg/
326	523	4	20260630	4	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-cyrus-pro-k681wbp-lila/
327	525	4	20260630	4	60.0000	USD	1.000000	60.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-cyrus-pro-k681mg-green/
328	526	4	20260630	4	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-gloria-pro-k664wbp/
329	527	4	20260630	4	55.0000	USD	1.000000	55.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-veigar-k643wgc/
330	528	4	20260630	4	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-horus-mini-pro-k632-wh/
331	529	4	20260630	4	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-magnetico-redragon-ghostblade-k735/
332	530	4	20260630	4	45.0000	USD	1.000000	45.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-ironguard-k722/
333	531	4	20260630	4	50.0000	USD	1.000000	50.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-kumara-k552wgl/
334	532	4	20260630	4	50.0000	USD	1.000000	50.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-kumara-k552lgy/
335	533	4	20260630	4	75.0000	USD	1.000000	75.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-yama-k550-white-switch-purple/
336	534	4	20260630	4	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-y-mouse-meetion-mini5000/
337	535	4	20260630	4	35.0000	USD	1.000000	35.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-meetion-wk310-black/
338	439	4	20260630	4	90.0000	USD	1.000000	90.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-flekact-pro-art-k708gf/
339	508	4	20260630	4	70.0000	USD	1.000000	70.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-primus-ballista-82t-star-wars-c-3po/
340	498	4	20260630	4	40.0000	USD	1.000000	40.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-meetion-wk330-black/
341	202	4	20260630	4	75.0000	USD	1.000000	75.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-redragon-eisa-k686-rgb/
342	441	4	20260630	4	70.0000	USD	1.000000	70.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-redragon-ucal-pro-k673-rgb-gris-degradado-switch-red/
343	497	4	20260630	4	70.0000	USD	1.000000	70.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/teclado-inalambrico-redragon-cyrus-pro-k681-rgb-blanco-verde/
344	623	4	20260630	4	95.0000	USD	1.000000	95.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-razer-viper-v3-hyperspeed/
345	472	4	20260630	4	40.0000	USD	1.000000	40.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-redragon-fyzu-ultra-light-m995/
346	187	4	20260630	4	175.0000	USD	1.000000	175.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-logitech-g-g502-x-plus-lightspeed/
347	621	4	20260630	4	145.0000	USD	1.000000	145.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-logitech-g-pro-x-superlight-2-se/
348	620	4	20260630	4	155.0000	USD	1.000000	155.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-logitech-g-pro-x-superlight-2c/
349	475	4	20260630	4	160.0000	USD	1.000000	160.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-razer-basilisk-v3-pro-35k-phantom-green-edition/
350	618	4	20260630	4	110.0000	USD	1.000000	110.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-razer-cobra-hyperspeed/
351	617	4	20260630	4	150.0000	USD	1.000000	150.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-logitech-mx-master-4/
352	616	4	20260630	4	85.0000	USD	1.000000	85.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-asus-rog-harpe-ace-aim-lab-edition/
353	469	4	20260630	4	45.0000	USD	1.000000	45.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-logitech-ergo-m575s/
354	644	4	20260630	4	170.0000	USD	1.000000	170.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-corsair-scimitar-elite-se-carbon/
355	458	4	20260630	4	55.0000	USD	1.000000	55.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-corsair-m55-carbon/
356	459	4	20260630	4	140.0000	USD	1.000000	140.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-corsair-m75-white/
357	659	4	20260630	4	160.0000	USD	1.000000	160.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-corsair-nightsabre-carbon/
358	461	4	20260630	4	140.0000	USD	1.000000	140.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-corsair-m65-rgb-ultra-wh/
359	670	4	20260630	4	90.0000	USD	1.000000	90.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-corsair-scimitar-rgb-elite-carbon/
360	669	4	20260630	4	45.0000	USD	1.000000	45.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-corsair-harpoon-rgb-pro-carbon/
361	463	4	20260630	4	15.0000	USD	1.000000	15.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-redragon-azzmach-m618-black/
362	199	4	20260630	4	35.0000	USD	1.000000	35.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/combo-inalambrico-logitech-mk250/
363	465	4	20260630	4	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-meetion-btm008/
364	466	4	20260630	4	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-ergonomico-inalambrico-klipxtreme-everrest-kmw-390/
365	476	4	20260630	4	40.0000	USD	1.000000	40.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/combo-inalambrico-meetion-ikey-c210/
366	283	4	20260630	4	15.0000	USD	1.000000	15.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-logitech-m196/
367	477	4	20260630	4	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-meetion-btm001/
368	488	4	20260630	4	45.0000	USD	1.000000	45.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/kit-inalambrico-meetion-ikey-c230/
369	666	4	20260630	4	100.0000	USD	1.000000	100.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-inalambrico-logitech-mx-ergo-s/
370	665	4	20260630	4	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/combo-inalambrico-logitech-pop-icon/
371	664	4	20260630	4	140.0000	USD	1.000000	140.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/mouse-logitech-pro-2-lightspeed/
372	250	4	20260630	4	160.0000	USD	1.000000	160.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifonos-lightspeed-logitech-g733/
373	663	4	20260630	4	270.0000	USD	1.000000	270.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-jbl-tour-one-m3-black/
374	493	4	20260630	4	55.0000	USD	1.000000	55.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-inalambrico-jbl-tune-530bt/
375	662	4	20260630	4	35.0000	USD	1.000000	35.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-jbl-tune-530-3-5mm/
376	495	4	20260630	4	95.0000	USD	1.000000	95.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-inalambrico-jbl-tune-680nc/
377	496	4	20260630	4	65.0000	USD	1.000000	65.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-inalambrico-jbl-tune-730bt/
378	487	4	20260630	4	115.0000	USD	1.000000	115.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-inalambrico-jbl-tune-780nc-black/
379	478	4	20260630	4	45.0000	USD	1.000000	45.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/auriculares-primus-arcus250-star-wars-bb-8/
380	253	4	20260630	4	40.0000	USD	1.000000	40.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/primus-arcus240-stormtrooper-tws/
381	479	4	20260630	4	40.0000	USD	1.000000	40.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/auricular-primus-arcus230-grogu-tws/
382	480	4	20260630	4	80.0000	USD	1.000000	80.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-redragon-zeus-x-h510-rgb-wh/
383	661	4	20260630	4	220.0000	USD	1.000000	220.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-logitech-g-pro-x-lightspeed/
384	481	4	20260630	4	55.0000	USD	1.000000	55.0000	t	2026-06-30 00:00:00	https://nomadaware.com.ec/producto/audifono-gamer-logitech-g332-3-5mm/
385	660	5	20260630	5	542.1600	USD	1.000000	542.1600	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
386	157	5	20260630	5	516.9800	USD	1.000000	516.9800	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
387	162	5	20260630	5	467.1100	USD	1.000000	467.1100	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
388	44	5	20260630	5	860.1600	USD	1.000000	860.1600	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
389	485	5	20260630	5	429.0000	USD	1.000000	429.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
390	151	5	20260630	5	89.0000	USD	1.000000	89.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
391	537	5	20260630	5	857.1200	USD	1.000000	857.1200	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
392	486	5	20260630	5	490.7000	USD	1.000000	490.7000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
393	657	5	20260630	5	530.9000	USD	1.000000	530.9000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
394	484	5	20260630	5	745.9100	USD	1.000000	745.9100	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
395	656	5	20260630	5	437.9700	USD	1.000000	437.9700	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
396	483	5	20260630	5	384.5200	USD	1.000000	384.5200	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=procesador&post_type=product#
397	365	5	20260630	5	576.4500	USD	1.000000	576.4500	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
398	30	5	20260630	5	145.0000	USD	1.000000	145.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
399	482	5	20260630	5	205.0000	USD	1.000000	205.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
400	655	5	20260630	5	69.0000	USD	1.000000	69.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
401	489	5	20260630	5	339.0000	USD	1.000000	339.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
402	654	5	20260630	5	249.0000	USD	1.000000	249.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
403	494	5	20260630	5	109.0000	USD	1.000000	109.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
404	17	5	20260630	5	459.0000	USD	1.000000	459.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
405	491	5	20260630	5	429.0000	USD	1.000000	429.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
406	88	5	20260630	5	499.0000	USD	1.000000	499.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
407	50	5	20260630	5	279.0000	USD	1.000000	279.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
408	370	5	20260630	5	389.0000	USD	1.000000	389.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=procesador&post_type=product#
409	651	5	20260630	5	419.0000	USD	1.000000	419.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
410	51	5	20260630	5	275.0000	USD	1.000000	275.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
411	162	5	20260630	5	425.0000	USD	1.000000	425.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
412	474	5	20260630	5	299.0000	USD	1.000000	299.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
413	650	5	20260630	5	459.0000	USD	1.000000	459.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
414	471	5	20260630	5	225.0000	USD	1.000000	225.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
415	138	5	20260630	5	299.0000	USD	1.000000	299.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
416	29	5	20260630	5	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
417	86	5	20260630	5	209.0000	USD	1.000000	209.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
418	541	5	20260630	5	399.0000	USD	1.000000	399.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
419	524	5	20260630	5	215.0000	USD	1.000000	215.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
420	510	5	20260630	5	125.0000	USD	1.000000	125.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=procesador&post_type=product#
421	648	5	20260630	5	83.4500	USD	1.000000	83.4500	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
422	505	5	20260630	5	430.8100	USD	1.000000	430.8100	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
423	511	5	20260630	5	510.2300	USD	1.000000	510.2300	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
424	381	5	20260630	5	1065.9300	USD	1.000000	1065.9300	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
425	364	5	20260630	5	1235.4400	USD	1.000000	1235.4400	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
426	75	5	20260630	5	499.0000	USD	1.000000	499.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
427	21	5	20260630	5	549.0000	USD	1.000000	549.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=tarjeta+de+video&post_type=product#
428	116	5	20260630	5	248.0000	USD	1.000000	248.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=tarjeta+de+video&post_type=product#
429	117	5	20260630	5	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=tarjeta+de+video&post_type=product#
430	647	5	20260630	5	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=tarjeta+de+video&post_type=product#
431	22	5	20260630	5	469.0000	USD	1.000000	469.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=tarjeta+de+video&post_type=product#
432	118	5	20260630	5	144.1700	USD	1.000000	144.1700	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
433	119	5	20260630	5	107.5400	USD	1.000000	107.5400	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
434	120	5	20260630	5	128.8200	USD	1.000000	128.8200	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
435	121	5	20260630	5	260.1800	USD	1.000000	260.1800	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
436	122	5	20260630	5	182.7700	USD	1.000000	182.7700	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
437	123	5	20260630	5	197.1700	USD	1.000000	197.1700	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=memoria+ram&post_type=product#
438	649	5	20260630	5	371.0000	USD	1.000000	371.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=memoria+ram&post_type=product#
439	28	5	20260630	5	289.0000	USD	1.000000	289.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=memoria+ram&post_type=product#
440	115	5	20260630	5	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=memoria+ram&post_type=product#
441	649	5	20260630	5	371.0000	USD	1.000000	371.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=disco+solido+ssd&post_type=product#
442	124	5	20260630	5	109.0000	USD	1.000000	109.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
443	126	5	20260630	5	116.0000	USD	1.000000	116.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
444	127	5	20260630	5	85.0000	USD	1.000000	85.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
445	128	5	20260630	5	84.0000	USD	1.000000	84.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
446	129	5	20260630	5	49.0000	USD	1.000000	49.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
447	130	5	20260630	5	189.0000	USD	1.000000	189.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=disco+solido+ssd&post_type=product#
448	131	5	20260630	5	235.0000	USD	1.000000	235.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
449	132	5	20260630	5	319.0000	USD	1.000000	319.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
450	133	5	20260630	5	215.0000	USD	1.000000	215.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
451	652	5	20260630	5	69.0000	USD	1.000000	69.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
452	134	5	20260630	5	549.0000	USD	1.000000	549.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
453	653	5	20260630	5	155.0000	USD	1.000000	155.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
454	135	5	20260630	5	259.0000	USD	1.000000	259.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
455	125	5	20260630	5	209.0000	USD	1.000000	209.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
456	114	5	20260630	5	265.0000	USD	1.000000	265.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
457	113	5	20260630	5	159.0000	USD	1.000000	159.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
458	112	5	20260630	5	1194.2600	USD	1.000000	1194.2600	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
459	90	5	20260630	5	928.0000	USD	1.000000	928.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=monitor&post_type=product#
460	91	5	20260630	5	609.0700	USD	1.000000	609.0700	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
461	92	5	20260630	5	269.0000	USD	1.000000	269.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
462	93	5	20260630	5	149.0000	USD	1.000000	149.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
463	94	5	20260630	5	255.0000	USD	1.000000	255.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
464	95	5	20260630	5	194.0000	USD	1.000000	194.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
465	96	5	20260630	5	355.0000	USD	1.000000	355.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
466	97	5	20260630	5	98.0000	USD	1.000000	98.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
467	289	5	20260630	5	275.0000	USD	1.000000	275.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
468	98	5	20260630	5	259.0000	USD	1.000000	259.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
469	646	5	20260630	5	195.0000	USD	1.000000	195.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
470	658	5	20260630	5	185.0000	USD	1.000000	185.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
471	99	5	20260630	5	178.0000	USD	1.000000	178.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=monitor&post_type=product#
472	100	5	20260630	5	149.0000	USD	1.000000	149.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
473	101	5	20260630	5	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
474	102	5	20260630	5	249.0000	USD	1.000000	249.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
475	103	5	20260630	5	329.0000	USD	1.000000	329.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
476	104	5	20260630	5	249.0000	USD	1.000000	249.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
477	105	5	20260630	5	269.0000	USD	1.000000	269.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
478	106	5	20260630	5	249.0000	USD	1.000000	249.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
479	107	5	20260630	5	219.0000	USD	1.000000	219.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
480	108	5	20260630	5	249.0000	USD	1.000000	249.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
481	109	5	20260630	5	83.0000	USD	1.000000	83.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
482	110	5	20260630	5	289.0000	USD	1.000000	289.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
483	111	5	20260630	5	199.0000	USD	1.000000	199.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=monitor&post_type=product#
484	136	5	20260630	5	24.0000	USD	1.000000	24.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
485	89	5	20260630	5	13.0000	USD	1.000000	13.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
486	137	5	20260630	5	27.0000	USD	1.000000	27.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
487	139	5	20260630	5	23.0000	USD	1.000000	23.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
488	167	5	20260630	5	25.0000	USD	1.000000	25.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
489	168	5	20260630	5	27.0000	USD	1.000000	27.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
490	169	5	20260630	5	32.0000	USD	1.000000	32.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
491	170	5	20260630	5	42.0000	USD	1.000000	42.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
492	171	5	20260630	5	9.0000	USD	1.000000	9.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
493	172	5	20260630	5	15.0000	USD	1.000000	15.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
494	173	5	20260630	5	15.0000	USD	1.000000	15.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=teclado&post_type=product#
495	667	5	20260630	5	12.0000	USD	1.000000	12.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
496	174	5	20260630	5	30.0000	USD	1.000000	30.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
497	175	5	20260630	5	40.0000	USD	1.000000	40.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
498	176	5	20260630	5	29.0000	USD	1.000000	29.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
499	668	5	20260630	5	24.0000	USD	1.000000	24.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
500	166	5	20260630	5	12.0000	USD	1.000000	12.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
501	177	5	20260630	5	21.0000	USD	1.000000	21.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
502	179	5	20260630	5	12.0000	USD	1.000000	12.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
503	180	5	20260630	5	15.0000	USD	1.000000	15.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
504	671	5	20260630	5	59.0000	USD	1.000000	59.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
505	181	5	20260630	5	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
506	182	5	20260630	5	24.0000	USD	1.000000	24.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=teclado&post_type=product#
507	183	5	20260630	5	26.0000	USD	1.000000	26.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=teclado&post_type=product#
508	645	5	20260630	5	25.0000	USD	1.000000	25.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=teclado&post_type=product#
509	184	5	20260630	5	23.0000	USD	1.000000	23.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/3/?s=teclado&post_type=product#
510	185	5	20260630	5	10.0000	USD	1.000000	10.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
511	643	5	20260630	5	28.0000	USD	1.000000	28.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
512	186	5	20260630	5	14.0000	USD	1.000000	14.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
513	187	5	20260630	5	55.0000	USD	1.000000	55.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
514	188	5	20260630	5	14.5000	USD	1.000000	14.5000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
515	178	5	20260630	5	10.0000	USD	1.000000	10.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
516	619	5	20260630	5	8.5000	USD	1.000000	8.5000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
517	165	5	20260630	5	11.0000	USD	1.000000	11.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
518	164	5	20260630	5	12.0000	USD	1.000000	12.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=mouse&post_type=product#
519	163	5	20260630	5	16.0000	USD	1.000000	16.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=mouse&post_type=product#
520	622	5	20260630	5	15.0000	USD	1.000000	15.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=mouse&post_type=product#
521	140	5	20260630	5	48.0000	USD	1.000000	48.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=mouse&post_type=product#
522	141	5	20260630	5	25.0000	USD	1.000000	25.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=mouse&post_type=product#
524	625	5	20260630	5	13.0000	USD	1.000000	13.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=audifonos&post_type=product#
525	142	5	20260630	5	55.0000	USD	1.000000	55.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=audifonos&post_type=product#
526	626	5	20260630	5	11.0000	USD	1.000000	11.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/?s=audifonos&post_type=product#
527	143	5	20260630	5	18.0000	USD	1.000000	18.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=audifonos&post_type=product#
528	144	5	20260630	5	15.0000	USD	1.000000	15.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=audifonos&post_type=product#
529	145	5	20260630	5	20.0000	USD	1.000000	20.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=audifonos&post_type=product#
530	146	5	20260630	5	23.0000	USD	1.000000	23.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=audifonos&post_type=product#
531	147	5	20260630	5	55.0000	USD	1.000000	55.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=audifonos&post_type=product#
532	148	5	20260630	5	75.0000	USD	1.000000	75.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=audifonos&post_type=product#
533	149	5	20260630	5	79.0000	USD	1.000000	79.0000	t	2026-06-30 00:00:00	https://tecnogame.ec/page/2/?s=audifonos&post_type=product#
534	150	6	20260630	6	337.9900	USD	1.000000	337.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-5-250k-plus-turbo-5-3ghz-18-cores-lga1851/
535	151	6	20260630	6	95.9900	USD	1.000000	95.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-3-3200g-con-graficos-radeon-vega-8/
536	152	6	20260630	6	502.9900	USD	1.000000	502.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-7-270k-plus-24-cores-3-7ghz-base-36mb-lga1851-125w-base/
537	153	6	20260630	6	305.9900	USD	1.000000	305.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-14400-2-5ghz-14th-lga1700-uhd770-10-cores-20mb-cache/
538	154	6	20260630	6	175.9900	USD	1.000000	175.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i3-13100f-3-40ghz-13th-lga1700-4-cores-12mb-cache/
539	155	6	20260630	6	619.9900	USD	1.000000	619.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-14700k-20-cores-28-hilos-8p12e-base-3-4ghz-turbo-5-4ghz-cache-33mb-graficos-intel-lga1700-14th-gen/
540	156	6	20260630	6	115.9900	USD	1.000000	115.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-180/
541	157	6	20260630	6	514.9900	USD	1.000000	514.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-138/
542	158	6	20260630	6	567.9900	USD	1.000000	567.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-137/
543	159	6	20260630	6	369.9900	USD	1.000000	369.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-7-265kf-base-3-9-ghz-30mb-lga1851-20-cores-8p12e-250w/
544	160	6	20260630	6	272.9900	USD	1.000000	272.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-5-225-20mb-4-9ghz-lga1851-10-cores-65w-intel-graphics/
545	161	6	20260630	6	886.9900	USD	1.000000	886.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-9-9950x-4-3ghz-turbo-5-7ghz-16-cores-32-hilos-am5-170w/
546	162	6	20260630	6	490.9900	USD	1.000000	490.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-9700x-amd-am5-zen-5-65w-8-cores-16-thread/
547	138	6	20260630	6	353.9900	USD	1.000000	353.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-8700g-4-2ghz-base-8-cores-16-hilos-am5-65w-with-radeon-graphics/
548	88	6	20260630	6	599.9900	USD	1.000000	599.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-7800x3d-8-cores-base-4-2ghz-am5-cache-8mb/
549	87	6	20260630	6	434.9900	USD	1.000000	434.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-7700-3-8ghz-base-8-cores-16-hilos-8mb-am5-65w-100000592box/
550	86	6	20260630	6	220.9900	USD	1.000000	220.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-8400f-6-cores-4-7-ghz-turbo-65w-am5-sin-graficos/
551	30	6	20260630	6	151.9900	USD	1.000000	151.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-3-5300g-am4-16mb-64w-8-thread/
552	31	6	20260630	6	748.9900	USD	1.000000	748.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-9850x3d-4-7ghz-8-cores-16-hilos-96mb-am5-120w/
553	32	6	20260630	6	204.9900	USD	1.000000	204.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-8500g-base-3-5ghz-65w-am5-graficos-amd-radeon-740m-100-100000931box/
554	33	6	20260630	6	300.9900	USD	1.000000	300.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-5700x-3-4ghz-4-6ghz-8-core-16-threads/
555	34	6	20260630	6	179.9900	USD	1.000000	179.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i3-14100f-3-5-ghz-14th-lga1700-4-cores/
556	35	6	20260630	6	248.9900	USD	1.000000	248.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-8600g-4-3ghz-base-6-cores-12-hilos-am5-65w-with-radeon-graphics/
557	36	6	20260630	6	216.9900	USD	1.000000	216.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-5600gt-3-6ghz-turbo-4-6ghz-am4-6-core-12-threads-graficos-radeon-vega-integrados/
558	37	6	20260630	6	486.9900	USD	1.000000	486.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-12700/
559	38	6	20260630	6	151.9900	USD	1.000000	151.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-5500/
560	39	6	20260630	6	115.9900	USD	1.000000	115.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-4790k-4ghz-turbo-4-4ghz-lga1150-h/
561	632	6	20260630	6	143.9900	USD	1.000000	143.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-hpe-dl380-gen9-intel-xeon-e5-2640v3-kit-719049-b/
562	40	6	20260630	6	288.9900	USD	1.000000	288.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-10600kf-4-1ghz-12mb-cache-lga-1200/
563	41	6	20260630	6	280.9900	USD	1.000000	280.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-5700g-3-8ghz-turbo-4-6ghz-am4-8-core-16-threads-graficos-radeon-vega-integrados/
564	633	6	20260630	6	19999.0000	USD	1.000000	19999.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ia-workstation-9960x-dual-rtx-5090-128gb/
565	42	6	20260630	6	627.9900	USD	1.000000	627.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i9-14900k-24-cores-32-hilos-8p16e-base-3-2ghz-turbo-6ghz-cache-36mb-lga1700-14th-gen/
566	43	6	20260630	6	752.9900	USD	1.000000	752.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-182/
567	44	6	20260630	6	853.9900	USD	1.000000	853.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-9-285k-24-cores-36mb-lga1851-graphics/
568	45	6	20260630	6	873.9900	USD	1.000000	873.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-9-285-24-cores-36mb-lga1851/
569	46	6	20260630	6	450.9900	USD	1.000000	450.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-7-265k-30mb-lga1851-20-cores-8p12e-graphics/
570	47	6	20260630	6	466.9900	USD	1.000000	466.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-5-245k-base-4-2ghz-26mb-159w-lga1851/
571	48	6	20260630	6	276.9900	USD	1.000000	276.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-ultra-5-225f-20mb-4-9ghz-lga1851-10-cores-65w-no-graphics/
572	49	6	20260630	6	688.9900	USD	1.000000	688.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-9800x3d-8-nucleos-16-hilos-4-7ghz-base-5-2ghz-turbo-am5-ddr5/
573	50	6	20260630	6	325.9900	USD	1.000000	325.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-7-8700f-turbo-5-00-ghz-8-cores-16-hilos-am5-65w-sin-graficos-incluye-cooler/
574	51	6	20260630	6	333.9900	USD	1.000000	333.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-9600x-am5-6-cores-12-thread-38mb-65w/
575	32	6	20260630	6	179.9900	USD	1.000000	179.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-8500g-base-3-5ghz-65w-am5-graficos-amd-radeon-740m-tray/
576	29	6	20260630	6	216.9900	USD	1.000000	216.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-5600xt-3-7-ghz-base-hasta-4-7ghz-65w-am4/
577	27	6	20260630	6	1370.9900	USD	1.000000	1370.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-9-9950x3d2-dual-edition-16-cores-32-hilos-am5-graficos-integrados/
578	2	6	20260630	6	999.9900	USD	1.000000	999.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-9-9950x3d-4-3ghz-turbo-5-7ghz-16-cores-32-hilos-am5-170w/
579	26	6	20260630	6	769.9900	USD	1.000000	769.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-9-9900x3d-4-4ghz-12-cores-24hilos-128mb-l3-cache-120w/
580	3	6	20260630	6	317.9900	USD	1.000000	317.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-9600-am5-6-cores-12-thread-turbo-5-2ghz-65w/
581	4	6	20260630	6	244.9900	USD	1.000000	244.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-5-5500x3d-3-0ghz-base-6-cores-12hilos-96mb-l3-cache-105w/
582	5	6	20260630	6	365.9900	USD	1.000000	365.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-9700f-3ghz-12mb-cache-lga1151/
583	6	6	20260630	6	494.9900	USD	1.000000	494.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-14700kf-20-cores-28-hilos-8p12e-base-3-4ghz-turbo-5-4ghz-cache-33mb-lga1700-14th-gen-no-graphics/
584	7	6	20260630	6	575.9900	USD	1.000000	575.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-10700k/
585	8	6	20260630	6	462.9900	USD	1.000000	462.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-13600kf-14-cores-20-hilos-6p8e-base-3-5ghz-turbo-5-1ghz-cache-24mb-lga1700-13th-gen-no-graphics/
586	9	6	20260630	6	151.9900	USD	1.000000	151.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-9750h-srf6u-para-laptop/
587	10	6	20260630	6	535.9900	USD	1.000000	535.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-13700f-13th-lga-1700-2-10ghz-hasta-5-20ghz-24m-65w-16-cores-bx8071513700f/
588	11	6	20260630	6	583.9900	USD	1.000000	583.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i7-13700-13th-lga-1700-2-10ghz-hasta-5-20ghz-30m-8-cores-16-nucleos/
589	12	6	20260630	6	309.9900	USD	1.000000	309.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-13400f-2-50ghz-base-65w-10-nucleos-bx8071513400f/
590	13	6	20260630	6	284.9900	USD	1.000000	284.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-13400-4-6ghz-20mb-lga1700-13th-gen/
591	14	6	20260630	6	204.9900	USD	1.000000	204.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i5-12400-4-4ghz-18mb-lga1700-12th-gen-tray-sin-caja/
592	15	6	20260630	6	175.9900	USD	1.000000	175.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i3-14100-3-5ghz-14th-lga1700-4-cores/
593	16	6	20260630	6	220.9900	USD	1.000000	220.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-intel-core-i3-13100-3-40ghz-13th-lga1700-4-cores-12mb-cache/
594	17	6	20260630	6	543.9900	USD	1.000000	543.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/procesador-amd-ryzen-9-7900x-4-7ghz-base-12-cores-24-hilos-am5-170w/
595	18	6	20260630	6	473.9900	USD	1.000000	473.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-5050-8gb-gddr6-oc-edition-windforce-2x-hdmi-dp-gv-n5050wf2ocv2-8gdg10/
596	19	6	20260630	6	366.9900	USD	1.000000	366.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gigabyte-gv-r76gaming-oc-8gd-g11/
597	20	6	20260630	6	553.9900	USD	1.000000	553.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gigabyte-gv-n5060wf2maxoc/
598	21	6	20260630	6	513.9900	USD	1.000000	513.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-amd-radeon-rx-7600-xt-16gb-gddr6-gaming-oc-windforce-raytracing-3-fans-hdmi-dp-gv-r76xtgaming-oc-16gd/
599	22	6	20260630	6	776.9900	USD	1.000000	776.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-amd-radeon-rx-9060-xt-16gb-gddr6-gaming-oc-windforce-3-fans-hdmi-dp-gv-r9060xtgaming-oc-16gd/
600	23	6	20260630	6	320.9900	USD	1.000000	320.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-msi-ventus-2x-rtx-3050-6gb-gddr6-oc-hdmi-dp-pcie-4-0-ray-tracing-dlss-912-v812-060/
601	24	6	20260630	6	519.9900	USD	1.000000	519.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-msi-geforce-rtx-5060-8g-ventus-3x-oc-edition-8gb-gddr7-hdmi-2-1b-dp-v2-1b-912-v537-036/
602	25	6	20260630	6	1499.9900	USD	1.000000	1499.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-5070ti-gaming-oc-16gb-gddr7-dp-2-1b-hdmi-2-1b-black-gv-n507tgaming-oc-16gd/
603	52	6	20260630	6	427.9900	USD	1.000000	427.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-aorus-extreme-amd-radeon-rx-6900xt-16gb-gddr6-4k-uhd-pci-e-4-0-waterblock-dp-1-4-with-dsc-hdmi-2-1-vrr-aorus-robot-xtreme-gv-r69xtaorusx-wb-16gd/
604	53	6	20260630	6	997.9900	USD	1.000000	997.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-prime-geforce-rtx-5070-12gb-gddr7-oc-edition-hdmi-2-1b-dp-2-1b-pci-e-5-0-black-prime-rtx5070-o12g/
605	636	6	20260630	6	63.9900	USD	1.000000	63.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-geforce-gt710-2gb-gddr5-hdmi-d-sub-dvi-d-gt710-sl-2gd5-brk-evo/
606	53	6	20260630	6	981.9900	USD	1.000000	981.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-5070-12gb-gddr7-oc-edition-hdmi-dp-black-dual-rtx5070-o12g/
607	18	6	20260630	6	443.9900	USD	1.000000	443.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-5050-8gb-gddr6-oc-edition-hdmi-dp-black-dual-rtx5050-o8g/
608	23	6	20260630	6	311.9900	USD	1.000000	311.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-3050-6gb-gddr6-oc-edition-dp-hdmi-dvi-d-dual-rtx3050-o6g/
609	20	6	20260630	6	550.9900	USD	1.000000	550.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-5060-eagle-max-oc-8gb-gddr7-oc-edition-windforce-dp-2-1b-hdmi-2-1b-black-gv-n5060eaglemax-oc-8gd/
610	74	6	20260630	6	853.9900	USD	1.000000	853.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-5060ti-16gb-gddr7-oc-edition-pcie-5-0-hdmi-dp-dual-rtx5060ti-o16g-evo/
611	74	6	20260630	6	730.9900	USD	1.000000	730.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-5060ti-16gb-gddr7-oc-edition-pcie-5-0-hdmi-dp-dual-rtx5060ti-o16g/
612	75	6	20260630	6	556.9900	USD	1.000000	556.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-5060-8gb-gddr7-oc-edition-dp-hdmi-dual-rtx5060-o8g/
613	76	6	20260630	6	4518.9900	USD	1.000000	4518.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/asus-rog-astral-rtx5090-o32g-gaming/
614	23	6	20260630	6	336.9900	USD	1.000000	336.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-3050-6gb-gddr6-oc-edition-windforce-hdmi-dp-gv-n3050wf2oc-6gd/
615	77	6	20260630	6	280.9900	USD	1.000000	280.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-phoenix-geforce-gtx-1630-4gb-gddr6-auto-extreme-hdmi-dp-dvi-d-ph-gtx1630-4g/
616	639	6	20260630	6	88.9900	USD	1.000000	88.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-gt-710-2gb-gv-n710d3-2gl-rev2-0/
617	640	6	20260630	6	727.9900	USD	1.000000	727.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-capturadora-de-video-blackmagic-design-decklink-duo-2-4ch-sdi-tarjeta-de-reproduccion-y-captura-bmd-bdlkduo2/
618	73	6	20260630	6	19999.0000	USD	1.000000	19999.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ia-workstation-9960x-dual-rtx-5090-128gb/
619	78	6	20260630	6	2166.9900	USD	1.000000	2166.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/msi-geforce-rtx-5080-16g-inspire-3x/
620	73	6	20260630	6	3503.9900	USD	1.000000	3503.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gigabyte-gv-n5090wf3oc-32gd/
621	642	6	20260630	6	140.9900	USD	1.000000	140.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gpu-gigabyte-geforce-gt-1030/
622	672	6	20260630	6	94.9900	USD	1.000000	94.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gpu-asus-geforce-gt-710/
623	75	6	20260630	6	486.9900	USD	1.000000	486.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-msi-shadow-2x-geforce-rtx-5060-8gb-gddr7-oc-edition-gddr7-hdmi-dp-black-912-v537-038/
624	80	6	20260630	6	838.9900	USD	1.000000	838.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-msi-geforce-rtx-5060ti-16g-ventus-2x-oc-plus-16gb-gddr7-dp-hdmi-2-fan-hdmi-dp-black-912-v537-017/
625	81	6	20260630	6	2117.9900	USD	1.000000	2117.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-5080-gaming-oc-16gb-gddr7-hdmi-2-1b-dp-1-4b-gv-n5080gaming-oc-16gd/
626	82	6	20260630	6	850.9900	USD	1.000000	850.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-5060ti-eagle-max-oc-16gb-gddr7-oc-edition-dp-2-1b-hdmi-2-1b-black-gv-n5060tieaglemax-oc-16gd/
627	59	6	20260630	6	478.9900	USD	1.000000	478.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-4060-8gb-gddr6-windforce-oc-edition-hdmi-2-1a-dp-1-4a-gv-n4060wf2oc-8gd/
628	83	6	20260630	6	1404.9900	USD	1.000000	1404.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-geforce-rtx-4070-ti-super-btf-white-edition-16gb-gddr6x-hdmi-dp-tuf-rtx4070s-o16g-bft-white/
629	84	6	20260630	6	660.9900	USD	1.000000	660.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-proart-geforce-rtx-4060ti-16gb-gddr6-advanced-edtion-hdmi-2-1a-dp-1-4a-black-proart-rtx4060ti-a-16g/
630	58	6	20260630	6	917.9900	USD	1.000000	917.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-4070-super-12gb-gddr6x-oc-edition-hdmi-dp-dual-rtx4070s-o12g/
631	85	6	20260630	6	1404.9900	USD	1.000000	1404.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-prime-rtx-5070-ti-16gb-gddr7-prime-rtx5070ti-o16g/
632	615	6	20260630	6	2999.9900	USD	1.000000	2999.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-profesional-asus-turbo-amd-radeon-ai-pro-r9700-32gb-gddr6-turbo-ai-pro-r9700-32g/
633	20	6	20260630	6	525.9900	USD	1.000000	525.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-aorus-elite-geforce-rtx-5060-8gb-gddr7-3-ventiladores-black-gv-n5060aorus-e-8gd/
634	75	6	20260630	6	513.9900	USD	1.000000	513.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-prime-geforce-rtx-5060-8gb-gddr7-oc-edition-hdmi-dp-prime-rtx5060-o8g/
635	79	6	20260630	6	3478.9900	USD	1.000000	3478.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-gaming-rtx5090-32gb-gddr7-pcie-5-0-dp-hdmi-black-tuf-rtx5090-32g-gaming/
636	72	6	20260630	6	614.9900	USD	1.000000	614.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-4060-ti-oc-edition-8gb-gddr6-hdmi-dp-dual-rtx4060ti-o8g/
637	60	6	20260630	6	305.9900	USD	1.000000	305.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-msi-geforce-rtx-3050-8gb-gddr6-ventus-2x-xs-dp-hdmi-dvi-d-912-v809-4266/
638	71	6	20260630	6	2380.9900	USD	1.000000	2380.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-rtx-4090-gaming-oc-edition-24gb-gddr6x-dp-1-4-hdmi-2-1-pci-e-4-0-gv-n4090gaming-oc-24gd/
639	54	6	20260630	6	2068.9900	USD	1.000000	2068.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-aorus-master-geforce-rtx-4080-16gb-gddr6x-rev-1-0-oc-edition-windforce-dlss-ray-tracing-reflex-studio-dp-hdmi-gv-n4080aorus-m-16gd/
640	55	6	20260630	6	1199.9900	USD	1.000000	1199.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-gaming-geforce-rtx-4070ti-12gb-gddr6x-hdmi-2-1a-dp-1-4a-argb-black-tuf-rtx4070ti-12g-gaming/
641	56	6	20260630	6	1104.9900	USD	1.000000	1104.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-gaming-geforce-rtx-4070-ti-12gb-gddr6x-oc-edition-tuf-rtx4070ti-o12g-gaming/
642	57	6	20260630	6	3054.9900	USD	1.000000	3054.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-rog-strix-geforce-rtx-4090-24gb-gddr6x-oc-edition-rog-strix-rtx4090-o24g-gaming/
643	58	6	20260630	6	929.9900	USD	1.000000	929.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-4070-super-evo-oc-12gb-gddr6x-dp-hdmi-black-90yv0kc0-m0na00/
644	59	6	20260630	6	498.9900	USD	1.000000	498.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-4060-8gb-gddr6-oc-edition-gpu-tweak-iii-dlss-3-hdmi-dp-dual-rtx4060-o8g-white/
645	59	6	20260630	6	455.9900	USD	1.000000	455.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-4060-8gb-gddr6-oc-edition-gpu-tweak-iii-dlss-3-hdmi-dp-dual-rtx4060-o8g-evo/
646	60	6	20260630	6	476.9900	USD	1.000000	476.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-eagle-geforce-rtx-3050-8gb-oc-hdmi-2-1-dp-1-4a-gv-n3050eagle-oc-8gd/
647	54	6	20260630	6	2166.9900	USD	1.000000	2166.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-gaming-geforce-rtx-4080-16gb-gddr6x-oc-edition-dlss-reflex-ray-tracing-dp-1-4a-hdmi-2-1a-tuf-rtx4080-o16g-gaming/
648	54	6	20260630	6	2396.9900	USD	1.000000	2396.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-rog-strix-gaming-geforce-rtx-4080-16gb-gddr6x-oc-edition-dlss-ray-tracing-reflex-dp-1-4a-hdmi-2-1a-rog-strix-rtx4080-o16g-gaming/
649	673	6	20260630	6	121.9900	USD	1.000000	121.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-geforce-gt730-2gb-gddr5-auto-extreme-0db-silent-4-hdmi-gt730-4h-sl-2gd5/
650	675	6	20260630	6	222.9900	USD	1.000000	222.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-afox-rx-550-4gb-gddr5-hdmi-dp-dvi-d/
651	61	6	20260630	6	476.9900	USD	1.000000	476.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-windforce-rtx-3050-oc-8gb-gv-n3050gaming-oc-8gd/
652	61	6	20260630	6	727.9900	USD	1.000000	727.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-rog-strix-rtx-3050-oc-8gb-rog-strix-rtx3050-o8g-gaming/
653	61	6	20260630	6	645.9900	USD	1.000000	645.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-zotac-geforce-rtx-3050-8gb-gddr6-twin-edge-dp-1-4a-hdmi-2-1-zt-a30500e-10m/
654	707	6	20260630	6	45.9900	USD	1.000000	45.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-biostar-g210-1gb-ddr3-hdmi-dvi-vga-vn2103nhg6-sbarl-bs2/
655	60	6	20260630	6	449.9900	USD	1.000000	449.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-geforce-rtx-3050-dual-gddr6-oc-edition-dp-hdmi-dual-rtx3050-o8g/
656	708	6	20260630	6	100.9900	USD	1.000000	100.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-gigabyte-geforce-gt-1030-2gb-ddr4-low-profile-gv-n1030d4-2gl/
657	62	6	20260630	6	721.9900	USD	1.000000	721.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-dual-radeon-rx-580-8gb-oc-edition-dual-rx580-o8g/
658	709	6	20260630	6	39.9900	USD	1.000000	39.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/gpu-msi-geforce-n210/
659	63	6	20260630	6	1450.9900	USD	1.000000	1450.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/tarjeta-de-video-asus-tuf-rx-6700xt-12gb-oc-edition-gddr6-90yv0g80-m0aa00/
660	64	6	20260630	6	225.9900	USD	1.000000	225.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-8gb-ddr5-5600mt-s-cl40-black-kf556c40bb-8/
661	65	6	20260630	6	156.9900	USD	1.000000	156.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-corsair-vengeance-lpx-8gb-a-3200mhz/
662	66	6	20260630	6	475.9900	USD	1.000000	475.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-193/
663	67	6	20260630	6	164.9900	USD	1.000000	164.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-ddr4-kingston-fury-8gb-3200mhz-kvr32n22s8-8-kvr32n22s6-8/
664	68	6	20260630	6	281.9900	USD	1.000000	281.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-ddr4-so-dimm-kingston-fury-impact-32gb-3200mhz-kf432s20ib-32/
665	69	6	20260630	6	47.9900	USD	1.000000	47.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-8gb-ddr3-1600mhz-dimm-valueram-kvr16n11-8/
666	70	6	20260630	6	318.9900	USD	1.000000	318.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-ddr5-5200mhz-cl40-kf552c40bb-16/
667	189	6	20260630	6	253.9900	USD	1.000000	253.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-rgb-ddr4-3600mhz-cl18-black-kf436c18bba-16/
668	28	6	20260630	6	326.9900	USD	1.000000	326.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-ddrr5-5600mhz-cl40-black-kf556c40bb-16/
669	65	6	20260630	6	269.9900	USD	1.000000	269.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-corsair-vengeance-rgb-rs-8gb-3200mhz-ddr4-cl16-black-cmg8gx4m1e3200c16/
670	67	6	20260630	6	156.9900	USD	1.000000	156.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-8gb-ddr4-3200mhz-cl16-black-kf432c16bb-8/
671	633	6	20260630	6	19999.0000	USD	1.000000	19999.0000	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ia-workstation-9960x-dual-rtx-5090-128gb/
672	311	6	20260630	6	463.9900	USD	1.000000	463.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-rgb-32gb-ddr5-5600mt-s-cl40-dimm-kf556c40bba-32/
673	312	6	20260630	6	306.9900	USD	1.000000	306.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-194/
674	313	6	20260630	6	51.9900	USD	1.000000	51.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-kingston-8gb-ddr3l-1600mhz-so-dimm-kvr16ls11-8/
675	314	6	20260630	6	72.9900	USD	1.000000	72.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-ddr4-kingston-fury-8gb-2666mhz/
676	292	6	20260630	6	152.9900	USD	1.000000	152.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-ddr4-kingston-fury-16gb-3200mhz-hx432c16fb4-16/
677	315	6	20260630	6	120.9900	USD	1.000000	120.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-ddr4-xpg-spectrix-d50-rgb-8gb-3000mhz-ax4u30008g16a-st50/
678	314	6	20260630	6	51.9900	USD	1.000000	51.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-ddr4-kingston-fury-beast-8gb-2666mhz-kf436c17bba-8/
679	316	6	20260630	6	76.9900	USD	1.000000	76.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-8gb-ddr4-3200mhz-so-dimm-cl22-kvr32s22s8-8/
680	69	6	20260630	6	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-8gb-ddr3-1600mhz-ecc-1-5v-para-servidor-kvr16r11d4-8hc/
681	317	6	20260630	6	128.9900	USD	1.000000	128.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-kingston-16gb-a-3200mhz-so-dimm/
682	123	6	20260630	6	132.9900	USD	1.000000	132.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-16gb-ddr4-3200mhz-dimm-cl22-kvr32n22d8-16/
683	318	6	20260630	6	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-16gb-ddr4-2666mhz-so-dimm-cl19-kvr26s19s8-16/
684	319	6	20260630	6	221.9900	USD	1.000000	221.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-corsair-vengeance-rgb-pro-16gb-a-3200mhz/
685	65	6	20260630	6	47.9900	USD	1.000000	47.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-corsair-vengeance-rgb-rs-8gb-3200mhz-ddr4-cl16-black-cmg8gx4m1e3200c16-2/
686	320	6	20260630	6	39.9900	USD	1.000000	39.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-impact-8gb-ddr4-3200mhz-so-dimm-cl20-kf432s20ib-8/
687	67	6	20260630	6	47.9900	USD	1.000000	47.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-8gb-ddr4-3200mhz-rgb-cl16-black-kf432c16bba-8/
688	292	6	20260630	6	76.9900	USD	1.000000	76.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-rgb-ddr4-3200mhz-cl16-black-kf432c16bba-16/
689	321	6	20260630	6	108.9900	USD	1.000000	108.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-ddr5-4800mhz-cl38-black-kf548c38bbk2-32/
690	321	6	20260630	6	261.9900	USD	1.000000	261.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-ddr5-4800mhz-cl38-black-kf548c38bb-16/
691	322	6	20260630	6	67.9900	USD	1.000000	67.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-corsair-vengeance-lpx-8gb-a-3600mhz/
692	310	6	20260630	6	116.9900	USD	1.000000	116.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-corsair-vengeance-lpx-16gb-a-3600mhz/
693	323	6	20260630	6	43.9900	USD	1.000000	43.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-corsair-vengeance-lpx-ddr4-8gb-3000mhz-cmk8gx4m1d3000c16/
694	309	6	20260630	6	148.9900	USD	1.000000	148.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-corsair-vengeance-lpx-ddr4-16gb-3000mhz-cmk16gx4m1b3000c15/
695	310	6	20260630	6	67.9900	USD	1.000000	67.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-corsair-vengeance-rgb-pro-16gb-a-3600mhz-2/
696	309	6	20260630	6	128.9900	USD	1.000000	128.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-corsair-vengeance-lpx-16gb-3000mhz-ddr4-cl16-black-cmk16gx4m1d3000c16/
697	308	6	20260630	6	43.9900	USD	1.000000	43.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-corsair-vengeance-4gb-2400mhz-so-dimm-c16-black-cmsx4gxm1a2400c16/
698	290	6	20260630	6	314.9900	USD	1.000000	314.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-corsair-vengeance-16gb-ddr5-4800mhz-cl40-black-cmk32gx5m2a4800c40/
699	291	6	20260630	6	63.9900	USD	1.000000	63.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-16gb-ddr4-2666mhz-dimm-valueram-kvr26n19d8-16/
700	292	6	20260630	6	72.9900	USD	1.000000	72.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-ddr4-3200mhz-cl16-black-kf432c16bb-16/
701	293	6	20260630	6	43.9900	USD	1.000000	43.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-8gb-ddr4-2666mhz-dimm-valueram-kvr26n19s8-8/
702	294	6	20260630	6	108.9900	USD	1.000000	108.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-hyperx-fury-8gb-ddr4-3733mhz-cl19-hx437c19fb3a-8/
703	295	6	20260630	6	96.9900	USD	1.000000	96.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/memoria-ram-hyperx-fury-rgb-8gb-ddr4-2666mhz-hx426c16fb3a-8/
704	296	6	20260630	6	47.9900	USD	1.000000	47.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-8gb-ddr4-3600mhz-cl17-black-kf436c17bb-8/
705	189	6	20260630	6	67.9900	USD	1.000000	67.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-beast-16gb-ddr4-3600mhz-cl18-black-kf436c18bb-16/
706	297	6	20260630	6	104.9900	USD	1.000000	104.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ssd-corsair-force-mp510-240gb-nvme-pcie/
707	298	6	20260630	6	92.9900	USD	1.000000	92.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ssd-adata-su630-480gb-2-5/
708	299	6	20260630	6	92.9900	USD	1.000000	92.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ssd-adata-su630-240gb-2-5/
709	300	6	20260630	6	35.9900	USD	1.000000	35.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-kingston-value-8gb-a-2666mhz-so-dimm/
710	301	6	20260630	6	148.9900	USD	1.000000	148.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hyperx-fury-16gb-a-2666mhz/
711	302	6	20260630	6	108.9900	USD	1.000000	108.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hyperx-predator-rgb-8gb-a-3000mhz/
712	303	6	20260630	6	96.9900	USD	1.000000	96.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-kingston-fury-predator-8gb-a-3200mhz/
713	304	6	20260630	6	152.9900	USD	1.000000	152.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hyperx-impact-16gb-a-2666mhz-so-dimm/
714	305	6	20260630	6	209.9900	USD	1.000000	209.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hyperx-fury-rgb-16gb-a-3000mhz/
715	722	6	20260630	6	112.9900	USD	1.000000	112.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hyperx-fury-rgb-a-3000mhz/
716	305	6	20260630	6	152.9900	USD	1.000000	152.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hyperx-fury-16gb-a-3000mhz/
717	306	6	20260630	6	112.9900	USD	1.000000	112.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hp-v8-8gb-a-3000mhz/
718	303	6	20260630	6	80.9900	USD	1.000000	80.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hp-v6-8gb-a-3200mhz/
719	306	6	20260630	6	72.9900	USD	1.000000	72.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-hp-v6-8gb-a-3000mhz-blue/
720	307	6	20260630	6	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/ram-ddr4-adata-xpg-spectix-d60g-rgb-8gb-a-3200mhz/
721	95	6	20260630	6	176.9900	USD	1.000000	176.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-ultragear-24g411a-b/
722	324	6	20260630	6	465.9900	USD	1.000000	465.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-rog-strix-xg27acmes/
723	289	6	20260630	6	281.9900	USD	1.000000	281.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-tuf-vg259qm5a/
724	132	6	20260630	6	316.9900	USD	1.000000	316.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs27qa/
725	723	6	20260630	6	53.9900	USD	1.000000	53.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-para-dos-monitores-kmm-510-con-regleta-integrada-y-puertos-usb/
726	724	6	20260630	6	109.9900	USD	1.000000	109.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-huanuo-2-brazos-vertical-para-monitores-de-13-a-32-hnhm2/
727	326	6	20260630	6	86.9900	USD	1.000000	86.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-acer-k202q-19-5/
728	349	6	20260630	6	78.9900	USD	1.000000	78.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-1916s-19-5-1600x900-5ms-75hz-hdmi-vga/
729	350	6	20260630	6	346.9900	USD	1.000000	346.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-msi-gaming-mag-275qf-27-wqhd-2560x1440-ips-180hz-0-5ms-gtg-hdmi-dp-black-9s6-3ce21m-014/
730	351	6	20260630	6	352.9900	USD	1.000000	352.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-29u511a-b-ultrawide-29-ips-2560x1080-hdmi-100hz-srgb-99-5ms-gtg/
731	726	6	20260630	6	72.9900	USD	1.000000	72.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-portatil-env-15-6-fhd-ips-ultrafino-usb-c-black/
732	352	6	20260630	6	191.9900	USD	1.000000	191.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2415s-24-gaming-plano-ips-fhd-120hz-1ms-dp-hdmi-vga/
733	353	6	20260630	6	310.9900	USD	1.000000	310.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-empresarial-asus-va279qgs-27-ips-fhd-1920x1080-120hz-1ms-hdmi-dp-vga-usb-black/
734	728	6	20260630	6	132.9900	USD	1.000000	132.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-portatil-acer-pm1-15-6-fhd-6ms-ultrafino-mini-hdmi-usb-c-black-pm161q/
735	354	6	20260630	6	396.9900	USD	1.000000	396.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-msi-mag-274qf-x24-27-wqhd-2560x1440-fast-ips-0-5ms-240hz-hdmi-dp-black-9s6-3ce41h-020/
736	729	6	20260630	6	342.9900	USD	1.000000	342.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-samsung-gaming-odyssey-g3-27-fhd-180hz-dp-hdmi-black/
737	94	6	20260630	6	259.9900	USD	1.000000	259.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-xiaomi-g24i-23-8-fhd-1920x1080-180hz-1ms-gtg-hdmi-dp-black-p24fca-rggl/
738	355	6	20260630	6	840.9900	USD	1.000000	840.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-mo27q28g-ga1-27-woled-2560x1440p-280hz-anti-reflection-0-03ms-gtg-hdr-true-black-500-hdmi-dp/
739	356	6	20260630	6	428.9900	USD	1.000000	428.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs32q-32-qhd-2560x1440-ss-ips-165hz-non-glare-ods-low-blue-light-hdmi-dp/
740	357	6	20260630	6	467.9900	USD	1.000000	467.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-m27q2-ice-sa1-27-qhd-2560x1440p-ss-ips-1ms-gtg-200hz-oc-210hz-hdr400-non-glare-hdmi-dp-white/
741	131	6	20260630	6	239.9900	USD	1.000000	239.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs25f2-25-24-5-fhd-1920x1080-200hz-non-glare-speaker-osd-low-blue-light-dci-p3-hdmi-dp/
742	102	6	20260630	6	269.9900	USD	1.000000	269.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs27fa-27-fhd-1920x1080-ss-ips-180hz-non-glare-ods-low-blue-light-hdmi-1dp/
743	358	6	20260630	6	965.9900	USD	1.000000	965.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-m28u-sa-28-superspeed-ips-4k-uhd-2ms-mprt-144hz-hdmi-2-1-dp-1-4-usb-c-black/
744	135	6	20260630	6	267.9900	USD	1.000000	267.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs25f2a/
745	359	6	20260630	6	1762.9900	USD	1.000000	1762.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-msi-mpg-491cqp-qd-oled-49/
746	731	6	20260630	6	170.9900	USD	1.000000	170.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-indurama-vortix-nova-27-fhd-ips-120hz-5ms-hdmidp-black-27mmnavn/
747	719	6	20260630	6	156.9900	USD	1.000000	156.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-indurama-vortix-nova-25/
748	114	6	20260630	6	235.9900	USD	1.000000	235.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-va249hg-eye-care-23-8-fhd-1920x1080-120hz-99-srgb-1ms-mprt-hdmi-vga-black/
749	360	6	20260630	6	368.9900	USD	1.000000	368.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-proart-pa248qfv-24-ips-wuxga-1920x1080-100hz-hdr-10-dp-hdmi-usb-black/
750	106	6	20260630	6	253.9900	USD	1.000000	253.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-va279hg/
751	97	6	20260630	6	94.9900	USD	1.000000	94.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-20u401a-b-19-5-1600x900-hdmi-vga/
752	705	6	20260630	6	136.9900	USD	1.000000	136.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-indurama-vortix-core-22/
753	361	6	20260630	6	566.9900	USD	1.000000	566.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-samsung-ls24a608ucn-24-wqhd-2560x1440-ultra-thin-5ms-75hz-hdmi-dp/
754	362	6	20260630	6	638.9900	USD	1.000000	638.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-proart-pa279crv-27-4k-uhd-3840x2160-99-dci-p3-99-adobe-rgb-dispalyhdr-400-dp-hdmi-type-c-usb-3-2/
755	704	6	20260630	6	497.9900	USD	1.000000	497.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gaming-zowie-xl2731k-27-fhd-165hz-dyac-320-nits-tn-hdmi2-0-dp-1-2-9h-lkclb-qbl/
756	703	6	20260630	6	44.9900	USD	1.000000	44.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-brazo-para-monitores-klip-xtreme-kpm-310/
757	676	6	20260630	6	43.9900	USD	1.000000	43.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-klip-xtreme-kmm-400-para-monitores-13-27/
758	677	6	20260630	6	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/soporte-klip-xtreme-kmm-301-para-monitor-y-laptop/
759	363	6	20260630	6	350.9900	USD	1.000000	350.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-22mn430h-b/
760	133	6	20260630	6	213.9900	USD	1.000000	213.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-ultragear-27g411a/
761	348	6	20260630	6	209.9900	USD	1.000000	209.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-zenscreen-mb166c/
762	347	6	20260630	6	620.9900	USD	1.000000	620.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-m27up-ice/
763	346	6	20260630	6	566.9900	USD	1.000000	566.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-msi-mag-346cq-34-uwqhd-3440x1440-va-1ms-mprt-curved-1500r-180hz-169-hdr-ready-hdmi-dp-black-9s6-3dd71m-004/
764	109	6	20260630	6	76.9900	USD	1.000000	76.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-xtratech-xtm19-19-5-hd-1600x900-entradas-hdmi-y-vga/
765	327	6	20260630	6	247.9900	USD	1.000000	247.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-samsung-gaming-essential-s3-s36gd-27-fhd-1920x1080-100hz-4ms-d-sub-hdmi-black-s27d366gan/
766	328	6	20260630	6	245.9900	USD	1.000000	245.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2787g-27-fhd-curvo-180hz-2ms-dp-hdmi/
767	329	6	20260630	6	354.9900	USD	1.000000	354.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gaming-msi-mag-275cqf-e18-27-wqhd-2k2560x1440-curvo-180hz-0-5ms-gtg-hdr-ready-hdmi-2-0b-dp-1-4a-black-9s6-3ce91h-004/
768	330	6	20260630	6	400.9900	USD	1.000000	400.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-ultragear-27gs65f-b-27-fhd-ips-180hz-1ms-hdr10-g-sync-freesync-black/
769	125	6	20260630	6	211.9900	USD	1.000000	211.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs24f14-24-ips-fhd-144hz-1ms/
770	685	6	20260630	6	394.9900	USD	1.000000	394.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-indurama-vortix-ultra-32/
771	331	6	20260630	6	227.9900	USD	1.000000	227.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-vp227he-21-45-fhd-75hz-non-glare-va-5ms-gtg-hdmi-v1-4-vga-black/
772	332	6	20260630	6	356.9900	USD	1.000000	356.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-tuf-gaming-vg279q1a-27-fhd-1920x1080p-panel-ips-non-glare-1ms-mprt-165hz-freesync-premium-dp-1-2-hdmi-v1-4/
773	333	6	20260630	6	334.9900	USD	1.000000	334.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-256/
774	107	6	20260630	6	227.9900	USD	1.000000	227.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-168/
775	334	6	20260630	6	443.9900	USD	1.000000	443.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-167/
776	335	6	20260630	6	840.9900	USD	1.000000	840.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-90/
777	336	6	20260630	6	574.9900	USD	1.000000	574.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-88/
778	337	6	20260630	6	846.9900	USD	1.000000	846.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-87/
779	338	6	20260630	6	441.9900	USD	1.000000	441.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-84/
780	339	6	20260630	6	903.9900	USD	1.000000	903.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-pa329cvr/
781	340	6	20260630	6	1508.9900	USD	1.000000	1508.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-82/
782	687	6	20260630	6	336.9900	USD	1.000000	336.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-touch-sat-1053fph-15-1024-x-768px-multi-touch-3-puntos-hdmi-vga-usb/
783	341	6	20260630	6	199.9900	USD	1.000000	199.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2123s-21-45-fhd-ips-1ms-100hz-hdmi-vga-black/
784	110	6	20260630	6	320.9900	USD	1.000000	320.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gaming-msi-g2712f-27-fhd-ips-180-hz-1ms-300-nits-dp-hdmi-black/
785	342	6	20260630	6	382.9900	USD	1.000000	382.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-29wq500-b-29-ultrawide-219-full-hd-2560x1080-ips-1ms-hdmidp/
786	343	6	20260630	6	602.9900	USD	1.000000	602.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-tuf-vg289q/
787	344	6	20260630	6	499.9900	USD	1.000000	499.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-proart-pa247cv-23-8-full-hd-ips-100-srgb-75hz-5ms-dp-hdmi-usb-c-black-90lm03y1-b013b0/
788	345	6	20260630	6	316.9900	USD	1.000000	316.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2766g-27-fhd-curvo-r1500-va-180hz-1ms-hdmi-vga-black/
789	325	6	20260630	6	257.9900	USD	1.000000	257.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2711s-27-fhd-100hz-1ms-ips-hdmi/
790	288	6	20260630	6	217.9900	USD	1.000000	217.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2411s-gaming-24-1920x1080-1ms-200-nits-100hz-hdmi-vga/
791	287	6	20260630	6	215.9900	USD	1.000000	215.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2401s-23-8-curvo-r3000-va-fhd-5ms-100hz-hdmi-vga-black/
792	286	6	20260630	6	207.9900	USD	1.000000	207.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-2124s-21-45-fhd-ips-100hz-5ms-plano-hdmi-vga-black/
793	215	6	20260630	6	69.9900	USD	1.000000	69.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-teros-te-1914s-19-5-1600x900-5ms-220-nits-hdmi-vga/
794	216	6	20260630	6	590.9900	USD	1.000000	590.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-samsung-ur55-28-uhd-ips-hdr10-4ms-60hz-hdmi-dp-lu28r550uqnxza/
795	217	6	20260630	6	538.9900	USD	1.000000	538.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-msi-optix-g274rw-27-fhd-ips-170hz-1ms-mprt-hdmi-dp-white/
796	218	6	20260630	6	459.9900	USD	1.000000	459.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-ultragear-27gr75q-b-27-qhd-2560x1440-165hz-ips-1ms-gtg-srgb-99-anti-glare-hdr10-hdmi-2-2-dp-1-4-black/
797	219	6	20260630	6	324.9900	USD	1.000000	324.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-32mn600p-b-31-5-ips-full-hd-amd-freesync/
798	220	6	20260630	6	437.9900	USD	1.000000	437.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-lg-27qn600-b-27-ips-2k-qhd-2560x1440-srgb-99-75hz-5ms-hdr-freesync-hdmi-dp/
799	221	6	20260630	6	646.9900	USD	1.000000	646.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-m32qc-sa-31-5-qhd-165hz-hdr400-1ms-mprt-hdmi-94-dci-p3-123-srgb-2-0-dp-1-2/
800	222	6	20260630	6	727.9900	USD	1.000000	727.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs34wqc-34-va-1500r-wqhd-3440x1440-non-glare-120-srgb-1ms-mprt-135hz-hdr-hdmi-2-0-dp-1-4-black/
801	223	6	20260630	6	469.9900	USD	1.000000	469.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-gigabyte-gs27q-27-ss-ips-2k-qhd-2560x1440-non-glare-100-srgb-1ms-mprt-170hz-hdr-hdmi-2-0-dp-1-4-black/
802	224	6	20260630	6	126.9900	USD	1.000000	126.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-env-1esm1695-21-5-full-hd-1920x1080-va-230-nits-75hz-6-5ms-vga-hdmi-vesa/
803	225	6	20260630	6	158.9900	USD	1.000000	158.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-env-1eenv1711-24-fhd-panel-va-300-nits-16ms-vga-hdmi/
804	226	6	20260630	6	1310.9900	USD	1.000000	1310.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-corsair-xeneon-32uhd144-a-32-uhd-ips-144hz-hdr600-non-glare-100-adobe-rgb-1ms-amd-freesync-premium-black-cm-9020006-na/
805	227	6	20260630	6	536.9900	USD	1.000000	536.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-vy27uq-27-4k-3840-x-2160-non-glare-ips-dhr-10-adaptive-sync-eye-care-dp-hdmi-black/
806	228	6	20260630	6	257.9900	USD	1.000000	257.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-va27ehf-27-full-hd-ips-100hz-1ms-vrr-adaptive-sync-hdmiv1-4/
807	229	6	20260630	6	241.9900	USD	1.000000	241.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-va24ehf-24-23-8-full-hd-ips-100hz-1ms-vrr-adaptive-sync-hdmiv1-4/
808	230	6	20260630	6	338.9900	USD	1.000000	338.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/monitor-asus-tuf-vg248q1b-24-fhd-led-panel-tn-165hz-0-5ms-gtg-freesync-premium-dp-1-2-hdmi-v1-4/
809	231	6	20260630	6	92.9900	USD	1.000000	92.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-msi-forge-gk600-tkl-white-violet/
810	702	6	20260630	6	471.9900	USD	1.000000	471.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-corsair-galleon-100-sd-integrated-stream-deck-lcd-full-color-teclas-pbt-switch-mlx-black-ch-912a311-na/
811	674	6	20260630	6	174.9900	USD	1.000000	174.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-razer-blackwidow-v4-x-pokemon-edition-razer-chroma-rgb-abs-switch-lineal-es-grenn-detalles-tematicos-pokemon-rz03-04704200-r3m1/
812	232	6	20260630	6	144.9900	USD	1.000000	144.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-logitech-g515-tkl-tactical-teclas-pbt-tactile-lightsync-rgb-grafite-920-012868/
813	233	6	20260630	6	47.9900	USD	1.000000	47.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-241/
814	612	6	20260630	6	84.9900	USD	1.000000	84.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-239/
815	234	6	20260630	6	86.9900	USD	1.000000	86.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-redragon-yama-k550rgb-1-sp-rgb-chroma-100-anti-ghosting-black/
816	235	6	20260630	6	7.9900	USD	1.000000	7.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-genius-kb-117-alambrico-usb-black/
817	236	6	20260630	6	90.9900	USD	1.000000	90.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-corsair-gaming-k70-core-rgb-mecanico-mlx-red-100-anit-ghosting-black-ch-910971e-sp/
818	237	6	20260630	6	69.9900	USD	1.000000	69.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-meetion-mt-mk20-lina-inverse-mecanico-switch-blue-anti-ghosting-black-red/
819	214	6	20260630	6	114.9900	USD	1.000000	114.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-teclado-y-mouse-logitech-mk850-wireless-920-008219-920008659/
820	213	6	20260630	6	11.9900	USD	1.000000	11.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-teclado-y-mouse-genius-slimstar-c126-wired-black/
821	559	6	20260630	6	96.9900	USD	1.000000	96.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-dyi-glorious-gmmk-tkl-rgb-sin-switch-sin-keycaps-black/
822	560	6	20260630	6	51.9900	USD	1.000000	51.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-inalambrico-trust-gxt-sento-black-20062/
823	190	6	20260630	6	11.9900	USD	1.000000	11.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-teclado-y-mouse-genius-km-160-usb-negro/
824	212	6	20260630	6	15.9900	USD	1.000000	15.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-logitech-k120/
825	191	6	20260630	6	29.9900	USD	1.000000	29.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/kit-logitech-mk200-teclado-y-mouse-usb-920-002716/
826	182	6	20260630	6	25.9900	USD	1.000000	25.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/kit-de-teclado-y-mouse-logitech-mk120-alambrico-usb-negro-920-004428/
827	192	6	20260630	6	57.9900	USD	1.000000	57.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-inalambrico-logitech-slim-mk320-teclado-y-mouse/
828	193	6	20260630	6	27.9900	USD	1.000000	27.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-marvo-cm370pm-pink-4-en-1-tecladomousemousepadaudifono/
829	554	6	20260630	6	154.9900	USD	1.000000	154.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-razer-blackwidow-v4-tenkeyless-hyperspeed-wireless-usb-c-razer-chroma-rgb-abs-doubleshot-swtich-tactile-and-quiet-black-rz03-05480600-r311/
830	549	6	20260630	6	160.9900	USD	1.000000	160.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-asus-rog-strix-scope-ii-96-wireless/
831	194	6	20260630	6	39.9900	USD	1.000000	39.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-logitech-pebble-keys-2-k380s-bluetooth-silencioso-espanol-white-920-011784/
832	195	6	20260630	6	253.9900	USD	1.000000	253.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-logitech-g915-tkl-bluetooth-mecanico-lightspeed-rgb-920-009495/
833	196	6	20260630	6	215.9900	USD	1.000000	215.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-logitech-g815-mecanico-lightsync-rgb-gl-tactile-g-keys-white-920-011354/
834	197	6	20260630	6	39.9900	USD	1.000000	39.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-249/
835	546	6	20260630	6	166.9900	USD	1.000000	166.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-244/
836	548	6	20260630	6	132.9900	USD	1.000000	132.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-243/
837	544	6	20260630	6	140.9900	USD	1.000000	140.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-242/
838	176	6	20260630	6	29.9900	USD	1.000000	29.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-240/
839	588	6	20260630	6	235.9900	USD	1.000000	235.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-238/
840	198	6	20260630	6	96.9900	USD	1.000000	96.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-232/
841	199	6	20260630	6	35.9900	USD	1.000000	35.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-67/
842	200	6	20260630	6	11.9900	USD	1.000000	11.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-53/
843	593	6	20260630	6	11.9900	USD	1.000000	11.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-52/
844	201	6	20260630	6	11.9900	USD	1.000000	11.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-49/
845	202	6	20260630	6	90.9900	USD	1.000000	90.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-redragon-eisa-k686-wireless-bluetooth-usb-c-keycaps-premium-pbt-rgb-chroma-100-anti-ghosting-lineal-red-black-white-red-k686ak-rgb-pro/
846	203	6	20260630	6	88.9900	USD	1.000000	88.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-k621-rgb-sp-wireless-tkl-bluetooth-5-0-rgb-chroma-100-anti-ghosting-black/
847	204	6	20260630	6	37.9900	USD	1.000000	37.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-gaming-marvo-kg962-white-r-60-switch-red-anti-ghosting-cable-type-c-desmontable-white/
848	205	6	20260630	6	7.9900	USD	1.000000	7.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-genius-smart-kb-100-usb-espanol/
849	206	6	20260630	6	7.9900	USD	1.000000	7.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-genius-kb-116-alambrico-usb-black/
850	207	6	20260630	6	33.9900	USD	1.000000	33.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-redragon-shiva-k512rgb-sp-membrana-rgb-reposamunecas-magnetico-black/
851	208	6	20260630	6	49.9900	USD	1.000000	49.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-redragon-kumara-k552w-rgb-sps-red-mecanico-tkl-us-dust-proof-red-white/
852	209	6	20260630	6	74.9900	USD	1.000000	74.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-primus-gaming-ballista90t-edition-star-wars-mandalorian-mechanical-anti-ghosting-linear-y-silent-switch-red-pks-s092ml-s/
853	607	6	20260630	6	277.9900	USD	1.000000	277.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-perzonalizable-corsair-elgato-stream-deck-8-teclas-lcd-usb-c-black-10gbd9901/
854	608	6	20260630	6	47.9900	USD	1.000000	47.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-meetion-mt-director-wireless-ergonomico-black/
855	210	6	20260630	6	78.9900	USD	1.000000	78.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-redragon-horus-tkl-k621w-rgb-sp-wireless-bluetooth-dongle-rf-usb/
856	211	6	20260630	6	67.9900	USD	1.000000	67.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-redragon-deimos-k599-krs-tkl-70-wireless-wired-rgb-chroma-switch-linear-45-gr-black/
857	611	6	20260630	6	76.9900	USD	1.000000	76.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-hyperx-origins-60-rgb-switch-linear-100-anti-ghosting-compatible-ps5-ps4-xbox-series-xs-xbox-one-black-4p5n4aa/
858	601	6	20260630	6	156.9900	USD	1.000000	156.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-hyperx-alloy-elite-2-rgb-switch-rojo-100-anti-ghost-compatible-ps5-ps4-xbox-series-xs-xbox-one-black-4p5n3aiac8/
859	561	6	20260630	6	94.9900	USD	1.000000	94.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-horus-k618-rgb-sp-wireless-rgb-chroma-fps-bluetooth-5-0-100-anti-ghosting-black/
860	238	6	20260630	6	37.9900	USD	1.000000	37.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-gaming-marvo-kg962-60-switch-red-anti-ghosting-cable-type-c-desmontable-black/
861	586	6	20260630	6	27.9900	USD	1.000000	27.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-gaming-evil-772eg-rainbow-670g-switch-blue-usb-black-kb-772eg/
862	566	6	20260630	6	122.9900	USD	1.000000	122.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-mecanico-gaming-cougar-luxlim-low-profile-switch-red-usb-black/
863	239	6	20260630	6	51.9900	USD	1.000000	51.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-marvo-kg980a-tkl-mechanical-rgb-usb-2-0-black/
864	240	6	20260630	6	35.9900	USD	1.000000	35.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-marvo-kg962-b-60-rgb-100-anti-ghosting-usb-type-c-switch-blue-black/
865	241	6	20260630	6	7.9900	USD	1.000000	7.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/teclado-genius-kb-100x-alambrico-usb-espanol/
866	267	6	20260630	6	17.9900	USD	1.000000	17.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-teclado-y-mouse-genius-q8000-wireless-12-fn-keys-plug-and-play-black/
867	571	6	20260630	6	49.9900	USD	1.000000	49.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-asus-tuf-gaming-m4-wireless-bluetooth-12000-dpi-6-botones-black-b0ua00/
868	268	6	20260630	6	29.9900	USD	1.000000	29.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-msi-versa-300-wireless-8000dpi-bluetooth-60g-white/
869	269	6	20260630	6	17.9900	USD	1.000000	17.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-msi-forge-gm320-rgb-12800dpi-7-botones-sensor-optical-usb-2-0-black/
870	270	6	20260630	6	13.9900	USD	1.000000	13.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-msi-forge-gm300-7200dpi-7-botones-rgb-black/
871	271	6	20260630	6	6.9900	USD	1.000000	6.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-lenovo-300-usb-1600dpi-black/
872	271	6	20260630	6	10.9900	USD	1.000000	10.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-lenovo-essential-usb-diseno-ambidextro-1600dpi-black-4y50r20863/
873	272	6	20260630	6	74.9900	USD	1.000000	74.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-razer-basilisk-v3-35k-rgb-750ips-70g-optical-11-botones-black-rz01-05230100-r3u1/
874	273	6	20260630	6	82.9900	USD	1.000000	82.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-razer-cobra-chroma-rgb-gengar-edition-58g-8500dpi-6-botones-programables-300ips-black-rz01-04650700-r3m1/
875	274	6	20260630	6	31.9900	USD	1.000000	31.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-primus-pmo-w203/
876	275	6	20260630	6	126.9900	USD	1.000000	126.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-mx-master-3s-bluetooth-edition-ergonomico-7-botones-8000dpi-grafito-910-007502/
877	266	6	20260630	6	6.9900	USD	1.000000	6.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-gamdias-aura-gs3-rgb-black/
878	276	6	20260630	6	92.9900	USD	1.000000	92.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-101/
879	277	6	20260630	6	9.9900	USD	1.000000	9.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-95/
880	278	6	20260630	6	29.9900	USD	1.000000	29.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-lenovo-legion-m200-rgb-6-botones-usb/
881	584	6	20260630	6	37.9900	USD	1.000000	37.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-gaming-edition-star-wars-mandalorian-11-botones-12400dpi-sensor-optico-cafe-pmo-s202ml/
882	585	6	20260630	6	8.9900	USD	1.000000	8.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-klip-xtreme-optical-liteglider-usb-ps-2-adapter-kmo-102/
883	279	6	20260630	6	45.9900	USD	1.000000	45.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-gaming-meetion-hera-mt-g3330-rgb-led-9-botones-8000dpi-usb-black/
884	280	6	20260630	6	35.9900	USD	1.000000	35.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-gaming-hades-meetion-pro-mt-g3325-rgb-colorful-8-botones-5000dpi-black/
885	580	6	20260630	6	61.9900	USD	1.000000	61.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-glorious-model-d-matte-white-gd-white/
886	579	6	20260630	6	29.9900	USD	1.000000	29.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-cougar-minos-xt-black-3mmxtwob-0001/
887	578	6	20260630	6	75.9900	USD	1.000000	75.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-glorious-model-d-61g-d-minus-glo-ms-dm-mw-matte-white/
888	577	6	20260630	6	31.9900	USD	1.000000	31.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-hp-omen-600/
889	281	6	20260630	6	80.9900	USD	1.000000	80.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-cooler-master-mm711-blue/
890	282	6	20260630	6	17.9900	USD	1.000000	17.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-quasad-qm-g10/
891	576	6	20260630	6	221.9900	USD	1.000000	221.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-asus-p707-rog-spatha-x-wireless-aura-sync-19000dpi-black-90mp0220-bmua00/
892	283	6	20260630	6	13.9900	USD	1.000000	13.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-m196-bluetooth-1000-dpi-bateria-aa-rose-910-007458/
893	284	6	20260630	6	164.9900	USD	1.000000	164.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-g-pro-2-lightspeed-rgb-wireless-44000dpi-888-ips-1ms-80g-black-910-007246/
894	285	6	20260630	6	197.9900	USD	1.000000	197.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-gaming-g-pro-x-superlight-2-lightspeed-wireless-usb-connectivity-32000dpi-0-5-response-time-5-botones-white-910-006636/
895	285	6	20260630	6	174.9900	USD	1.000000	174.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-gaming-g-pro-x-superlight-2-lightspeed-wireless-usb-connectivity-32000dpi-0-5-response-time-5-botones-black-910-006628/
896	242	6	20260630	6	130.9900	USD	1.000000	130.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-g-pro-lightspeed-rgb-inalambrico-25600dpi-black-910-005271/
897	567	6	20260630	6	6.9900	USD	1.000000	6.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-169/
898	265	6	20260630	6	88.9900	USD	1.000000	88.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-100/
899	264	6	20260630	6	45.9900	USD	1.000000	45.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-99/
900	263	6	20260630	6	19.9900	USD	1.000000	19.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-97/
901	242	6	20260630	6	94.9900	USD	1.000000	94.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-gaming-g309-lightspeed-bluetooth-bateria-aa-25600dpi-white-910-007205/
902	242	6	20260630	6	90.9900	USD	1.000000	90.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-gaming-g309-lightspeed-bluetooth-bateria-aa-25600dpi-black-910-007197/
903	243	6	20260630	6	23.9900	USD	1.000000	23.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-pebble-m350-wireless-usb-bluetooth-silencioso-almond-milk-910-006658/
904	244	6	20260630	6	9.9900	USD	1.000000	9.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-logitech-m110s-silent-blue-alambrico-diseno-ambidiestro-usb-910-006662/
905	245	6	20260630	6	39.9900	USD	1.000000	39.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-hyperx-pulsefire-haste-2-26000dpi-ultra-ligh-wired-rgb-52g-black-6n0a7aa/
906	246	6	20260630	6	78.9900	USD	1.000000	78.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/mouse-corsair-m65-rgb-ultra-wired-optical-8-botones-26000dpi-peso-ajustable-2-zone-rgb-black-ch-9309411-na2/
907	575	6	20260630	6	33.9900	USD	1.000000	33.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-teclado-y-mouse-hp-235-alambrico-usb-a-black-1y4d0aaabm/
908	247	6	20260630	6	17.9900	USD	1.000000	17.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-teclado-y-mouse-genius-km-8101-wireless-2-4ghz-plug-and-play-us/
909	248	6	20260630	6	37.9900	USD	1.000000	37.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/audifonos-primus-arcus-arcus110t-star-wars-edition-dark-side-3-5mm-omnidireccional-stereo-50mm-black-red-phs-s110ds/
910	249	6	20260630	6	35.9900	USD	1.000000	35.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/almohadillas-de-repuesto-para-audifonos-logitech-g433-g935-g533-g332-black/
911	250	6	20260630	6	27.9900	USD	1.000000	27.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/almohadillas-de-repuesto-para-audifonos-logitech-g733-correa-de-repuesto-black/
912	251	6	20260630	6	162.9900	USD	1.000000	162.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/audifonos-gaming-cougar-omnes-essential-wireless-mic-omnidirectional-53mm-black-3hw50g53b-0001/
913	252	6	20260630	6	191.9900	USD	1.000000	191.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-corsair-hs60-haptic/
914	253	6	20260630	6	23.9900	USD	1.000000	23.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/audifonos-primus-arcus240-edicion-star-wars-edition-death-trooper-bluetooth-12mm-ipx5-black-pwh-s240dt/
915	250	6	20260630	6	20.9900	USD	1.000000	20.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/almohadillas-de-repuesto-para-audifonos-logitech-g733-black/
916	606	6	20260630	6	55.9900	USD	1.000000	55.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/audifonos-primus-gaming-edition-star-wars-mandalorian-arcus-210-tws-wireless-omnidireccional-usb-type-c-5-rms-black-pwh-s210ml/
917	589	6	20260630	6	19.9900	USD	1.000000	19.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/audifonos-klipxtreme-jogbudz-ii-ksm-150gn-bluetooth-v5-0-px41-12hrs/
918	599	6	20260630	6	80.9900	USD	1.000000	80.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/microfono-hyperx-quadcast-soporte-antivibracion-usb-conector-de-audifonos-incorporado-ajuste-de-control-de-ganancia-para-pc-ps4-black-red-4p5p6aa/
919	254	6	20260630	6	17.9900	USD	1.000000	17.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-marvo-cm370-4-en-1-tecladomousemousepadaudifono/
920	595	6	20260630	6	40.9900	USD	1.000000	40.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/stand-cougar-bunker-s-para-audifonos/
921	255	6	20260630	6	23.9900	USD	1.000000	23.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/combo-marvo-cm409-4-en-1-tecladomousemousepadaudifono/
922	550	6	20260630	6	53.9900	USD	1.000000	53.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/bundle-quasad-4-en-1-mouse-teclado-mouse-pad-headset-gaming/
923	256	6	20260630	6	24.9900	USD	1.000000	24.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/producto-66/
924	257	6	20260630	6	20.9900	USD	1.000000	20.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-meetion-mt-hp010/
925	258	6	20260630	6	59.9900	USD	1.000000	59.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-cooler-master-ch321/
926	259	6	20260630	6	47.9900	USD	1.000000	47.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/base-para-headsets-corsair-st50-premium/
927	260	6	20260630	6	63.9900	USD	1.000000	63.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headset-hp-h500gs/
928	557	6	20260630	6	261.9900	USD	1.000000	261.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-corsair-virtuoso-rgb-wireless-white/
929	556	6	20260630	6	136.9900	USD	1.000000	136.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-corsair-void-rgb-elite-wireless-white/
930	545	6	20260630	6	128.9900	USD	1.000000	128.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-corsair-void-rgb-elite-premium-black/
931	261	6	20260630	6	82.9900	USD	1.000000	82.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-corsair-hs45-carbon/
932	262	6	20260630	6	189.9900	USD	1.000000	189.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-astro-a20-black-green/
933	732	6	20260630	6	74.9900	USD	1.000000	74.9900	t	2026-06-30 00:00:00	https://www.tecnosmart.com.ec/producto/headsets-asus-tuf-gaming-h3-gunmetal/
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

\unrestrict CZpNII8jkezAtnDuIIIesNSIeVaSmcIacAs7BUkCmwf7UzDgt98QkBXcgQqY10U

