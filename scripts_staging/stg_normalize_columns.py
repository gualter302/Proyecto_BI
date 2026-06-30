"""
stg_normalize_columns.py  —  Homologacion de nombres de columnas.

Transformacion exigida: "Garantizar campos con el mismo nombre y tipado base".

Las 6 tiendas ya se extrajeron con un esquema uniforme, pero este modulo
GARANTIZA y DOCUMENTA el esquema canonico de Staging, renombrando cualquier
variante y forzando el tipado base (texto). Asi, si una fuente cambiara el
nombre de un campo, aqui se reconcilia a un unico nombre.
"""
import pandas as pd

# Esquema canonico de la tabla de hechos de precios en Staging
ESQUEMA_CANONICO = [
    "tienda", "pais", "moneda", "categoria",
    "producto", "precio_raw", "url_producto", "fecha_extraccion",
]

# Posibles variantes de nombre por fuente -> nombre canonico
ALIAS_COLUMNAS = {
    "store":        "tienda",
    "nombre":       "producto",
    "name":         "producto",
    "precio":       "precio_raw",
    "price":        "precio_raw",
    "url":          "url_producto",
    "fecha":        "fecha_extraccion",
}


def normalizar_columnas(df: pd.DataFrame) -> pd.DataFrame:
    """Renombra variantes al nombre canonico y asegura columnas faltantes."""
    df = df.rename(columns=ALIAS_COLUMNAS)
    # Asegurar que existan todas las columnas del esquema (faltantes -> NA)
    for col in ESQUEMA_CANONICO:
        if col not in df.columns:
            df[col] = pd.NA
    # Tipado base: todo a texto en esta etapa (el casting numerico va aparte)
    for col in ["tienda", "pais", "moneda", "categoria", "producto",
                "precio_raw", "url_producto", "fecha_extraccion"]:
        df[col] = df[col].astype("string")
    return df
