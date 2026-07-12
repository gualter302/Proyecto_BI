"""
app.py  —  Dashboard BI: Comparador de Precios de Hardware en Ecuador (E5).

Lee EN VIVO desde el Data Warehouse PostgreSQL (NO desde CSV). Cumple:
  - 5+ KPIs estrategicos con valores reales.
  - 3 familias de graficos: barras, dispersion (scatter) y serie temporal.
  - Filtros reactivos por categoria, tienda y rango de precio.
  - Multi-vista: 3 pestañas.

Ejecutar en local:
    streamlit run dashboard/app.py

Conexion: por variables de entorno (para Streamlit Cloud / Neon) o valores
locales por defecto. Para editar textos/colores/consultas, ver el bloque
CONFIG y las funciones q_*().
"""
import os
import pandas as pd
import plotly.express as px
import streamlit as st
from sqlalchemy import create_engine, text

# ─────────────────────────────────────────────────────────────
# CONFIG  (edita aquí colores, título y conexión)
# ─────────────────────────────────────────────────────────────
TITULO = "Comparador de Precios de Hardware · Ecuador"
SUBTITULO = "Data Warehouse en vivo · VI Inteligencia de Negocios · UPSE"

# Paleta categorica accesible (orden fijo, apta para daltonismo — Okabe-Ito)
PALETA = ["#0072B2", "#E69F00", "#009E73", "#D55E00", "#CC79A7", "#56B4E9", "#F0E442"]

# Conexion al DW: usa variables de entorno; por defecto el Docker local.
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
    """Ejecuta SQL contra el DW y devuelve un DataFrame (cacheado 5 min)."""
    with get_engine().connect() as con:
        return pd.read_sql(text(sql), con, params=params or {})


# ─────────────────────────────────────────────────────────────
# CONSULTAS  (todas leen del DW; edita el SQL aquí)
# ─────────────────────────────────────────────────────────────
def q_dimensiones():
    cats = run_sql("SELECT DISTINCT categoria FROM dim_producto ORDER BY 1")["categoria"].tolist()
    tiendas = run_sql("SELECT nombre_tienda FROM dim_tienda ORDER BY 1")["nombre_tienda"].tolist()
    return cats, tiendas


def q_base(cats, tiendas, pmin, pmax):
    """
    Base de casi todos los gráficos: lee desde la vista vw_precios_validos del
    DW, que ya EXCLUYE los outliers (regla IQR). Así los KPIs coinciden con los
    valores oficiales del Data Warehouse (brecha, ahorro, etc.).
    """
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
# LAYOUT
# ─────────────────────────────────────────────────────────────
st.set_page_config(page_title=TITULO, page_icon="💻", layout="wide")
st.title("💻 " + TITULO)
st.caption(SUBTITULO)

# --- Verificar conexión al DW ---
try:
    cats_all, tiendas_all = q_dimensiones()
except Exception as e:
    st.error(f"No se pudo conectar al Data Warehouse. ¿Está encendido el contenedor?\n\n{e}")
    st.stop()

