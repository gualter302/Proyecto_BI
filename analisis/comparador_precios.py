"""
comparador_precios.py  —  Logica de negocio del proyecto.

Responde la pregunta central del BI:
    "Para un mismo producto, ¿en que tienda ecuatoriana esta mas barato?"

Toma staging/stg_precios.csv, agrupa por clave_canonica (modelo homologado),
se queda con los productos que aparecen en 2+ tiendas y reporta la tienda con
el menor precio_usd, junto con el ahorro frente al precio mas alto.

Salida: staging/comparador_mejor_precio.csv
"""
import os
import pandas as pd

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGING = os.path.join(RAIZ, "staging")


def main():
    ruta = os.path.join(STAGING, "stg_precios.csv")
    df = pd.read_csv(ruta, encoding="utf-8-sig")

    # Solo productos con modelo identificado y presentes en 2+ tiendas
    df = df[df["clave_canonica"] != "sin_clasificar"].copy()
    grupos = df.groupby("clave_canonica")
    filas = []
    for clave, g in grupos:
        tiendas = g["tienda"].nunique()
        if tiendas < 2:
            continue
        idx_min = g["precio_usd"].idxmin()
        idx_max = g["precio_usd"].idxmax()
        pmin = g.loc[idx_min]
        pmax = g.loc[idx_max]
        filas.append({
            "clave_canonica":   clave,
            "categoria":        pmin["categoria"],
            "tiendas_comparadas": tiendas,
            "tienda_mas_barata": pmin["tienda"],
            "precio_min_usd":   round(pmin["precio_usd"], 2),
            "precio_max_usd":   round(pmax["precio_usd"], 2),
            "ahorro_usd":       round(pmax["precio_usd"] - pmin["precio_usd"], 2),
            "ahorro_pct":       round((1 - pmin["precio_usd"] / pmax["precio_usd"]) * 100, 1)
                                 if pmax["precio_usd"] else 0.0,
            "producto_ejemplo": str(pmin["producto"])[:70],
        })

    if not filas:
        print("[i] No se hallaron productos comparables en 2+ tiendas.")
        return

    res = pd.DataFrame(filas).sort_values("ahorro_usd", ascending=False)
    out = os.path.join(STAGING, "comparador_mejor_precio.csv")
    res.to_csv(out, index=False, encoding="utf-8-sig")

    print("=" * 70)
    print("  COMPARADOR DE PRECIOS — productos en 2+ tiendas")
    print("=" * 70)
    print(f"  Productos comparables: {len(res)}")
    print(f"\n  Top 10 mayores ahorros entre tiendas:")
    cols = ["clave_canonica", "tienda_mas_barata", "precio_min_usd", "precio_max_usd", "ahorro_usd", "ahorro_pct"]
    print(res[cols].head(10).to_string(index=False))
    print(f"\n  Guardado: {out}")
    print("=" * 70)


if __name__ == "__main__":
    main()
