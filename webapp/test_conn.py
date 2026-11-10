import os

import pymysql

try:
    conn = pymysql.connect(
        host=os.getenv("DB_HOST", "127.0.0.1"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "app_user"),
        password=os.getenv("DB_PASSWORD", "app_password"),
        database=os.getenv("DB_NAME", "db_proyectofinal"),
        connect_timeout=10, read_timeout=10, write_timeout=10,
    )
    with conn.cursor() as cursor:
        cursor.execute("SELECT @@hostname AS nodo;")
        print("Conexion exitosa. Atendido por:", cursor.fetchone())
    conn.close()
except Exception as e:
    print("Error de conexion detallado:", e)
