"""
extraer_api.py  —  Consumo de API (Bloque B del entregable).

============================  DOCUMENTACION DEL ENDPOINT  ====================
  API            : Frankfurter API (tasas de cambio del Banco Central Europeo)
  Base URL       : https://api.frankfurter.dev/v1
  Endpoints      : /latest                 -> tasas mas recientes
                   /{inicio}..{fin}         -> serie historica (paginacion por fecha)
  Autenticacion  : Sin clave (tier gratuito / libre)
  Parametros     : base=USD  (Ecuador opera en USD)
                   symbols=EUR,GBP,BRL,MXN,CAD,JPY  (referencia internacional)
  Paginacion     : el endpoint de serie historica devuelve un diccionario
                   {fecha: {moneda: tasa}}; se ITERA cada fecha como registro
                   estructurado (manejo de paginacion por rango temporal).
  Frecuencia     : Diaria
  Uso en el BI   : convertir los precios USD de las tiendas a divisas de
                   referencia, para comparar que tan caro esta el hardware en
                   Ecuador frente a la region / el mundo.
=============================================================================

Guarda en:  raw/api/frankfurter_YYYY-MM-DD.json   (con timestamp interno)
"""
import os
import sys
import json
import requests
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bitacora

PROYECTO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_API_DIR = os.path.join(PROYECTO_DIR, "raw", "api")

BASE_URL   = "https://api.frankfurter.dev/v1"
MONEDA_BASE = "USD"
SYMBOLS     = ["EUR", "GBP", "BRL", "MXN", "CAD", "JPY"]
DIAS_HISTORICO = 30


def _get(url, params):
    """GET con manejo de errores HTTP -> bitacora."""
    try:
        r = requests.get(url, params=params, timeout=20)
        r.raise_for_status()
        return r.json()
    except requests.exceptions.HTTPError as e:
        bitacora.registrar("Frankfurter API", "HTTP",
                           f"{e} en {url}", "Llamada abortada")
    except Exception as e:
        bitacora.registrar("Frankfurter API", "Conexion",
                           f"{e} en {url}", "Llamada abortada")
    return None


def obtener_tasas():
    os.makedirs(RAW_API_DIR, exist_ok=True)
    symbols_str = ",".join(SYMBOLS)
    ts = datetime.now()

    print("[API] Consultando tasas mas recientes (/latest)...")
    latest = _get(f"{BASE_URL}/latest",
                  {"base": MONEDA_BASE, "symbols": symbols_str})

    # --- Paginacion estructurada: serie historica por rango de fechas ---
    fin = ts.date()
    inicio = fin - timedelta(days=DIAS_HISTORICO)
    print(f"[API] Consultando serie historica {inicio}..{fin} (paginacion por fecha)...")
    historico = _get(f"{BASE_URL}/{inicio}..{fin}",
                     {"base": MONEDA_BASE, "symbols": symbols_str})

    # Iterar cada fecha como registro estructurado (manejo de paginacion)
    registros_historicos = 0
    if historico and "rates" in historico:
        registros_historicos = len(historico["rates"])
        print(f"      {registros_historicos} fechas (registros) recibidos en la serie.")

    if not latest:
        print("[API] No se obtuvieron tasas. Revisar bitacora.")
        return None

    paquete = {
        "_metadata": {
            "api":            "Frankfurter API v1",
            "endpoint_latest": f"{BASE_URL}/latest",
            "endpoint_serie":  f"{BASE_URL}/{inicio}..{fin}",
            "autenticacion":   "Sin clave (tier gratuito)",
            "base":            MONEDA_BASE,
            "symbols":         SYMBOLS,
            "timestamp_extraccion": ts.strftime("%Y-%m-%d %H:%M:%S"),
            "registros_serie_historica": registros_historicos,
        },
        "latest":    latest,
        "historico": historico,
    }

    fecha = ts.strftime("%Y-%m-%d")
    ruta = os.path.join(RAW_API_DIR, f"frankfurter_{fecha}.json")
    with open(ruta, "w", encoding="utf-8") as f:
        json.dump(paquete, f, indent=2, ensure_ascii=False)

    print(f"[API] Tasas USD -> {latest['rates']}")
    print(f"[API] Guardado: {ruta}")
    return ruta


if __name__ == "__main__":
    obtener_tasas()
