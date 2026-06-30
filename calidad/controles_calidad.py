"""
controles_calidad.py  —  Framework de Calidad de Datos (Core de Evaluacion).

Implementa EN CODIGO los 7 controles obligatorios del entregable, cada uno
devolviendo metricas cuantitativas (no descripciones cualitativas):

  3.1 Duplicados            -> control_duplicados()
  3.2 Control de Nulos      -> control_nulos()
  3.3 Formatos y Casting    -> limpiar_precio() / control_casting()
  3.4 Estandarizacion       -> control_estandarizacion()
  3.5 Homologacion fuentes  -> MAPEO_FUENTES / control_homologacion()
  3.6 Registro de Errores   -> (modulo bitacora.py, usado en todo el pipeline)
  3.7 Reporte de Metricas   -> reporte_metricas()
"""
import os
import re
import sys
import pandas as pd

# Permite importar bitacora desde scripts_extraccion
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts_extraccion"))
import bitacora


# ===========================================================================
# 3.3  FORMATOS Y CASTING  —  limpieza de strings numericos "sucios"
# ===========================================================================
_RE_MONTO = re.compile(r"\d[\d.,]*\d|\d")

def _normalizar_monto(token: str):
    """Convierte un token numerico sucio a float, detectando el formato."""
    t = token.strip()
    # Formato europeo "1.299,99" (punto=miles, coma=decimal)
    if re.fullmatch(r"\d{1,3}(\.\d{3})+,\d{1,2}", t):
        t = t.replace(".", "").replace(",", ".")
    # Formato anglosajon "1,299.99" (coma=miles, punto=decimal)
    elif re.fullmatch(r"\d{1,3}(,\d{3})+\.\d{1,2}", t):
        t = t.replace(",", "")
    # Solo coma decimal "248,99"
    elif re.fullmatch(r"\d+,\d{1,2}", t):
        t = t.replace(",", ".")
    # Coma como miles sin decimal "1,299"
    elif re.fullmatch(r"\d{1,3}(,\d{3})+", t):
        t = t.replace(",", "")
    else:
        t = t.replace(",", "")  # caso por defecto
    try:
        return float(t)
    except ValueError:
        return None


def limpiar_precio(precio_raw):
    """
    Casting robusto: de un texto de precio sucio a float (USD).
    Maneja: simbolo $, "Inc. IVA", descuentos con varios montos, coma/punto.
    Cuando hay varios montos (producto en oferta) toma el MENOR positivo,
    que corresponde al precio actual / con descuento.
    Retorna None si no se puede extraer un valor > 0.
    """
    if precio_raw is None or (isinstance(precio_raw, float) and pd.isna(precio_raw)):
        return None
    texto = str(precio_raw)
    montos = []
    for m in _RE_MONTO.findall(texto):
        val = _normalizar_monto(m)
        if val is not None and val > 0:
            montos.append(val)
    if not montos:
        return None
    return round(min(montos), 2)  # precio actual = menor (oferta)


def control_casting(df, col_raw="precio_raw", col_out="precio_usd"):
    """Aplica el casting y devuelve evidencia 'antes -> despues'."""
    df[col_out] = df[col_raw].apply(limpiar_precio)
    muestra = (
        df[[col_raw, col_out]]
        .dropna(subset=[col_out])
        .head(8)
        .apply(lambda r: f"{str(r[col_raw])[:30].strip()!r} -> {r[col_out]}", axis=1)
        .tolist()
    )
    fallidos = int(df[col_out].isna().sum())
    return {"ejemplos_antes_despues": muestra, "no_parseables": fallidos}


# ===========================================================================
# 3.1  DUPLICADOS
# ===========================================================================
# Criterio de unicidad: una oferta es unica por la combinacion
# (tienda + categoria + clave_canonica + precio_usd).
# Estrategia: conservar el registro MAS COMPLETO (menos nulos).
CLAVE_DUP = ["tienda", "categoria", "clave_canonica", "precio_usd"]

