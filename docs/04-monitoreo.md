# 4. Monitoreo y observabilidad (Prometheus + Grafana)

## Instrumentación

La aplicación expone `GET /metrics` con `prometheus-client`:

| Métrica                            | Tipo       | Para qué                                     |
|------------------------------------|------------|----------------------------------------------|
| `calculadora_peticiones_segundos`  | Histograma | RPS y latencia promedio                      |
| `calculadora_operaciones_total`    | Contador   | Métrica de negocio: operaciones por tipo     |
| `calculadora_errores_total`        | Contador   | Operaciones rechazadas, por motivo           |

`/metrics` y `/health` no se miden, porque los consultan Prometheus y las probes cada pocos segundos y
falsearían el RPS. El label `path` usa la ruta declarada en la app, y las URL inexistentes caen en
`no_encontrada` para no crear una serie nueva por cada URL inventada.

Prometheus tiene dos jobs: `calculadora`, que descubre los pods anotados con `prometheus.io/scrape`, y
`cadvisor`, que lee CPU y memoria por pod a través del kubelet.

## Paso a paso

```bash
kubectl apply -f monitoring/
./scripts/generar-carga.sh          # sin argumentos abre un port-forward al Service
./scripts/abrir-monitoreo.sh        # Prometheus :9090, Grafana :3000 (admin / devops2026)
```

## Dashboard

Dashboard **Calculadora - Monitoreo y Alertas**, exportado en
[`grafana/dashboard.json`](../grafana/dashboard.json). Grafana lo carga desde
`monitoring/grafana-dashboard.yaml` y usa Prometheus como fuente de datos.

| Requisito                | Consulta                                                                                  |
|--------------------------|-------------------------------------------------------------------------------------------|
| RPS                      | `sum by (version) (rate(calculadora_peticiones_segundos_count[1m]))`                      |
| Latencia promedio        | `sum(rate(calculadora_peticiones_segundos_sum[1m])) / sum(rate(calculadora_peticiones_segundos_count[1m]))` |
| CPU por pod              | `sum by (pod) (rate(container_cpu_usage_seconds_total{pod=~"calculadora-.*"}[1m]))`       |
| Memoria por pod          | `sum by (pod) (container_memory_working_set_bytes{pod=~"calculadora-.*"})`                |
| Métrica de negocio       | `sum by (operacion) (rate(calculadora_operaciones_total[1m])) * 60`                       |

## Resultados obtenidos

Consultas a Prometheus después de correr la carga:

```
RPS:      {version="1.2"}  2.09
Latencia: 0.00425 s (4,25 ms)
CPU:      calculadora-blue  ~0.003 a 0.011 cores por pod
Memoria:  ~37 MB por pod
Negocio (ultimos 5 min): suma 59.8, resta 59.8, multiplicacion 60.3, division 60.3

ALERTS: DemasiadasOperaciones           firing  warning
        DemasiadasOperacionesInvalidas  firing  critical
```

Los valores con decimales son normales: `increase()` extrapola sobre los bordes de la ventana.

> En minikube con driver docker, cAdvisor publica las series a nivel de pod, sin label `container`. Por eso
> las consultas de CPU y memoria filtran solo por `pod`.
