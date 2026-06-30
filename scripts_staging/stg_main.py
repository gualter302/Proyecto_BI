"""
stg_main.py  —  Orquestador de la capa Staging + Framework de Calidad.

Pipeline:  Raw  ->  (homologacion, fechas, casting, estandarizacion,
                      clasificacion, conversion, deduplicacion)  ->  Staging
           aplicando y MIDIENDO los 7 controles de calidad obligatorios.

Salidas:
  staging/stg_precios.csv      (tabla de hechos de precios, lista para el DW)
  staging/stg_encuesta.csv     (fuente propia limpia)
  staging/stg_cpu_specs.csv    (archivo estructurado limpio)
  logs/reporte_calidad.json    (metricas exactas de los 7 controles)
  logs/errores_pipeline.csv    (bitacora persistente, control 3.6)
"""
import os
import sys
import glob
import json
import pandas as pd
from datetime import datetime

BASE = os.path.dirname(os.path.abspath(__file__))
PROYECTO_DIR = os.path.dirname(BASE)
sys.path.insert(0, BASE)
sys.path.insert(0, os.path.join(PROYECTO_DIR, "scripts_extraccion"))
sys.path.insert(0, os.path.join(PROYECTO_DIR, "calidad"))

import bitacora
import controles_calidad as qc
from stg_normalize_columns import normalizar_columnas
from stg_dates import estandarizar_fechas
from stg_currency import convertir_monedas
from stg_roles import clasificar
from stg_dedup import deduplicar

RAW_SCRAPING = os.path.join(PROYECTO_DIR, "raw", "scraping")
RAW_PROPIA   = os.path.join(PROYECTO_DIR, "raw", "fuente_propia")
RAW_ARCHIVOS = os.path.join(PROYECTO_DIR, "raw", "archivos")
STAGING_DIR  = os.path.join(PROYECTO_DIR, "staging")
LOGS_DIR     = os.path.join(PROYECTO_DIR, "logs")

CAMPOS_CLAVE = ["tienda", "categoria", "producto", "precio_usd", "clave_canonica"]


def leer_raw_scraping() -> pd.DataFrame:
    archivos = glob.glob(os.path.join(RAW_SCRAPING, "*", "*.csv"))
    frames = []
    for ruta in archivos:
        try:
            frames.append(pd.read_csv(ruta, encoding="utf-8-sig"))
        except Exception as e:
            bitacora.registrar("Staging:lectura", "Lectura",
                               f"No se pudo leer {os.path.basename(ruta)}: {e}",
                               "Archivo omitido")
    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True)


