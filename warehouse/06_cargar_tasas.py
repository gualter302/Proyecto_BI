"""
06_cargar_tasas.py  —  Tabla de serie temporal de tasas de cambio en el DW.

Carga la serie historica de la API Frankfurter (raw/api) en una tabla del DW,
para alimentar el grafico de SERIE TEMPORAL del dashboard leyendo desde el DW
(no desde CSV). Justificada: es la referencia de conversion usada en Staging.
"""
import os
import glob
import json
import psycopg2
from psycopg2.extras import execute_values

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_API = os.path.join(BASE, "raw", "api")
PG = dict(host=os.environ.get("PG_HOST", "localhost"), port=os.environ.get("PG_PORT", "5433"),
          dbname=os.environ.get("PG_DB", "bi_hardware"), user=os.environ.get("PG_USER", "bi_user"),
          password=os.environ.get("PG_PASS", "bi_pass_2026"))

DDL = """
DROP TABLE IF EXISTS fact_tasa_cambio CASCADE;
CREATE TABLE fact_tasa_cambio (
    id_tasa   INT PRIMARY KEY,
    fecha     DATE  NOT NULL,
    moneda    CHAR(3) NOT NULL,
    tasa_usd  DECIMAL(12,6) NOT NULL CHECK (tasa_usd > 0)
);
"""


def main():
    archivo = sorted(glob.glob(os.path.join(RAW_API, "frankfurter_*.json")))[-1]
    with open(archivo, encoding="utf-8") as f:
        data = json.load(f)
    rates = data["historico"]["rates"]   # {fecha: {moneda: tasa}}

    filas, i = [], 1
    for fecha in sorted(rates):
        for moneda, tasa in rates[fecha].items():
            filas.append((i, fecha, moneda, round(float(tasa), 6)))
            i += 1

    conn = psycopg2.connect(**PG); cur = conn.cursor()
    cur.execute(DDL)
    execute_values(cur, "INSERT INTO fact_tasa_cambio VALUES %s", filas)
    conn.commit()
    cur.execute("SELECT COUNT(*), COUNT(DISTINCT fecha), COUNT(DISTINCT moneda) FROM fact_tasa_cambio")
    n, nf, nm = cur.fetchone()
    print(f"[OK] fact_tasa_cambio: {n} filas ({nf} fechas x {nm} monedas)")
    cur.close(); conn.close()


if __name__ == "__main__":
    main()
