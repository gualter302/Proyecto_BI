# config_tiendas.py
# ---------------------------------------------------------------------------
# Configuracion de las 6 tiendas ecuatorianas a scrapear.
# Todas operan en USD (Ecuador usa dolar estadounidense).
#
# La extraccion se hace por BUSQUEDA de palabra clave restringida a productos
# (post_type=product en WooCommerce), una busqueda por cada categoria.
# Los selectores fueron verificados en vivo con sondeo_v2.py.
# ---------------------------------------------------------------------------

# Categorias del proyecto -> palabras clave de busqueda en cada tienda.
# (Una categoria puede tener varias busquedas, p.ej. perifericos.)
CATEGORIAS = {
    "CPU":        ["procesador"],
    "GPU":        ["tarjeta de video"],
    "RAM":        ["memoria ram"],
    "SSD":        ["disco solido ssd"],
    "Monitor":    ["monitor"],
    "Periferico": ["teclado", "mouse", "audifonos"],
}

# Lista blanca: palabras que validan que el producto pertenece a la categoria.
# Filtra ruido del buscador (accesorios, cables, fundas que no son hardware).
FILTRO_CATEGORIA = {
    "CPU":        ["procesador", "ryzen", "core", "intel", "amd", "xeon", "pentium", "celeron"],
    "GPU":        ["tarjeta", "video", "grafica", "rtx", "gtx", "rx ", "radeon", "geforce", "arc"],
    "RAM":        ["memoria", "ram", "ddr3", "ddr4", "ddr5", "dimm", "sodimm"],
    "SSD":        ["ssd", "solido", "nvme", "m.2", "m2", "disco"],
    "Monitor":    ["monitor", "pantalla", "display", "led", "ips", "hz"],
    "Periferico": ["teclado", "keyboard", "mouse", "raton", "audifono", "auricular", "headset", "diadema"],
}

# Estandar WooCommerce (sirve para 5 de las 6 tiendas).
_WOO = {
    "contenedor":     "li.product",
    "sel_nombre":     "h2.woocommerce-loop-product__title, h3.wd-entities-title, .woocommerce-loop-product__title",
    "sel_precio":     "span.price",
    "sel_url":        "a",
    "sel_siguiente":  "a.next.page-numbers",
}

TIENDAS = [
    {
        "nombre":        "Computron",
        "pais":          "Ecuador",
        "moneda":        "USD",
        "url_busqueda":  "https://www.computron.com.ec/?s={kw}&post_type=product",
        "contenedor":    "div.meta-wrapper",
        "sel_nombre":    "h3.heading-title.product-name",
        "sel_precio":    "span.price",
        "sel_url":       "a",
        "sel_siguiente": "a.next.page-numbers",
    },
    {
        "nombre":        "Tecnosmart",
        "pais":          "Ecuador",
        "moneda":        "USD",
        "url_busqueda":  "https://www.tecnosmart.com.ec/?s={kw}&post_type=product",
        "contenedor":    "div.product-grid-item",
        "sel_nombre":    "h3.wd-entities-title",
        "sel_precio":    "span.price",
        "sel_url":       "a",
        "sel_siguiente": "a.next.page-numbers",
    },
    {
        "nombre":        "MTEC",
        "pais":          "Ecuador",
        "moneda":        "USD",
        "url_busqueda":  "https://mtec-ec.com/?s={kw}&post_type=product",
        **_WOO,
    },
    {
        "nombre":        "NomadaWare",
        "pais":          "Ecuador",
        "moneda":        "USD",
        "url_busqueda":  "https://nomadaware.com.ec/?s={kw}&post_type=product",
        **_WOO,
    },
    {
        "nombre":        "TecnoGame",
        "pais":          "Ecuador",
        "moneda":        "USD",
        "url_busqueda":  "https://tecnogame.ec/?s={kw}&post_type=product",
        **_WOO,
    },
    {
        "nombre":        "CompuGamer",
        "pais":          "Ecuador",
        "moneda":        "USD",
        "url_busqueda":  "https://compugamer.com.ec/?s={kw}&post_type=product",
        **_WOO,
    },
]
