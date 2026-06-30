# Comparador de Precios de Hardware en Ecuador — Pipeline de Datos (Entregable 3)

**VI Inteligencia de Negocios · Ingeniería de Software · UPSE**

Pipeline de datos de extremo a extremo que **extrae precios de hardware de PC
desde 6 tiendas ecuatorianas** (más 3 fuentes adicionales), los almacena en una
zona **Raw** inmutable, los transforma en **Staging** con limpieza y
homologación, y aplica un **framework de 7 controles de calidad** medidos
cuantitativamente. El objetivo de negocio: **determinar en qué tienda está más
barato cada componente**.

---

## 1. Lógica de negocio

> Para un mismo producto (ej. *AMD Ryzen 9 9950X3D*), ¿en qué tienda
> ecuatoriana conviene comprarlo? El pipeline homologa el modelo entre tiendas
> y calcula la tienda más barata y el ahorro frente al precio más alto.

Salida: [`staging/comparador_mejor_precio.csv`](staging/comparador_mejor_precio.csv).

---

## 2. Fuentes de datos (las 4 tipologías obligatorias)

| Tipo | Fuente | Script | Salida Raw |
|---|---|---|---|
| **A. Web Scraping** | 6 tiendas EC: Computron, Tecnosmart, MTEC, NomadaWare, TecnoGame, CompuGamer | [`scripts_extraccion/main_scraping.py`](scripts_extraccion/main_scraping.py) | `raw/scraping/<tienda>/<tienda>_YYYY-MM-DD.csv` |
| **B. API** | Frankfurter (tasas de cambio, sin clave) | [`scripts_extraccion/extraer_api.py`](scripts_extraccion/extraer_api.py) | `raw/api/frankfurter_YYYY-MM-DD.json` |
| **C. Archivo estructurado** | CPU Spec Dataset (AMD, GitHub) | [`scripts_extraccion/cargar_archivo.py`](scripts_extraccion/cargar_archivo.py) | `raw/archivos/cpu_specs_amd_YYYY-MM-DD.csv` |
| **D. Fuente propia** | Encuesta anonimizada de hábitos de compra | [`scripts_extraccion/generar_encuesta.py`](scripts_extraccion/generar_encuesta.py) | `raw/fuente_propia/encuesta_hardware_YYYY-MM-DD.csv` |

### Documentación de la API (Bloque B)

| Campo | Detalle |
|---|---|
| API | Frankfurter API v1 |
| Endpoints | `/latest` y `/{inicio}..{fin}` (serie histórica) |
| Autenticación | Sin clave (tier gratuito / libre) |
| Parámetros | `base=USD`, `symbols=EUR,GBP,BRL,MXN,CAD,JPY` |
| Paginación | Serie histórica devuelve `{fecha: {moneda: tasa}}` → se itera cada fecha como registro estructurado |
| Frecuencia | Diaria |

---

## 3. Arquitectura de capas (Raw vs Staging)

```
raw/                         ← INMUTABLE: datos tal cual llegan del origen
  scraping/<tienda>/<tienda>_YYYY-MM-DD.csv
  api/frankfurter_YYYY-MM-DD.json
  archivos/cpu_specs_amd_YYYY-MM-DD.csv
  fuente_propia/encuesta_hardware_YYYY-MM-DD.csv
staging/                     ← datos limpios, homologados y listos para el DW
  stg_precios.csv            (tabla de hechos de precios)
  stg_encuesta.csv           (fuente propia limpia)
  stg_cpu_specs.csv          (archivo estructurado limpio)
  comparador_mejor_precio.csv
logs/
  errores_pipeline.csv       (bitácora persistente, control 3.6)
  reporte_calidad.json       (métricas de los 7 controles, control 3.7)
```

**Inmutabilidad:** los scripts de extracción solo *escriben* en `raw/` con
nomenclatura `fuente_YYYY-MM-DD.ext`. La limpieza ocurre exclusivamente en
Staging, leyendo de Raw sin modificarlo.

### Scripts de Staging (modulares, comentados)

