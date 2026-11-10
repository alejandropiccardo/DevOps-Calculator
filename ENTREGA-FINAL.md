# Laboratorio 4: Trabajo integrador

**Materia:** DevOps — UCU
**Integrantes:** Alejandro Piccardo, Tomas Darracq, Diego Handalian
**Proyecto:** Calculadora API (FastAPI) con despliegue blue/green en Kubernetes

---

## 1. Contenerización (Docker)

### 1.a y 1.b Componentes y Dockerfiles

| Componente     | Imagen                   | Origen              |
| -------------- | ------------------------ | ------------------- |
| API v1 (blue)  | `calculadora:1.2`        | `app/v1/Dockerfile` |
| API v2 (green) | `calculadora:2.2`        | `app/v2/Dockerfile` |
| Prometheus     | `prom/prometheus:v3.1.0` | imagen oficial      |
| Grafana        | `grafana/grafana:11.5.0` | imagen oficial      |

### 1.c Requisitos de las imágenes

- **Versión específica:** `python:3.12.16-alpine3.24`, nunca `latest`.
- **Sin root:** `USER 10001`. Es numérico para que Kubernetes pueda verificar `runAsNonRoot`.
- **Multi-stage:** la etapa `build` instala las dependencias y la etapa final copia solo `/opt/venv`.

![Build de las imagenes](IMG/image1.png)

### 1.d Validación de calidad

**Vulnerabilidades (Trivy 0.76.1).** Se pasó de 47 vulnerabilidades HIGH sobre la base Debian a 0 de cualquier
severidad con Alpine. Evidencia: `reports/trivyreport.txt`, escaneo del 27/10/2026.

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.76.1 image --severity HIGH,CRITICAL calculadora:2.2
```

**Tamaño y capas (Dive v0.13.1).**

```bash
./scripts/analizar-imagenes.sh
```

```
Tamano (bytes): 70733461
Capas del filesystem: 8
  efficiency: 99.5877 %
  wastedBytes: 513248 bytes (513 kB)
  userWastedPercent: 0.8240 %
Result:PASS [Total:3] [Passed:2] [Failed:0] [Warn:0] [Skipped:1]
```

![Analisis de capas con Dive](IMG/image2.png)

### 1.e Reporte

El tamaño total, la cantidad de capas y las optimizaciones posibles están en `reports/image-analysis.md`.

| Dato         | `calculadora:1.2` | `calculadora:2.2` |
| ------------ | ----------------- | ----------------- |
| Tamaño total | 70,7 MB           | 70,7 MB           |
| Capas        | 8                 | 8                 |
| Eficiencia   | 99,59 %           | 99,59 %           |

---

## 2. Orquestación y despliegue (Kubernetes)

Helm era opcional según lo indicado por la cátedra, por lo que la aplicación se despliega con manifiestos de
Kubernetes.

| Recurso                 | Archivo                                                 |
| ----------------------- | ------------------------------------------------------- |
| Deployment blue y green | `k8s/deployment-blue.yaml`, `k8s/deployment-green.yaml` |
| Service (NodePort)      | `k8s/service.yaml`                                      |
| ConfigMap por entorno   | `k8s/configmap.yaml`                                    |

No se usa Ingress: es un solo servicio HTTP y se accede por el NodePort.

```bash
kubectl apply -f k8s/
```

### 2.e Verificación

```
$ kubectl get pods -l app=calculadora
NAME                                 READY   STATUS    RESTARTS   AGE
calculadora-blue-86ccfcbff-5qjw2     1/1     Running   0          2m11s
calculadora-blue-86ccfcbff-pxcwr     1/1     Running   0          2m19s
calculadora-green-655f99497f-65qbp   1/1     Running   0          2m19s
calculadora-green-655f99497f-w6cmv   1/1     Running   0          2m11s

$ kubectl get svc calculadora
NAME          TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
calculadora   NodePort   10.104.85.27   <none>        80:30080/TCP   12d

$ kubectl port-forward svc/calculadora 18081:80
$ curl "http://127.0.0.1:18081/suma?a=2&b=3"
{"operacion":"suma","resultado":5.0,"version":"1.2","color":"blue"}
```

![Pods y Services en Kubernetes](IMG/image3.png)

---

## 3. Integración y entrega continua (Jenkins)


### 3.a Pipeline en Jenkins

Jenkins corre en un contenedor construido a partir de [`jenkins/Dockerfile`](jenkins/Dockerfile),
sobre la imagen `jenkins/jenkins:2.541.3-lts-jdk17`, con Docker CLI, kubectl v1.29.5, Helm 3.16.3,
Semgrep, Snyk y pytest instalados adentro. Se levanta con `docker compose up -d --build` desde la
carpeta `jenkins/` y queda disponible en `http://localhost:8081`.

