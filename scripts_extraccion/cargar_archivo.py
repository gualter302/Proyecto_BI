"""
cargar_archivo.py  —  Archivo Estructurado (Bloque C del entregable).

============================  ORIGEN DEL DATASET  ===========================
  Dataset  : CPU Specification Dataset (especificaciones oficiales de
             fabricante, Intel y AMD).
  Autor    : felixsteinke/cpu-spec-dataset (GitHub, dominio publico)
  URL AMD  : https://raw.githubusercontent.com/felixsteinke/cpu-spec-dataset/main/dataset/amd-cpus.csv
  URL Intel: https://raw.githubusercontent.com/felixsteinke/cpu-spec-dataset/main/dataset/intel-cpus.csv
  Formato  : CSV (UTF-8)
  Uso BI   : enriquecer los productos scrapeados (nucleos, TDP, socket, clock)
             para analizar precio vs. especificaciones tecnicas.
=============================================================================

  - Descarga el CSV desde la URL documentada (origen claro).
  - Guarda copia INMUTABLE en raw/archivos/ con fecha (no se modifica).
  - Valida el esquema: confirma que existan las columnas clave esperadas.
  - Reporta metricas de volumen (filas y columnas).
"""
import os
import sys
import io
import requests
import pandas as pd
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bitacora

PROYECTO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_ARCHIVOS_DIR = os.path.join(PROYECTO_DIR, "raw", "archivos")

DATASETS = {
    "cpu_specs_amd": "https://raw.githubusercontent.com/felixsteinke/cpu-spec-dataset/main/dataset/amd-cpus.csv",
}

# Columnas clave que DEBEN existir (validacion de esquema)
ESQUEMA_REQUERIDO = ["Model", "# of CPU Cores", "Default TDP"]


def validar_esquema(df: pd.DataFrame, nombre: str) -> bool:
    faltantes = [c for c in ESQUEMA_REQUERIDO if c not in df.columns]
    if faltantes:
        bitacora.registrar(
            f"Archivo:{nombre}", "Esquema",
            f"Columnas requeridas ausentes: {faltantes}",
            "Dataset rechazado por no cumplir el esquema esperado",
        )
        return False
    return True


def cargar():
    os.makedirs(RAW_ARCHIVOS_DIR, exist_ok=True)
    fecha = datetime.now().strftime("%Y-%m-%d")
    resumen = []

    for nombre, url in DATASETS.items():
        print(f"\n[ARCHIVO] Descargando {nombre} desde:\n          {url}")
        try:
            r = requests.get(url, timeout=30)
            r.raise_for_status()
        except Exception as e:
            bitacora.registrar(f"Archivo:{nombre}", "Descarga",
                               f"No se pudo descargar: {e}",
                               "Dataset omitido")
            continue

        # Guardar copia cruda inmutable (bytes tal cual llegaron)
        ruta = os.path.join(RAW_ARCHIVOS_DIR, f"{nombre}_{fecha}.csv")
        with open(ruta, "wb") as f:
            f.write(r.content)

        # Leer y validar esquema + metricas de volumen
        try:
            df = pd.read_csv(io.BytesIO(r.content), encoding="utf-8-sig", low_memory=False)
        except Exception as e:
            bitacora.registrar(f"Archivo:{nombre}", "Parseo",
                               f"CSV ilegible: {e}", "Dataset omitido")
            continue

        ok = validar_esquema(df, nombre)
        filas, cols = df.shape
        estado = "VALIDO" if ok else "ESQUEMA INVALIDO"
        print(f"          Filas={filas}  Columnas={cols}  -> {estado}")
        print(f"          Guardado: {ruta}")
        resumen.append((nombre, filas, cols, estado))

    print("\n" + "=" * 60)
    print("  RESUMEN ARCHIVO ESTRUCTURADO")
    print("=" * 60)
    for nombre, filas, cols, estado in resumen:
        print(f"  {nombre:18s} filas={filas:<6} cols={cols:<4} {estado}")
    return resumen


if __name__ == "__main__":
    cargar()
