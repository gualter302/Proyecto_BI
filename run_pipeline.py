"""
run_pipeline.py  —  Orquestador End-to-End del pipeline E3.

Ejecuta TODO el flujo de extremo a extremo:
    1. Extraccion API        (Frankfurter -> raw/api)
    2. Archivo estructurado  (CPU specs   -> raw/archivos)
    3. Fuente propia         (encuesta    -> raw/fuente_propia)
    4. Web scraping          (6 tiendas   -> raw/scraping)   [opcional]
    5. Staging + Calidad     (raw -> staging + logs)
    6. Analisis comparador   (tienda mas barata)

Uso:
    python run_pipeline.py                # todo (incluye scraping, ~15 min)
    python run_pipeline.py --sin-scraping # usa el raw/scraping ya existente

Rutas PORTABLES: todo se resuelve relativo a la ubicacion de este archivo.
"""
import os
import sys
import subprocess

RAIZ = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable
EXTRACCION = os.path.join(RAIZ, "scripts_extraccion")
STAGING = os.path.join(RAIZ, "scripts_staging")
ANALISIS = os.path.join(RAIZ, "analisis")


def correr(descripcion, ruta_script, cwd=None):
    print("\n" + "#" * 70)
    print(f"#  {descripcion}")
    print("#" * 70)
    r = subprocess.run([PY, ruta_script], cwd=cwd or os.path.dirname(ruta_script))
    if r.returncode != 0:
        print(f"[!] '{descripcion}' termino con codigo {r.returncode}")
    return r.returncode


def main():
    sin_scraping = "--sin-scraping" in sys.argv

    correr("1/6  API (Frankfurter)",      os.path.join(EXTRACCION, "extraer_api.py"))
    correr("2/6  Archivo estructurado",   os.path.join(EXTRACCION, "cargar_archivo.py"))
    correr("3/6  Fuente propia (encuesta)", os.path.join(EXTRACCION, "generar_encuesta.py"))

    if sin_scraping:
        print("\n[i] --sin-scraping: se reutiliza raw/scraping existente.")
    else:
        correr("4/6  Web scraping (6 tiendas)", os.path.join(EXTRACCION, "main_scraping.py"))

    correr("5/6  Staging + Calidad",       os.path.join(STAGING, "stg_main.py"))
    correr("6/6  Analisis comparador",     os.path.join(ANALISIS, "comparador_precios.py"))

    print("\n" + "=" * 70)
    print("  PIPELINE COMPLETO. Revisa: staging/ y logs/reporte_calidad.json")
    print("=" * 70)


if __name__ == "__main__":
    main()
