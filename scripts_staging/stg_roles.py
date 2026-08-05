"""
stg_roles.py  —  Clasificacion de productos (categoria + clave canonica).

Transformacion exigida: "Asignacion de categorias globales mediante tokens
o keywords".

En este proyecto de comparacion de precios, el equivalente a "clasificar
roles" es:
  1. Confirmar/ajustar la CATEGORIA del producto por keywords.
  2. Generar una CLAVE_CANONICA (modelo homologado) que permita comparar el
     MISMO producto entre tiendas distintas. Ej:
       "PROCESADOR AMD RYZEN 5 8500G AM5 3.5GHZ" -> "amd ryzen 5 8500g"
       "Procesador AMD Ryzen 5 8500G con graficos" -> "amd ryzen 5 8500g"
   Esa clave es la que habilita el analisis "donde esta mas barato".

CPU y GPU tienen un numero de modelo con formato fijo (ver TOKENS) y se
canonizan por coincidencia de patron. RAM/SSD/Monitor/Periferico no tienen
un formato de titulo unico entre tiendas, asi que se canonizan combinando
marca + especificaciones clave detectadas en el texto (capacidad, DDR/
velocidad para RAM; capacidad/interfaz para SSD; codigo de modelo para
Monitor; tipo+codigo de modelo para Periferico). Cuando no se detectan
suficientes señales para identificar el producto con confianza, se deja
'sin_clasificar' -> no se compara (evita falsos emparejamientos).
"""
import re
import pandas as pd

# Tokens de MODELO (con numero) por categoria para CPU/GPU.
TOKENS = {
    "CPU": [
        r"ryzen\s*\d+\s*\d{3,4}\s*x?\d*\w*",      # ryzen 9 9950x3d
        r"core\s*ultra\s*\d+\s*\d{3}\w*",          # core ultra 7 265kf
        r"core\s*i[3579][- ]?\d{4,5}\w*",          # core i7-14700k
        r"xeon\s*\w*\d{3,4}\w*",
    ],
    "GPU": [
        r"rtx\s*\d{4}\s*(ti\s*)?(super\s*)?\d*\s*gb?",  # rtx 5070 ti / rtx 5090 32gb
        r"rtx\s*\d{4}\s*(ti|super)?",
        r"gtx\s*\d{3,4}\s*(ti)?",
        r"rx\s*\d{3,4}\s*(xt)?\w*",                # rx 7800 xt
        r"arc\s*[ab]\d{3,4}",
    ],
}

# Claves demasiado genericas que NO identifican un producto unico -> rechazar.
GENERICAS = {"core", "ryzen", "rtx", "gtx", "rx", "ddr5", "ddr4", "ddr3",
             "nvme", "sata", "1tb", "2tb", "4tb", "ips", "va", "oled", "arc"}


def _extraer_clave_cpu_gpu(txt: str, categoria: str) -> str:
    for patron in TOKENS.get(categoria, []):
        m = re.search(patron, txt)
        if m:
            clave = re.sub(r"\s+", " ", m.group()).strip()
            if clave in GENERICAS or not re.search(r"\d", clave):
                continue
            return clave
    return "sin_clasificar"


# ── RAM ──────────────────────────────────────────────────────────────
_RAM_MARCAS = ["kingston", "corsair", "hyperx", "xpg", "adata", "mushkin",
               "patriot", "teamgroup", "team group", "g.skill", "gskill",
               "hiksemi", "crucial", "acer", "hp"]
_RAM_LINEAS = ["fury", "vengeance", "valueram", "value", "lancer", "caster",
               "spectrix", "ripjaws", "trident", "predator"]


def _clave_ram(txt: str) -> str:
    marca = next((m for m in _RAM_MARCAS if re.search(rf"\b{re.escape(m)}\b", txt)), None)
    cap = re.search(r"\b(\d{1,3})\s*gb\b", txt)
    if not marca or not cap:
        return "sin_clasificar"
    partes = [marca.replace(" ", ""), f"{cap.group(1)}gb"]
    ddr = re.search(r"\bddr[345]\b", txt)
    if ddr:
        partes.append(ddr.group())
    if re.search(r"so-?dimm", txt):
        partes.append("sodimm")
    linea = next((l for l in _RAM_LINEAS if re.search(rf"\b{re.escape(l)}\b", txt)), None)
    if linea:
        partes.append(linea)
    mhz = re.search(r"\b(\d{3,5})\s*(mhz|mts|mt/s)\b", txt)
    if mhz:
        partes.append(f"{mhz.group(1)}mhz")
    return " ".join(partes)


# ── SSD ──────────────────────────────────────────────────────────────
_SSD_MARCAS = ["adata", "xpg", "hiksemi", "kingston", "corsair", "crucial",
               "samsung", "western digital", "wd", "seagate", "hp", "lenovo",
               "msi", "indilinx", "dato", "teamgroup"]


def _clave_ssd(txt: str) -> str:
    cap = re.search(r"\b(\d{1,4})\s*(gb|tb)\b", txt)
    if re.search(r"\bnvme\b|m\.2|\bm2\b", txt):
        partes.append("nvme")
    elif re.search(r"\bsata\b", txt):
        partes.append("sata")
    if re.search(r"\bext(erno)?\b|\bexternal\b", txt):
        partes.append("ext")
    return " ".join(partes)


# ── Monitor ──────────────────────────────────────────────────────────
_MONITOR_MARCAS = ["lg", "gigabyte", "asus", "teros", "msi", "samsung",
                    "xtratech", "indurama", "acer", "asrock", "corsair",
                    "boetec", "thunderobot", "xiaomi", "armaggeddon",
                    "cooler master", "benq", "rca", "env"]