Las herramientas van **dentro de la imagen** y no como contenedores aparte por una razón concreta:
Jenkins usa el socket Docker del host, así que un `docker run -v $(pwd):/src` resolvería la ruta
contra el filesystem del host y no contra el workspace, y el escaneo correría sobre una carpeta
vacía. El socket se usa solo para `docker build` y `docker push`, que sí funcionan porque el CLI
lee el contexto y se lo manda al daemon.

El job `Calculadora-DevOps` es de tipo Pipeline, definido como *Pipeline script from SCM* apuntando
a la rama `main` del repositorio y al `Jenkinsfile` de la raíz. Toma tres credenciales, cargadas en
el almacén de Jenkins y referenciadas por ID:

| ID | Tipo | Uso |
|---|---|---|
| `dockerhub` | Username with password | publicar las imágenes |
| `snyk-token` | Secret text | autenticar el escaneo de dependencias |
| `kubeconfig-ucu` | Secret file | desplegar en el cluster de la UCU |

El kubeconfig no se versiona: contiene un token de acceso real al cluster y está en el `.gitignore`.
Jenkins lo escribe en un archivo temporal durante la etapa y lo borra al salir del bloque.

El disparo es **manual** (*Build with Parameters*), con dos parámetros:

| Parámetro | Para qué |
|---|---|
| `ENTORNO_ACTIVO` | `blue` (v1) o `green` (v2): a cuál apunta el Service al terminar |
| `DESPLEGAR` | desmarcado corre solo CI, sin tocar el cluster compartido |

### 3.b Etapas del pipeline

<img width="1568" height="324" alt="image" src="https://github.com/user-attachments/assets/ca076e1c-6eed-4ccd-893d-cd1ece420d26" />

| # | Etapa | Herramienta | Detiene el pipeline si |
|---|---|---|---|
| 1 | Clonar repositorio | git | no puede clonar |
| 2 | Análisis estático | Semgrep | hay hallazgos de severidad `ERROR` |
| 3 | Dependencias | Snyk | hay vulnerabilidades críticas |
| 4 | Construcción y test | pytest | falla algún test |
| 5 | Imagen Docker | docker | falla el build o el push |
| 6 | Despliegue | Helm | el rollout no queda listo en 5 minutos |
| 7 | Smoke test | kubectl + curl | el Service no responde |

Las etapas 6 y 7 están condicionadas por el parámetro `DESPLEGAR`.

### 3.c Jenkinsfile

El pipeline es declarativo y está en [`Jenkinsfile`](Jenkinsfile), en la raíz del repositorio.

El tag de las imágenes sale del **hash del commit**, no del número de build, para poder rastrear en
los dos sentidos qué código está corriendo en el cluster:

```groovy
env.COMMIT = sh(returnStdout: true, script: 'git rev-parse --short=7 HEAD').trim()
env.TAG_V1 = "${env.VERSION_V1}-${env.COMMIT}"
```

`VERSION_V1` y `VERSION_V2` se declaran una sola vez en el bloque `environment` y alimentan tanto el
tag de la imagen como el `APP_VERSION` que la aplicación reporta por la API, de modo que no puedan
desincronizarse.

Comprobación de la trazabilidad sobre el despliegue real:

```
DEPLOY              IMAGEN
calculadora-blue    alepiccardo/calculadora:1.2-5dc826e
calculadora-green   alepiccardo/calculadora:2.2-5dc826e
```

### 3.d Ejecución y registros de cada fase

Cada etapa escribe su salida en la consola del build, con marca de tiempo (`timestamps()`). Además
quedan archivados como artefactos del build mediante `archiveArtifacts`:

| Artefacto | Contenido |
|---|---|
| `reports/semgrep-ci.txt` | informe completo de Semgrep, todas las severidades |
| `reports/snyk-ci.txt` | informe completo de dependencias de v1 y v2 |
| `reports/junit-v1.xml`, `reports/junit-v2.xml` | resultados de los tests |
| `reports/smoke-test.txt` | respuesta del Service desde dentro del cluster |

Los resultados de los tests se publican además con el paso `junit`, así que aparecen en la pestaña
*Test Result* del build con el detalle test por test.

Resultados medidos en el build #6, que terminó en verde:

