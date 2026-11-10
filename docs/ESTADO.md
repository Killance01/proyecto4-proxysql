# Estado del Proyecto 4 (ProxySQL) — actualizado el 10-nov-2026

**Entrega: martes 17 de noviembre de 2026.** Informe IEEE (máx. 7 págs.) en el sitio del curso; diapositivas y repositorio en GitHub. Presentación + sustentación: máx. 20 min.

## Cómo empezar (cada integrante, en su máquina)

```bash
git clone https://github.com/Killance01/proyecto4-proxysql.git && cd proyecto4-proxysql
cp .env.example .env
docker compose up -d
# Antes de inicializar ProxySQL, comprobar que el cnf aplicó solo (debe haber 3 servidores y 8 reglas):
docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT hostgroup_id,hostname,status FROM runtime_mysql_servers; SELECT rule_id FROM runtime_mysql_query_rules;"
./scripts/init-replication.sh
./scripts/init-proxysql.sh
curl -s localhost:5000/write; curl -s localhost:5000/read
```

Repositorio privado: acepta la invitación como colaborador y autentícate al clonar (SSH: git@github.com:Killance01/proyecto4-proxysql.git, o HTTPS con token / gh auth login).

Si algo falla, abre un Issue con la salida completa. Tu primer arranque ES la prueba de clon limpio: reportarlo vale como tarea.

## Reglas del equipo
- Una rama por tarea (`feat/...`) y Pull Request a `main`, revisado por otra persona. Sin push directo a `main`.
- Nunca subir `.env` (solo `.env.example`).
- Cada máquina corre su propio stack: los contenedores tienen nombre fijo, no caben dos stacks en el mismo host.
- No ejecutar `init-replication.sh` sobre un clúster que ya replica: resiembra los esclavos.
- **Benchmarks finales en UNA sola máquina**, anotando `nproc`, RAM y `docker stats`, para que las cifras sean comparables.
- La evidencia va en `docs/resultados/` guardada con `tee`; no se editan a mano las salidas.

## Hecho (verificado con salidas)
- [x] Compose con maestro, 2 esclavos, ProxySQL, Sysbench y webapp en la red `db-net`
- [x] Replicación binlog activa (IO/SQL = Yes, lag 0)
- [x] Hostgroups 10 (escritura) y 20 (lectura) con `mysql_replication_hostgroups`
- [x] 8 query rules con regex (1-3 casos especiales al maestro, 4 SELECT a esclavos, 5-8 DML/DDL al maestro)
- [x] `max_connections` por backend (100 maestro / 200 esclavos) y multiplexación
- [x] Admin 6032 solo en `docker-compose.override.yml` (dev); puerto de aplicación por `.env` (3306 → 6033)
- [x] Webapp Flask en contenedor: `/test-db`, `/write` (maestro), `/read` (esclavos)
- [x] Routing verificado con `stats_mysql_query_digest` (SELECT a hostgroup 20, INSERT a 10)
- [x] `stats_mysql_connection_pool` consultado (pool reutilizado: ~16 conexiones para ~180.000 consultas por esclavo)
- [x] Sysbench preliminar a 60 s: `docs/resultados/sysbench-preliminar-60s.md`

## Hecho pero sin validar en un clon limpio
- [ ] `proxysql/proxysql.cnf` completo aplica solo en el primer arranque (volumen vacío)
- [ ] `scripts/init-replication.sh` e `init-proxysql.sh` desde cero
- [ ] `--read-only=1` en los esclavos y `hostname:` en el compose (tras recrear, siguen `read_only=1` y en el hostgroup 20)
- [ ] `scripts/capture-evidence.sh` genera todos los archivos de `docs/resultados/`

## Pendiente (un Issue por tarea; poner responsable)

| # | Tarea | Listo cuando | Responsable |
|---|---|---|---|
| T1 | Validar clon limpio (ver «Cómo empezar») | Cada integrante levanta el stack sin editar nada; fallos reportados como Issue | todos |
| T2 | Caída del maestro | `docs/resultados/failover-maestro.txt` con estado de servidores antes/durante/después; SELECT sigue, INSERT falla; se documenta que ProxySQL no promueve esclavos (opcional: promoción manual) | |
| T3 | Tercer esclavo en caliente | Servicio `mysql-slave3` (server-id=4, read-only); `SLAVES=mysql-slave3 ./scripts/init-replication.sh`; alta en ProxySQL; evidencia de que `Queries` crece en slave3; `scripts/add-slave3.sh` | |
| T4 | Benchmarks Sysbench | 16 hilos, **120 s**, con y sin ProxySQL, solo lectura (`--skip_trx=on`) y lectura/escritura, 3 repeticiones alternando el orden; tabla en `docs/resultados/`; `scripts/run-benchmarks.sh`; `capture-evidence.sh` ejecutado justo después | |
| T5 | README final | Diagrama (Mermaid), explicación de cada regla, cómo verificar el routing, pruebas mínimas del enunciado, problemas conocidos | |
| T6 | Matriz de decisión multicriterio | Alternativas (NGINX stream, HAProxy, ProxySQL, MaxScale), criterios con pesos, qué se mide y qué es documental | |
| T7 | Informe IEEE (máx. 7 págs.) | Introducción, Contexto, Alternativas, Diseño, Implementación, Pruebas, Discusión, Conclusiones, Referencias | |
| T8 | Diapositivas (~9) | `docs/slides.pdf` en el repo | |
| T9 | Reproducibilidad | Versiones de imagen fijadas (el log mostró ProxySQL 3.x; el enunciado dice 2.x: fijar y documentar), `Makefile` con `make up`, healthchecks opcionales | |
| T10 | Demo y ensayo | Guion de 5 min y ensayo cronometrado de 20 min; plan B con capturas | |
| T11 | Entrega | Informe subido al sitio del curso, repo accesible al profesor, diapositivas en el repo | |

Dependencias: T2, T3 y T4 alimentan T7 y T8. T6 puede avanzar desde ya. Los resultados se congelan el viernes 13.

## Calendario
- **Mar 10:** todos levantan el proyecto (T1). Repartir tareas.
- **Mié 11 – jue 12:** T2, T3, T4 (en la máquina elegida), borrador de T5 y T6.
- **Vie 13:** resultados congelados. Borrador completo del informe.
- **Sáb 14 – dom 15:** informe final, diapositivas (T7, T8), README final.
- **Lun 16:** ensayo cronometrado (T10) y revisión cruzada.
- **Mar 17:** entrega (T11).

## Problemas conocidos
- `proxysql.cnf` **solo se lee con el volumen vacío**. Para reaplicarlo: `docker compose rm -sf proxysql && docker volume rm <prefijo>_proxysql-data && docker compose up -d proxysql`.
- ProxySQL escucha en **6033** dentro de la red; el host lo ve en 3306 (`3306:6033`). Mapear 3306:3306 produce `(2013, Lost connection...)`.
- Los esclavos deben arrancar con `read_only=1`; si no, el monitor de ProxySQL los mueve al hostgroup 10.
- `admin:admin` solo conecta desde dentro del contenedor; `radmin:radmin` sirve desde el host cuando el 6032 está publicado (dev).
- Si `Permission denied` al editar archivos del repo: `sudo chown -R $USER:$USER .` (alguien los creó con sudo).
