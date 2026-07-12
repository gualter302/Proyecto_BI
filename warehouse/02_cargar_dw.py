"""
02_cargar_dw.py  —  Carga del Data Warehouse (E4) desde la zona Staging (E3).

Lee EXCLUSIVAMENTE staging/stg_precios.csv (no toca la zona Raw), construye
las dimensiones y la tabla de hechos del esquema estrella y las inserta en
PostgreSQL 16.

Conexion (override por variables de entorno PG_*):
    host=localhost port=5433 db=bi_hardware user=bi_user pass=bi_pass_2026

Uso:  python warehouse/02_cargar_dw.py
"""
import os
import re
import unicodedata
from datetime import date, timedelta

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGING = os.path.join(BASE, "staging", "stg_precios.csv")
SCHEMA_SQL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "01_schema_dw.sql")

PG = dict(
    host=os.environ.get("PG_HOST", "localhost"),
    port=os.environ.get("PG_PORT", "5433"),
    dbname=os.environ.get("PG_DB", "bi_hardware"),
    user=os.environ.get("PG_USER", "bi_user"),
    password=os.environ.get("PG_PASS", "bi_pass_2026"),
)

CAT_MAP = {"CPU": "CPU", "GPU": "GPU", "RAM": "RAM", "SSD": "SSD",
           "MONITOR": "Monitor", "PERIFERICO": "Periferico"}

MARCAS_OTRAS = ["corsair", "kingston", "g.skill", "gskill", "teamgroup", "crucial",
                "samsung", "western digital", "seagate", "adata", "xpg", "logitech",
                "razer", "hyperx", "redragon", "asus", "msi", "gigabyte", "acer",
                "aoc", "benq", "lg", "viewsonic", "wd"]


def derivar_marca(nombre, categoria):
    n = str(nombre).lower()
    if categoria == "CPU":
        if any(k in n for k in ["ryzen", "amd", "threadripper"]): return "AMD"
        if any(k in n for k in ["core", "intel", "xeon", "pentium", "celeron"]): return "Intel"
    if categoria == "GPU":
        if any(k in n for k in ["rtx", "gtx", "geforce", "nvidia"]): return "NVIDIA"
        if any(k in n for k in ["radeon", "rx "]): return "AMD"
        if "arc" in n: return "Intel"
    for m in MARCAS_OTRAS:
        if m in n:
            return "WD" if m == "wd" else m.title()
    return "Varios"


def derivar_subcat(nombre, categoria):
    n = str(nombre).lower()
    if categoria == "RAM":
        for d in ["ddr5", "ddr4", "ddr3"]:
            if d in n: return d.upper()
    if categoria == "SSD":
        if "nvme" in n or "m.2" in n or "m2" in n: return "NVMe"
        if "sata" in n: return "SATA"
    if categoria == "Monitor":
        for r in ["ips", "oled", "va", "tn"]:
            if r in n: return r.upper()
    if categoria == "Periferico":
        if "teclado" in n: return "Teclado"
        if "mouse" in n or "raton" in n: return "Mouse"
        if any(k in n for k in ["audifono", "auricular", "headset", "diadema"]): return "Headset"
    return None


def slug(texto):
    t = unicodedata.normalize("NFKD", str(texto)).encode("ascii", "ignore").decode()
    t = re.sub(r"\s+", " ", t).strip().lower()
    return t[:155]


# ── Fuentes (dim_fuente): 6 scraping + API + archivo + fuente propia ──
def _urls_tienda(nombre):
    return {
        "Computron": "https://www.computron.com.ec",
        "Tecnosmart": "https://www.tecnosmart.com.ec",
        "MTEC": "https://mtec-ec.com",
        "NomadaWare": "https://nomadaware.com.ec",
        "TecnoGame": "https://tecnogame.ec",
        "CompuGamer": "https://compugamer.com.ec",
    }.get(nombre, "")


def construir_dim_fuente(tiendas):
    filas, fid = [], 1
    fuente_por_tienda = {}
    for t in tiendas:
        filas.append((fid, f"Scraping {t}", "Web Scraping", "Playwright", "Semanal", _urls_tienda(t)))
        fuente_por_tienda[t] = fid
        fid += 1
    # Fuentes no-hecho (existen en el pipeline E3, se documentan en el modelo)
    filas.append((fid, "API Frankfurter", "API Publica", "requests", "Diaria",
                  "https://api.frankfurter.dev/v1/latest")); fid += 1
    filas.append((fid, "CSV CPU Specs (AMD)", "Archivo CSV", "pandas read_csv", "Unica",
                  "https://raw.githubusercontent.com/felixsteinke/cpu-spec-dataset")); fid += 1
    filas.append((fid, "Encuesta Propia Hardware", "Fuente Propia", "Formulario", "Unica",
                  "raw/fuente_propia/encuesta_hardware")); fid += 1
    return filas, fuente_por_tienda


