"""
app.py  —  Dashboard BI: Comparador de Precios de Hardware en Ecuador (E5).

Lee EN VIVO desde el Data Warehouse PostgreSQL (NO desde CSV). Cumple:
  - 5+ KPIs estratégicos con valores reales.
  - 3 familias de gráficos: barras, dispersión (scatter) y serie temporal.
  - Filtros reactivos por categoría, tienda, gama y rango de precio, que
    restringen las TRES vistas por igual (incluida "Tendencias y calidad").
  - Multi-vista en una sola pantalla: pastillas de navegación horizontales
    arriba del contenido (sin panel lateral).

Estilo ejecutivo: área clara con tarjetas y paneles blancos, navegación y
filtros en una barra superior.  Ejecutar:  streamlit run dashboard/app.py

Para editar: colores de la INTERFAZ -> .streamlit/config.toml
             colores de los GRÁFICOS -> variable PALETA (abajo)
"""
import math
import os
import pandas as pd
import plotly.express as px
import streamlit as st
from sqlalchemy import create_engine, text

# ─────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────
TITULO = "Comparador de Precios de Hardware · Ecuador"
SUBTITULO = "Análisis en vivo desde el Data Warehouse · VI Inteligencia de Negocios · UPSE"

# Paleta de los GRÁFICOS (azules corporativos + acentos). Orden fijo por serie.
PALETA = ["#1F4E79", "#2E75B6", "#5B9BD5", "#E0A93B", "#6AA84F", "#B0413E", "#8E6FB3"]

# Colores de los paneles blancos (donde van los gráficos)
PANEL_BG   = "#FFFFFF"
PANEL_TXT  = "#1F2A37"
PANEL_GRID = "#E1E8EF"

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


