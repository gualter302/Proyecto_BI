# config_tiendas.py
# Categorias: CPU | GPU | RAM | SSD | Monitor | Periferico
# Configuracion inicial: 4 tiendas internacionales de distintas regiones/monedas.
# Los selectores CSS pueden necesitar ajuste si la tienda cambia su HTML.
#
# [!] HALLAZGO (verificacion con Playwright):
#     - PCComponentes y Scan devuelven HTTP 403 (proteccion anti-bot).
#     - CanadaComputers da timeout de conexion.
#     - Solo Newegg responde (200). Con una sola tienda no hay comparacion.
#     => Se evaluara migrar a tiendas ECUATORIANAS (ver commit siguiente).

CONFIGURACIONES = [
    {
        "nombre": "Newegg",
        "moneda": "USD",
        "pais": "EE.UU.",
        "tipo_tienda": "Tienda especializada",
        "url_base": "https://www.newegg.com",
        "contenedor": "div.item-cell",
        "nombre_selector": "a.item-title",
        "precio_selector": "li.price-current",
        "selector_siguiente": "button.btn-icon-right",
        "categorias": {
            "cpu":    {"urls": ["https://www.newegg.com/Desktop-CPU-Processor/SubCategory/ID-343"], "categoria_producto": "CPU"},
            "gpu":    {"urls": ["https://www.newegg.com/GPUs-Video-Graphics-Cards/SubCategory/ID-48"], "categoria_producto": "GPU"},
            "ram":    {"urls": ["https://www.newegg.com/Desktop-Memory/SubCategory/ID-147"], "categoria_producto": "RAM"},
            "ssd":    {"urls": ["https://www.newegg.com/Internal-SSDs/SubCategory/ID-636"], "categoria_producto": "SSD"},
            "monitor":{"urls": ["https://www.newegg.com/Computer-Monitor/SubCategory/ID-20"], "categoria_producto": "Monitor"},
        },
    },
    {
        "nombre": "PCComponentes",
        "moneda": "EUR",
        "pais": "Espana",
        "tipo_tienda": "Tienda especializada",
        "url_base": "https://www.pccomponentes.com",
        "contenedor": "article.c-product-card",
        "nombre_selector": "a.c-product-card__title",
        "precio_selector": "span.c-pvp-main",
        "selector_siguiente": "a[rel='next']",
        "categorias": {
            "cpu":    {"urls": ["https://www.pccomponentes.com/procesadores"], "categoria_producto": "CPU"},
            "gpu":    {"urls": ["https://www.pccomponentes.com/tarjetas-graficas"], "categoria_producto": "GPU"},
            "ram":    {"urls": ["https://www.pccomponentes.com/memorias-ram"], "categoria_producto": "RAM"},
            "ssd":    {"urls": ["https://www.pccomponentes.com/discos-ssd"], "categoria_producto": "SSD"},
            "monitor":{"urls": ["https://www.pccomponentes.com/monitores"], "categoria_producto": "Monitor"},
        },
    },
    {
        "nombre": "Scan",
        "moneda": "GBP",
        "pais": "Reino Unido",
        "tipo_tienda": "Tienda especializada",
        "url_base": "https://www.scan.co.uk",
        "contenedor": "li.product",
        "nombre_selector": "a.description",
        "precio_selector": "span.price",
        "selector_siguiente": "a.next",
        "categorias": {
            "cpu":    {"urls": ["https://www.scan.co.uk/shop/computer-hardware/cpu-intel-and-amd/all"], "categoria_producto": "CPU"},
            "gpu":    {"urls": ["https://www.scan.co.uk/shop/computer-hardware/gpu-nvidia-and-amd/all"], "categoria_producto": "GPU"},
            "ram":    {"urls": ["https://www.scan.co.uk/shop/computer-hardware/desktop-ram/all"], "categoria_producto": "RAM"},
            "ssd":    {"urls": ["https://www.scan.co.uk/shop/computer-hardware/ssd-drives-3-5-and-2-5-nvme-m2/all"], "categoria_producto": "SSD"},
            "monitor":{"urls": ["https://www.scan.co.uk/shop/monitors-and-displays/gaming/all"], "categoria_producto": "Monitor"},
        },
    },
    {
        "nombre": "CanadaComputers",
        "moneda": "CAD",
        "pais": "Canada",
        "tipo_tienda": "Tienda especializada",
        "url_base": "https://www.canadacomputers.com",
        "contenedor": "div.product-item",
        "nombre_selector": "div.product-item__title",
        "precio_selector": "span.price-visible",
        "selector_siguiente": "a.page-next",
        "categorias": {
            "cpu":    {"urls": ["https://www.canadacomputers.com/index.php?cPath=4_197"], "categoria_producto": "CPU"},
            "gpu":    {"urls": ["https://www.canadacomputers.com/index.php?cPath=27_1063"], "categoria_producto": "GPU"},
            "ram":    {"urls": ["https://www.canadacomputers.com/index.php?cPath=4_719"], "categoria_producto": "RAM"},
            "ssd":    {"urls": ["https://www.canadacomputers.com/index.php?cPath=4_755"], "categoria_producto": "SSD"},
            "monitor":{"urls": ["https://www.canadacomputers.com/index.php?cPath=23"], "categoria_producto": "Monitor"},
        },
    },
]