_RUIDO_MONITOR = re.compile(
    r"\b\d{3,4}\s*[x×]\s*\d{3,4}\b|"
    r"\b\d{2,3}[\s-]*hz\b|"
    r"\b\d(\.\d)?[\s-]*ms\b|"
    r"\b\d{2}(\.\d)?\s*(\"|″|pulg\w*)\b|"
    r"\b(fhd|qhd|uhd|4k|2k|1080p|1440p|hd\+?|wqhd|full\s*hd|quad\s*hd|ultra\s*wide|ultrawide)\b|"
    r"\b(ips|va|tn|oled|qd-oled|ss\s*ips)\b|"
    r"\b(hdmi\w*|dp|vga|usb\w*|display\s*port)\b|"
    r"\b(rgb|gtg|mprt|hdr\d*|srgb|freesync\w*|g-?sync\w*|adaptive\s*sync|nits?)\b|"
    r"\b(curvo|curve|gaming|gamer|plano|led|lcd|negro|black|white|blanco|azul|blue|"
    r"non-glare|modelo)\b"
)


def _candidatos_modelo(limpio: str) -> list[str]:
    """Tokens alfanumericos que parecen codigo de modelo: mezcla letras+digitos
    (>=2 digitos, al menos 1 letra), sin exigir que empiecen con letra (el
    tamaño de pantalla suele ir pegado al codigo, ej. '24g411a-b')."""
    return [t for t in re.findall(r"[a-z0-9][a-z0-9-]{2,14}", limpio)
            if len(re.findall(r"\d", t)) >= 2 and re.search(r"[a-z]", t)]


def _clave_monitor(txt: str) -> str:
    marca = next((m for m in _MONITOR_MARCAS if re.search(rf"\b{re.escape(m)}\b", txt)), None)
    if not marca:
        return "sin_clasificar"
    limpio = _RUIDO_MONITOR.sub(" ", txt)
    limpio = re.sub(rf"\b{re.escape(marca)}\b", " ", limpio)
    candidatos = _candidatos_modelo(limpio)
    if not candidatos:
        return "sin_clasificar"
    modelo = max(candidatos, key=len)
    return f"{marca.replace(' ', '')} {modelo}"


# ── Periferico ───────────────────────────────────────────────────────
_PERIF_MARCAS = ["logitech", "corsair", "razer", "hyperx", "redragon", "primus",
                  "klip xtreme", "genius", "quasad", "ezmi", "xtech", "xtratech",
                  "targus", "manhattan", "gamdias", "alcatroz", "armaggeddon",
                  "thunderobot", "cougar", "steelseries", "marvo", "xtrike me",
                  "evil pc", "msi", "meetion", "glorious", "trust", "jbl",
                  "asus", "hp", "lenovo", "cooler master", "env"]

_RUIDO_PERIF = re.compile(
    r"\b(teclado|keyboard|mouse|rat[oó]n|audifono|audifonos|auricular|auriculares|"
    r"headset|headsets|diadema)\b|"
    r"\b(gamer|gaming|mecanico|mecanica|mechanical|inalambrico|inalambricos|"
    r"alambrico|alambricos|wireless|wired|usb\w*|bluetooth|rgb|retroiluminado|"
    r"ergonomico|dpi|hz|switch|negro|blanco|black|white|gris|azul|blue|combo|kit|"
    r"edition|pro|plus|mini|magnetic|optical|optico|multimedia|espanol|english|ingles)\b"
)


def _tipo_periferico(txt: str) -> str | None:
    es_teclado = bool(re.search(r"\bteclado\b|\bkeyboard\b", txt))
    es_mouse = bool(re.search(r"\bmouse\b|\brat[oó]n\b", txt))
    es_audio = bool(re.search(r"\baudifono\w*|auricular\w*|headset\w*|\bdiadema\b", txt))
    if sum([es_teclado, es_mouse, es_audio]) >= 2:
        return "combo"
    if es_teclado:
        return "teclado"
    if es_mouse:
        return "mouse"
    if es_audio:
        return "audifonos"
    return None


def _clave_periferico(txt: str) -> str:
    tipo = _tipo_periferico(txt)
    marca = next((m for m in _PERIF_MARCAS if re.search(rf"\b{re.escape(m)}\b", txt)), None)
    if not tipo or not marca:
        return "sin_clasificar"
    limpio = _RUIDO_PERIF.sub(" ", txt)
    limpio = re.sub(rf"\b{re.escape(marca)}\b", " ", limpio)
    candidatos = _candidatos_modelo(limpio)
    if not candidatos:
        return "sin_clasificar"
    modelo = max(candidatos, key=len)
    return f"{marca.replace(' ', '')} {tipo} {modelo}"


_EXTRACTORES = {
    "RAM": _clave_ram,
    "SSD": _clave_ssd,
    "MONITOR": _clave_monitor,
    "PERIFERICO": _clave_periferico,
}


def extraer_clave_canonica(nombre: str, categoria: str) -> str:
    """Genera la clave canonica homologada para las 6 categorias del proyecto."""
    if not nombre or pd.isna(nombre):
        return "sin_clasificar"
    txt = re.sub(r"\(.*?\)|\[.*?\]", " ", str(nombre).lower())
    txt = re.sub(r"\s+", " ", txt).strip()

    cat = str(categoria).upper()
    if cat in TOKENS:
        return _extraer_clave_cpu_gpu(txt, cat)
    extractor = _EXTRACTORES.get(cat)
    if extractor:
        return extractor(txt)
    return "sin_clasificar"


def clasificar(df: pd.DataFrame) -> pd.DataFrame:
    df["clave_canonica"] = df.apply(
        lambda r: extraer_clave_canonica(r["producto"], r["categoria"]), axis=1
    )
    return df
