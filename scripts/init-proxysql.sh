#!/usr/bin/env bash
# Configura ProxySQL por la interfaz de administracion. Es idempotente.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
AU="${PROXYSQL_ADMIN_USER:-admin}"; AP="${PROXYSQL_ADMIN_PASSWORD:-admin}"
admin() { docker exec -i proxysql mysql -u"$AU" -p"$AP" -h127.0.0.1 -P6032 "$@"; }

until admin -e "SELECT 1" >/dev/null 2>&1; do echo "Esperando al admin de ProxySQL..."; sleep 2; done

admin <<SQL
DELETE FROM mysql_servers;
INSERT INTO mysql_servers (hostgroup_id,hostname,port,max_connections) VALUES
 (10,'mysql-master',3306,100),(20,'mysql-slave1',3306,200),(20,'mysql-slave2',3306,200);
DELETE FROM mysql_replication_hostgroups;
INSERT INTO mysql_replication_hostgroups (writer_hostgroup,reader_hostgroup,comment) VALUES (10,20,'cluster principal');

DELETE FROM mysql_users;
INSERT INTO mysql_users (username,password,default_hostgroup,transaction_persistent,fast_forward,active)
 VALUES ('${MYSQL_USER}','${MYSQL_PASSWORD}',10,1,0,1);

UPDATE global_variables SET variable_value='${MONITOR_USER}' WHERE variable_name='mysql-monitor_username';
UPDATE global_variables SET variable_value='${MONITOR_PASSWORD}' WHERE variable_name='mysql-monitor_password';
UPDATE global_variables SET variable_value='true' WHERE variable_name='mysql-multiplexing';
UPDATE global_variables SET variable_value='false' WHERE variable_name='mysql-monitor_writer_is_also_reader';

DELETE FROM mysql_query_rules;
INSERT INTO mysql_query_rules (rule_id,active,match_digest,destination_hostgroup,apply,comment) VALUES
 (1,1,'^SELECT .* FOR UPDATE',10,1,'SELECT FOR UPDATE al maestro'),
 (2,1,'^SELECT @@',10,1,'variables de sesion al maestro'),
 (3,1,'^SELECT .*(NOW|RAND|UUID)\\(',10,1,'no deterministas al maestro'),
 (4,1,'^SELECT',20,1,'SELECT a esclavos'),
 (5,1,'^(INSERT|REPLACE)',10,1,'INSERT/REPLACE al maestro'),
 (6,1,'^UPDATE',10,1,'UPDATE al maestro'),
 (7,1,'^DELETE',10,1,'DELETE al maestro'),
 (8,1,'^(CREATE|ALTER|DROP|TRUNCATE)',10,1,'DDL al maestro');

LOAD MYSQL SERVERS TO RUNTIME;     SAVE MYSQL SERVERS TO DISK;
LOAD MYSQL USERS TO RUNTIME;       SAVE MYSQL USERS TO DISK;
LOAD MYSQL VARIABLES TO RUNTIME;   SAVE MYSQL VARIABLES TO DISK;
LOAD MYSQL QUERY RULES TO RUNTIME; SAVE MYSQL QUERY RULES TO DISK;
SQL

sleep 5
admin -e "SELECT hostgroup_id,hostname,status,max_connections FROM runtime_mysql_servers; SELECT rule_id,active,destination_hostgroup FROM runtime_mysql_query_rules;"
