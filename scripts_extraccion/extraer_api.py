import requests
import pandas as pd
import os

print("[*] Consultando la API de MercadoLibre Ecuador...")

# Buscamos tarjetas RTX 4060 directamente en la base de datos de MercadoLibre
url = "https://api.mercadolibre.com/sites/MEC/search?q=rtx+4060"
respuesta = requests.get(url)
datos = respuesta.json()

productos_extraidos = []

# Filtramos solo lo que nos interesa
for articulo in datos.get('results', []):
    productos_extraidos.append({
        'tienda': 'MercadoLibre',
        'producto': articulo['title'],
        'precio_raw': articulo['price']
    })

# Guardamos en nuestra carpeta datos_crudos
carpeta_destino = 'datos_crudos'
os.makedirs(carpeta_destino, exist_ok=True)
ruta_salida = os.path.join(carpeta_destino, 'precios_mercadolibre.csv')

df = pd.DataFrame(productos_extraidos)
df.to_csv(ruta_salida, index=False, encoding='utf-8-sig')

print(f"[+] ¡Éxito total! {len(productos_extraidos)} productos guardados en {ruta_salida}")