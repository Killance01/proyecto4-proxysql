#!/usr/bin/env bash
# Genera evidencia del cluster en docs/resultados/ (no reinicia contadores).
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
OUT=docs/resultados
APP="localhost:${WEBAPP_PORT:-5000}"
mkdir -p "$OUT"

padmin() {
  docker exec -i proxysql mysql -t -u"${PROXYSQL_ADMIN_USER:-admin}" \
    -p"${PROXYSQL_ADMIN_PASSWORD:-admin}" -h127.0.0.1 -P6032 -e "$1" 2>/dev/null
}
viaproxy() {
  docker exec -i -e MYSQL_PWD="$MYSQL_PASSWORD" mysql-master \
    mysql -t -u"$MYSQL_USER" -hproxysql -P6033 "$MYSQL_DATABASE" -e "$1" 2>/dev/null
}

# 1) Trafico de la app a traves de ProxySQL
{
  echo "# $(date '+%F %T')  /write x3 (INSERT -> maestro)"
  for i in 1 2 3; do curl -s "$APP/write"; echo; done
  echo "# /read x30 (SELECT -> esclavos): conteo por nodo"
  for i in $(seq 1 30); do curl -s "$APP/read"; echo; done \
    | grep -o '"leido_en":"[^"]*"' | sort | uniq -c
} > "$OUT/enrutamiento-app.txt"

# 2) Una consulta por cada tipo de query rule
{
  echo "# $(date '+%F %T')  prueba de query rules (nodo que atiende)"
  echo "-- regla 1: SELECT ... FOR UPDATE (maestro)"
  viaproxy "SELECT 'r1' AS prueba, @@hostname AS nodo FROM app_ping LIMIT 1 FOR UPDATE;"
  echo "-- regla 2: SELECT @@ (maestro)"
  viaproxy "SELECT @@hostname AS nodo;"
  echo "-- regla 3: funcion no determinista (maestro)"
  viaproxy "SELECT NOW() AS ahora, @@hostname AS nodo;"
  echo "-- regla 4: SELECT normal (esclavo)"
  viaproxy "SELECT COUNT(*) AS filas, @@hostname AS nodo FROM app_ping;"
  echo "-- reglas 5, 6, 7 y 8: INSERT, UPDATE, DELETE y DDL (maestro)"
  viaproxy "INSERT INTO app_ping (nota) VALUES ('prueba regla 5');"
  viaproxy "UPDATE app_ping SET nota='prueba regla 6' WHERE nota='prueba regla 5' LIMIT 1;"
  viaproxy "DELETE FROM app_ping WHERE nota='prueba regla 6' LIMIT 1;"
  viaproxy "CREATE TABLE IF NOT EXISTS app_tmp (id INT); DROP TABLE app_tmp;"
  echo "ejecutadas"
} > "$OUT/prueba-query-rules.txt"

# 3) Estado de la replicacion
{
  echo "# $(date '+%F %T')"
  for S in mysql-slave1 mysql-slave2; do
    echo "== $S"
    docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$S" mysql -uroot \
      -e "SHOW REPLICA STATUS\G" 2>/dev/null \
      | grep -E "Source_Host|Replica_IO_Running:|Replica_SQL_Running:|Seconds_Behind_Source|Last_(IO|SQL)_Error:"
  done
} > "$OUT/replicacion.txt"

# 4) Estado y estadisticas de ProxySQL
padmin "SELECT hostgroup_id,hostname,port,status,max_connections FROM runtime_mysql_servers; SELECT * FROM runtime_mysql_replication_hostgroups;" > "$OUT/proxysql-servidores.txt"
padmin "SELECT rule_id,active,match_digest,destination_hostgroup,apply FROM runtime_mysql_query_rules;" > "$OUT/proxysql-query-rules.txt"
padmin "SELECT rule_id,hits FROM stats.stats_mysql_query_rules ORDER BY hits DESC;" > "$OUT/reglas-hits.txt"
padmin "SELECT hostgroup,SUBSTR(digest_text,1,60) AS consulta,count_star,ROUND(sum_time/count_star) AS avg_us FROM stats.stats_mysql_query_digest ORDER BY count_star DESC LIMIT 15;" > "$OUT/query-digest.txt"
padmin "SELECT hostgroup,SUM(count_star) AS total FROM stats.stats_mysql_query_digest GROUP BY hostgroup;" > "$OUT/digest-por-hostgroup.txt"
padmin "SELECT hostgroup,srv_host,status,ConnUsed,ConnFree,ConnOK,ConnERR,Queries FROM stats.stats_mysql_connection_pool;" > "$OUT/connection-pool.txt"

echo "Evidencia guardada en $OUT/:"; ls -1 "$OUT"
