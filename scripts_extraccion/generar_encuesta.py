"""
generar_encuesta.py  —  Fuente Propia (Bloque D del entregable).

============================  METODOLOGIA  ==================================
  Instrumento : Encuesta estructurada (formulario en linea tipo Google Forms)
  Objetivo    : Conocer habitos de compra de hardware de PC en Ecuador para
                contextualizar el comparador de precios (presupuesto tipico,
                categoria de mayor interes, tienda y canal habitual).
  Poblacion   : Estudiantes y profesionales de tecnologia del Ecuador.
  Muestreo    : No probabilistico por conveniencia (difusion en redes y aulas).
  Recoleccion : Respuestas anonimas; NO se solicita nombre, correo, telefono
                ni cedula -> anonimizacion desde el origen (consideracion etica).
  Identificador: Se asigna un codigo anonimo secuencial (ENC-XXXX) que NO
                permite reidentificar a la persona.

  CAMPOS DEL INSTRUMENTO:
    id_anonimo, fecha_respuesta, ciudad, rango_edad, ocupacion,
    categoria_interes, presupuesto_usd, marca_preferida, canal_preferido,
    tienda_habitual, frecuencia_compra_anual, importancia_precio(1-5)
=============================================================================

NOTA: este script genera un conjunto de respuestas de muestra ANONIMIZADO
para que el pipeline corra de extremo a extremo. Debe reemplazarse/ampliarse
con las respuestas reales recolectadas por el equipo (export del formulario).
Se incluyen algunos campos vacios a proposito (realismo) para ejercitar los
controles de calidad de la capa Staging.
"""
import os
import sys
import csv
import json
import random
from datetime import datetime, timedelta

PROYECTO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_PROPIA_DIR = os.path.join(PROYECTO_DIR, "raw", "fuente_propia")

random.seed(2026)  # reproducibilidad

CIUDADES   = ["Guayaquil", "Quito", "Cuenca", "Manta", "Machala", "Ambato", "Loja", "Santa Elena"]
EDADES     = ["18-24", "25-34", "35-44", "45+"]
OCUPACION  = ["Estudiante", "Profesional TI", "Gamer", "Disenador", "Docente", "Otro"]
CATEGORIAS = ["CPU", "GPU", "RAM", "SSD", "Monitor", "Periferico"]
MARCAS = {
    "CPU": ["AMD", "Intel"], "GPU": ["NVIDIA", "AMD", "Intel"],
    "RAM": ["Corsair", "Kingston", "G.Skill", "TeamGroup"],
    "SSD": ["Samsung", "Kingston", "WD", "Crucial"],
    "Monitor": ["LG", "Samsung", "Asus", "Acer"],
    "Periferico": ["Logitech", "Razer", "HyperX", "Redragon"],
}
CANAL      = ["Online", "Tienda fisica", "Ambos"]
TIENDAS    = ["Computron", "Tecnosmart", "MTEC", "NomadaWare", "TecnoGame", "CompuGamer", "Otra"]
FRECUENCIA = ["1-2", "3-5", "6+"]

INSTRUMENTO = {
    "titulo": "Encuesta de habitos de compra de hardware de PC en Ecuador",
    "anonimo": True,
    "preguntas": [
        {"campo": "ciudad", "pregunta": "Ciudad de residencia", "tipo": "opcion"},
        {"campo": "rango_edad", "pregunta": "Rango de edad", "tipo": "opcion"},
        {"campo": "ocupacion", "pregunta": "Ocupacion", "tipo": "opcion"},
        {"campo": "categoria_interes", "pregunta": "Componente que mas te interesa comprar", "tipo": "opcion"},
        {"campo": "presupuesto_usd", "pregunta": "Presupuesto aproximado (USD)", "tipo": "numerico"},
        {"campo": "marca_preferida", "pregunta": "Marca preferida para ese componente", "tipo": "opcion"},
        {"campo": "canal_preferido", "pregunta": "Canal de compra preferido", "tipo": "opcion"},
        {"campo": "tienda_habitual", "pregunta": "Tienda donde sueles comprar", "tipo": "opcion"},
        {"campo": "frecuencia_compra_anual", "pregunta": "Compras de hardware al ano", "tipo": "opcion"},
        {"campo": "importancia_precio", "pregunta": "Importancia del precio (1=baja, 5=alta)", "tipo": "escala"},
    ],
}

N_RESPUESTAS = 120


def generar():
    os.makedirs(RAW_PROPIA_DIR, exist_ok=True)
    fecha = datetime.now().strftime("%Y-%m-%d")

    # Guardar el instrumento (documentacion del formulario)
    ruta_instr = os.path.join(RAW_PROPIA_DIR, "instrumento_encuesta.json")
    with open(ruta_instr, "w", encoding="utf-8") as f:
        json.dump(INSTRUMENTO, f, indent=2, ensure_ascii=False)

    campos = ["id_anonimo", "fecha_respuesta", "ciudad", "rango_edad", "ocupacion",
              "categoria_interes", "presupuesto_usd", "marca_preferida",
              "canal_preferido", "tienda_habitual", "frecuencia_compra_anual",
              "importancia_precio"]

    filas = []
    base = datetime.now() - timedelta(days=14)
    for i in range(1, N_RESPUESTAS + 1):
        cat = random.choice(CATEGORIAS)
        f_resp = (base + timedelta(days=random.randint(0, 14),
                                   hours=random.randint(0, 23))).strftime("%Y-%m-%d %H:%M")
        # Presupuesto coherente con la categoria
        rango = {"CPU": (120, 700), "GPU": (200, 1500), "RAM": (40, 250),
                 "SSD": (35, 300), "Monitor": (120, 700), "Periferico": (15, 200)}[cat]
        presupuesto = round(random.uniform(*rango), 2)

        fila = {
            "id_anonimo":               f"ENC-{i:04d}",
            "fecha_respuesta":          f_resp,
            "ciudad":                   random.choice(CIUDADES),
            "rango_edad":               random.choice(EDADES),
            "ocupacion":                random.choice(OCUPACION),
            "categoria_interes":        cat,
            "presupuesto_usd":          presupuesto,
            "marca_preferida":          random.choice(MARCAS[cat]),
            "canal_preferido":          random.choice(CANAL),
            "tienda_habitual":          random.choice(TIENDAS),
            "frecuencia_compra_anual":  random.choice(FRECUENCIA),
            "importancia_precio":       random.randint(1, 5),
        }
        # Nulos realistas (~6% en presupuesto, ~3% en ciudad) para QA en staging
        if random.random() < 0.06:
            fila["presupuesto_usd"] = ""
        if random.random() < 0.03:
            fila["ciudad"] = ""
        filas.append(fila)

    ruta = os.path.join(RAW_PROPIA_DIR, f"encuesta_hardware_{fecha}.csv")
    with open(ruta, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=campos)
        w.writeheader()
        w.writerows(filas)

    print(f"[ENCUESTA] Instrumento: {ruta_instr}")
    print(f"[ENCUESTA] {len(filas)} respuestas anonimas -> {ruta}")
    print(f"[ENCUESTA] Campos: {len(campos)}  | Registros unicos por id_anonimo: {len(set(r['id_anonimo'] for r in filas))}")
    return ruta


if __name__ == "__main__":
    generar()
