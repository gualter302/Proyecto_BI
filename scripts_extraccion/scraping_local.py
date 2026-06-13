import asyncio
import os
import pandas as pd
from playwright.async_api import async_playwright

# 1. Definimos tus 5 búsquedas clave
BUSQUEDAS = ["tarjeta de video", "procesador", "laptop gamer", "mouse", "teclado"]

# 2. EL NUEVO FILTRO INTELIGENTE (Lista Blanca / Whitelist)
# Le decimos exactamente qué palabras validan que el producto es real
FILTRO_ESTRICTO = {
    "tarjeta de video": ["tarjeta", "video", "rtx", "gtx", "rx", "radeon", "geforce"],
    "procesador": ["procesador", "ryzen", "core", "intel", "amd"],
    "laptop gamer": ["laptop", "notebook", "gamer", "gaming", "rog", "tuf", "legion"],
    "mouse": ["mouse", "raton"],
    "teclado": ["teclado", "keyboard"]
}

CARPETA_DESTINO = "datos_crudos"
FILE_OUTPUT = os.path.join(CARPETA_DESTINO, "precios_computron_completo.csv")

async def extraer_datos_computron():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False)
        page = await browser.new_page()

        os.makedirs(CARPETA_DESTINO, exist_ok=True)
        productos_extraidos = []

        for termino in BUSQUEDAS:
            print(f"\n[=========== INICIANDO BÚSQUEDA: {termino.upper()} ===========]")
            
            url_busqueda = f"https://www.computron.com.ec/?s={termino.replace(' ', '+')}&post_type=product"
            
            await page.goto(url_busqueda, wait_until="networkidle", timeout=60000)
            numero_pagina = 1

            while True:
                print(f"[-] Extrayendo datos de: {termino.upper()} | Página {numero_pagina}...")
                
                selector_caja_principal = "div.meta-wrapper" 
                
                try:
                    await page.wait_for_selector(selector_caja_principal, timeout=10000)
                    await page.wait_for_timeout(2000) 
                except Exception as e:
                    print(f"[!] No se encontraron (o se acabaron) los productos para '{termino}'.")
                    break 

                bloques_items = await page.query_selector_all(selector_caja_principal)
                
                for bloque in bloques_items:
                    try:
                        # 1. El Nombre
                        nombre_elem = await bloque.query_selector("h3.heading-title.product-name")
                        nombre = (await nombre_elem.inner_text()).strip() if nombre_elem else "Sin nombre"
                        
                        # ==========================================
                        # VALIDACIÓN POR LISTA BLANCA (WHITELIST)
                        # ==========================================
                        nombre_minusculas = nombre.lower()
                        palabras_permitidas = FILTRO_ESTRICTO[termino]
                        
                        # Si el nombre NO tiene al menos una de las palabras permitidas, lo descartamos
                        if not any(palabra_valida in nombre_minusculas for palabra_valida in palabras_permitidas):
                            print(f"    [X] Descartado (No coincide con '{termino}'): {nombre}")
                            continue
                        # ==========================================
                        
                        # 2. Precio Tarjeta
                        precio_tarjeta_elem = await bloque.query_selector("div.price-tarjeta span.price")
                        precio_tarjeta = (await precio_tarjeta_elem.inner_text()).strip() if precio_tarjeta_elem else "Sin precio"
                        
                        # 3. Precio Crédito
                        precio_credito_elem = await bloque.query_selector("div.price-credito")
                        if precio_credito_elem:
                            precio_credito = (await precio_credito_elem.inner_text()).strip().replace('\n', ' ')
                        else:
                            precio_credito = "Sin precio"
                        
                        # Solo agregamos si hay un nombre válido (y ya pasó el filtro estricto)
                        if nombre != "Sin nombre":
                            productos_extraidos.append({
                                'categoria_busqueda': termino, 
                                'tienda': 'Computron',
                                'producto': nombre,
                                'precio_tarjeta': precio_tarjeta,
                                'precio_credito': precio_credito
                            })
                    except Exception:
                        continue
                
                # === LÓGICA DE PAGINACIÓN ===
                boton_siguiente = await page.query_selector("a.next")
                
                if boton_siguiente:
                    print(f"[-] Pasando a la siguiente página de {termino}...")
                    await boton_siguiente.click()
                    await page.wait_for_load_state("networkidle")
                    numero_pagina += 1
                    await page.wait_for_timeout(2000) 
                else:
                    print(f"[+] Fin de los resultados para: {termino}")
                    break 

        df = pd.DataFrame(productos_extraidos)
        df.to_csv(FILE_OUTPUT, index=False, encoding="utf-8-sig")
        
        print(f"\n[+] PIPELINE COMPLETADO EXITOSAMENTE")
        print(f"[+] Total de registros 100% VÁLIDOS extraídos: {len(productos_extraidos)}")
        print(f"[+] Archivo unificado listo en: {FILE_OUTPUT}")
        
        await browser.close()

if __name__ == "__main__":
    asyncio.run(extraer_datos_computron())