"""
sondeo_v2.py
Reintento usando post_type=product (busqueda SOLO de productos WooCommerce)
y contenedor estandar li.product + precio. Confirma nombre+precio reales.
"""
import asyncio, sys
sys.stdout.reconfigure(encoding="utf-8")
from playwright.async_api import async_playwright
from playwright_stealth import Stealth

# busqueda restringida a productos
TIENDAS = [
    ("Tecnosmart",      "https://www.tecnosmart.com.ec/?s=procesador&post_type=product"),
    ("MundoDigital",    "https://mundodigitalecuador.com/?s=procesador&post_type=product"),
    ("TecnoGame",       "https://tecnogame.ec/?s=procesador&post_type=product"),
    ("CompumundoStore", "https://compumundostore.com/?s=procesador&post_type=product"),
    ("CompuGamer",      "https://compugamer.com.ec/?s=procesador&post_type=product"),
    ("MTEC",            "https://mtec-ec.com/?s=procesador&post_type=product"),
    ("NomadaWare",      "https://nomadaware.com.ec/?s=procesador&post_type=product"),
    ("Compuzone",       "https://www.compuzone.com.ec/?s=procesador&post_type=product"),
]

CONT = ["li.product", "div.product-grid-item", "div.product-small.box"]
SEL_NOMBRE = ["h2.woocommerce-loop-product__title", "h3.wd-entities-title", ".wd-entities-title",
              ".woocommerce-loop-product__title", "h3.product-title", ".product-title", "h2 a", "h3 a"]
SEL_PRECIO = ["span.price", ".price ins .amount", ".price .amount", ".woocommerce-Price-amount",
              ".price bdi", "ins .amount", ".price"]

async def primer(item, sels):
    for s in sels:
        try:
            el = await item.query_selector(s)
            if el:
                t = (await el.inner_text()).strip()
                if t: return t, s
        except Exception: pass
    return None, None

async def probar(p, nombre, url):
    print(f"\n{'='*70}\n  {nombre}\n{'='*70}")
    b = await p.chromium.launch(headless=False, args=["--disable-blink-features=AutomationControlled"])
    ctx = await b.new_context(user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", locale="es-EC")
    page = await ctx.new_page()
    try:
        await page.goto(url, wait_until="domcontentloaded", timeout=45000)
        await page.wait_for_timeout(4000)
        cont_usado, items = None, []
        for c in CONT:
            items = await page.query_selector_all(c)
            if len(items) >= 2:
                cont_usado = c; break
        print(f"  contenedor='{cont_usado}'  items={len(items)}")
        sn_g = sp_g = None
        for i, item in enumerate(items[:3]):
            nom, sn = await primer(item, SEL_NOMBRE)
            pre, sp = await primer(item, SEL_PRECIO)
            sn_g = sn_g or sn; sp_g = sp_g or sp
            print(f"   {i+1}. {(nom[:45]+'...') if nom else '—SIN NOMBRE—'}  |  {pre or '—SIN PRECIO—'}")
        print(f"  >> nombre='{sn_g}'  precio='{sp_g}'")
    except Exception as e:
        print("  ERROR:", str(e)[:110])
    finally:
        await b.close()

async def main():
    async with Stealth().use_async(async_playwright()) as p:
        for n, u in TIENDAS:
            await probar(p, n, u)

asyncio.run(main())
