"""
stg_roles.py  —  Clasificacion de productos (categoria + clave canonica).

Transformacion exigida: "Asignacion de categorias globales mediante tokens
o keywords".

En este proyecto de comparacion de precios, el equivalente a "clasificar
roles" es:
  1. Confirmar/ajustar la CATEGORIA del producto por keywords.
  2. Generar una CLAVE_CANONICA (modelo homologado) que permita comparar el
     MISMO producto entre tiendas distintas. Ej:
       "PROCESADOR AMD RYZEN 5 8500G AM5 3.5GHZ" -> "amd ryzen 5 8500g"
       "Procesador AMD Ryzen 5 8500G con graficos" -> "amd ryzen 5 8500g"
   Esa clave es la que habilita el analisis "donde esta mas barato".
"""
import re
import pandas as pd

# Tokens de MODELO (con numero) por categoria. Solo se canonizan CPU y GPU,
# que tienen identificador de modelo claro y permiten emparejar el MISMO
# producto entre tiendas de forma confiable. RAM/SSD/Monitor/Periferico tienen
# titulos demasiado heterogeneos (marca+capacidad+velocidad sin formato fijo),
# por lo que se dejan como 'sin_clasificar' para no generar comparaciones
# falsas (mejora prevista para E4 con normalizacion mas fina).
TOKENS = {
    "CPU": [
        r"ryzen\s*\d+\s*\d{3,4}\s*x?\d*\w*",      # ryzen 9 9950x3d
        r"core\s*ultra\s*\d+\s*\d{3}\w*",          # core ultra 7 265kf
        r"core\s*i[3579][- ]?\d{4,5}\w*",          # core i7-14700k
        r"xeon\s*\w*\d{3,4}\w*",
    ],
    "GPU": [
        r"rtx\s*\d{4}\s*(ti\s*)?(super\s*)?\d*\s*gb?",  # rtx 5070 ti / rtx 5090 32gb
        r"rtx\s*\d{4}\s*(ti|super)?",
        r"gtx\s*\d{3,4}\s*(ti)?",
        r"rx\s*\d{3,4}\s*(xt)?\w*",                # rx 7800 xt
        r"arc\s*[ab]\d{3,4}",
    ],
}

# Claves demasiado genericas que NO identifican un producto unico -> rechazar.
GENERICAS = {"core", "ryzen", "rtx", "gtx", "rx", "ddr5", "ddr4", "ddr3",
             "nvme", "sata", "1tb", "2tb", "4tb", "ips", "va", "oled", "arc"}


def extraer_clave_canonica(nombre: str, categoria: str) -> str:
    """Genera la clave canonica homologada (solo CPU/GPU con modelo)."""
    if not nombre or pd.isna(nombre):
        return "sin_clasificar"
    txt = re.sub(r"\(.*?\)|\[.*?\]", " ", str(nombre).lower())
    txt = re.sub(r"\s+", " ", txt).strip()
    for patron in TOKENS.get(categoria, []):
        m = re.search(patron, txt)
        if m:
            clave = re.sub(r"\s+", " ", m.group()).strip()
            # Debe tener un digito (numero de modelo) y no ser un token generico
            if clave in GENERICAS or not re.search(r"\d", clave):
                continue
            return clave
    return "sin_clasificar"


def clasificar(df: pd.DataFrame) -> pd.DataFrame:
    df["clave_canonica"] = df.apply(
        lambda r: extraer_clave_canonica(r["producto"], r["categoria"]), axis=1
    )
    return df
