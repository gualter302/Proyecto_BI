"""
05_reporte_analitico.py  —  Ejecuta los KPIs y las consultas analíticas del DW
y muestra los resultados reales (base para los hallazgos del E4).
"""
import os
import psycopg2

BASE = os.path.dirname(os.path.abspath(__file__))
PG = dict(host=os.environ.get("PG_HOST", "localhost"), port=os.environ.get("PG_PORT", "5433"),
          dbname=os.environ.get("PG_DB", "bi_hardware"), user=os.environ.get("PG_USER", "bi_user"),
          password=os.environ.get("PG_PASS", "bi_pass_2026"))


def q(cur, sql):
    cur.execute(sql)
    cols = [d[0] for d in cur.description]
    return cols, cur.fetchall()


def show(titulo, cols, rows):
    print("\n" + "=" * 70)
    print("  " + titulo)
    print("=" * 70)
    print("  " + " | ".join(cols))
    for r in rows:
        print("  " + " | ".join(str(x) for x in r))


def main():
    conn = psycopg2.connect(**PG)
    cur = conn.cursor()
    # crear/actualizar vistas KPI
    with open(os.path.join(BASE, "04_kpis.sql"), encoding="utf-8") as f:
        cur.execute(f.read())
    conn.commit()
    print("[OK] Vistas KPI creadas.")

    show("PRINCIPAL — tienda más barata por modelo (muestra)", *q(cur, """
        SELECT categoria, clave_canonica, tienda_mas_barata, menor_precio_usd
        FROM vw_kpi_menor_precio_modelo ORDER BY menor_precio_usd DESC LIMIT 8"""))

    show("SEC1 — brecha promedio máx-mín y # modelos", *q(cur, """
        SELECT ROUND(AVG(brecha_pct),1) AS brecha_prom_pct, COUNT(*) AS modelos
        FROM vw_kpi_brecha_modelo"""))

    show("SEC2 — ranking global de tiendas más competitivas", *q(cur, """
        SELECT nombre_tienda, SUM(veces_mas_barata) AS veces_mas_barata
        FROM vw_kpi_tienda_competitiva GROUP BY nombre_tienda
        ORDER BY veces_mas_barata DESC"""))

    show("SEC3 — índice de nivel de precios por tienda (menor=más barata)", *q(cur, """
        WITH prom AS (
          SELECT t.nombre_tienda, p.categoria, AVG(f.precio_usd) precio_prom
          FROM fact_precios f JOIN dim_producto p ON f.id_producto=p.id_producto
          JOIN dim_tienda t ON f.id_tienda=t.id_tienda WHERE p.identificado
          GROUP BY t.nombre_tienda,p.categoria),
        rk AS (SELECT nombre_tienda,categoria,
               DENSE_RANK() OVER (PARTITION BY categoria ORDER BY precio_prom) rank_barato
               FROM prom)
        SELECT nombre_tienda, ROUND(AVG(rank_barato),2) indice, COUNT(*) cats
        FROM rk GROUP BY nombre_tienda ORDER BY indice"""))

    show("SEC4 — ahorro potencial promedio", *q(cur, """
        SELECT ROUND(AVG(ahorro_pct),1) AS ahorro_prom_pct, COUNT(*) modelos
        FROM vw_kpi_ahorro_potencial"""))

    show("KPI5 — precio promedio por categoría (todas las tiendas)", *q(cur, """
        SELECT p.categoria, COUNT(*) n, ROUND(AVG(f.precio_usd),2) prom,
               ROUND(MIN(f.precio_usd),2) minimo, ROUND(MAX(f.precio_usd),2) maximo
        FROM fact_precios f JOIN dim_producto p ON f.id_producto=p.id_producto
        GROUP BY p.categoria ORDER BY prom DESC"""))

    show("KPI6 — cobertura de identificación por categoría", *q(cur, """
        SELECT categoria, total_ofertas, ofertas_identificadas, cobertura_pct
        FROM vw_kpi_cobertura ORDER BY cobertura_pct DESC"""))

    show("KPI7 — outliers detectados (IQR)", *q(cur, """
        SELECT COUNT(*) AS n_outliers FROM vw_kpi_outliers"""))
    show("KPI7 — outliers extremos (top)", *q(cur, """
        SELECT categoria, clave_canonica, nombre_tienda, precio_usd
        FROM vw_kpi_outliers ORDER BY precio_usd DESC LIMIT 5"""))

    # Datos para la encuesta (fuente propia) cruzada — contexto de negocio
    conn.close()


if __name__ == "__main__":
    main()
