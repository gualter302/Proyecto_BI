"""
bitacora.py  —  Registro de Errores (Error Log File) del pipeline.

Cumple el control de calidad 3.6 del entregable: cada excepcion o anomalia
queda guardada con una estructura auditable:
    Timestamp | Fuente | Tipo de Error | Descripcion | Accion Tomada

Se usa tanto en extraccion (scraping/API) como en staging (limpieza).
El log es PERSISTENTE: se agrega (append), nunca se sobrescribe.

Ruta: <proyecto>/logs/errores_pipeline.csv
"""
import os
import csv
from datetime import datetime

# Raiz del proyecto = carpeta padre de este script
PROYECTO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGS_DIR = os.path.join(PROYECTO_DIR, "logs")
LOG_PATH = os.path.join(LOGS_DIR, "errores_pipeline.csv")

CABECERA = ["timestamp", "fuente", "tipo_error", "descripcion", "accion_tomada"]


def _asegurar_log():
    os.makedirs(LOGS_DIR, exist_ok=True)
    if not os.path.exists(LOG_PATH):
        with open(LOG_PATH, "w", newline="", encoding="utf-8") as f:
            csv.writer(f).writerow(CABECERA)


def registrar(fuente: str, tipo_error: str, descripcion: str, accion_tomada: str):
    """Agrega una fila a la bitacora persistente de errores."""
    _asegurar_log()
    fila = [
        datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        fuente,
        tipo_error,
        descripcion.replace("\n", " ").strip()[:300],
        accion_tomada,
    ]
    with open(LOG_PATH, "a", newline="", encoding="utf-8") as f:
        csv.writer(f).writerow(fila)
    print(f"   [BITACORA] {fuente} | {tipo_error} | {descripcion[:60]}")
