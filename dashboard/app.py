"""
app.py  —  Dashboard BI: Comparador de Precios de Hardware en Ecuador (E5).

Lee EN VIVO desde el Data Warehouse PostgreSQL (NO desde CSV). Cumple:
  - 5+ KPIs estrategicos con valores reales.
  - 3 familias de graficos: barras, dispersion (scatter) y serie temporal.
  - Filtros reactivos por categoria, tienda y rango de precio.
  - Multi-vista: 3 pestañas.

Estilo ejecutivo (fondo azul marino + tarjetas y paneles claros).
Ejecutar en local:  streamlit run dashboard/app.py

Para editar: colores de la INTERFAZ -> .streamlit/config.toml
             colores de los GRAFICOS -> variable PALETA (abajo)
"""
import os
import pandas as pd
import plotly.express as px
import streamlit as st
from sqlalchemy import create_engine, text

# ─────────────────────────────────────────────────────────────
# CONFIG  (edita aquí paleta de gráficos, título y conexión)
# ─────────────────────────────────────────────────────────────
TITULO = "Comparador de Precios de Hardware · Ecuador"
SUBTITULO = "Análisis en vivo desde el Data Warehouse · VI Inteligencia de Negocios · UPSE"

# Paleta de los GRAFICOS (estilo ejecutivo). Orden fijo por serie.
PALETA = ["#2E75B6", "#6AA84F", "#E0A93B", "#8E6FB3", "#C0504D", "#3AAFA9", "#E8973A"]

# Colores de los paneles claros (donde van los gráficos)
PANEL_BG   = "#E9F2FA"   # fondo claro de cada gráfico
PANEL_TXT  = "#12314A"   # texto dentro del panel claro
PANEL_GRID = "#CBD9E6"   # líneas de la cuadrícula

PG = {
    "host": os.environ.get("PG_HOST", "localhost"),
    "port": os.environ.get("PG_PORT", "5433"),
    "db":   os.environ.get("PG_DB",   "bi_hardware"),
    "user": os.environ.get("PG_USER", "bi_user"),
    "pass": os.environ.get("PG_PASS", "bi_pass_2026"),
}


@st.cache_resource
def get_engine():
    url = f"postgresql+psycopg2://{PG['user']}:{PG['pass']}@{PG['host']}:{PG['port']}/{PG['db']}"
    return create_engine(url, pool_pre_ping=True)


@st.cache_data(ttl=300)
def run_sql(sql: str, params: dict | None = None) -> pd.DataFrame:
    with get_engine().connect() as con:
        return pd.read_sql(text(sql), con, params=params or {})


def estilizar(fig, alto=340):
    """Aplica el estilo 'panel claro' a un gráfico Plotly."""
    fig.update_layout(
        height=alto,
        paper_bgcolor=PANEL_BG,
        plot_bgcolor=PANEL_BG,
        font=dict(color=PANEL_TXT, size=13),
        margin=dict(l=12, r=12, t=12, b=12),
        legend=dict(bgcolor="rgba(0,0,0,0)", font=dict(color=PANEL_TXT)),
        colorway=PALETA,
    )
    fig.update_xaxes(gridcolor=PANEL_GRID, zerolinecolor=PANEL_GRID,
                     title_font=dict(color=PANEL_TXT), tickfont=dict(color=PANEL_TXT))
    fig.update_yaxes(gridcolor=PANEL_GRID, zerolinecolor=PANEL_GRID,
                     title_font=dict(color=PANEL_TXT), tickfont=dict(color=PANEL_TXT))
    return fig


# ─────────────────────────────────────────────────────────────
# CONSULTAS  (todas leen del DW)
# ─────────────────────────────────────────────────────────────
def q_dimensiones():
    cats = run_sql("SELECT DISTINCT categoria FROM dim_producto ORDER BY 1")["categoria"].tolist()
    tiendas = run_sql("SELECT nombre_tienda FROM dim_tienda ORDER BY 1")["nombre_tienda"].tolist()
    return cats, tiendas


def q_base(cats, tiendas, pmin, pmax):
    """Lee de vw_precios_validos (excluye outliers) para KPIs consistentes."""
    sql = """
        SELECT categoria, marca, clave_canonica, identificado,
               nombre_tienda, precio_usd
        FROM vw_precios_validos
        WHERE categoria = ANY(:cats)
          AND nombre_tienda = ANY(:tiendas)
          AND precio_usd BETWEEN :pmin AND :pmax
    """
    return run_sql(sql, {"cats": cats, "tiendas": tiendas, "pmin": pmin, "pmax": pmax})


