"""
iniciar.py  —  Lanzador único del proyecto (Data Warehouse + Dashboard).

Con UN solo comando:
    python iniciar.py

hace todo lo necesario para ver el dashboard funcionando:
  1. Verifica que Docker esté encendido.
  2. Levanta (o crea) el contenedor PostgreSQL del Data Warehouse.
  3. Si la base está vacía, restaura el dump (esquema + datos + vistas KPI).
  4. Carga la serie temporal de tasas (necesaria para el dashboard).
  5. Lanza el dashboard en http://localhost:8501

Requisitos previos: Docker Desktop, Python 3.11+, y
    pip install -r dashboard/requirements.txt

Opción:  python iniciar.py --no-run   (prepara todo pero NO abre el dashboard)
"""
import os
import sys
import time
import subprocess

BASE = os.path.dirname(os.path.abspath(__file__))
CONT = "bi_hardware_dw"
DUMP = os.path.join(BASE, "warehouse", "dump_bi_hardware.sql")

# Parametros del contenedor (host 5433 -> contenedor 5432)
DOCKER_RUN = [
    "docker", "run", "-d", "--name", CONT,
    "-e", "POSTGRES_USER=bi_user",
    "-e", "POSTGRES_PASSWORD=bi_pass_2026",
    "-e", "POSTGRES_DB=bi_hardware",
    "-p", "5433:5432",
    "-v", "bi_hardware_pgdata:/var/lib/postgresql/data",
    "postgres:16",
]


def run(cmd, **kw):
    return subprocess.run(cmd, **kw)


def salida(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()


def paso(n, txt):
    print(f"\n[{n}] {txt}")


def main():
    print("=" * 60)
    print("  INICIANDO: Data Warehouse + Dashboard BI")
    print("=" * 60)

    # 1. Docker encendido?
    paso(1, "Verificando Docker...")
    if run(["docker", "info"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        print("  [!] Docker no responde. Abre Docker Desktop, espera a que arranque")
        print("      y vuelve a ejecutar:  python iniciar.py")
        sys.exit(1)
    print("      Docker OK.")

    # 2. Contenedor: crear / iniciar
    paso(2, "Preparando el contenedor PostgreSQL...")
    existe = CONT in salida(["docker", "ps", "-a", "--format", "{{.Names}}"]).split("\n")
    corriendo = CONT in salida(["docker", "ps", "--format", "{{.Names}}"]).split("\n")
    if not existe:
        print("      Creando contenedor nuevo...")
        run(DOCKER_RUN, stdout=subprocess.DEVNULL)
    elif not corriendo:
        print("      Iniciando contenedor existente...")
        run(["docker", "start", CONT], stdout=subprocess.DEVNULL)
    else:
        print("      Contenedor ya está corriendo.")

    # 3. Esperar a que Postgres acepte conexiones
    paso(3, "Esperando a PostgreSQL...")
    for _ in range(30):
        ok = run(["docker", "exec", CONT, "pg_isready", "-U", "bi_user", "-d", "bi_hardware"],
                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        if ok:
            break
        time.sleep(2)
    print("      PostgreSQL listo.")

    # 4. ¿Hay datos? Si no, restaurar el dump
    paso(4, "Verificando datos del Data Warehouse...")
    n = salida(["docker", "exec", CONT, "psql", "-U", "bi_user", "-d", "bi_hardware",
                "-tAc", "SELECT COUNT(*) FROM fact_precios;"])
    if not n.isdigit() or int(n) == 0:
        print("      Base vacía → restaurando el dump...")
        with open(DUMP, "rb") as f:
            run(["docker", "exec", "-i", CONT, "psql", "-U", "bi_user", "-d", "bi_hardware"],
                stdin=f, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        n = salida(["docker", "exec", CONT, "psql", "-U", "bi_user", "-d", "bi_hardware",
                    "-tAc", "SELECT COUNT(*) FROM fact_precios;"])
    print(f"      fact_precios: {n} registros.")

    # 5. Serie temporal de tasas (el dump no la incluye)
    paso(5, "Cargando serie temporal de tasas...")
    run([sys.executable, os.path.join(BASE, "warehouse", "06_cargar_tasas.py")])

    # 6. Lanzar dashboard
    if "--no-run" in sys.argv:
        print("\n[6] --no-run: todo preparado. Para abrir el dashboard ejecuta:")
        print("      streamlit run dashboard/app.py")
        return
    paso(6, "Lanzando el dashboard en http://localhost:8501 ...")
    print("      (Deja esta ventana abierta. Ctrl+C para detener.)")
    run([sys.executable, "-m", "streamlit", "run", os.path.join(BASE, "dashboard", "app.py")])


if __name__ == "__main__":
    main()