def procesar_precios():
    print("\n[1] Leyendo Raw scraping (6 tiendas)...")
    df = leer_raw_scraping()
    total_raw = len(df)
    print(f"    Registros crudos: {total_raw}")

    print("[2] Homologacion de columnas (stg_normalize_columns)...")
    df = normalizar_columnas(df)

    print("[3] Estandarizacion de fechas ANSI (stg_dates)...")
    df = estandarizar_fechas(df)

    print("[4] Estandarizacion estricta (UTF-8, categorias)...")
    df, est = qc.control_estandarizacion(df)

    # Filtro de relevancia: la busqueda por keyword a veces trae PCs/equipos
    # completos (ej. "PC Gamer con RTX 5090"), que no son el componente suelto y
    # distorsionan la comparacion de precios. Se descartan de las categorias de
    # componentes y se registra en bitacora.
    BUNDLES = r"pc\s*gamer|pc\s*gaming|computador|computadora|torre\s*gamer|barebone|all[\s-]*in[\s-]*one|equipo\s*gamer|cpu\s*gamer"
    es_bundle = df["producto"].str.contains(BUNDLES, case=False, regex=True, na=False)
    n_bundles = int(es_bundle.sum())
    if n_bundles:
        df = df[~es_bundle].copy()
        bitacora.registrar("Staging:relevancia", "Fuera de alcance",
                           f"{n_bundles} listados de PC/equipo completo en categorias de componentes",
                           "Descartados: no son el componente individual a comparar")
    print(f"      Equipos completos (bundles) descartados: {n_bundles}")

    print("[5] Formatos y casting de precios (string sucio -> float)...")
    casting = qc.control_casting(df)
    for ej in casting["ejemplos_antes_despues"][:5]:
        print(f"      {ej}")

    # --- 3.2 NULOS: medir % antes de resolver ---
    nulos_pre = qc.control_nulos(df, CAMPOS_CLAVE)
    print(f"[6] Control de nulos (% por campo clave): {nulos_pre}")

    # Estrategia de nulos criticos: sin precio_usd no se puede comparar -> eliminar
    n_antes = len(df)
    df = df[df["precio_usd"].notna() & (df["precio_usd"] > 0)].copy()
    nulos_criticos = n_antes - len(df)
    print(f"      Eliminados por precio nulo/invalido (critico): {nulos_criticos}")

    print("[7] Clasificacion / clave canonica (stg_roles)...")
    df = clasificar(df)

    print("[8] Conversion de monedas a referencia (stg_currency)...")
    df = convertir_monedas(df)

    print("[9] Deduplicacion integral (stg_dedup)...")
    df, dup = deduplicar(df)
    print(f"      Duplicados eliminados: {dup['duplicados_eliminados']}")

    # --- Guardar tabla de hechos ---
    os.makedirs(STAGING_DIR, exist_ok=True)
    cols = ["tienda", "pais", "moneda", "categoria", "producto", "clave_canonica",
            "precio_raw", "precio_usd",
            "precio_eur", "precio_brl", "precio_mxn", "precio_gbp",
            "url_producto", "fecha_extraccion", "fecha_staging"]
    cols = [c for c in cols if c in df.columns]
    df[cols].to_csv(os.path.join(STAGING_DIR, "stg_precios.csv"),
                    index=False, encoding="utf-8-sig")

    metricas = qc.reporte_metricas(total_raw, df, nulos_criticos,
                                   dup["duplicados_eliminados"], CAMPOS_CLAVE)
    cobertura = round((1 - (df["clave_canonica"] == "sin_clasificar").mean()) * 100, 2)

    return df, {
        "total_raw": total_raw,
        "estandarizacion": est,
        "casting": casting,
        "nulos_por_campo_pct": nulos_pre,
        "nulos_criticos_eliminados": nulos_criticos,
        "duplicados": dup,
        "cobertura_clave_canonica_pct": cobertura,
        "metricas_finales": metricas,
        "por_tienda": df["tienda"].value_counts().to_dict(),
        "por_categoria": df["categoria"].value_counts().to_dict(),
    }


def procesar_encuesta():
    """Fuente propia -> staging, con imputacion de nulos por mediana (3.2)."""
    archivos = sorted(glob.glob(os.path.join(RAW_PROPIA, "encuesta_hardware_*.csv")))
    if not archivos:
        return None
    df = pd.read_csv(archivos[-1], encoding="utf-8-sig")
    n = len(df)
    # presupuesto nulo -> imputar mediana del componente (categoria_interes)
    df["presupuesto_usd"] = pd.to_numeric(df["presupuesto_usd"], errors="coerce")
    nulos_presu = int(df["presupuesto_usd"].isna().sum())
    df["presupuesto_usd"] = df.groupby("categoria_interes")["presupuesto_usd"]\
        .transform(lambda s: s.fillna(s.median()))
    # ciudad nula -> "No especificada"
    nulos_ciudad = int(df["ciudad"].isna().sum())
    df["ciudad"] = df["ciudad"].fillna("No especificada")
    if nulos_presu or nulos_ciudad:
        bitacora.registrar("Staging:encuesta", "Nulo",
                           f"presupuesto nulos={nulos_presu}, ciudad nulos={nulos_ciudad}",
                           "presupuesto imputado por mediana del componente; ciudad -> 'No especificada'")
    df.to_csv(os.path.join(STAGING_DIR, "stg_encuesta.csv"), index=False, encoding="utf-8-sig")
    return {"registros": n, "presupuesto_imputado": nulos_presu, "ciudad_imputada": nulos_ciudad}


