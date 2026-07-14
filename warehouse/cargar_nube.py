"""
cargar_nube.py  —  Carga el Data Warehouse completo en una BD en la nube (Neon).

Lee la conexión de la variable de entorno DATABASE_URL y carga:
  esquema estrella + datos (desde Staging) + vistas KPI + serie de tasas.

Uso (NO deja la contraseña en el código):
    Windows PowerShell:  $env:DATABASE_URL="postgresql://.../neondb?sslmode=require"; python warehouse/cargar_nube.py
    Bash:                DATABASE_URL="postgresql://.../neondb?sslmode=require" python warehouse/cargar_nube.py
"""
import os
import re
import json
import glob
import unicodedata
from datetime import date, timedelta

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WH = os.path.join(BASE, "warehouse")
STAGING = os.path.join(BASE, "staging", "stg_precios.csv")
RAW_API = os.path.join(BASE, "raw", "api")

URL = os.environ.get("DATABASE_URL", "")
if not URL:
    raise SystemExit("Falta la variable DATABASE_URL (cadena de conexión de Neon).")

CAT_MAP = {"CPU": "CPU", "GPU": "GPU", "RAM": "RAM", "SSD": "SSD",
           "MONITOR": "Monitor", "PERIFERICO": "Periferico"}
MARCAS_OTRAS = ["corsair", "kingston", "g.skill", "gskill", "teamgroup", "crucial",
                "samsung", "western digital", "seagate", "adata", "xpg", "logitech",
                "razer", "hyperx", "redragon", "asus", "msi", "gigabyte", "acer",
                "aoc", "benq", "lg", "viewsonic", "wd"]
URLS = {"Computron": "https://www.computron.com.ec", "Tecnosmart": "https://www.tecnosmart.com.ec",
        "MTEC": "https://mtec-ec.com", "NomadaWare": "https://nomadaware.com.ec",
        "TecnoGame": "https://tecnogame.ec", "CompuGamer": "https://compugamer.com.ec"}


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


def slug(t):
    t = unicodedata.normalize("NFKD", str(t)).encode("ascii", "ignore").decode()
    return re.sub(r"\s+", " ", t).strip().lower()[:155]


def build_data():
    df = pd.read_csv(STAGING, encoding="utf-8-sig")
    df["categoria"] = df["categoria"].map(CAT_MAP).fillna(df["categoria"])

    tiendas = sorted(df["tienda"].unique().tolist())
    dim_tienda = [(i + 1, t, "Ecuador", "USD", "Tienda especializada", URLS.get(t, "")) for i, t in enumerate(tiendas)]
    tienda_id = {t: i + 1 for i, t in enumerate(tiendas)}

    dim_fuente, fpt, fid = [], {}, 1
    for t in tiendas:
        dim_fuente.append((fid, f"Scraping {t}", "Web Scraping", "Playwright", "Semanal", URLS.get(t, ""))); fpt[t] = fid; fid += 1
    dim_fuente += [(fid, "API Frankfurter", "API Publica", "requests", "Diaria", "https://api.frankfurter.dev/v1/latest"),
                   (fid + 1, "CSV CPU Specs (AMD)", "Archivo CSV", "pandas read_csv", "Unica", "github/felixsteinke"),
                   (fid + 2, "Encuesta Propia Hardware", "Fuente Propia", "Formulario", "Unica", "raw/fuente_propia")]

    dim_tiempo, d = [], date(2026, 1, 1)
    dias = ["Lunes", "Martes", "Miercoles", "Jueves", "Viernes", "Sabado", "Domingo"]
    while d.year == 2026:
        idt = d.year * 10000 + d.month * 100 + d.day
        dim_tiempo.append((idt, d.isoformat(), d.isocalendar()[1], d.month, (d.month - 1) // 3 + 1, d.year, dias[d.weekday()]))
        d += timedelta(days=1)

    df["_m"] = df.apply(lambda r: derivar_marca(r["producto"], r["categoria"]), axis=1)
    df["_s"] = df.apply(lambda r: derivar_subcat(r["producto"], r["categoria"]), axis=1)
    df["_id"] = df["clave_canonica"] != "sin_clasificar"
    df["_k"] = df.apply(lambda r: r["clave_canonica"] if r["_id"] else slug(r["producto"]), axis=1)
    prod = df.sort_values("_id", ascending=False).drop_duplicates(subset="_k", keep="first").reset_index(drop=True)
    dim_producto, pid = [], {}
    for i, r in prod.iterrows():
        pid[r["_k"]] = i + 1
        dim_producto.append((i + 1, r["_k"][:160], r["_m"], r["categoria"], r["_s"], str(r["producto"])[:250], bool(r["_id"])))

    fact = []
    for i, r in df.iterrows():
        f = pd.to_datetime(r["fecha_extraccion"]).date()
        fact.append((i + 1, pid[r["_k"]], tienda_id[r["tienda"]], f.year * 10000 + f.month * 100 + f.day,
                     fpt[r["tienda"]], round(float(r["precio_usd"]), 4), "USD", 1.0, round(float(r["precio_usd"]), 4),
                     True, f.isoformat(), r.get("url_producto") if pd.notna(r.get("url_producto")) else None))
    return dim_tiempo, dim_fuente, dim_tienda, dim_producto, fact


def build_tasas():
    arch = sorted(glob.glob(os.path.join(RAW_API, "frankfurter_*.json")))
    if not arch:
        return []
    rates = json.load(open(arch[-1], encoding="utf-8"))["historico"]["rates"]
    filas, i = [], 1
    for fecha in sorted(rates):
        for moneda, tasa in rates[fecha].items():
            filas.append((i, fecha, moneda, round(float(tasa), 6))); i += 1
    return filas


def main():
    print("Cargando el Data Warehouse en la nube (Neon)...")
    dt, dfu, dti, dp, fact = build_data()
    tasas = build_tasas()

    conn = psycopg2.connect(URL); cur = conn.cursor()
    cur.execute(open(os.path.join(WH, "01_schema_dw.sql"), encoding="utf-8").read())
    execute_values(cur, "INSERT INTO dim_tiempo VALUES %s", dt)
    execute_values(cur, "INSERT INTO dim_fuente VALUES %s", dfu)
    execute_values(cur, "INSERT INTO dim_tienda VALUES %s", dti)
    execute_values(cur, "INSERT INTO dim_producto VALUES %s", dp)
    execute_values(cur, "INSERT INTO fact_precios VALUES %s", fact)
    cur.execute(open(os.path.join(WH, "04_kpis.sql"), encoding="utf-8").read())
    if tasas:
        cur.execute("DROP TABLE IF EXISTS fact_tasa_cambio CASCADE;"
                    "CREATE TABLE fact_tasa_cambio (id_tasa INT PRIMARY KEY, fecha DATE NOT NULL,"
                    " moneda CHAR(3) NOT NULL, tasa_usd DECIMAL(12,6) NOT NULL CHECK (tasa_usd>0));")
        execute_values(cur, "INSERT INTO fact_tasa_cambio VALUES %s", tasas)
    conn.commit()

    for t in ["fact_precios", "dim_producto", "dim_tienda", "fact_tasa_cambio"]:
        cur.execute(f"SELECT COUNT(*) FROM {t}"); print(f"  {t}: {cur.fetchone()[0]}")
    cur.close(); conn.close()
    print("[OK] Data Warehouse cargado en la nube.")


if __name__ == "__main__":
    main()
