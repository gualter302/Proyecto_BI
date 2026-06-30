"""
stg_currency.py  —  Conversion de monedas (a USD + referencia internacional).

Transformacion exigida: "Unificacion a USD con tasa de cambio documentada".

Todas las tiendas operan en USD (Ecuador), por lo que el precio base ya esta
en dolares. Para dar valor analitico, se agregan precios de REFERENCIA en
divisas internacionales usando las tasas extraidas por la API Frankfurter
(raw/api/frankfurter_*.json). Las tasas quedan documentadas en el registro.

Esto permite responder: "que tan caro esta el hardware en Ecuador frente a
otras economias".
"""
import os
import sys
import json
import glob
import pandas as pd

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts_extraccion"))
import bitacora

PROYECTO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_API_DIR = os.path.join(PROYECTO_DIR, "raw", "api")

TASAS_RESPALDO = {"EUR": 0.92, "GBP": 0.79, "BRL": 5.0, "MXN": 18.0, "CAD": 1.37, "JPY": 156.0}


def cargar_tasas() -> dict:
    """Lee la ultima extraccion de la API. Si falla, usa tasas de respaldo."""
    archivos = sorted(glob.glob(os.path.join(RAW_API_DIR, "frankfurter_*.json")))
    if not archivos:
        bitacora.registrar("Staging:currency", "Fuente",
                           "No se encontro archivo de tasas en raw/api/",
                           "Se usan tasas de respaldo")
        return dict(TASAS_RESPALDO)
    try:
        with open(archivos[-1], encoding="utf-8") as f:
            data = json.load(f)
        tasas = data["latest"]["rates"]
        print(f"   [currency] tasas USD-> {tasas} (fuente: {os.path.basename(archivos[-1])})")
        return tasas
    except Exception as e:
        bitacora.registrar("Staging:currency", "Parseo",
                           f"No se pudieron leer las tasas: {e}",
                           "Se usan tasas de respaldo")
        return dict(TASAS_RESPALDO)


def convertir_monedas(df: pd.DataFrame, col_usd="precio_usd") -> pd.DataFrame:
    """Agrega columnas de precio de referencia en divisas internacionales."""
    tasas = cargar_tasas()
    for moneda, tasa in tasas.items():
        df[f"precio_{moneda.lower()}"] = (df[col_usd] * tasa).round(2)
    # Guardar las tasas usadas como metadato en cada fila (trazabilidad)
    df["tasas_referencia"] = json.dumps(tasas, ensure_ascii=False)
    return df
