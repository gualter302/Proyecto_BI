"""
app.py  —  Dashboard BI: Comparador de Precios de Hardware en Ecuador (E5).

Lee EN VIVO desde el Data Warehouse PostgreSQL (NO desde CSV). Cumple:
  - 5+ KPIs estrategicos con valores reales.
  - 3 familias de graficos: barras, dispersion (scatter) y serie temporal.
  - Filtros reactivos por categoria, tienda y rango de precio.
  - Multi-vista: 3 pestañas.

Estilo ejecutivo "DashPro": barra lateral oscura + área clara con tarjetas y
paneles blancos.  Ejecutar:  streamlit run dashboard/app.py

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

# Paleta de los GRAFICOS (azules corporativos + acentos). Orden fijo por serie.
PALETA = ["#1F4E79", "#2E75B6", "#5B9BD5", "#E0A93B", "#6AA84F", "#B0413E", "#8E6FB3"]

# Colores de los paneles blancos (donde van los gráficos)
PANEL_BG   = "#FFFFFF"   # fondo del gráfico
PANEL_TXT  = "#1F2A37"   # texto dentro del panel
PANEL_GRID = "#E1E8EF"   # líneas de la cuadrícula

# Columnas que SIEMPRE debe tener la base (evita KeyError si el filtro deja 0 filas)
COLS_BASE = ["categoria", "marca", "clave_canonica", "identificado", "nombre_tienda", "precio_usd"]

def _cfg(clave, defecto):
    """Config desde st.secrets (Streamlit Cloud) -> variable de entorno -> local."""
    try:
        if clave in st.secrets:
            return st.secrets[clave]
    except Exception:
        pass
    return os.environ.get(clave, defecto)


PG = {
    "host": _cfg("PG_HOST", "localhost"),
    "port": _cfg("PG_PORT", "5433"),
    "db":   _cfg("PG_DB",   "bi_hardware"),
    "user": _cfg("PG_USER", "bi_user"),
    "pass": _cfg("PG_PASS", "bi_pass_2026"),
}


@st.cache_resource
def get_engine():
    # Si hay DATABASE_URL (ej. Neon en la nube) se usa directamente; si no, local.
    url = str(_cfg("DATABASE_URL", ""))
    if url:
        url = url.replace("postgresql://", "postgresql+psycopg2://").replace("postgres://", "postgresql+psycopg2://")
    else:
        url = f"postgresql+psycopg2://{PG['user']}:{PG['pass']}@{PG['host']}:{PG['port']}/{PG['db']}"
    return create_engine(url, pool_pre_ping=True)


@st.cache_data(ttl=300)
def run_sql(sql: str, params: dict | None = None) -> pd.DataFrame:
    with get_engine().connect() as con:
        return pd.read_sql(text(sql), con, params=params or {})


def estilizar(fig, alto=340):
    """Aplica el estilo 'panel blanco' a un gráfico Plotly."""
    fig.update_layout(
        height=alto, paper_bgcolor=PANEL_BG, plot_bgcolor=PANEL_BG,
        font=dict(color=PANEL_TXT, size=13),
        margin=dict(l=12, r=12, t=10, b=10),
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
    """Lee de vw_precios_validos (excluye outliers). Garantiza las columnas."""
    sql = """
        SELECT categoria, marca, clave_canonica, identificado,
               nombre_tienda, precio_usd
        FROM vw_precios_validos
        WHERE categoria = ANY(:cats)
          AND nombre_tienda = ANY(:tiendas)
          AND precio_usd BETWEEN :pmin AND :pmax
    """
    df = run_sql(sql, {"cats": cats, "tiendas": tiendas, "pmin": pmin, "pmax": pmax})
    # Garantiza SIEMPRE las columnas esperadas (aunque el filtro deje 0 filas)
    return df.reindex(columns=COLS_BASE)


def q_serie_tasas():
    return run_sql("SELECT fecha, moneda, tasa_usd FROM fact_tasa_cambio ORDER BY fecha")


# ─────────────────────────────────────────────────────────────
# LAYOUT + ESTILO (CSS)
# ─────────────────────────────────────────────────────────────
st.set_page_config(page_title=TITULO, page_icon="💻", layout="wide",
                   initial_sidebar_state="expanded")

st.markdown("""
<style>
/* Área principal gris claro */
.stApp { background-color: #E9EDF2; }

/* ---------- BARRA LATERAL OSCURA (estilo DashPro) ---------- */
section[data-testid="stSidebar"] { background-color: #15232F; }
section[data-testid="stSidebar"] * { color: #DCE6EF; }
/* Desplegables (multiselect) legibles sobre la barra oscura */
section[data-testid="stSidebar"] div[data-baseweb="select"] > div {
    background-color: #22384A !important; border-color: #33506A !important;
}
section[data-testid="stSidebar"] [data-baseweb="tag"] { background-color: #2E75B6 !important; }
section[data-testid="stSidebar"] div[data-baseweb="select"] svg { fill: #DCE6EF; }

/* ---------- TARJETAS DE KPI (blancas) ---------- */
div[data-testid="stMetric"] {
    background-color: #FFFFFF;
    border-radius: 14px;
    padding: 16px 18px;
    box-shadow: 0 2px 12px rgba(31,42,55,0.08);
    border: 1px solid #E5EBF1;
}
div[data-testid="stMetric"] label p { color: #5C6B7A !important; font-weight: 600; }
div[data-testid="stMetricValue"] { color: #12314A !important; font-weight: 800; }

/* ---------- PANELES DE GRÁFICOS (blancos) ---------- */
div[data-testid="stVerticalBlockBorderWrapper"] {
    background-color: #FFFFFF;
    border-radius: 14px;
    box-shadow: 0 2px 12px rgba(31,42,55,0.08);
    border: 1px solid #E5EBF1;
}
h1 { font-weight: 800; color: #12314A; }
</style>
""", unsafe_allow_html=True)

# ─────────────────────────────────────────────────────────────
# CONEXIÓN
# ─────────────────────────────────────────────────────────────
try:
    cats_all, tiendas_all = q_dimensiones()
    rango = run_sql("SELECT MIN(precio_usd) lo, MAX(precio_usd) hi FROM fact_precios").iloc[0]
except Exception as e:
    st.error(f"No se pudo conectar al Data Warehouse. ¿Está encendido el contenedor?\n\n{e}")
    st.stop()

# El DW podría estar vacío (MIN/MAX devuelven NULL) -> validar antes de usar en el slider
precio_max = float(rango.hi) if pd.notna(rango.hi) else 0.0
if precio_max <= 0 or not cats_all:
    st.warning("El Data Warehouse no tiene datos cargados. Carga el DW antes de usar el "
               "dashboard (ver el README principal o ejecuta `python iniciar.py`).")
    st.stop()

# ─────────────────────────────────────────────────────────────
# BARRA LATERAL: logo + filtros DESPLEGABLES
# ─────────────────────────────────────────────────────────────
with st.sidebar:
    st.markdown("### 💻 HARDWARE · EC")
    st.caption("Comparador de precios · BI")
    st.divider()
    st.markdown("#### 🔎 Filtros")
    # default vacío = "Todas" -> desplegables limpios que se abren al hacer clic
    cats_sel = st.multiselect("Categoría", cats_all, default=[], placeholder="Todas")
    tiendas_sel = st.multiselect("Tienda", tiendas_all, default=[], placeholder="Todas")
    pmin, pmax = st.slider("Rango de precio (USD)", 0.0, precio_max,
                           (0.0, precio_max), step=50.0)
    st.divider()
    st.caption("Datos en vivo desde PostgreSQL (DW)")

# vacío = todas
if not cats_sel: cats_sel = cats_all
if not tiendas_sel: tiendas_sel = tiendas_all

df = q_base(cats_sel, tiendas_sel, pmin, pmax)

# ─────────────────────────────────────────────────────────────
# ENCABEZADO + PESTAÑAS
# ─────────────────────────────────────────────────────────────
st.title("💻 " + TITULO)
st.caption(SUBTITULO)

if df.empty:
    st.warning("⚠️ No hay datos con los filtros seleccionados. Amplía el rango de precio "
               "o incluye más categorías/tiendas.")
    st.stop()

tab1, tab2, tab3 = st.tabs(["📊 Resumen Ejecutivo", "🏷️ Comparador de Precios", "📈 Tendencias y Calidad"])

# ═════════════════════ TAB 1 — RESUMEN ═════════════════════
with tab1:
    df_id = df[df["identificado"] == True]
    comp = df_id.groupby("clave_canonica")["nombre_tienda"].nunique() if not df_id.empty else pd.Series(dtype=int)
    modelos_comp = int((comp >= 2).sum())
    if modelos_comp:
        g = df_id[df_id["clave_canonica"].isin(comp[comp >= 2].index)].groupby("clave_canonica")["precio_usd"]
        brecha = ((g.max() - g.min()) / g.min() * 100).mean()
        ahorro = ((g.mean() - g.min()) / g.mean() * 100).mean()
    else:
        brecha = ahorro = 0

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
    df_id = df[df["identificado"] == True].copy()
    if df_id.empty:
        st.info("No hay modelos identificados (CPU/GPU) con los filtros actuales.")
    else:
        resumen = (df_id.groupby(["clave_canonica", "categoria"])
                   .agg(precio_min=("precio_usd", "min"),
                        precio_max=("precio_usd", "max"),
                        tiendas=("nombre_tienda", "nunique"))
                   .reset_index())
        resumen = resumen[resumen["tiendas"] >= 2]
        if resumen.empty:
            st.info("No hay modelos presentes en 2+ tiendas con los filtros actuales.")
        else:
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
                    m = float(resumen["precio_max"].max())
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
            if tasas.empty:
                st.info("Ejecuta warehouse/06_cargar_tasas.py para ver la serie temporal.")
            else:
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
