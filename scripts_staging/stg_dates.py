"""
stg_dates.py  —  Estandarizacion de fechas al formato ANSI (YYYY-MM-DD).

Transformacion exigida: "Conversion unificada al formato ANSI estandar".

La fecha de extraccion viene como 'YYYY-MM-DD HH:MM:SS'. Se separa en:
  - fecha_extraccion (solo fecha, ANSI YYYY-MM-DD)
  - fecha_staging    (timestamp de procesamiento, trazabilidad)
Si una fila trae fecha invalida o nula, se registra y se imputa la fecha
de procesamiento (no se descarta por eso).
"""
import sys, os
import pandas as pd
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts_extraccion"))
import bitacora


def estandarizar_fechas(df: pd.DataFrame) -> pd.DataFrame:
    hoy = datetime.now().strftime("%Y-%m-%d")

    # Parsear a datetime; los no parseables quedan NaT
    parsed = pd.to_datetime(df["fecha_extraccion"], errors="coerce")
    invalidas = int(parsed.isna().sum())
    if invalidas:
        bitacora.registrar(
            "Staging:fechas", "Formato",
            f"{invalidas} fecha(s) de extraccion invalidas o nulas",
            "Imputadas con la fecha de procesamiento del pipeline",
        )

    # Formato ANSI YYYY-MM-DD; imputar las invalidas con hoy
    df["fecha_extraccion"] = parsed.dt.strftime("%Y-%m-%d").fillna(hoy)
    df["fecha_staging"] = hoy
    return df
