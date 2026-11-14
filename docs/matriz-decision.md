# Matriz de Decisión Multicriterio — Balanceo de Carga MySQL (T6)

Evaluación comparativa de alternativas de proxy y balanceo de carga para una arquitectura **MySQL 8.0 Maestro–Esclavos** desplegada en contenedores Docker, considerando criterios funcionales, operativos, de rendimiento y de licenciamiento.

---

## 1. Alternativas Evaluadas

1. **NGINX (`ngx_stream_core_module`):** Proxy inverso TCP/UDP de capa 4 (L4). Balancea conexiones a nivel de socket sin inspeccionar el protocolo MySQL ni distinguir sentencias SQL.
2. **HAProxy (modo TCP + `mysql-check`):** Balanceador TCP de alto rendimiento con healthchecks específicos para MySQL, pero sin enrutamiento nativo por sentencia SQL (requiere separar puertos de lectura y escritura en la aplicación).
3. **ProxySQL (`2.7.3`):** Proxy consciente del protocolo MySQL (capa 7 / L7) con análisis léxico de consultas (`query rules`), multiplexación de conexiones, manejo de *hostgroups* de replicación y administración dinámica en caliente sin reinicio.
4. **MariaDB MaxScale:** Proxy de base de datos L7 con enrutamiento Read/Write Split y failover automático, pero sujeto a licencia comercial restrictiva (BSL 1.1) en entornos productivos de más de dos nodos y optimizado primariamente para MariaDB.

---

## 2. Criterios, Pesos y Naturaleza de la Evaluación

| ID | Criterio | Peso | Fuente de Evaluación | Justificación del Peso |
| :--- | :--- | :---: | :---: | :--- |
| **C1** | **Enrutamiento Read/Write Split transparente (L7)** | **25 %** | Documental + Experimental (T1, reglas 1–8) | Requisito central: separar `SELECT` hacia réplicas y escrituras/transacciones (`FOR UPDATE`, `NOW()`, DML/DDL) hacia el maestro sin modificar el código de la aplicación ni usar dos puertos. |
| **C2** | **Multiplexación y gestión de pool de conexiones** | **20 %** | Experimental (`stats_mysql_connection_pool`, T4) | Reduce la sobrecarga de apertura/cierre de conexiones en MySQL bajo alta concurrencia (16 hilos Sysbench reutilizando ~15–17 conexiones backend). |
| **C3** | **Reconfiguración en caliente y alta disponibilidad** | **20 %** | Experimental (T2 y T3) | Capacidad de detectar caída del maestro (`SHUNNED`), mantener lecturas activas y añadir un tercer esclavo (`mysql-slave3`) en caliente sin reiniciar el servicio. |
| **C4** | **Latencia y sobrecarga (overhead) en entorno contenerizado** | **15 %** | Experimental (T4 — Sysbench 16 hilos, 120 s) | Impacto medible en TPS, QPS y latencia p95 introducido por la capa intermedia respecto a la conexión directa al maestro. |
| **C5** | **Licenciamiento Open Source y compatibilidad MySQL 8.0** | **10 %** | Documental | Ausencia de restricciones comerciales por número de nodos y soporte nativo para autenticación y protocolo de MySQL 8.0. |
| **C6** | **Observabilidad y métricas internas** | **10 %** | Documental + Experimental (`stats_mysql_query_digest`) | Disponibilidad de estadísticas granulares por regla, *digest* de consultas, tiempos promedio y estado de conexiones en tiempo real. |
| | **TOTAL** | **100 %** | | |

---

## 3. Matriz de Puntuación (Escala 1 a 5)

> **Escala:** `1` = No cumple / Muy deficiente · `2` = Cumplimiento parcial con limitaciones graves · `3` = Aceptable · `4` = Bueno · `5` = Excelente / Soporte nativo completo.