| Etapa | Resultado |
|---|---|
| Semgrep (informe) | 258 reglas sobre 20 archivos, 0 hallazgos |
| Semgrep (corte) | 107 reglas de severidad `ERROR`, 0 hallazgos |
| Snyk | 15 dependencias por variante, 0 vulnerabilidades |
| pytest | v2: 22 pasados; v1: 21 pasados y 1 omitido (la raíz no existe en v1) |
| Imágenes | `1.2-5dc826e` y `2.2-5dc826e` publicadas en DockerHub |
| Helm | release `calculadora` instalado, 4 pods `Running` |
| Smoke test | el Service responde desde dentro del cluster |

### 3.e Detención ante vulnerabilidades críticas

Las etapas 2 y 3 ejecutan cada herramienta **dos veces**, con dos propósitos distintos:

1. Un informe completo, con todas las severidades, que se guarda como evidencia y **no** corta el
   pipeline (se encierra entre `set +e` y `set -e`).
2. Una corrida restringida a lo crítico, cuyo código de salida sí decide si el pipeline continúa.

Semgrep:

```
semgrep scan --config ... --severity ERROR --error app k8s monitoring helm
```

`--error` hace que Semgrep salga con código distinto de cero si encuentra algo, y `--severity ERROR`
limita el corte a los hallazgos críticos.

Snyk:

```
snyk test --file=app/v1/requirements.txt --package-manager=pip --severity-threshold=critical
```

Snyk sale con código 1 si encuentra alguna vulnerabilidad en el umbral indicado o por encima.

Cuando una de las dos corta, Jenkins marca la etapa en rojo, **omite todas las etapas siguientes** y
el bloque `post { failure { ... } }` indica dónde está el detalle. Al no llegar a la etapa 5 no se
construye ni publica ninguna imagen, y al no llegar a la 6 el cluster no se toca: el código con una
vulnerabilidad crítica no puede llegar a ejecutarse.

Así se vio en una ejecución real en la que la etapa 3 falló:

```
[Pipeline] { (4. Construccion y test)
Stage "4. Construccion y test" skipped due to earlier failure(s)
[Pipeline] { (5. Imagen Docker)
Stage "5. Imagen Docker" skipped due to earlier failure(s)
[Pipeline] { (6. Despliegue con Helm)
Stage "6. Despliegue con Helm" skipped due to earlier failure(s)
```

El mismo mecanismo aplica a los tests de la etapa 4: si un test falla, no se publica la imagen.

---

## 4. Monitoreo y observabilidad (Prometheus + Grafana)

### 4.a y 4.b Instrumentación

La aplicación expone `GET /metrics` con `prometheus-client`.

| Métrica                           | Tipo       | Uso                                      |
| --------------------------------- | ---------- | ---------------------------------------- |
| `calculadora_peticiones_segundos` | Histograma | RPS y latencia promedio                  |
| `calculadora_operaciones_total`   | Contador   | Métrica de negocio: operaciones por tipo |
| `calculadora_errores_total`       | Contador   | Operaciones rechazadas, por motivo       |

`/metrics` y `/health` no se miden, porque los consultan Prometheus y las probes cada pocos segundos y
falsearían el RPS.

### 4.c Prometheus

Se despliega en el cluster con `monitoring/prometheus.yaml` y tiene dos jobs: `calculadora`, que descubre los
pods anotados, y `cadvisor`, que obtiene CPU y memoria por pod.

```bash
kubectl apply -f monitoring/
./scripts/abrir-monitoreo.sh     # Prometheus en :9090, Grafana en :3000
```

![Targets de Prometheus](IMG/image4.png)

### 4.d Grafana

Se despliega con `monitoring/grafana.yaml` y usa Prometheus como fuente de datos (`http://prometheus:9090`).

![Prometheus como fuente de datos en Grafana](IMG/image5.png)

### 4.e Dashboard

| Requisito          | Consulta                                                                                                    |
| ------------------ | ----------------------------------------------------------------------------------------------------------- |
| RPS                | `sum by (version) (rate(calculadora_peticiones_segundos_count[1m]))`                                        |
| Latencia promedio  | `sum(rate(calculadora_peticiones_segundos_sum[1m])) / sum(rate(calculadora_peticiones_segundos_count[1m]))` |
| CPU por pod        | `sum by (pod) (rate(container_cpu_usage_seconds_total{pod=~"calculadora-.*"}[1m]))`                         |
| Memoria por pod    | `sum by (pod) (container_memory_working_set_bytes{pod=~"calculadora-.*"})`                                  |
| Métrica de negocio | `sum by (operacion) (rate(calculadora_operaciones_total[1m])) * 60`                                         |

