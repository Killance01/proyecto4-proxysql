# Sysbench preliminar (16 hilos, 60 s, 4 tablas x 10.000 filas)

PRELIMINAR: el enunciado pide 120 s. Se repetira con 3 corridas por escenario.

| Escenario | TPS | QPS | Lat. media (ms) | p95 (ms) | Max (ms) |
|---|---|---|---|---|---|
| Solo lectura, via ProxySQL (skip_trx=on) | 426,05 | 5.964,64 | 37,54 | 71,83 | 669,11 |
| Solo lectura, directo al maestro (skip_trx=on) | 734,93 | 10.289,01 | 21,76 | 27,17 | 690,52 |
| Lectura/escritura, via ProxySQL | 43,72 | 874,33 | 365,08 | 569,67 | 1.767,42 |

## Distribucion observada (tras las pruebas via ProxySQL)
- Consultas por hostgroup: hostgroup 20 (lectura) = 358.718; hostgroup 10 (escritura) = 53.068
- Aciertos por regla: regla 4 (SELECT) = 395.664; regla 6 (UPDATE) = 5.406; regla 5 (INSERT/REPLACE) = 2.719; regla 7 (DELETE) = 2.703; regla 8 (DDL) = 8; reglas 1 a 3 = 0
- Pool de conexiones (ConnOK / Queries): mysql-master 17 / 53.415; mysql-slave1 16 / 179.891; mysql-slave2 16 / 178.827

## Notas
- Todo corre en la misma maquina virtual, asi que repartir lecturas entre esclavos no suma capacidad de CPU o disco.
- La corrida via ProxySQL fue la primera; la directa se hizo despues, con caches calientes.
- Pendiente: lectura/escritura directa al maestro, 120 s y 3 repeticiones por escenario.
