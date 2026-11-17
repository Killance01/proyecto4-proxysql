#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export MSYS_NO_PATHCONV=1
set -a
source .env
set +a

OUT="docs/resultados/benchmarks/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

TABLES=4
SIZE=10000
THREADS=16
SECONDS_RUN=120

sb() {
  local host=$1 port=$2 workload=$3
  shift 3
  docker exec sysbench sysbench \
    "/usr/share/sysbench/${workload}.lua" \
    --db-driver=mysql \
    --mysql-host="$host" --mysql-port="$port" \
    --mysql-user="$MYSQL_USER" --mysql-password="$MYSQL_PASSWORD" \
    --mysql-db=sbtest --tables="$TABLES" --table-size="$SIZE" \
    "$@"
}

wait_replicas() {
  local attempt node status ready
  for ((attempt=1; attempt<=120; attempt++)); do
    ready=1
    for node in mysql-slave1 mysql-slave2 mysql-slave3; do
      status=$(docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$node" \
        mysql -uroot -e "SHOW REPLICA STATUS\G")
      if ! grep -qE 'Replica_IO_Running: Yes' <<< "$status" ||
         ! grep -qE 'Replica_SQL_Running: Yes' <<< "$status" ||
         ! grep -qE 'Seconds_Behind_Source: 0[[:space:]]*$' <<< "$status"; then
        ready=0
      fi
    done
    if [[ "$ready" == 1 ]]; then
      return 0
    fi
    sleep 2
  done
  echo "ERROR: las replicas no se sincronizaron."
  return 1
}

admin() {
  docker exec proxysql mysql \
    -u"${PROXYSQL_ADMIN_USER:-admin}" \
    -p"${PROXYSQL_ADMIN_PASSWORD:-admin}" \
    -h127.0.0.1 -P6032 -e "$1"
}

printf 'carga,repeticion,destino,tps,qps,latencia_media_ms,p95_ms,errores\n' \
  > "$OUT/resumen.csv"

{
  date -Iseconds
  echo "Tablas=$TABLES FilasPorTabla=$SIZE Hilos=$THREADS Duracion=$SECONDS_RUN"
  echo "Topologia: un maestro y tres replicas; misma maquina Docker."
  echo "RO: sin transacciones explicitas. RW: transacciones habilitadas."
  docker info --format 'CPUs={{.NCPU}} RAM_bytes={{.MemTotal}}'
  docker exec proxysql proxysql --version
  docker exec sysbench sysbench --version
  docker exec mysql-master mysql --version
  docker inspect --format '{{.Name}} imagen={{.Config.Image}} id={{.Image}}' \
    mysql-master mysql-slave1 mysql-slave2 mysql-slave3 proxysql sysbench
} > "$OUT/entorno.txt" 2>&1

for workload in oltp_read_only oltp_read_write; do
  extra=()
  if [[ "$workload" == oltp_read_only ]]; then
    extra=(--skip_trx=on)
  fi

  for repetition in 1 2 3; do
    order=(directo proxy)
    if [[ "$repetition" == 2 ]]; then
      order=(proxy directo)
    fi

    for target in "${order[@]}"; do
      name="${workload}-${repetition}-${target}"
      echo "=== $name ==="

      # Restablecer los mismos datos iniciales antes de cada caso.
      sb mysql-master 3306 oltp_read_only cleanup \
        > "$OUT/$name-preparacion.txt" 2>&1
      sb mysql-master 3306 oltp_read_only prepare \
        >> "$OUT/$name-preparacion.txt" 2>&1
      wait_replicas

      host=mysql-master
      port=3306
      if [[ "$target" == proxy ]]; then
        host=proxysql
        port=6033
      fi

      # Calentamiento de solo lectura para no modificar los datos.
      sb "$host" "$port" oltp_read_only \
        --threads="$THREADS" --time=15 --events=0 --skip_trx=on run \
        > "$OUT/$name-calentamiento.txt" 2>&1

      # Reiniciar contadores de digest para aislar la medicion.
      admin "SELECT COUNT(*) FROM stats_mysql_query_digest_reset;" \
        > "$OUT/$name-reset.txt" 2>&1

      sb "$host" "$port" "$workload" \
        --threads="$THREADS" --time="$SECONDS_RUN" --events=0 \
        --report-interval=10 "${extra[@]}" run \
        2>&1 | tee "$OUT/$name.txt"

      # Capturar estadisticas inmediatamente despues de la medicion.
      admin "SELECT hostgroup, srv_host, status, ConnUsed, ConnFree, Queries
             FROM stats_mysql_connection_pool;
             SELECT hostgroup, digest_text, count_star
             FROM stats_mysql_query_digest ORDER BY count_star DESC;" \
        > "$OUT/$name-proxysql.txt" 2>&1
      docker stats --no-stream > "$OUT/$name-recursos.txt"

      awk -v w="$workload" -v r="$repetition" -v d="$target" '
        /transactions:/ {t=$3; gsub(/[()]/,"",t)}
        /^[[:space:]]*queries:/ {q=$3; gsub(/[()]/,"",q)}
        /^[[:space:]]*avg:/ {a=$2}
        /95th percentile:/ {p=$3}
        /ignored errors:/ {e=$3}
        END {print w "," r "," d "," t "," q "," a "," p "," e}
      ' "$OUT/$name.txt" >> "$OUT/resumen.csv"

      wait_replicas
    done
  done
done

echo "Pruebas terminadas. Resultados: $OUT"
cat "$OUT/resumen.csv"