Valores obtenidos con `./scripts/generar-carga.sh`:

```
RPS:      2.09
Latencia: 0.00425 s (4,25 ms)
Memoria:  ~37 MB por pod
Alertas:  DemasiadasOperaciones y DemasiadasOperacionesInvalidas en firing
```

![Dashboard de Grafana](IMG/image6.png)

![Alertas de Prometheus en FIRING](IMG/image7.png)

### 4.f Exportación

Dashboard exportado en `grafana/dashboard.json`.

---

## 5. Seguridad integrada (DevSecOps)

### 5.1 Análisis estático (Semgrep)

```bash
./scripts/escanear-semgrep.sh
```

Se aplican los rulesets `p/python`, `p/dockerfile`, `p/kubernetes`, `p/secrets` y `p/security-audit`, y tres
reglas propias para Python en `semgrep/reglas-python.yaml`:

| Regla                          | Detecta                       | CWE     |
| ------------------------------ | ----------------------------- | ------- |
| `calculadora-eval-exec`        | `eval()` y `exec()`           | CWE-95  |
| `calculadora-subprocess-shell` | `subprocess` con `shell=True` | CWE-78  |
| `calculadora-fastapi-debug`    | `FastAPI(debug=True)`         | CWE-489 |

```
Ran 258 rules on 13 files: 0 findings.
```

**Hallazgos corregidos:** los 6 hallazgos iniciales estaban en los manifiestos (`run-as-non-root` y
`writable-filesystem-container`) y se corrigieron con `securityContext`.

**Lo que se mantiene, con justificación:**

- `uvicorn --host 0.0.0.0`: dentro de un contenedor es necesario para que el Service llegue al pod.
- Clave de demo de Grafana en un Secret versionado: es solo para minikube; en un entorno real iría en un gestor
  de secretos.

Reporte completo: `reports/semgrep-report.txt`.

![Resultado de Semgrep](IMG/image8.png)

### 5.2 Escaneo de dependencias (Snyk)

```bash
SNYK_TOKEN=xxxx ./scripts/escanear-snyk.sh
```

Se escanearon las dependencias de las dos versiones de la aplicación. Evidencia: `reports/snyk-report.txt`.

```
Tested 15 dependencies for known issues, found 0 issues, 0 vulnerable paths.
Open Security issues: 0
```

**Vulnerabilidades críticas:** no hay ninguna abierta. El antecedente es `starlette 0.41.3`, con 7
vulnerabilidades detectadas por `pip-audit` (`reports/npm-audit.txt`). Se corrigió actualizando `fastapi` a
0.162.0 y fijando `starlette` en 1.10.0 en `requirements.txt`, para que una versión vulnerable no pueda entrar
por la resolución transitiva.

![Resultado de Snyk](IMG/image9.png)

### 5.3 Políticas de seguridad en Kubernetes (Kyverno)

Kyverno 1.19.2 con cuatro `ValidatingPolicy` en modo `Deny`, en `kyverno/politicas/`:

| #   | Política                 | Rechaza                                               |
| --- | ------------------------ | ----------------------------------------------------- |
| 1   | `prohibir-tag-latest`    | Imágenes `latest` o sin tag                           |
| 2   | `exigir-requests-limits` | Contenedores sin requests y limits de CPU y memoria   |
| 3   | `prohibir-root`          | Contenedores que corren como root                     |
| 4   | `prohibir-privilegiados` | `privileged: true` o `allowPrivilegeEscalation: true` |

La política 4 es la adicional: un contenedor privilegiado casi no tiene aislamiento con el nodo.

```bash
./scripts/validar-kyverno.sh
```

```
Policy prohibir-tag-latest failed: No se permite la etiqueta latest ni imagenes sin tag. Contenedores: app (calculadora:latest)
Policy exigir-requests-limits failed: Todos los contenedores deben declarar requests y limits de cpu y memory. Contenedores: app
Policy prohibir-root failed: Los contenedores no pueden correr como root: se requiere runAsNonRoot: true y runAsUser distinto de 0. Contenedores: app
Policy prohibir-privilegiados failed: No se permiten contenedores privilegiados ni con allowPrivilegeEscalation: true. Contenedores: app

$ kubectl apply -f kyverno/pruebas/conforme.yaml
pod/prueba-conforme created
```

