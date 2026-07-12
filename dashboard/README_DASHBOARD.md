# Dashboard BI — Guía de uso y edición (E5)

Dashboard interactivo (Streamlit) que lee **en vivo** desde el Data Warehouse
PostgreSQL. Comparador de precios de hardware en Ecuador.

## Cómo ejecutarlo (local)

```bash
# 1. El DW debe estar encendido (contenedor en el puerto 5433)
docker start bi_hardware_dw

# 2. Instalar dependencias (una vez)
pip install -r dashboard/requirements.txt

# 3. Lanzar el dashboard
streamlit run dashboard/app.py
```
Se abre en `http://localhost:8501`.

> Si es la primera vez o recreaste el DW, carga la serie temporal de tasas:
> `python warehouse/06_cargar_tasas.py`

---

## 🛠️ Cómo EDITARLO tú mismo

Todo el dashboard está en **`dashboard/app.py`**, comentado por secciones. No
necesitas tocar la base de datos para cambiar la mayoría de cosas.

### 1. Cambiar título, subtítulo o colores
Al inicio del archivo, bloque **`CONFIG`**:
```python
TITULO = "Comparador de Precios de Hardware · Ecuador"   # <- cámbialo aquí
SUBTITULO = "Data Warehouse en vivo · ..."
PALETA = ["#0072B2", "#E69F00", ...]   # colores de los gráficos (orden fijo)
```

### 2. Cambiar una consulta (qué datos se leen)
Las funciones **`q_*()`** contienen el SQL. Por ejemplo, para cambiar qué se
muestra, edita el `SELECT` dentro de `q_base()`. Todo sale del DW.

### 3. Agregar un KPI (tarjeta con número)
Dentro de la pestaña (ej. `with tab1:`), en la fila de columnas:
```python
c1, c2, c3 = st.columns(3)
c1.metric("Mi KPI", f"{mi_valor}")     # <- agrega una línea así
```

### 4. Agregar un gráfico
```python
fig = px.bar(mi_df, x="columna_x", y="columna_y",
             color_discrete_sequence=PALETA)
st.plotly_chart(fig, use_container_width=True)
```
Tipos: `px.bar` (barras), `px.scatter` (dispersión), `px.line` (serie temporal),
`px.pie`, `px.box`, etc.

### 5. Agregar una pestaña
Busca la línea `tab1, tab2, tab3 = st.tabs([...])` y añade una:
```python
tab1, tab2, tab3, tab4 = st.tabs(["Resumen", "Comparador", "Tendencias", "Nueva"])
...
with tab4:
    st.subheader("Mi nueva vista")
    # tus gráficos aquí
```

### 6. Agregar un filtro
En el bloque de la barra lateral (`st.sidebar`):
```python
marca_sel = st.sidebar.multiselect("Marca", opciones)
```
Luego úsalo para filtrar tu DataFrame: `df[df["marca"].isin(marca_sel)]`.

> **Truco:** Streamlit recarga solo al guardar el archivo. Deja `streamlit run`
> corriendo, edita `app.py`, guarda y refresca el navegador.

---

## 🌐 Publicar el dashboard (URL pública para el E5)

El E5 pide una URL pública. Como Streamlit Cloud no puede ver tu `localhost`,
hay dos caminos:

- **Opción A (URL pública real):** subir el DW a **Neon** (PostgreSQL gratis en
  la nube) y el dashboard a **Streamlit Community Cloud**. La app se conecta a
  Neon con variables de entorno (`PG_HOST`, `PG_PORT`, `PG_USER`, `PG_PASS`,
  `PG_DB`) puestas en los *Secrets* de Streamlit Cloud.
- **Opción B (permitida):** ejecutarlo en local y entregar estas instrucciones +
  un **video demostrativo**.

Pide ayuda al equipo para montar la Opción A si se requiere la URL pública.

## Archivos
| Archivo | Qué es |
|---|---|
| `app.py` | El dashboard completo (edítalo aquí) |
| `requirements.txt` | Dependencias para ejecutar/desplegar |
| `README_DASHBOARD.md` | Esta guía |