def estilizar(fig, alto=430):
    """Aplica el estilo 'panel blanco' a un gráfico Plotly."""
    fig.update_layout(
        height=alto, paper_bgcolor=PANEL_BG, plot_bgcolor=PANEL_BG,
        font=dict(color=PANEL_TXT, size=14),
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
    return df.reindex(columns=COLS_BASE)


def q_serie_tasas():
    return run_sql("SELECT fecha, moneda, tasa_usd FROM fact_tasa_cambio ORDER BY fecha")


def q_cobertura(cats, tiendas, pmin, pmax):
    """Cobertura de identificación por categoría, restringida a los filtros
    activos. Se recalcula desde las tablas base (no desde la vista agregada
    vw_kpi_cobertura) porque esa vista ya viene agrupada por categoría y no
    se puede filtrar por tienda/precio después de agregada."""
    sql = """
        SELECT p.categoria,
               ROUND(100.0 * SUM(CASE WHEN p.identificado THEN 1 ELSE 0 END)
                     / COUNT(*), 1) AS cobertura_pct
        FROM fact_precios f
        JOIN dim_producto p ON f.id_producto = p.id_producto
        JOIN dim_tienda   t ON f.id_tienda   = t.id_tienda
        WHERE p.categoria = ANY(:cats) AND t.nombre_tienda = ANY(:tiendas)
          AND f.precio_usd BETWEEN :pmin AND :pmax
        GROUP BY p.categoria
        ORDER BY cobertura_pct DESC
    """
    return run_sql(sql, {"cats": cats, "tiendas": tiendas, "pmin": pmin, "pmax": pmax})


def q_outliers(cats, tiendas, pmin, pmax):
    """Outliers (IQR) restringidos a los filtros activos."""
    sql = """
        SELECT categoria, clave_canonica, nombre_tienda, precio_usd
        FROM vw_kpi_outliers
        WHERE categoria = ANY(:cats) AND nombre_tienda = ANY(:tiendas)
          AND precio_usd BETWEEN :pmin AND :pmax
        ORDER BY precio_usd DESC
        LIMIT 15
    """
    return run_sql(sql, {"cats": cats, "tiendas": tiendas, "pmin": pmin, "pmax": pmax})


@st.cache_data(ttl=300)
def q_gama_bounds():
    """Umbrales de gama por categoría: tercios de precio (33% y 66%)."""
    return run_sql("""
        SELECT categoria,
               PERCENTILE_CONT(0.33) WITHIN GROUP (ORDER BY precio_usd) AS q33,
               PERCENTILE_CONT(0.66) WITHIN GROUP (ORDER BY precio_usd) AS q66
        FROM vw_precios_validos
        GROUP BY categoria
    """)


def asignar_gama(df, bounds):
    """Clasifica cada oferta en Baja / Media / Alta según su precio dentro de su categoría."""
    if df.empty:
        return df.assign(gama=pd.Series(dtype="object"))
    b = bounds.set_index("categoria")

    def clasificar(r):
        if r["categoria"] not in b.index:
            return "Media"
        lim = b.loc[r["categoria"]]
        if r["precio_usd"] <= lim["q33"]:
            return "Baja"
        if r["precio_usd"] <= lim["q66"]:
            return "Media"
        return "Alta"

    return df.assign(gama=df.apply(clasificar, axis=1))


# ─────────────────────────────────────────────────────────────
# LAYOUT + ESTILO (CSS)
# ─────────────────────────────────────────────────────────────
st.set_page_config(page_title=TITULO, layout="wide")

st.markdown("""
<style>
/* Área principal gris claro */
.stApp { background-color: #E9EDF2; }

/* ---------- NAVEGACIÓN SUPERIOR (pastillas horizontales, sin panel lateral) ---------- */
div[role="radiogroup"] { gap: 8px; flex-wrap: wrap; }
div[role="radiogroup"] label {
    background: #FFFFFF; border-radius: 999px; padding: 8px 18px;
    border: 1px solid #E5EBF1; cursor: pointer; transition: all .15s;
    box-shadow: 0 1px 4px rgba(31,42,55,0.06);
}
div[role="radiogroup"] label:hover { border-color: #2E75B6; }
div[role="radiogroup"] label > div:first-child { display: none; }
div[role="radiogroup"] label div[data-testid="stMarkdownContainer"] p {
    color: #5C6B7A; font-weight: 600; margin: 0;
}
div[role="radiogroup"] label:has(input:checked) { background: #2E75B6; border-color: #2E75B6; }
div[role="radiogroup"] label:has(input:checked) div[data-testid="stMarkdownContainer"] p { color: #FFFFFF; }

/* ---------- BARRA DE FILTROS (tarjeta blanca compacta) ---------- */
div[data-testid="stExpander"] { border-radius: 14px; border: 1px solid #E5EBF1; }

/* ---------- TARJETAS DE KPI (blancas) ---------- */
div[data-testid="stMetric"] {
    background-color: #FFFFFF;
    border-radius: 14px;
    padding: 18px 20px;
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

/* (Las animaciones se inyectan más abajo, con un nombre que cambia por vista
   para que se repitan cada vez que se navega entre vistas.) */
</style>
""", unsafe_allow_html=True)

# ─────────────────────────────────────────────────────────────
# CONEXIÓN
# ─────────────────────────────────────────────────────────────
try:
    cats_all, tiendas_all = q_dimensiones()
    rango = run_sql("SELECT MIN(precio_usd) lo, MAX(precio_usd) hi FROM fact_precios").iloc[0]
except Exception as e:
    st.error(f"No se pudo conectar al Data Warehouse.\n\n{e}")
    st.stop()

# El DW podría estar vacío (MIN/MAX devuelven NULL) -> validar antes del slider.
# El tope del slider es el precio real más alto que existe en el catálogo
# (redondeado hacia arriba a la centena, solo para que el número quede parejo).
# Si aparece un tope que no corresponde a ningún producto real, el problema está
# en el dato de origen (ver scripts_staging/stg_main.py, filtro de relevancia),
# no en este slider -- corregirlo ahí, no acá.
precio_max = 0.0
if pd.notna(rango.hi):
    precio_max = float(math.ceil(float(rango.hi) / 100) * 100)
if precio_max <= 0 or not cats_all:
    st.warning("El Data Warehouse no tiene datos cargados. Carga el DW antes de usar el "
               "dashboard (ver el README principal o ejecuta `python iniciar.py`).")
    st.stop()

# ─────────────────────────────────────────────────────────────
# ENCABEZADO
# ─────────────────────────────────────────────────────────────
st.title(TITULO)
st.caption(SUBTITULO)

# ─────────────────────────────────────────────────────────────
# NAVEGACIÓN + FILTROS — barra superior, sin panel lateral.
# Los filtros son GLOBALES: se aplican por igual a las tres vistas (incluida
# "Tendencias y calidad", que antes ignoraba Categoría/Tienda/Precio).
# ─────────────────────────────────────────────────────────────
VISTAS = ["Resumen ejecutivo", "Comparador de precios", "Tendencias y calidad"]
vista = st.radio("Navegación", VISTAS, horizontal=True, label_visibility="collapsed")

with st.expander("Filtros", expanded=True, icon=":material/tune:"):
    f1, f2, f3, f4 = st.columns([1.2, 1.2, 1, 2.4])
    with f1:
        cats_sel = st.multiselect("Categoría", cats_all, default=[], placeholder="Todas")
    with f2:
        tiendas_sel = st.multiselect("Tienda", tiendas_all, default=[], placeholder="Todas")
    with f3:
        gama_sel = st.multiselect("Gama", ["Baja", "Media", "Alta"], default=[], placeholder="Todas")
    with f4:
        # Dos campos numéricos en vez de un slider de doble manija: arrastrar dos
        # controles superpuestos en un rango de hasta $7.000 es incómodo y poco
        # preciso. Escribir el mínimo/máximo exacto es más rápido y no tiene el
        # problema de "las dos manijas quedan pegadas" en los extremos.
        st.caption("Rango de precio (USD)")
        fp1, fp2 = st.columns(2)
        with fp1:
            pmin = st.number_input("Mínimo", min_value=0.0, max_value=precio_max,
                                   value=0.0, step=10.0, format="%.0f")
        with fp2:
            pmax = st.number_input("Máximo", min_value=0.0, max_value=precio_max,
                                   value=precio_max, step=10.0, format="%.0f")
        if pmin > pmax:
            st.caption(":red[El mínimo no puede ser mayor que el máximo — se ignora el filtro de precio.]")
            pmin, pmax = 0.0, precio_max

if not cats_sel: cats_sel = cats_all
if not tiendas_sel: tiendas_sel = tiendas_all

# Confirmación visual de qué filtro está activo -- evita la duda de "¿de
# verdad se aplicó?" cuando una categoría chica (Monitor, Periférico...)
# de repente muestra pocos resultados.
_activos = []
if len(cats_sel) < len(cats_all):
    _activos.append("Categoría: " + ", ".join(cats_sel))
if len(tiendas_sel) < len(tiendas_all):
    _activos.append("Tienda: " + ", ".join(tiendas_sel))
if gama_sel:
    _activos.append("Gama: " + ", ".join(gama_sel))
if pmin > 0 or pmax < precio_max:
    # OJO: st.caption() renderiza markdown, y "$...$" dispara modo matemático
    # (LaTeX) -- por eso el rango se arma sin el símbolo "$" pegado al número.
    _activos.append(f"Precio: USD {pmin:,.0f}–{pmax:,.0f}")
st.caption("Filtrando por " + " · ".join(_activos) if _activos else
           "Sin filtros activos — mostrando todo el catálogo")

# ── ANIMACIONES ──────────────────────────────────────────────
# El nombre de la animación cambia con la vista (k). Al navegar, el navegador
# ve una animación "nueva" y la vuelve a ejecutar -> se re-anima cada vista.
k = VISTAS.index(vista)
st.markdown(f"""
<style>
@keyframes aparecer{k} {{
    from {{ opacity: 0; transform: translateY(16px); }}
    to   {{ opacity: 1; transform: translateY(0); }}
}}
/* Las barras crecen desde 0 (escala horizontal desde el eje) */
@keyframes crecerBarra{k} {{
    from {{ transform: scaleX(0); }}
    to   {{ transform: scaleX(1); }}
}}

h1 {{ animation: aparecer{k} .5s ease both; }}

/* Tarjetas de KPI: entran escalonadas */
div[data-testid="stMetric"] {{ animation: aparecer{k} .5s ease both; }}
div[data-testid="stHorizontalBlock"] > div:nth-child(1) div[data-testid="stMetric"] {{ animation-delay: .05s; }}
div[data-testid="stHorizontalBlock"] > div:nth-child(2) div[data-testid="stMetric"] {{ animation-delay: .12s; }}
div[data-testid="stHorizontalBlock"] > div:nth-child(3) div[data-testid="stMetric"] {{ animation-delay: .19s; }}
div[data-testid="stHorizontalBlock"] > div:nth-child(4) div[data-testid="stMetric"] {{ animation-delay: .26s; }}
div[data-testid="stHorizontalBlock"] > div:nth-child(5) div[data-testid="stMetric"] {{ animation-delay: .33s; }}
div[data-testid="stHorizontalBlock"] > div:nth-child(6) div[data-testid="stMetric"] {{ animation-delay: .40s; }}

/* Paneles de gráficos: entran después de los KPIs */
div[data-testid="stVerticalBlockBorderWrapper"] {{
    animation: aparecer{k} .6s ease both;
    animation-delay: .42s;
}}

/* Barras de Plotly: crecen desde el eje (barras horizontales) */
g.barlayer path {{
    transform-box: fill-box;
    transform-origin: left center;
    animation: crecerBarra{k} .9s cubic-bezier(.2,.75,.25,1) both;
    animation-delay: .55s;
}}

/* Accesibilidad: sin movimiento para quien lo prefiera */
@media (prefers-reduced-motion: reduce) {{
    h1, div[data-testid="stMetric"],
    div[data-testid="stVerticalBlockBorderWrapper"],
    g.barlayer path {{ animation: none !important; }}
}}
</style>
""", unsafe_allow_html=True)

df = q_base(cats_sel, tiendas_sel, pmin, pmax)
df = asignar_gama(df, q_gama_bounds())
if gama_sel:
    df = df[df["gama"].isin(gama_sel)]

if df.empty:
    st.warning("No hay datos con los filtros seleccionados. Amplía el rango de precio "
               "o incluye más categorías/tiendas.")
    st.stop()

# ─────────────────────────────────────────────────────────────
# TARJETAS DE KPI (siempre arriba)
# ─────────────────────────────────────────────────────────────
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

# ═════════════════════ VISTA 1 — RESUMEN ═════════════════════
if vista == VISTAS[0]:
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

# ═════════════════════ VISTA 2 — COMPARADOR ═════════════════════
elif vista == VISTAS[1]:
    st.subheader("¿En qué tienda está más barato cada modelo?")
    df_id = df[df["identificado"] == True].copy()
    if df_id.empty:
        st.info("No hay modelos identificados con los filtros actuales.")
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

            colL, colR = st.columns([1.05, 1])
            with colL:
                with st.container(border=True):
                    st.markdown("**Modelos comparables** (menor precio y ahorro)")
                    st.dataframe(resumen.sort_values("ahorro_%", ascending=False)
                                 [["clave_canonica", "categoria", "tienda_mas_barata",
                                   "precio_min", "precio_max", "ahorro_%"]],
                                 use_container_width=True, height=500, hide_index=True)
            with colR:
                with st.container(border=True):
                    st.markdown("**Dispersión: precio mínimo vs máximo por modelo**")
                    fig = px.scatter(resumen, x="precio_min", y="precio_max", color="categoria",
                                     hover_name="clave_canonica", color_discrete_sequence=PALETA,
                                     size="ahorro_%", size_max=20)
                    m = float(resumen["precio_max"].max())
                    fig.add_shape(type="line", x0=0, y0=0, x1=m, y1=m,
                                  line=dict(color="#94A9BD", dash="dot"))
                    fig.update_layout(xaxis_title="Precio mínimo (USD)", yaxis_title="Precio máximo (USD)")
                    st.plotly_chart(estilizar(fig, alto=500), use_container_width=True)

# ═════════════════════ VISTA 3 — TENDENCIAS Y CALIDAD ═════════════════════
else:
    with st.container(border=True):
        st.markdown("**Serie temporal — Tasas de cambio de referencia (USD →)**")
        st.caption("Referencia internacional, no depende de los filtros de categoría/tienda.")
        try:
            tasas = q_serie_tasas()
            if tasas.empty:
                st.info("Ejecuta warehouse/06_cargar_tasas.py para ver la serie temporal.")
            else:
                fig = px.line(tasas, x="fecha", y="tasa_usd", color="moneda",
                              color_discrete_sequence=PALETA, markers=True)
                fig.update_layout(xaxis_title="Fecha", yaxis_title="Unidades por 1 USD")
                st.plotly_chart(estilizar(fig, alto=440), use_container_width=True)
        except Exception:
            st.info("Tabla fact_tasa_cambio no encontrada. Ejecuta warehouse/06_cargar_tasas.py.")

    # OJO: antes estos dos paneles corrían SQL sin filtrar (siempre mostraban
    # las 6 categorías/todas las tiendas sin importar lo elegido arriba). Por
    # eso al filtrar por Monitor/Periférico "no pasaba nada" en esta pestaña:
    # el filtro sí se aplicaba, pero estos dos gráficos lo ignoraban por
    # completo. Ahora usan los mismos cats_sel/tiendas_sel/pmin/pmax que el
    # resto del dashboard (la Gama no aplica aquí: se calcula en el motor de
    # base de datos, no sobre el DataFrame ya clasificado en gamas).
    colA, colB = st.columns(2)
    with colA:
        with st.container(border=True):
            st.markdown("**Cobertura de identificación por categoría**")
            cob = q_cobertura(cats_sel, tiendas_sel, pmin, pmax)
            if cob.empty:
                st.info("No hay ofertas con los filtros actuales.")
            else:
                fig = px.bar(cob, x="cobertura_pct", y="categoria", orientation="h",
                             color_discrete_sequence=PALETA, text_auto=".1f")
                fig.update_layout(showlegend=False, xaxis_title="% identificado", yaxis_title="",
                                  xaxis_range=[0, 100])
                st.plotly_chart(estilizar(fig, alto=400), use_container_width=True)
    with colB:
        with st.container(border=True):
            st.markdown("**Outliers detectados (IQR)** — precios atípicos")
            out = q_outliers(cats_sel, tiendas_sel, pmin, pmax)
            if out.empty:
                st.info("No se detectaron outliers con los filtros actuales.")
            else:
                st.dataframe(out, use_container_width=True, height=400, hide_index=True)

st.divider()
st.caption("HARDWARE · EC — Comparador de precios · BI · Datos en vivo desde PostgreSQL (DW)")
