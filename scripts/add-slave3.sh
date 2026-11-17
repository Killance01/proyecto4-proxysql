#!/usr/bin/env bash
# Incorpora a ProxySQL el tercer esclavo previamente configurado.
# No reinicializa ni vuelve a sembrar sus datos.
set -euo pipefail
cd "$(dirname "$0")/.."

set -a
source .env
set +a

AU="${PROXYSQL_ADMIN_USER:-admin}"
AP="${PROXYSQL_ADMIN_PASSWORD:-admin}"

docker compose up -d --no-deps mysql-slave3

STATUS=$(docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql-slave3 \
  mysql -uroot -e "SHOW REPLICA STATUS\G")

if ! grep -qE 'Replica_IO_Running: Yes' <<< "$STATUS" ||
   ! grep -qE 'Replica_SQL_Running: Yes' <<< "$STATUS" ||
   ! grep -qE 'Seconds_Behind_Source: 0[[:space:]]*$' <<< "$STATUS"; then
  echo "La replica debe estar configurada, activa y sin retraso antes del alta."
  echo "Para preparar exclusivamente una replica nueva:"
  echo "SLAVES=mysql-slave3 bash scripts/init-replication.sh"
  exit 1
fi

READ_ONLY=$(docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql-slave3 \
  mysql -uroot -Nse "SELECT @@global.read_only;")

if [[ "$READ_ONLY" != "1" ]]; then
  echo "Error: mysql-slave3 no esta en modo de solo lectura."
  exit 1
fi

docker exec -i proxysql mysql -u"$AU" -p"$AP" \
  -h127.0.0.1 -P6032 <<'SQL'
INSERT INTO mysql_servers
  (hostgroup_id, hostname, port, weight, max_connections)
SELECT 20, 'mysql-slave3', 3306, 1, 200
WHERE NOT EXISTS (
  SELECT 1 FROM mysql_servers
  WHERE hostgroup_id=20 AND hostname='mysql-slave3' AND port=3306
);
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;

SELECT hostgroup_id, hostname, status
FROM runtime_mysql_servers
ORDER BY hostgroup_id, hostname;
SQL