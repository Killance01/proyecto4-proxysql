# Resultados del Benchmark

## 1. Entorno y Metodología
* **Componentes:** ProxySQL 2.7.3, MySQL 8.0.46 y Sysbench 1.0.17.
* **Recursos Docker:** 12 CPUs disponibles y ~7.71 GB de memoria RAM (8,278,130,688 bytes) compartidos entre un maestro y tres réplicas en el mismo equipo.
* **Parámetros de Prueba:**
  * 4 tablas de 10,000 filas (recreadas antes de cada medición).
  * 16 hilos y 120 segundos por medición.
  * Calentamiento previo de solo lectura durante 15 segundos.
  * Tres repeticiones por carga y destino (orden: `directo/proxy`, `proxy/directo`, `directo/proxy`).
  * Solo lectura con `skip_trx=on`.
  * Lectura/escritura con transacciones explícitas.
  * Espera de replicación activa y retraso reportado de cero antes de cada caso.

---

## 2. Promedios de TPS (Transacciones por Segundo)
*Los promedios corresponden a las tres ejecuciones de cada caso. Los datos individuales se conservan en `resumen.csv` y en los logs originales.*

| Carga | Directo al maestro | Mediante ProxySQL | Cambio respecto a directo |
| :--- | :---: | :---: | :---: |
| **Solo lectura** | 6,116.17 | 2,128.46 | **-65.2 %** |
| **Lectura / Escritura** | 411.07 | 342.77 | **-16.6 %** |

---

## 3. Enrutamiento Observado
* **Solo lectura:** El *digest* registra las consultas en el **hostgroup 20** y el pool muestra actividad en las tres réplicas correctamente.
* **Lectura / Escritura:** La mayoría de las consultas se registra en el **hostgroup 10**, incluyendo los comandos `SELECT` dentro de transacciones (comportamiento coherente con `transaction_persistent=1`).
* **Nota sobre métricas:** El contador `Queries` del pool es acumulativo e incluye los calentamientos previos, por lo que no representa por sí solo las consultas de una única medición. El *digest* sí se reinició antes de cada prueba.

---

## 4. Errores y Limitaciones
* **Solo lectura:** Cero errores ignorados reportados.
* **Lectura / Escritura:** 
  * *Directo:* 2, 3 y 3 errores ignorados en las ejecuciones.
  * *ProxySQL:* 1, 2 y 1 errores ignorados en las ejecuciones.
  * *Detalle:* Sysbench utilizó la lista predeterminada de errores ignorables (`1213`, `1020`, `1205`). Los logs no detallan los códigos exactos que ocurrieron, por lo que no se atribuyen estos eventos a una causa concreta.
* **Restricciones del entorno:**
  * Los archivos de recursos son instantáneas posteriores a cada medición; no describen el consumo promedio ni máximo durante la prueba.
  * Todos los servicios comparten el mismo equipo y el conjunto de datos es pequeño, por lo que **los resultados no se pueden generalizar** a servidores independientes ni a otras cargas de trabajo.
  * Las estadísticas individuales de ProxySQL se guardaron inmediatamente después de cada medición mediante `run-benchmarks.sh`.
  * La captura complementaria final se realizó después de la serie.

---

## 5. Conclusión

> **Resumen del Rendimiento:** En este entorno específico, ProxySQL permitió distribuir exitosamente las lecturas entre las tres réplicas, pero obtuvo **menor rendimiento (TPS) y mayor latencia** que la conexión directa al maestro.

El sobrecosto computacional del proxy, el tamaño pequeño del conjunto de datos y la contención por recursos compartidos son los factores principales identificados, aunque esta prueba preliminar no aísla de forma independiente el impacto de cada uno. Esto demuestra que **el balanceo de consultas no implica automáticamente una mejora de rendimiento** para cualquier arquitectura o carga.