def control_duplicados(df):
    n0 = len(df)
    df = df.copy()
    df["_completitud"] = df.notna().sum(axis=1)
    df = (df.sort_values("_completitud", ascending=False)
            .drop_duplicates(subset=CLAVE_DUP, keep="first")
            .drop(columns="_completitud")
            .reset_index(drop=True))
    eliminados = n0 - len(df)
    return df, {"criterio": " + ".join(CLAVE_DUP),
                "estrategia": "conservar el registro mas completo",
                "duplicados_eliminados": eliminados}


# ===========================================================================
# 3.2  CONTROL DE NULOS
# ===========================================================================
def control_nulos(df, campos_clave):
    """% de nulos por campo clave + matriz de resolucion aplicada."""
    matriz = {}
    for campo in campos_clave:
        if campo in df.columns:
            pct = round(df[campo].isna().mean() * 100, 2)
            matriz[campo] = pct
    return matriz


# ===========================================================================
# 3.4  ESTANDARIZACION ESTRICTA
# ===========================================================================
CATEGORIAS_VALIDAS = {"CPU", "GPU", "RAM", "SSD", "MONITOR", "PERIFERICO"}

def control_estandarizacion(df):
    """Unifica codificacion, espacios y categorias maestras a forma canonica."""
    cambios = {}
    # Texto: trim + colapsar espacios y saltos de linea (UTF-8 al leer/escribir).
    # Incluye precio_raw: en Raw conserva los saltos de linea del descuento, pero
    # en Staging se aplana a una sola linea por registro (limpieza permitida aqui).
    for col in ["producto", "tienda", "categoria", "precio_raw"]:
        if col in df.columns:
            df[col] = (df[col].astype(str)
                       .str.replace(r"\s+", " ", regex=True)
                       .str.strip())
    # Categoria maestra en MAYUSCULA homogenea
    if "categoria" in df.columns:
        df["categoria"] = df["categoria"].str.upper()
        invalidas = set(df["categoria"].unique()) - CATEGORIAS_VALIDAS
        cambios["categorias_no_estandar"] = sorted(invalidas)
    return df, cambios


# ===========================================================================
# 3.5  HOMOLOGACION INTER-FUENTES
# ===========================================================================
# Mapeo conceptual explicito de campos equivalentes entre origenes
# heterogeneos hacia el esquema unificado de Staging.
MAPEO_FUENTES = {
    "producto": {
        "scraping_tiendas": "producto",
        "archivo_specs":    "Model",
        "encuesta":         "(no aplica)",
    },
    "precio_usd": {
        "scraping_tiendas": "precio_raw -> limpiar_precio()",
        "encuesta":         "presupuesto_usd",
    },
    "categoria": {
        "scraping_tiendas": "categoria",
        "encuesta":         "categoria_interes",
    },
    "tienda": {
        "scraping_tiendas": "tienda",
        "encuesta":         "tienda_habitual",
    },
}

def control_homologacion():
    return MAPEO_FUENTES


# ===========================================================================
# 3.7  REPORTE FINAL DE METRICAS
# ===========================================================================
def reporte_metricas(total_raw, df_staging, nulos_criticos, duplicados,
                     campos_completitud):
    """Consolidado estadistico exacto de los flujos del pipeline."""
    n_stg = len(df_staging)
    # Tasa de completitud general sobre los campos clave
    completos = df_staging[campos_completitud].notna().all(axis=1).sum() if n_stg else 0
    completitud = round((completos / n_stg) * 100, 2) if n_stg else 0.0
    return {
        "total_registros_raw":            int(total_raw),
        "total_registros_staging":        int(n_stg),
        "registros_depurados_duplicados": int(duplicados),
        "registros_eliminados_nulos":     int(nulos_criticos),
        "tasa_completitud_general_pct":   completitud,
        "tasa_error_pct":                 round(((total_raw - n_stg) / total_raw) * 100, 2) if total_raw else 0.0,
    }
