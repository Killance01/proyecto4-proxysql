# Proyecto 4: Balanceo de carga MySQL con ProxySQL

Cluster MySQL 8.0 (1 maestro + 2 esclavos) con ProxySQL (hostgroup 10 = escritura,
20 = lectura) y Sysbench, todo en Docker Compose.

## Arranque rapido

```bash
git clone https://github.com/Killance01/proyecto4-proxysql.git && cd proyecto4-proxysql
cp .env.example .env               # cambia las contrasenas ANTES del primer arranque
docker compose up -d
./scripts/init-replication.sh      # usuarios + replicacion
./scripts/init-proxysql.sh         # servidores, usuarios, query rules (idempotente)

```

## Accesos

* Aplicaciones (via ProxySQL): 127.0.0.1:3306 (puerto interno 6033)
* Admin ProxySQL (solo dev): `docker exec -it proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032`
* Produccion sin el puerto 6032: `docker compose -f docker-compose.yml up -d`

## Notas importantes

* `proxysql.cnf` solo se lee en el primer arranque. Si lo cambias, reinicia el volumen:
`docker compose rm -sf proxysql && docker volume rm <prefijo>_proxysql-data && docker compose up -d proxysql`
* Reiniciar todo desde cero: `docker compose down -v` y repetir el arranque rapido.
* No ejecutes `init-replication.sh` sobre un cluster que ya replica: resiembra los esclavos.

```

```