def q_serie_tasas():
    return run_sql("SELECT fecha, moneda, tasa_usd FROM fact_tasa_cambio ORDER BY fecha")


# ─────────────────────────────────────────────────────────────
# LAYOUT + ESTILO (CSS)
# ─────────────────────────────────────────────────────────────
st.set_page_config(page_title=TITULO, page_icon="💻", layout="wide")

st.markdown("""
<style>
/* Fondo con degradado azul marino */
.stApp { background: linear-gradient(160deg, #0E2A44 0%, #123A5A 100%); }

/* Tarjetas de KPI: claras, redondeadas, con sombra */
div[data-testid="stMetric"] {
    background-color: #E9F2FA;
    border-radius: 16px;
    padding: 18px 20px;
    box-shadow: 0 4px 14px rgba(0,0,0,0.30);
    border: 1px solid rgba(255,255,255,0.10);
}
div[data-testid="stMetric"] label p { color: #4A6072 !important; font-weight: 600; }
div[data-testid="stMetricValue"] { color: #0C2A45 !important; font-weight: 800; }

/* Título grande */
h1 { font-weight: 800; letter-spacing: .3px; }

/* Paneles de los gráficos (contenedores con borde) */
div[data-testid="stVerticalBlockBorderWrapper"] {
    background-color: #E9F2FA;
    border-radius: 16px;
    box-shadow: 0 4px 14px rgba(0,0,0,0.28);
}
div[data-testid="stVerticalBlockBorderWrapper"] * { color: #12314A; }
</style>
""", unsafe_allow_html=True)

st.title("💻 " + TITULO)
st.caption(SUBTITULO)

# --- Conexión ---
try:
    cats_all, tiendas_all = q_dimensiones()
except Exception as e:
    st.error(f"No se pudo conectar al Data Warehouse. ¿Está encendido el contenedor?\n\n{e}")
    st.stop()

# --- Filtros ---
st.sidebar.header("🔎 Filtros")
cats_sel = st.sidebar.multiselect("Categoría", cats_all, default=cats_all)
tiendas_sel = st.sidebar.multiselect("Tienda", tiendas_all, default=tiendas_all)
rango = run_sql("SELECT MIN(precio_usd) lo, MAX(precio_usd) hi FROM fact_precios").iloc[0]
pmin, pmax = st.sidebar.slider("Rango de precio (USD)", 0.0, float(rango.hi),
                               (0.0, float(rango.hi)), step=50.0)
if not cats_sel: cats_sel = cats_all
if not tiendas_sel: tiendas_sel = tiendas_all

df = q_base(cats_sel, tiendas_sel, pmin, pmax)

tab1, tab2, tab3 = st.tabs(["📊 Resumen Ejecutivo", "🏷️ Comparador de Precios", "📈 Tendencias y Calidad"])

# ═════════════════════ TAB 1 — RESUMEN ═════════════════════
with tab1:
    df_id = df[df["identificado"]]
    comp = df_id.groupby("clave_canonica")["nombre_tienda"].nunique()
    modelos_comp = int((comp >= 2).sum())
    g = df_id[df_id["clave_canonica"].isin(comp[comp >= 2].index)].groupby("clave_canonica")["precio_usd"]
    brecha = ((g.max() - g.min()) / g.min() * 100).mean() if modelos_comp else 0
    ahorro = ((g.mean() - g.min()) / g.mean() * 100).mean() if modelos_comp else 0

    c1, c2, c3, c4, c5, c6 = st.columns(6)
    c1.metric("Ofertas analizadas", f"{len(df):,}")
    c2.metric("Tiendas", df["nombre_tienda"].nunique())
    c3.metric("Modelos comparables", modelos_comp)
    c4.metric("Brecha de precio prom.", f"{brecha:.1f}%")
    c5.metric("Ahorro potencial prom.", f"{ahorro:.1f}%")
    c6.metric("Precio promedio", f"${df['precio_usd'].mean():,.0f}")

    st.write("")
    colA, colB = st.columns(2)
    with colA:
        with st.container(border=True):
            st.markdown("**Precio promedio por categoría** (USD)")
            d = df.groupby("categoria", as_index=False)["precio_usd"].mean().sort_values("precio_usd")
            fig = px.bar(d, x="precio_usd", y="categoria", orientation="h",
                         color="categoria", color_discrete_sequence=PALETA, text_auto=".0f")
            fig.update_layout(showlegend=False, xaxis_title="USD", yaxis_title="")
            st.plotly_chart(estilizar(fig), use_container_width=True)
    with colB:
        with st.container(border=True):
            st.markdown("**Ofertas por tienda**")
            d = df.groupby("nombre_tienda", as_index=False).size().sort_values("size")
            fig = px.bar(d, x="size", y="nombre_tienda", orientation="h",
                         color="nombre_tienda", color_discrete_sequence=PALETA, text_auto=True)
            fig.update_layout(showlegend=False, xaxis_title="N.º de ofertas", yaxis_title="")
            st.plotly_chart(estilizar(fig), use_container_width=True)

