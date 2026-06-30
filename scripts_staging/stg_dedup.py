"""
stg_dedup.py  —  Deduplicacion integral.

Transformacion exigida: "Criterio tecnico unificado mediante claves primarias
compuestas".

Clave primaria compuesta de una oferta unica:
    (tienda + categoria + clave_canonica + precio_usd)

Una misma busqueda en distintas categorias (p.ej. un combo que aparece tanto
en 'mouse' como en 'teclado') puede traer el mismo producto/precio repetido.
Estrategia: conservar el registro MAS COMPLETO (el que tiene menos nulos).

Este modulo delega en controles_calidad.control_duplicados() para mantener
el criterio en un solo lugar y devolver metricas.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "calidad"))
from controles_calidad import control_duplicados


def deduplicar(df):
    """Retorna (df_sin_duplicados, metricas)."""
    return control_duplicados(df)