| Criterio (Peso) | NGINX Stream | HAProxy | ProxySQL 2.7.3 | MariaDB MaxScale |
| :--- | :---: | :---: | :---: | :---: |
| **C1. Read/Write Split transparente L7 (25 %)** | 1 (0,25) | 2 (0,50) | **5 (1,25)** | 5 (1,25) |
| **C2. Multiplexación y pool de conexiones (20 %)** | 1 (0,20) | 2 (0,40) | **5 (1,00)** | 4 (0,80) |
| **C3. Reconfiguración en caliente y HA (20 %)** | 2 (0,40) | 3 (0,60) | **5 (1,00)** | 5 (1,00) |
| **C4. Latencia / Overhead en contenedores (15 %)** | **5 (0,75)** | **5 (0,75)** | 3 (0,45) | 3 (0,45) |
| **C5. Licencia Open Source y MySQL 8.0 (10 %)** | **5 (0,50)** | **5 (0,50)** | **5 (0,50)** | 2 (0,20) |
| **C6. Observabilidad y métricas SQL (10 %)** | 1 (0,10) | 2 (0,20) | **5 (0,50)** | 4 (0,40) |
| **Puntaje Ponderado Total (sobre 5,00)** | **2,20** | **2,95** | **4,70** | **4,10** |
| **Porcentaje de Adecuación** | **44,0 %** | **59,0 %** | **94,0 %** | **82,0 %** |

---

## 4. Análisis Comparativo: Qué se Mide vs. Qué es Documental

### Evidencia Experimental Medida en el Clúster (ProxySQL 2.7.3)
* **Enrutamiento L7 y persistencia transaccional (C1, C6):** En `oltp_read_only`, el 100 % de las lecturas (`15.131.600` hits acumulados en la regla 4) se enrutó al *hostgroup* `20` (esclavos). En `oltp_read_write`, `transaction_persistent=1` mantuvo las lecturas dentro de transacciones explícitas en el *hostgroup* `10` (maestro), evitando lecturas inconsistentes por retraso de replicación.
* **Multiplexación (C2):** Bajo carga de 16 hilos concurrentes en Sysbench, ProxySQL mantuvo entre `15` y `16` conexiones activas reutilizadas por réplica para atender más de `4,46 millones` de consultas por nodo.
* **Tolerancia a fallos y escalado en caliente (C3):** Al detener `mysql-master` (T2), ProxySQL lo marcó como `SHUNNED` y mantuvo las lecturas operativas (`HTTP 200`) en los esclavos sin intervención manual; al restaurarlo, volvió a `ONLINE` automáticamente. Al incorporar `mysql-slave3` (T3), `LOAD MYSQL SERVERS TO RUNTIME` distribuyó tráfico de lectura inmediatamente sin reiniciar contenedores ni cortar sesiones.
* **Sobrecarga de capa intermedia (C4):** En un único host Docker (12 CPUs, 8 GB RAM), ProxySQL introdujo una penalización esperada frente a la conexión directa al maestro: `-65,2 %` de TPS en solo lectura (`2.128,46` vs. `6.116,17` TPS) y `-16,6 %` en lectura/escritura (`342,77` vs. `411,07` TPS), explicada por el salto TCP adicional, la inspección L7 de cada paquete SQL y la contención de CPU entre los cuatro contenedores MySQL y ProxySQL en la misma máquina.

### Criterios Documentales (C1, C5)
* **NGINX Stream y HAProxy** operan en capa 4 (TCP): ofrecen menor latencia bruta (C4 = 5), pero carecen de *parser* SQL, por lo que no pueden enrutar `SELECT ... FOR UPDATE`, funciones no deterministas (`NOW()`, `RAND()`, `UUID()`) ni transacciones mixtas sobre un único *endpoint* `3306`.
* **MariaDB MaxScale** ofrece capacidades L7 equivalentes, pero su licencia *Business Source License (BSL 1.1)* restringe el uso gratuito en producción a un máximo de 2 nodos backend, mientras que **ProxySQL** es software libre bajo **GPLv3** sin límite de nodos y con soporte nativo para MySQL 8.0.

---

## 5. Conclusión de Selección

**ProxySQL 2.7.3** obtiene la mayor puntuación ponderada (**4,70 / 5,00 — 94,0 %**) al ser la única alternativa completamente *open source* (GPLv3) capaz de realizar separación transparente de lecturas y escrituras a nivel SQL (L7), preservar consistencia transaccional (`transaction_persistent=1`), multiplexar conexiones y escalar réplicas en caliente sin modificar la aplicación cliente.