Los 5 objetos no conformes se rechazan, el Pod conforme se acepta y los manifiestos del proyecto pasan el dry-run
en el servidor. Evidencia: `reports/kyverno-validation.log`.

![Rechazos de Kyverno](IMG/image10.png)

### 5.4 Seguridad en tiempo de ejecución (Falco)

Falco 0.45.1 instalado con el chart oficial y el driver `modern_ebpf`:

```bash
helm install falco falco --repo https://falcosecurity.github.io/charts --version 9.2.1 -n falco --create-namespace -f falco/values.yaml
./scripts/disparar-falco.sh
```

**Evento detectado:** el Pod `prueba-falco` ejecuta `find /etc -name id_rsa`, como haría un atacante que busca
claves privadas dentro de un contenedor comprometido. No se abre ningún shell: `find` es directamente el comando
del contenedor. Falco lo detecta con la regla por defecto **Search Private Keys or Passwords**, de prioridad
Warning.

```
Warning Grep private keys or passwords activities found | evt_type=execve user_uid=10001 process=find
proc_exepath=/bin/busybox parent=containerd-shim command=find /etc -name id_rsa terminal=0
```

Evidencia: `reports/falco-event.log`.

![Alerta de Falco](IMG/image11.png)

---

## 6. Reporte técnico final

### 6.a Descripción general

API REST de una calculadora, desarrollada con FastAPI, con dos versiones que conviven en el cluster. El cambio de
versión consiste en mover el `selector` del Service de blue a green. El proyecto suma monitoreo con Prometheus y
Grafana y controles de seguridad en el código, la imagen, el cluster y la ejecución.

### 6.b Arquitectura final

<img width="1568" height="1938" alt="image" src="https://github.com/user-attachments/assets/65d24297-d6ea-49d4-afe7-38dfce8894dc" />

### 6.c Pipeline implementado

Pipeline declarativo de Jenkins ([`Jenkinsfile`](Jenkinsfile)) de siete etapas, descrito en detalle
en la sección 3. Clona el repositorio, analiza el código con Semgrep, escanea las dependencias con
Snyk, corre 23 tests sobre las dos variantes, construye y publica las imágenes en DockerHub usando
el hash del commit como tag, despliega en el cluster de la UCU con Helm y verifica el resultado con
un smoke test desde dentro del cluster.

Las etapas de Semgrep y Snyk detienen la ejecución ante hallazgos críticos, de modo que el código
vulnerable no llega a construirse ni a desplegarse. Los informes completos quedan archivados como
artefactos del build aunque este pase.

El despliegue mantiene la estrategia blue/green de la sección 2: el chart deja los dos entornos
corriendo y el parámetro `ENTORNO_ACTIVO` decide a cuál apunta el Service. La aplicación queda
publicada en `https://calculadora-grupo5.reto-ucu.net` mediante un Ingress sobre el gateway APISIX
del cluster.

### 6.d Métricas y dashboard de Grafana

Ver la sección 4. El dashboard exportado se adjunta en `grafana/dashboard.json`.

### 6.e Resultados de análisis de seguridad

| Herramienta | Resultado                                                     | Evidencia                        |
| ----------- | ------------------------------------------------------------- | -------------------------------- |
| Semgrep     | 258 reglas (3 propias), 0 hallazgos; 6 corregidos             | `reports/semgrep-report.txt`     |
| Snyk        | 15 dependencias por versión, 0 vulnerabilidades               | `reports/snyk-report.txt`        |
| Trivy       | De 47 HIGH a 0 vulnerabilidades                               | `reports/trivyreport.txt`        |
| Kyverno     | 4 políticas en `Deny`; 5 objetos rechazados y 1 aceptado      | `reports/kyverno-validation.log` |
| Falco       | Alerta `Search Private Keys or Passwords`, sin abrir un shell | `reports/falco-event.log`        |

### 6.f Problemas encontrados y soluciones

