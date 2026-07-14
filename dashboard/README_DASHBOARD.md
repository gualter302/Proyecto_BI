# Dashboard BI — Guía de edición (E5)

Dashboard interactivo (Streamlit) que lee **en vivo** desde el Data Warehouse
PostgreSQL. Comparador de precios de hardware en Ecuador.

> 📌 **Cómo ejecutarlo** (Docker + Streamlit): ver el **[README principal](../README.md)**
> o simplemente `python iniciar.py`. Este documento cubre solo la **edición** y el
> **despliegue** del dashboard.

---

## 🛠️ Cómo EDITARLO tú mismo

Todo el dashboard está en **`dashboard/app.py`**, comentado por secciones. No
necesitas tocar la base de datos para cambiar la mayoría de cosas.
Los colores de la **interfaz** están en **`.streamlit/config.toml`**.

### 1. Cambiar título, subtítulo o colores de los gráficos
Al inicio del archivo, bloque **`CONFIG`**:
```python
TITULO = "Comparador de Precios de Hardware · Ecuador"   # <- cámbialo aquí
SUBTITULO = "..."
PALETA = ["#1F4E79", "#2E75B6", "#5B9BD5", ...]   # colores de los gráficos (orden fijo)
```
> Los colores del **fondo, tarjetas y barra lateral** se cambian en
> `.streamlit/config.toml` (requiere reiniciar Streamlit).

### 2. Cambiar una consulta (qué datos se leen)
Las funciones **`q_*()`** contienen el SQL. Edita el `SELECT` dentro de
`q_base()`. Todo sale del DW.

### 3. Agregar un KPI (tarjeta con número)
Dentro de la pestaña (ej. `with tab1:`), en la fila de columnas:
```python
c1, c2, c3 = st.columns(3)
c1.metric("Mi KPI", f"{mi_valor}")     # <- agrega una línea así
```

### 4. Agregar un gráfico
```python
fig = px.bar(mi_df, x="columna_x", y="columna_y", color_discrete_sequence=PALETA)
st.plotly_chart(estilizar(fig), use_container_width=True)   # estilizar = panel blanco
```
Tipos: `px.bar` (barras), `px.scatter` (dispersión), `px.line` (serie temporal),
`px.pie`, `px.box`, etc.

### 5. Agregar una pestaña
Busca `tab1, tab2, tab3 = st.tabs([...])` y añade una:
```python
tab1, tab2, tab3, tab4 = st.tabs(["Resumen", "Comparador", "Tendencias", "Nueva"])
...
with tab4:
    st.subheader("Mi nueva vista")
```

### 6. Agregar un filtro
En el bloque de la barra lateral (`with st.sidebar:`):
```python
marca_sel = st.multiselect("Marca", opciones, default=[], placeholder="Todas")
```
Luego úsalo para filtrar tu DataFrame: `df[df["marca"].isin(marca_sel)]`.

> **Truco:** Streamlit recarga solo al guardar `app.py`. Deja `streamlit run`
> corriendo, edita, guarda y refresca el navegador. (Los cambios de
> `config.toml` sí requieren reiniciar Streamlit.)

---

## 🌐 Publicar el dashboard (URL pública para el E5)

El E5 pide una URL pública. Como Streamlit Cloud no puede ver tu `localhost`,
hay dos caminos:

- **Opción A (URL pública real):** subir el DW a **Neon** (PostgreSQL gratis en
  la nube) y el dashboard a **Streamlit Community Cloud**. En los *Secrets* de
  Streamlit Cloud se pone **`DATABASE_URL`** con la cadena de conexión de Neon
  (recomendado), por ejemplo:
  ```toml
  DATABASE_URL = "postgresql://usuario:clave@ep-xxxx.aws.neon.tech/neondb?sslmode=require"
  ```
  Alternativamente se pueden usar las variables sueltas `PG_HOST`, `PG_PORT`,
  `PG_USER`, `PG_PASS`, `PG_DB`. La app (`app.py`) lee cualquiera de las dos vías.
- **Opción B (permitida):** ejecutarlo en local y entregar instrucciones + un
  **video demostrativo**.

## Archivos
| Archivo | Qué es |
|---|---|
| `app.py` | El dashboard completo (edítalo aquí) |
| `requirements.txt` | Dependencias para ejecutar/desplegar |
| `README_DASHBOARD.md` | Esta guía de edición |
