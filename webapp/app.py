import os

import pymysql
from flask import Flask, jsonify

app = Flask(__name__)

# Conexion al puerto de trafico de ProxySQL. Los valores por defecto sirven para
# correr la app en el host; docker-compose los sobreescribe (proxysql:6033).
DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_USER = os.getenv("DB_USER", "app_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "app_password")
DB_NAME = os.getenv("DB_NAME", "db_proyectofinal")

_table_ready = False


def get_connection():
    return pymysql.connect(
        host=DB_HOST, port=DB_PORT, user=DB_USER, password=DB_PASSWORD,
        database=DB_NAME, connect_timeout=10, read_timeout=10,
        write_timeout=10, autocommit=True,
    )


def run(fn):
    """Ejecuta fn(cursor) en una conexion nueva y responde JSON."""
    try:
        conn = get_connection()
        try:
            with conn.cursor() as cur:
                data = fn(cur)
        finally:
            conn.close()
        return jsonify({"status": "success", **data})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


def ensure_table(cur):
    global _table_ready
    if not _table_ready:
        cur.execute(
            "CREATE TABLE IF NOT EXISTS app_ping ("
            "id INT AUTO_INCREMENT PRIMARY KEY, nota VARCHAR(100), "
            "creado TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"
        )
        _table_ready = True


@app.route("/")
def index():
    return "Aplicacion Flask conectada al cluster MySQL via ProxySQL"


@app.route("/test-db")
def test_db():
    # "SELECT @@..." coincide con la regla 2 -> siempre atiende el maestro
    def q(cur):
        cur.execute("SELECT @@hostname AS nodo_servidor")
        return {"servidor_atendiendo": cur.fetchone()[0]}
    return run(q)


@app.route("/write")
def write():
    # INSERT -> regla 5 -> hostgroup 10 (maestro)
    def q(cur):
        ensure_table(cur)
        cur.execute("INSERT INTO app_ping (nota) VALUES ('desde la app')")
        new_id = cur.lastrowid
        cur.execute("SELECT @@hostname AS nodo")  # regla 2 -> mismo maestro
        return {"id_insertado": new_id, "escrito_en": cur.fetchone()[0]}
    return run(q)


@app.route("/read")
def read():
    # "SELECT COUNT..." -> regla 4 -> hostgroup 20 (esclavo).
    # Si falla porque la tabla no existe, llama primero a /write.
    def q(cur):
        cur.execute("SELECT COUNT(*) AS total, @@hostname AS nodo FROM app_ping")
        total, nodo = cur.fetchone()
        return {"filas_en_ping": total, "leido_en": nodo}
    return run(q)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000,
            debug=os.getenv("FLASK_DEBUG", "0") == "1")
