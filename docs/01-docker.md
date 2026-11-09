# 1. Contenerización (Docker)

## Qué se contenerizó

| Componente             | Imagen                     | Origen                       |
|------------------------|----------------------------|------------------------------|
| API v1 (blue)          | `calculadora:1.2`          | [`app/v1/Dockerfile`](../app/v1/Dockerfile) |
| API v2 (green)         | `calculadora:2.2`          | [`app/v2/Dockerfile`](../app/v2/Dockerfile) |
| Prometheus             | `prom/prometheus:v3.1.0`   | imagen oficial               |
| Grafana                | `grafana/grafana:11.5.0`   | imagen oficial               |

Requisitos de las imágenes propias:

- **Versión específica:** `FROM python:3.12.16-alpine3.24`.
- **Sin root:** `USER 10001`.
- **Multi-stage:** etapa `build` para instalar dependencias y etapa final que copia solo `/opt/venv`.

## Paso a paso

Construir las imágenes:

```bash
docker build -t calculadora:1.2 app/v1
docker build -t calculadora:2.2 app/v2
```

Analizar tamaño y capas con Dive:

```bash
./scripts/analizar-imagenes.sh
```

Resultado para `calculadora:2.2` (`reports/dive-output.txt`):

```
Tamano (bytes): 70733461
Capas del filesystem: 8
  efficiency: 99.5877 %
  wastedBytes: 513248 bytes (513 kB)
  userWastedPercent: 0.8240 %
Result:PASS [Total:3] [Passed:2] [Failed:0] [Warn:0] [Skipped:1]
```

Escanear vulnerabilidades con Trivy:

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.76.1 image --severity HIGH,CRITICAL calculadora:2.2
```

La evidencia está en `reports/trivyreport.txt`: se pasó de 47 HIGH sobre la base Debian a 0 vulnerabilidades
con Alpine. Ese escaneo es del 27/10; desde entonces no cambiaron ni el Dockerfile ni las dependencias.

> En Git Bash para Windows, anteponer `MSYS_NO_PATHCONV=1` al comando de Trivy para que no reescriba la ruta
> del socket.

## Reporte

El análisis completo (tamaño, capas y optimizaciones posibles) está en
[`reports/image-analysis.md`](../reports/image-analysis.md).
