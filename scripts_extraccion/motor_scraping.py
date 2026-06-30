"""
motor_scraping.py  —  Motor de extraccion (Web Scraping) con Playwright.

Cumple los requisitos del bloque A (Web Scraping Avanzado) del entregable:
  - Manejo de errores HTTP (timeouts, 403, 404)  -> bitacora.registrar(...)
  - Delays preventivos aleatorios entre peticiones (no saturar)
  - Header User-Agent definido
  - Almacenamiento directo en la zona Raw (raw/scraping/<tienda>/...)

Estrategia: por cada categoria del proyecto se ejecuta una busqueda por
palabra clave (restringida a productos). Se paginan hasta N paginas siguiendo
el enlace "siguiente". Cada producto se filtra con una lista blanca para
descartar ruido del buscador.

La zona Raw es INMUTABLE: se guarda el texto del precio TAL CUAL llega
(incluye descuentos/IVA); la limpieza ocurre despues en Staging.
"""
import os
import asyncio
import random
from datetime import datetime

from playwright.async_api import async_playwright
from playwright_stealth import Stealth

import bitacora
from config_tiendas import CATEGORIAS, FILTRO_CATEGORIA

PROYECTO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_SCRAPING_DIR = os.path.join(PROYECTO_DIR, "raw", "scraping")

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

MAX_PAGINAS = 3          # paginas por busqueda
TIMEOUT_MS = 45000


async def _delay():
    """Delay preventivo aleatorio para no saturar el servidor."""
    await asyncio.sleep(random.uniform(2.0, 4.0))


def _pasa_filtro(nombre: str, categoria: str) -> bool:
    """Lista blanca: el producto debe contener alguna palabra clave de su categoria."""
    n = nombre.lower()
    return any(p in n for p in FILTRO_CATEGORIA.get(categoria, []))


async def _extraer_pagina(page, tienda, categoria, keyword, datos):
    """Extrae los productos de la pagina actual. Retorna cuantos se agregaron."""
    try:
        await page.wait_for_selector(tienda["contenedor"], timeout=15000)
    except Exception:
        # Sin productos en esta pagina (fin de resultados o busqueda vacia)
        return 0

    items = await page.query_selector_all(tienda["contenedor"])
    agregados = 0
    for item in items:
        try:
            nombre = await item.eval_on_selector(
                tienda["sel_nombre"], "el => el.innerText.trim()"
            )
        except Exception:
            continue  # sin nombre -> producto no valido
        try:
            precio_raw = await item.eval_on_selector(
                tienda["sel_precio"], "el => el.innerText.trim()"
            )
        except Exception:
            precio_raw = ""  # se registra igual; staging lo marcara como nulo
        try:
            url_prod = await item.eval_on_selector(tienda["sel_url"], "el => el.href")
        except Exception:
            url_prod = ""

        if not nombre:
            continue
        if not _pasa_filtro(nombre, categoria):
            continue  # ruido del buscador, fuera de categoria

        datos.append({
            "tienda":            tienda["nombre"],
            "pais":              tienda["pais"],
            "moneda":            tienda["moneda"],
            "categoria":         categoria,
            "keyword_busqueda":  keyword,
            "producto":          nombre,
            "precio_raw":        precio_raw,
            "url_producto":      url_prod,
            "fecha_extraccion":  datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        })
        agregados += 1
    return agregados


async def _buscar(page, tienda, categoria, keyword, datos):
    """Ejecuta una busqueda y pagina hasta MAX_PAGINAS siguiendo 'siguiente'."""
    url = tienda["url_busqueda"].format(kw=keyword.replace(" ", "+"))
    print(f"   [{tienda['nombre']}] {categoria} ('{keyword}') -> {url}")

    # --- Carga inicial con manejo de errores HTTP ---
    try:
        resp = await page.goto(url, wait_until="domcontentloaded", timeout=TIMEOUT_MS)
        status = resp.status if resp else None
        if status and status >= 400:
            bitacora.registrar(
                tienda["nombre"], "HTTP",
                f"Codigo {status} en busqueda '{keyword}' ({categoria})",
                "Busqueda omitida; se continua con la siguiente categoria",
            )
            return
    except Exception as e:
        bitacora.registrar(
            tienda["nombre"], "Timeout/Conexion",
            f"No se pudo cargar '{keyword}' ({categoria}): {e}",
            "Busqueda omitida; se continua",
        )
        return

    await _delay()

    for n in range(1, MAX_PAGINAS + 1):
        agregados = await _extraer_pagina(page, tienda, categoria, keyword, datos)
        print(f"      pagina {n}: {agregados} productos validos")
        if agregados == 0 and n > 1:
            break

        # Buscar enlace "siguiente"
        siguiente = await page.query_selector(tienda["sel_siguiente"])
        if not siguiente:
            break
        try:
            href = await siguiente.get_attribute("href")
            if not href:
                break
            await page.goto(href, wait_until="domcontentloaded", timeout=TIMEOUT_MS)
            await _delay()
        except Exception as e:
            bitacora.registrar(
                tienda["nombre"], "Paginacion",
                f"Fallo al avanzar pagina {n+1} en '{keyword}': {e}",
                "Se detiene la paginacion de esta busqueda",
            )
            break


async def extraer_tienda(tienda) -> str:
    """
    Extrae todas las categorias de una tienda y guarda el CSV crudo.
    Retorna la ruta del archivo guardado (o cadena vacia si no hubo datos).
    """
    datos = []
    async with Stealth().use_async(async_playwright()) as p:
        browser = await p.chromium.launch(
            headless=False, args=["--disable-blink-features=AutomationControlled"]
        )
        context = await browser.new_context(user_agent=USER_AGENT, locale="es-EC")
        page = await context.new_page()

        for categoria, keywords in CATEGORIAS.items():
            for keyword in keywords:
                try:
                    await _buscar(page, tienda, categoria, keyword, datos)
                except Exception as e:
                    bitacora.registrar(
                        tienda["nombre"], "Inesperado",
                        f"Error no controlado en {categoria}/'{keyword}': {e}",
                        "Se continua con la siguiente busqueda",
                    )

        await browser.close()

    if not datos:
        bitacora.registrar(
            tienda["nombre"], "Sin datos",
            "La tienda no devolvio ningun producto valido",
            "No se genero archivo raw para esta tienda",
        )
        return ""

    # --- Guardado en zona Raw (inmutable): fuente_YYYY-MM-DD.csv ---
    import pandas as pd
    fecha = datetime.now().strftime("%Y-%m-%d")
    slug = tienda["nombre"].lower()
    carpeta = os.path.join(RAW_SCRAPING_DIR, slug)
    os.makedirs(carpeta, exist_ok=True)
    ruta = os.path.join(carpeta, f"{slug}_{fecha}.csv")
    pd.DataFrame(datos).to_csv(ruta, index=False, encoding="utf-8-sig")
    print(f"   [+] {len(datos)} registros -> {ruta}")
    return ruta
