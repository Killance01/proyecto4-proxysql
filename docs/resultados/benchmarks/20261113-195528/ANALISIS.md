\# Resultados del benchmark



\## Entorno y metodología



\- ProxySQL 2.7.3, MySQL 8.0.46 y Sysbench 1.0.17.

\- Docker: 12 CPU disponibles y 8278130688 bytes de memoria.

\- Un maestro y tres replicas, compartiendo los recursos del mismo equipo.

\- 4 tablas de 10000 filas, recreadas antes de cada medicion.

\- 16 hilos y 120 segundos por medicion.

\- Calentamiento previo de solo lectura durante 15 segundos.

\- Tres repeticiones por carga y destino.

\- Orden: directo/proxy, proxy/directo, directo/proxy.

\- Solo lectura con skip\_trx=on.

\- Lectura/escritura con transacciones explicitas.

\- Espera de replicacion activa y retraso reportado de cero antes de cada caso.



\## Promedios de TPS



| Carga | Directo al maestro | Mediante ProxySQL | Cambio respecto a directo |

|---|---:|---:|---:|

| Solo lectura | 6116.17 | 2128.46 | -65.2 % |

| Lectura/escritura | 411.07 | 342.77 | -16.6 % |



Los promedios corresponden a las tres ejecuciones de cada caso.

Los datos individuales se conservan en resumen.csv y en los logs originales.



\## Enrutamiento observado



En la muestra revisada de solo lectura, el digest registra las consultas

en el hostgroup 20. El pool muestra actividad en las tres replicas.



En la muestra revisada de lectura/escritura, la mayoria de las consultas

se registra en el hostgroup 10, incluidos SELECT dentro de transacciones.

Este comportamiento es coherente con transaction\_persistent=1.



El contador Queries del pool es acumulativo e incluye calentamientos y

actividad anterior. No representa por si solo las consultas de una medicion.

El digest se reinicio antes de cada medicion.



\## Errores y limitaciones



Las pruebas de solo lectura reportaron cero errores ignorados.



En lectura/escritura se reportaron:

\- Directo: 2, 3 y 3 errores ignorados.

\- ProxySQL: 1, 2 y 1 errores ignorados.



Sysbench tenia la lista predeterminada de errores ignorables

1213,1020,1205. Los logs no detallan los codigos que ocurrieron.

Por tanto, no se atribuyen estos eventos a una causa concreta.



Los archivos de recursos son instantaneas posteriores a cada medicion;

no describen el consumo promedio ni maximo durante la prueba.



Todos los servicios comparten el mismo equipo y el conjunto de datos es

pequeno. Los resultados no se generalizan a servidores independientes

ni a otras cargas.



La captura complementaria final se realizo despues de la serie.

Las estadisticas individuales de ProxySQL se guardaron inmediatamente

despues de cada medicion por run-benchmarks.sh.



\## Conclusion



En este entorno, ProxySQL permitio enrutar lecturas a las tres replicas,

pero obtuvo menos TPS y mayor latencia que la conexion directa.



El costo adicional del proxy, el conjunto de datos pequeno y los recursos

compartidos son posibles factores; esta prueba no aisla sus efectos.



El balanceo de consultas no implica necesariamente una mejora de

rendimiento para cualquier carga.

