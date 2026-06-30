"""
main_scraping.py  —  Orquestador de Web Scraping (Bloque A del entregable).

Ejecuta la extraccion de las 6 tiendas ecuatorianas y guarda cada una en su
carpeta Raw:  raw/scraping/<tienda>/<tienda>_YYYY-MM-DD.csv

Uso:
    python main_scraping.py            # todas las tiendas
    python main_scraping.py Computron  # solo una tienda (por nombre)
"""
import os
import sys
import asyncio

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from motor_scraping import extraer_tienda
from config_tiendas import TIENDAS


async def main():
    filtro = sys.argv[1].lower() if len(sys.argv) > 1 else None
    tiendas = [t for t in TIENDAS if (filtro is None or t["nombre"].lower() == filtro)]

    print("=" * 70)
    print(f"  WEB SCRAPING — {len(tiendas)} tienda(s) ecuatoriana(s)")
    print("=" * 70)

    resumen = []
    for tienda in tiendas:
        print(f"\n[>>>] {tienda['nombre']} ({tienda['moneda']})")
        try:
            ruta = await extraer_tienda(tienda)
            resumen.append((tienda["nombre"], "OK" if ruta else "SIN DATOS", ruta))
        except Exception as e:
            resumen.append((tienda["nombre"], f"ERROR: {e}", ""))

    print("\n" + "=" * 70)
    print("  RESUMEN DE EXTRACCION")
    print("=" * 70)
    for nombre, estado, ruta in resumen:
        print(f"  {nombre:14s} {estado}")
    print("=" * 70)


if __name__ == "__main__":
    asyncio.run(main())