| Transformación | Script |
|---|---|
| Homologación de nombres de columnas | [`scripts_staging/stg_normalize_columns.py`](scripts_staging/stg_normalize_columns.py) |
| Estandarización de fechas (ANSI YYYY-MM-DD) | [`scripts_staging/stg_dates.py`](scripts_staging/stg_dates.py) |
| Conversión de monedas (USD + referencia) | [`scripts_staging/stg_currency.py`](scripts_staging/stg_currency.py) |
| Clasificación / clave canónica | [`scripts_staging/stg_roles.py`](scripts_staging/stg_roles.py) |
| Deduplicación integral | [`scripts_staging/stg_dedup.py`](scripts_staging/stg_dedup.py) |
| Orquestador + calidad | [`scripts_staging/stg_main.py`](scripts_staging/stg_main.py) |

---

## 4. Framework de Calidad (7 controles, en código)

Todos en [`calidad/controles_calidad.py`](calidad/controles_calidad.py) y
orquestados por `stg_main.py`. Métricas exactas en `logs/reporte_calidad.json`.

1. **Duplicados** — clave compuesta `tienda + categoria + clave_canonica + precio_usd`; estrategia: conservar el registro más completo.
2. **Control de nulos** — % por campo clave + matriz de resolución (precio nulo → eliminar; presupuesto encuesta → imputar mediana; ciudad → "No especificada").
3. **Formatos y casting** — `"$440,00 ... $425,00"` → `425.0` (maneja IVA, descuentos, coma/punto decimal). Evidencia antes/después en el reporte.
4. **Estandarización estricta** — UTF-8, colapso de espacios/saltos, categorías maestras en mayúscula.
5. **Homologación inter-fuentes** — mapeo explícito (ej. `producto`=`Model`(specs)=`categoria_interes`(encuesta)).
6. **Registro de errores** — bitácora persistente `logs/errores_pipeline.csv` con `timestamp | fuente | tipo | descripción | acción`.
7. **Reporte de métricas** — consolidado estadístico exacto (ver abajo).

### Reporte final de métricas (ejecución 2026-06-30)

| Métrica | Valor |
|---|---|
| Registros crudos procesados (Raw) | 1.388 |
| Registros aptos para Warehouse (Staging) | 940 |
| Equipos completos descartados (relevancia) | 80 |
| Registros depurados por duplicados | 363 |
| Registros eliminados por nulos críticos | 5 |
| Tasa de completitud general | 100 % |
| Tasa de error (Raw→Staging) | 32,28 % |
| Productos comparables en 2+ tiendas | 41 |

---

## 5. Requisitos e instalación

Requiere **Python 3.11+**. Rutas 100 % **portables** (relativas al proyecto, sin
rutas absolutas).

```bash
# 1. Instalar dependencias
pip install playwright playwright-stealth pandas requests beautifulsoup4

# 2. Instalar el navegador de Playwright (una sola vez)
python -m playwright install chromium
```

## 6. Cómo correr el pipeline completo (end-to-end)

```bash
# Todo, incluido el scraping de las 6 tiendas (~15 min, abre navegador)
python run_pipeline.py

# Reusar el raw/scraping ya extraído y correr solo el resto (rápido)
python run_pipeline.py --sin-scraping
```

O paso a paso:

```bash
python scripts_extraccion/extraer_api.py        # B. API
python scripts_extraccion/cargar_archivo.py     # C. Archivo
python scripts_extraccion/generar_encuesta.py   # D. Fuente propia
python scripts_extraccion/main_scraping.py      # A. Scraping (6 tiendas)
python scripts_staging/stg_main.py              # Staging + 7 controles
python analisis/comparador_precios.py           # Lógica de negocio
```

Verificación de scrapeabilidad de tiendas (diagnóstico):
`python scripts_extraccion/sondeo_v2.py`

---

## 7. Limitaciones conocidas (mejoras para E4)

- La **clave canónica** se genera de forma confiable solo para **CPU y GPU**
  (modelos con número). RAM/SSD/Monitor/Periférico tienen títulos demasiado
  heterogéneos y quedan como `sin_clasificar` (no se comparan para evitar
  falsos emparejamientos). Cobertura actual ≈ 30 %.
- El precio **máximo** del comparador puede incluir listados atípicos (PC armada
  premium no capturada por el filtro de bundles). El precio **mínimo** y la
  **tienda más barata** —el dato de negocio— son robustos.
- La encuesta incluye respuestas de muestra anonimizadas para correr el pipeline
  E2E; reemplazar por el export real del formulario del equipo.
```