# ═════════════════════ TAB 2 — COMPARADOR ═════════════════════
with tab2:
    st.subheader("¿En qué tienda está más barato cada modelo?")
    df_id = df[df["identificado"]].copy()
    if df_id.empty:
        st.info("No hay modelos identificados (CPU/GPU) con los filtros actuales.")
    else:
        resumen = (df_id.groupby(["clave_canonica", "categoria"])
                   .agg(precio_min=("precio_usd", "min"),
                        precio_max=("precio_usd", "max"),
                        tiendas=("nombre_tienda", "nunique"))
                   .reset_index())
        resumen = resumen[resumen["tiendas"] >= 2]
        idx = df_id.groupby("clave_canonica")["precio_usd"].idxmin()
        barata = df_id.loc[idx, ["clave_canonica", "nombre_tienda"]].rename(
            columns={"nombre_tienda": "tienda_mas_barata"})
        resumen = resumen.merge(barata, on="clave_canonica", how="left")
        resumen["ahorro_%"] = ((resumen["precio_max"] - resumen["precio_min"]) /
                               resumen["precio_max"] * 100).round(1)

        colL, colR = st.columns([1.1, 1])
        with colL:
            with st.container(border=True):
                st.markdown("**Modelos comparables** (menor precio y ahorro)")
                st.dataframe(resumen.sort_values("ahorro_%", ascending=False)
                             [["clave_canonica", "categoria", "tienda_mas_barata",
                               "precio_min", "precio_max", "ahorro_%"]],
                             use_container_width=True, height=420, hide_index=True)
        with colR:
            with st.container(border=True):
                st.markdown("**Dispersión: precio mínimo vs máximo por modelo**")
                fig = px.scatter(resumen, x="precio_min", y="precio_max", color="categoria",
                                 hover_name="clave_canonica", color_discrete_sequence=PALETA,
                                 size="ahorro_%", size_max=18)
                m = resumen["precio_max"].max()
                fig.add_shape(type="line", x0=0, y0=0, x1=m, y1=m,
                              line=dict(color="#94A9BD", dash="dot"))
                fig.update_layout(xaxis_title="Precio mínimo (USD)", yaxis_title="Precio máximo (USD)")
                st.plotly_chart(estilizar(fig, alto=420), use_container_width=True)

# ═════════════════════ TAB 3 — TENDENCIAS Y CALIDAD ═════════════════════
with tab3:
    with st.container(border=True):
        st.markdown("**Serie temporal — Tasas de cambio de referencia (USD →)**")
        try:
            tasas = q_serie_tasas()
            fig = px.line(tasas, x="fecha", y="tasa_usd", color="moneda",
                          color_discrete_sequence=PALETA, markers=True)
            fig.update_layout(xaxis_title="Fecha", yaxis_title="Unidades por 1 USD")
            st.plotly_chart(estilizar(fig, alto=360), use_container_width=True)
        except Exception:
            st.info("Tabla fact_tasa_cambio no encontrada. Ejecuta warehouse/06_cargar_tasas.py.")

    colA, colB = st.columns(2)
    with colA:
        with st.container(border=True):
            st.markdown("**Cobertura de identificación por categoría**")
            cob = run_sql("SELECT categoria, cobertura_pct FROM vw_kpi_cobertura ORDER BY cobertura_pct DESC")
            fig = px.bar(cob, x="cobertura_pct", y="categoria", orientation="h",
                         color_discrete_sequence=PALETA, text_auto=".1f")
            fig.update_layout(showlegend=False, xaxis_title="% identificado", yaxis_title="")
            st.plotly_chart(estilizar(fig, alto=320), use_container_width=True)
    with colB:
        with st.container(border=True):
            st.markdown("**Outliers detectados (IQR)** — precios atípicos")
            out = run_sql("""SELECT categoria, clave_canonica, nombre_tienda, precio_usd
                             FROM vw_kpi_outliers ORDER BY precio_usd DESC LIMIT 15""")
            st.dataframe(out, use_container_width=True, height=320, hide_index=True)

st.sidebar.divider()
st.sidebar.caption("Datos leídos en vivo desde PostgreSQL (Data Warehouse).")