# --- Filtros (sidebar) ---
st.sidebar.header("Filtros")
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
    st.subheader("KPIs estratégicos")
    df_id = df[df["identificado"]]
    # Modelos presentes en 2+ tiendas (comparables)
    comp = (df_id.groupby("clave_canonica")["nombre_tienda"].nunique())
    modelos_comp = int((comp >= 2).sum())
    # Brecha y ahorro promedio (sobre comparables)
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

    st.divider()
    colA, colB = st.columns(2)
    with colA:
        st.markdown("**Precio promedio por categoría** (USD)")
        d = df.groupby("categoria", as_index=False)["precio_usd"].mean().sort_values("precio_usd")
        fig = px.bar(d, x="precio_usd", y="categoria", orientation="h",
                     color="categoria", color_discrete_sequence=PALETA, text_auto=".0f")
        fig.update_layout(showlegend=False, height=340, xaxis_title="USD", yaxis_title="")
        st.plotly_chart(fig, use_container_width=True)
    with colB:
        st.markdown("**Ofertas por tienda**")
        d = df.groupby("nombre_tienda", as_index=False).size().sort_values("size")
        fig = px.bar(d, x="size", y="nombre_tienda", orientation="h",
                     color="nombre_tienda", color_discrete_sequence=PALETA, text_auto=True)
        fig.update_layout(showlegend=False, height=340, xaxis_title="N.º de ofertas", yaxis_title="")
        st.plotly_chart(fig, use_container_width=True)

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
        # tienda del precio mínimo
        idx = df_id.groupby("clave_canonica")["precio_usd"].idxmin()
        barata = df_id.loc[idx, ["clave_canonica", "nombre_tienda"]].rename(
            columns={"nombre_tienda": "tienda_mas_barata"})
        resumen = resumen.merge(barata, on="clave_canonica", how="left")
        resumen["ahorro_%"] = ((resumen["precio_max"] - resumen["precio_min"]) /
                               resumen["precio_max"] * 100).round(1)

        colL, colR = st.columns([1.1, 1])
        with colL:
            st.markdown("**Modelos comparables** (menor precio y ahorro)")
            st.dataframe(resumen.sort_values("ahorro_%", ascending=False)
                         [["clave_canonica", "categoria", "tienda_mas_barata",
                           "precio_min", "precio_max", "ahorro_%"]],
                         use_container_width=True, height=420, hide_index=True)
        with colR:
            st.markdown("**Dispersión: precio mínimo vs máximo por modelo**")
            fig = px.scatter(resumen, x="precio_min", y="precio_max", color="categoria",
                             hover_name="clave_canonica", color_discrete_sequence=PALETA,
                             size="ahorro_%", size_max=18)
            m = resumen["precio_max"].max()
            fig.add_shape(type="line", x0=0, y0=0, x1=m, y1=m,
                          line=dict(color="gray", dash="dot"))
            fig.update_layout(height=420, xaxis_title="Precio mínimo (USD)",
                              yaxis_title="Precio máximo (USD)")
            st.plotly_chart(fig, use_container_width=True)

# ═════════════════════ TAB 3 — TENDENCIAS Y CALIDAD ═════════════════════
with tab3:
    st.subheader("Serie temporal — Tasas de cambio de referencia (USD →)")
    try:
        tasas = q_serie_tasas()
        fig = px.line(tasas, x="fecha", y="tasa_usd", color="moneda",
                      color_discrete_sequence=PALETA, markers=True)
        fig.update_layout(height=360, xaxis_title="Fecha", yaxis_title="Unidades por 1 USD")
        st.plotly_chart(fig, use_container_width=True)
        st.caption("Fuente: API Frankfurter (serie histórica cargada en el DW). "
                   "Referencia usada en Staging para el precio internacional.")
    except Exception:
        st.info("Tabla fact_tasa_cambio no encontrada. Ejecuta warehouse/06_cargar_tasas.py.")

    st.divider()
    colA, colB = st.columns(2)
    with colA:
        st.markdown("**Cobertura de identificación por categoría**")
        cob = run_sql("SELECT categoria, cobertura_pct FROM vw_kpi_cobertura ORDER BY cobertura_pct DESC")
        fig = px.bar(cob, x="cobertura_pct", y="categoria", orientation="h",
                     color_discrete_sequence=PALETA, text_auto=".1f")
        fig.update_layout(showlegend=False, height=320, xaxis_title="% identificado", yaxis_title="")
        st.plotly_chart(fig, use_container_width=True)
    with colB:
        st.markdown("**Outliers detectados (IQR)** — precios atípicos")
        out = run_sql("""SELECT categoria, clave_canonica, nombre_tienda, precio_usd
                         FROM vw_kpi_outliers ORDER BY precio_usd DESC LIMIT 15""")
        st.dataframe(out, use_container_width=True, height=320, hide_index=True)

st.sidebar.divider()
st.sidebar.caption("Datos leídos en vivo desde PostgreSQL (Data Warehouse).")