def procesar_specs():
    """Archivo estructurado -> staging (seleccion y homologacion de columnas)."""
    archivos = sorted(glob.glob(os.path.join(RAW_ARCHIVOS, "cpu_specs_amd_*.csv")))
    if not archivos:
        return None
    df = pd.read_csv(archivos[-1], encoding="utf-8-sig", low_memory=False)
    cols_map = {"Model": "modelo", "# of CPU Cores": "nucleos",
                "# of Threads": "hilos", "Default TDP": "tdp",
                "Base Clock": "clock_base", "CPU Socket": "socket"}
    presentes = {k: v for k, v in cols_map.items() if k in df.columns}
    out = df[list(presentes)].rename(columns=presentes)
    out = out.dropna(subset=["modelo"]).drop_duplicates(subset=["modelo"])
    out.to_csv(os.path.join(STAGING_DIR, "stg_cpu_specs.csv"), index=False, encoding="utf-8-sig")
    return {"registros": len(out), "columnas": list(out.columns)}


def main():
    print("=" * 70)
    print("  STAGING + FRAMEWORK DE CALIDAD DE DATOS")
    print("=" * 70)
    os.makedirs(LOGS_DIR, exist_ok=True)

    df_precios, rep_precios = procesar_precios()
    rep_encuesta = procesar_encuesta()
    rep_specs = procesar_specs()

    # --- Reporte consolidado de calidad (3.7) ---
    reporte = {
        "fecha_ejecucion": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "control_3_1_duplicados":      rep_precios["duplicados"],
        "control_3_2_nulos":           {
            "porcentaje_por_campo": rep_precios["nulos_por_campo_pct"],
            "matriz_resolucion": {
                "precio_usd": "Eliminacion del registro (sin precio no es comparable)",
                "encuesta.presupuesto_usd": "Imputacion con la mediana del componente",
                "encuesta.ciudad": "Reemplazo por 'No especificada'",
            },
            "registros_eliminados_criticos": rep_precios["nulos_criticos_eliminados"],
        },
        "control_3_3_casting":         rep_precios["casting"],
        "control_3_4_estandarizacion": rep_precios["estandarizacion"],
        "control_3_5_homologacion":    qc.control_homologacion(),
        "control_3_6_bitacora":        "logs/errores_pipeline.csv (persistente)",
        "control_3_7_metricas":        rep_precios["metricas_finales"],
        "cobertura_clave_canonica_pct": rep_precios["cobertura_clave_canonica_pct"],
        "distribucion_por_tienda":     rep_precios["por_tienda"],
        "distribucion_por_categoria":  rep_precios["por_categoria"],
        "fuente_propia_encuesta":      rep_encuesta,
        "archivo_estructurado_specs":  rep_specs,
    }
    with open(os.path.join(LOGS_DIR, "reporte_calidad.json"), "w", encoding="utf-8") as f:
        json.dump(reporte, f, indent=2, ensure_ascii=False)

    # --- Reporte en consola ---
    m = rep_precios["metricas_finales"]
    print("\n" + "=" * 70)
    print("  REPORTE FINAL DE METRICAS DE CALIDAD (3.7)")
    print("=" * 70)
    print(f"  Total registros crudos (Raw)            : {m['total_registros_raw']}")
    print(f"  Total registros aptos (Staging)         : {m['total_registros_staging']}")
    print(f"  Depurados por duplicados                : {m['registros_depurados_duplicados']}")
    print(f"  Eliminados por nulos criticos           : {m['registros_eliminados_nulos']}")
    print(f"  Tasa de completitud general             : {m['tasa_completitud_general_pct']}%")
    print(f"  Tasa de error (Raw->Staging)            : {m['tasa_error_pct']}%")
    print(f"  Cobertura clave canonica                : {rep_precios['cobertura_clave_canonica_pct']}%")
    print(f"\n  Por tienda    : {rep_precios['por_tienda']}")
    print(f"  Por categoria : {rep_precios['por_categoria']}")
    print(f"\n  Salidas: staging/stg_precios.csv, stg_encuesta.csv, stg_cpu_specs.csv")
    print(f"           logs/reporte_calidad.json, logs/errores_pipeline.csv")
    print("=" * 70)


if __name__ == "__main__":
    main()