| Problema                                                                      | Solución                                                                      |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| 44 CVE HIGH sin parche en la base Debian                                      | Cambio a Alpine con build multi-stage                                         |
| La evidencia inicial de Falco era abrir un shell, algo no permitido           | Pod que ejecuta `find` y dispara una regla por defecto                        |
| `minikube image load` no reemplaza un tag existente y quedaba la imagen vieja | Borrar el tag dentro de minikube antes de cargar                              |
| Las consultas de CPU y memoria volvían vacías                                 | cAdvisor no publica el label `container` en este entorno: se filtra por `pod` |
| Una URL inventada podía crear series nuevas en Prometheus                     | El label `path` usa la ruta declarada, con `no_encontrada` como respaldo      |
| Los 26 plugins sugeridos de Jenkins fallaban en cascada al instalarse         | La causa era una sola línea del log: `Jenkins 2.516.3 or higher required`. Se subió la imagen base a `2.541.3-lts-jdk17` |
| Snyk fallaba con `Failed to test pip project`, sin más detalle                | Con `-d` salían dos causas encadenadas: el plugin invoca `python` (la imagen solo trae `python3`) y resuelve el árbol leyendo los paquetes **instalados**. Se crea un venv por variante y se le pasa con `--command` |
| El push a DockerHub daba `insufficient_scope: authorization failed`           | No era la credencial: el namespace del repositorio era `alepiccardo`, no `alejandropiccardo` |
| La etapa de Helm se quedaba 5 minutos y moría en el timeout                   | La `ResourceQuota` del namespace topea `requests.cpu` en 200m y los 4 pods a 50m la llenaban exacto, así que ningún rolling update podía crear el pod nuevo. Se bajó a 25m y se fijó `maxSurge: 0` |
| La etapa 6 fallaba aunque el despliegue terminara bien                        | El comando de diagnóstico usaba `endpointslices`, sobre el que el ServiceAccount no tiene permisos. Se cambió a la API `endpoints`, y el comando se volvió tolerante a fallos: un diagnóstico no debe tumbar un despliegue correcto |
| Por HTTP la URL pública devolvía 200 con una página ajena al cluster          | El gateway sirve la aplicación por HTTPS; el puerto 80 de esa misma IP lo atiende otro servicio |

### 6.g Conclusiones y oportunidades de mejora

Combinar controles en distintas capas permitió detectar problemas que una sola herramienta no veía: Semgrep marcó
los manifiestos, Trivy la imagen base y Kyverno impide que esas fallas vuelvan al cluster.

Como mejoras quedan guardar la clave de Grafana en un gestor de secretos, dar almacenamiento persistente a
Prometheus y agregar Alertmanager para que las alertas lleguen a alguien.

Del pipeline quedan tres mejoras identificadas:

- **Tag por contenido de cada carpeta.** Hoy el tag sale del commit global, así que un cambio en `app/v2/`
  también le cambia el tag a la imagen de v1 aunque su contenido sea idéntico, y eso reinicia los pods de
  v1 sin necesidad. Taggear por el hash del contenido de cada carpeta lo evitaría.
- **Disparo automático.** El build es manual a propósito, pero un webhook de GitHub no alcanzaría porque
  GitHub no puede llegar a `localhost`. Haría falta exponer Jenkins o usar `pollSCM`.
- **Monitoreo en el cluster de la UCU.** Prometheus y Grafana corren en minikube. Llevarlos al cluster
  remoto exigiría targets estáticos en vez de autodescubrimiento, porque el ServiceAccount del grupo no
  puede crear `Role` ni `RoleBinding`.

---

## Consideraciones adicionales

### a) y b) Scripts

| Script                           | Función                                                               |
| -------------------------------- | --------------------------------------------------------------------- |
| `scripts/iniciar.sh`             | Levanta minikube, imágenes, operadores, aplicación, monitoreo y carga |
| `scripts/instalar-operadores.sh` | Instala Kyverno y Falco y aplica las políticas                        |
| `scripts/generar-carga.sh`       | Hace solicitudes automáticas para poblar los dashboards               |
| `scripts/abrir-monitoreo.sh`     | Expone Grafana y Prometheus en localhost                              |
| `scripts/limpiar.sh`             | Borra todos los recursos (`--todo` borra también minikube)            |

Jenkins no usa un script propio: se levanta con Docker Compose desde la carpeta `jenkins/`, que construye
la imagen con todas las herramientas adentro y publica la interfaz en `http://localhost:8081`.

| Archivo | Función |
| --- | --- |
| `jenkins/docker-compose.yml` | `docker compose up -d --build` levanta Jenkins; `down` lo apaga |
| `jenkins/Dockerfile` | Imagen con Docker CLI, kubectl, Helm, Semgrep, Snyk y pytest |

### c) Documentación paso a paso

| Sección    | Documento               |
| ---------- | ----------------------- |
| Docker     | `docs/01-docker.md`     |
| Kubernetes | `docs/02-kubernetes.md` |
| Jenkins    | `docs/06-jenkins.md`    |
| Monitoreo  | `docs/04-monitoreo.md`  |
| Seguridad  | `docs/05-seguridad.md`  |
