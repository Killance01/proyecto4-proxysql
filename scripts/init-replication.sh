#!/usr/bin/env bash
# Crea usuarios en el maestro y enlaza los esclavos (dump + posicion del binlog).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

SLAVES="${SLAVES:-mysql-slave1 mysql-slave2}"
DUMP=/tmp/master.sql

mysql_in() {
  local c=$1; shift
  docker exec -i -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$c" mysql -uroot "$@"
}
wait_mysql() {
  until docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$1" \
      mysqladmin ping -h127.0.0.1 -uroot --silent >/dev/null 2>&1; do
    echo "Esperando a $1..."; sleep 3
  done
}

for c in mysql-master $SLAVES; do wait_mysql "$c"; done

mysql_in mysql-master <<SQL
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PASSWORD}';
CREATE USER IF NOT EXISTS '${REPL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPL_PASSWORD}';
CREATE USER IF NOT EXISTS '${MONITOR_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${MONITOR_PASSWORD}';
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
CREATE DATABASE IF NOT EXISTS sbtest;
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
GRANT ALL PRIVILEGES ON sbtest.* TO '${MYSQL_USER}'@'%';
GRANT REPLICATION SLAVE ON *.* TO '${REPL_USER}'@'%';
GRANT USAGE, REPLICATION CLIENT ON *.* TO '${MONITOR_USER}'@'%';
FLUSH PRIVILEGES;
SQL

docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql-master mysqldump -uroot \
  --single-transaction --source-data=2 --flush-privileges --all-databases > "$DUMP"
LOG_FILE=$(sed -n "s/.*SOURCE_LOG_FILE='\([^']*\)'.*/\1/p" "$DUMP" | head -1)
LOG_POS=$(sed -n "s/.*SOURCE_LOG_POS=\([0-9]*\).*/\1/p" "$DUMP" | head -1)
[ -n "$LOG_FILE" ] || { echo "No se leyo la posicion del binlog (mysqldump antiguo? usa --master-data=2)"; exit 1; }
echo "Posicion del binlog: $LOG_FILE $LOG_POS"

for S in $SLAVES; do
  echo "Configurando $S..."
  mysql_in "$S" -e "SET GLOBAL super_read_only=0; SET GLOBAL read_only=0; STOP REPLICA; RESET REPLICA ALL;"
  mysql_in "$S" < "$DUMP"
  mysql_in "$S" <<SQL
CHANGE REPLICATION SOURCE TO SOURCE_HOST='mysql-master', SOURCE_USER='${REPL_USER}', SOURCE_PASSWORD='${REPL_PASSWORD}', SOURCE_LOG_FILE='${LOG_FILE}', SOURCE_LOG_POS=${LOG_POS}, GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
SET GLOBAL read_only=1; SET GLOBAL super_read_only=1;
SQL
done

sleep 3
for S in $SLAVES; do
  echo "== $S"
  mysql_in "$S" -e "SHOW REPLICA STATUS\G" | grep -E "Replica_IO_Running:|Replica_SQL_Running:|Seconds_Behind_Source|Last_(IO|SQL)_Error:"
done