def construir_dim_tiempo(anio=2026):
    filas = []
    d = date(anio, 1, 1)
    dias_es = ["Lunes", "Martes", "Miercoles", "Jueves", "Viernes", "Sabado", "Domingo"]
    while d.year == anio:
        idt = d.year * 10000 + d.month * 100 + d.day
        trimestre = (d.month - 1) // 3 + 1
        semana = d.isocalendar()[1]
        filas.append((idt, d.isoformat(), semana, d.month, trimestre, d.year, dias_es[d.weekday()]))
        d += timedelta(days=1)
    return filas


def main():
    print("=" * 64)
    print("  CARGA DEL DATA WAREHOUSE (Staging E3 -> PostgreSQL)")
    print("=" * 64)

    df = pd.read_csv(STAGING, encoding="utf-8-sig")
    df["categoria"] = df["categoria"].map(CAT_MAP).fillna(df["categoria"])
    print(f"  Registros en Staging: {len(df)}")

    # --- dim_tienda ---
    tiendas = sorted(df["tienda"].unique().tolist())
    dim_tienda = [(i + 1, t, "Ecuador", "USD", "Tienda especializada", _urls_tienda(t))
                  for i, t in enumerate(tiendas)]
    tienda_id = {t: i + 1 for i, t in enumerate(tiendas)}

    # --- dim_fuente ---
    dim_fuente, fuente_por_tienda = construir_dim_fuente(tiendas)

    # --- dim_tiempo ---
    dim_tiempo = construir_dim_tiempo(2026)

    # --- dim_producto ---
    df["_marca"] = df.apply(lambda r: derivar_marca(r["producto"], r["categoria"]), axis=1)
    df["_subcat"] = df.apply(lambda r: derivar_subcat(r["producto"], r["categoria"]), axis=1)
    df["_ident"] = df["clave_canonica"] != "sin_clasificar"
    df["_clave"] = df.apply(
        lambda r: r["clave_canonica"] if r["_ident"] else slug(r["producto"]), axis=1)

    prod = (df.sort_values("_ident", ascending=False)
              .drop_duplicates(subset="_clave", keep="first")
              .reset_index(drop=True))
    dim_producto, prod_id = [], {}
    for i, r in prod.iterrows():
        pid = i + 1
        prod_id[r["_clave"]] = pid
        dim_producto.append((pid, r["_clave"][:160], r["_marca"], r["categoria"],
                             r["_subcat"], str(r["producto"])[:250], bool(r["_ident"])))

    # --- fact_precios ---
    fact = []
    for i, r in df.iterrows():
        fecha = pd.to_datetime(r["fecha_extraccion"]).date()
        idt = fecha.year * 10000 + fecha.month * 100 + fecha.day
        fact.append((
            i + 1,
            prod_id[r["_clave"]],
            tienda_id[r["tienda"]],
            idt,
            fuente_por_tienda[r["tienda"]],
            round(float(r["precio_usd"]), 4),   # precio_original (nativo USD en Ecuador)
            "USD",
            1.0,                                  # tasa_cambio_usd (Ecuador ya en USD)
            round(float(r["precio_usd"]), 4),
            True,
            fecha.isoformat(),
            r.get("url_producto") if pd.notna(r.get("url_producto")) else None,
        ))

    # --- Conexion y carga ---
    conn = psycopg2.connect(**PG); conn.autocommit = False
    cur = conn.cursor()
    with open(SCHEMA_SQL, encoding="utf-8") as f:
        cur.execute(f.read())
    print("  Esquema creado.")

    execute_values(cur, "INSERT INTO dim_tiempo VALUES %s", dim_tiempo)
    execute_values(cur, "INSERT INTO dim_fuente VALUES %s", dim_fuente)
    execute_values(cur, "INSERT INTO dim_tienda VALUES %s", dim_tienda)
    execute_values(cur, "INSERT INTO dim_producto VALUES %s", dim_producto)
    execute_values(cur, "INSERT INTO fact_precios VALUES %s", fact)
    conn.commit()

    # --- Verificacion ---
    print("\n  Registros cargados:")
    for tabla in ["dim_tiempo", "dim_fuente", "dim_tienda", "dim_producto", "fact_precios"]:
        cur.execute(f"SELECT COUNT(*) FROM {tabla}")
        print(f"    {tabla:14s}: {cur.fetchone()[0]}")
    cur.close(); conn.close()
    print("\n  [OK] Data Warehouse cargado.")


if __name__ == "__main__":
    main()
