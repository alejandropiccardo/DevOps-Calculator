# Análisis de imágenes

Imágenes analizadas: `calculadora:1.2` (blue) y `calculadora:2.2` (green).
Herramienta: Dive v0.13.1 en modo CI, más `docker image inspect` y `docker history`.
Salida completa: [`dive-output.txt`](dive-output.txt). Se regenera con `./scripts/analizar-imagenes.sh`.

## Resultado

| Dato                   | `calculadora:1.2`  | `calculadora:2.2`  |
|------------------------|--------------------|--------------------|
| Tamaño total           | 70,7 MB            | 70,7 MB            |
| Capas del filesystem   | 8                  | 8                  |
| Eficiencia (Dive)      | 99,59 %            | 99,59 %            |
| Espacio desperdiciado  | 513 kB             | 513 kB             |
| `userWastedPercent`    | 0,82 %             | 0,82 %             |
| Resultado Dive CI      | PASS               | PASS               |

Las dos versiones solo difieren en `main.py`, así que comparten todas las demás capas en disco y en el
registro.

## Composición de las capas (`calculadora:2.2`)

| Tamaño  | Capa                                                  | Origen       |
|---------|-------------------------------------------------------|--------------|
| 8,43 MB | Alpine 3.24 (minirootfs)                              | imagen base  |
| 910 kB  | `ca-certificates`, `tzdata`                           | imagen base  |
| 39,6 MB | Intérprete Python 3.12.16                             | imagen base  |
| 36 B    | Enlaces simbólicos de Python                          | imagen base  |
| 4,18 MB | `pip uninstall` + `adduser`                           | Dockerfile   |
| 17,6 MB | Virtualenv con las dependencias (etapa `build`)       | Dockerfile   |
| 0 B     | `WORKDIR /app`                                        | Dockerfile   |
| 4,48 kB | `main.py`                                             | Dockerfile   |

## Cumplimiento de la consigna

- **Versión específica:** `python:3.12.16-alpine3.24`, nunca `latest`.
- **Sin root:** `USER 10001`, numérico para que Kubernetes pueda verificar `runAsNonRoot`.
- **Multi-stage:** la etapa `build` instala las dependencias y la final copia solo `/opt/venv`.

## Observaciones de optimización posibles

1. **La capa de `pip uninstall` no achica la imagen.** Borrar `pip` y `setuptools` en la etapa final
   oculta esos archivos, pero siguen en la capa de Python y además se agregan 4,18 MB. Sirve para reducir
   la superficie de ataque, no el tamaño.
2. **El intérprete es más de la mitad de la imagen** (39,6 de 70,7 MB). Bajar de ahí requiere cambiar de
   runtime, por ejemplo una imagen distroless. Se mantiene Alpine porque ya resolvió las 44 CVE HIGH de la
   base Debian (ver [`trivyreport.txt`](trivyreport.txt)).
3. **El desperdicio restante viene de la imagen base.** Los 513 kB son archivos que las capas de Alpine y
   Python reescriben (`ca-certificates.crt`, la base de datos de `apk`). No se pueden corregir desde el
   Dockerfile del proyecto.
4. **El orden de las capas ya aprovecha la caché.** Las dependencias se copian antes que `main.py`, así que
   un cambio de código solo reconstruye una capa de 4,48 kB.
