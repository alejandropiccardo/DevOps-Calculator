# Entregable 1 — Calculadora API con despliegue blue/green

**Materia:** DevOps — UCU
**Integrantes:** Alejandro Piccardo, Tomas Darracq, Diego Handalian

---

## 1. Descripción

API REST de una calculadora, contenerizada con Docker y desplegada en Kubernetes (minikube).

Se desarrollaron 2 versiones de la aplicación y se alterna entre ellas usando la estrategia
**blue/green**: ambos entornos conviven en el cluster y el cambio de versión consiste únicamente en
mover el `selector` del Service de un entorno al otro.

| Entorno   | Imagen            | Versión | Operaciones                            |
|-----------|-------------------|---------|----------------------------------------|
| **blue**  | `calculadora:1.2` | 1.2     | suma, resta, multiplicación, división  |
| **green** | `calculadora:2.2` | 2.2     | idem + raíz cuadrada     |

El cambio mínimo entre versiones es el agregado del endpoint `/raiz`. Todos los endpoints de la v1 siguen funcionando igual en la v2.

### Endpoints

| Método | Endpoint                  | v1 (blue) | v2 (green) | Descripción                          |
|--------|---------------------------|-----------|------------|--------------------------------------|
| GET    | `/`                       | sí        | sí         | Versión, color y operaciones activas |
| GET    | `/health`                 | sí        | sí         | Usado por las probes de Kubernetes   |
| GET    | `/metrics`                | sí        | sí         | Métricas en formato Prometheus       |
| GET    | `/suma?a=2&b=3`           | sí        | sí         | a + b                                |
| GET    | `/resta?a=5&b=2`          | sí        | sí         | a - b                                |
| GET    | `/multiplicacion?a=3&b=4` | sí        | sí         | a * b                                |
| GET    | `/division?a=10&b=2`      | sí        | sí         | a / b (400 si b = 0)                 |
| GET    | `/raiz?a=9`               | **404**   | sí         | raíz de a (400 si a < 0)             |

Toda respuesta incluye los campos `version` y `color`, así se ve al instante qué entorno está
atendiendo el pedido:

```json
{"operacion":"suma","resultado":5.0,"version":"1.1","color":"blue"}
```

---

## 2. Estructura del proyecto

```
Entrega1/
├── app/
│   ├── v1/                     # versión 1.0 (sin raíz cuadrada)
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── v2/                     # versión 2.0 (con raíz cuadrada)
│       ├── main.py
│       ├── requirements.txt
│       └── Dockerfile
├── k8s/
│   ├── configmap.yaml          # configuración de cada entorno
│   ├── deployment-blue.yaml    # Deployment blue  -> calculadora:1.2
│   ├── deployment-green.yaml   # Deployment green -> calculadora:2.2
│   └── service.yaml            # Service NodePort con selector conmutable
├── monitoring/                 # Entrega 2
│   ├── prometheus.yaml         # RBAC + config + reglas de alerta + Deployment + Service
│   ├── grafana.yaml            # Secret + provisioning + Deployment + Service
│   └── grafana-dashboard.yaml  # el dashboard en JSON
├── scripts/
│   └── generar-carga.ps1       # genera trafico para disparar las alertas
├── kyverno/                    # Entrega 3
│   ├── politicas/              # las 3 ValidatingPolicy
│   └── pruebas/                # manifiestos conforme / no conforme
├── falco/
│   └── values.yaml             # values del chart de Helm de Falco
├── reports/                    # evidencia de la entrega 3 (ver sección 7)
└── README.md
```

Las dos versiones se mantienen en carpetas separadas para que ambas imágenes puedan reconstruirse
desde cero, sin depender del historial de git.

**Stack:** Python 3.12 + FastAPI + Uvicorn · Docker · Kubernetes (minikube).

---

## 3. Requisitos previos

- Docker
- kubectl
- minikube

Verificar que el cluster esté corriendo:

```bash
minikube start
```

```bash
kubectl get nodes
```

---

## 4. Despliegue paso a paso

### Paso 1 — Construir las imágenes

Desde la carpeta `Entrega1/`:

```bash
docker build -t calculadora:1.2 app/v1
```

```bash
docker build -t calculadora:2.2 app/v2
```

### Paso 2 — Cargar las imágenes en minikube

minikube corre en su propio nodo y no ve las imágenes del Docker local, por lo que hay que
cargarlas explícitamente:

```bash
minikube image load calculadora:1.2
```

```bash
minikube image load calculadora:2.2
```


En los Deployments se usa `imagePullPolicy: IfNotPresent` para que Kubernetes use la imagen local y
no intente descargarla de Docker Hub.

### Paso 3 — Desplegar ambos entornos

```bash
kubectl apply -f k8s/
```

Esto crea los dos ConfigMaps, los dos Deployments (2 réplicas cada uno) y el Service.
**Los dos entornos quedan corriendo al mismo tiempo**, pero el Service apunta solo a blue.

```bash
kubectl get pods -l app=calculadora -L version
```

```
NAME                                 READY   STATUS    RESTARTS   AGE   VERSION
calculadora-blue-68d89f4754-rksbc    1/1     Running   0          14s   blue
calculadora-blue-68d89f4754-sm82h    1/1     Running   0          14s   blue
calculadora-green-649ccd6fc5-g5s5d   1/1     Running   0          14s   green
calculadora-green-649ccd6fc5-xmvj2   1/1     Running   0          14s   green
```

Aunque hay 4 pods corriendo, el Service solo tiene como endpoints a los 2 de blue:

```bash
kubectl get endpointslice -l kubernetes.io/service-name=calculadora
```

### Paso 4 — Acceder a la aplicación

```bash
minikube service calculadora --url
```

Devuelve una URL tipo `http://127.0.0.1:59493`. **Dejar esa terminal abierta** (con el driver
`docker` en Windows, la terminal mantiene abierto el túnel) y usar otra para las pruebas.

```bash
curl "http://127.0.0.1:59493/"
```

```bash
curl "http://127.0.0.1:59493/suma?a=2&b=3"
```

```bash
curl "http://127.0.0.1:59493/raiz?a=9"
```

Salida:

```
{"app":"calculadora","version":"1.2","color":"blue","operaciones":["suma","resta","multiplicacion","division"]}
{"operacion":"suma","resultado":5.0,"version":"1.2","color":"blue"}
{"detail":"Not Found"}
```

`/raiz` devuelve 404 porque la v1 no tiene esa operación.

> **Por qué no usar `kubectl port-forward svc/calculadora` para la demo:** el port-forward elige un
> pod al establecer la conexión y se queda pegado a él, así que **no refleja el cambio de selector**.
> `minikube service` pasa por el NodePort y kube-proxy, que resuelve los endpoints en cada conexión;
> por eso es la forma correcta de demostrar el switch.

### Paso 5 — Validar green antes de darle tráfico


### Paso 6 — Switch blue -> green

Todo el despliegue se reduce a cambiar el selector del Service.

**PowerShell (Windows):**

```bash
kubectl patch service calculadora -p '{\"spec\":{\"selector\":{\"app\":\"calculadora\",\"version\":\"green\"}}}'
```

Consultando **la misma URL de antes**, sin reiniciar ni redesplegar nada:

```
{"app":"calculadora","version":"2.2","color":"green","operaciones":["suma","resta","multiplicacion","division","raiz"]}
{"operacion":"raiz","resultado":3.0,"version":"2.2","color":"green"}
```


### Paso 7 — Rollback

Si se detecta un error en producción con la v2, el rollback es el mismo patch al revés:

```bash
kubectl patch service calculadora -p '{\"spec\":{\"selector\":{\"app\":\"calculadora\",\"version\":\"blue\"}}}'
```

### Paso 8 — Limpieza

```bash
kubectl delete -f k8s/
```

---

## 5. Decisiones técnicas

- **Dos Deployments + un Service.** Es la implementación canónica de blue/green: los entornos son
  independientes y se distinguen por la label `version: blue|green`. El Service es el único punto de
  entrada estable, y el switch es un cambio de una sola línea, atómico y reversible.

- **Un ConfigMap por entorno.** `APP_VERSION` y `APP_COLOR` se inyectan con `envFrom.configMapRef`
  en lugar de estar hardcodeados en el código, que es el uso que corresponde a un ConfigMap.

- **Readiness y liveness probes sobre `/health`.** La readiness probe es lo que hace *seguro* el
  blue/green: Kubernetes solo agrega un pod a los endpoints del Service cuando responde
  correctamente, así que al conmutar el selector no hay riesgo de mandar tráfico a un pod que
  todavía está arrancando.

- **`type: NodePort`.** Es el tipo de Service más simple que funciona en minikube sin componentes
  extra (un `LoadBalancer` requeriría `minikube tunnel`).

- **`replicas: 2` en cada entorno.** Suficiente para mostrar que el Service balancea entre varios
  pods, sin consumir recursos de más en un cluster local.

---

## 6. Monitoreo y alertas (Entrega 2)

La calculadora expone métricas en `/metrics`, Prometheus las recolecta y evalúa dos reglas de
alerta, y Grafana las muestra en un dashboard. **No se usa Alertmanager**: las alertas se visualizan,
no se notifican (ver "Alcance" más abajo).

```
┌──────────────┐  /metrics   ┌────────────────────────┐  consulta   ┌─────────┐
│ calculadora  │ ──────────> │ Prometheus             │ ──────────> │ Grafana │
│ (4 pods)     │  cada 15 s  │  · guarda las métricas │             │         │
└──────────────┘             │  · evalúa las reglas   │             └─────────┘
                             │  · publica ALERTS{...} │
                             └────────────────────────┘
```

### Métricas expuestas

| Métrica | Tipo | Labels | Qué cuenta |
|---|---|---|---|
| `calculadora_operaciones_total` | Counter | `operacion`, `version` | operaciones resueltas correctamente |
| `calculadora_errores_total` | Counter | `operacion`, `motivo`, `version` | operaciones rechazadas por entrada inválida |

Los `motivo` posibles son `division_por_cero`, `raiz_negativa` y `parametro_invalido` (este último
lo levanta un `exception_handler` de `RequestValidationError`, porque FastAPI valida los tipos
*antes* de entrar al endpoint y ese rechazo nunca pasa por el código de la operación).

> **Qué cuenta como "operación inválida":** la operación existe pero el input no es válido. Un 404
> (por ejemplo `/raiz` contra la v1) **no** se cuenta: ahí el endpoint no existe, que es un problema
> distinto. La decisión está tomada a propósito para que la alerta no se dispare por escaneos o
> URLs mal tipeadas.

Prometheus agrega además la label `entorno` (`blue`/`green`) tomada de la label del pod. Se llama
distinto que `version` (`1.2`/`2.2`) a propósito, para que no colisionen.

### Reglas de alerta

Viven en el ConfigMap `prometheus-config`, dentro de `monitoring/prometheus.yaml`:

| Alerta | Expresión | Severidad |
|---|---|---|
| `DemasiadasOperaciones` | `sum(increase(calculadora_operaciones_total[5m])) > 20` | warning |
| `DemasiadasOperacionesInvalidas` | `sum(increase(calculadora_errores_total[5m])) > 5` | critical |

Las dos tienen `for: 30s`, así que primero pasan a `Pending` y recién después a `Firing`.

Desarmando la primera, que es literalmente la consigna ("X operaciones en Y minutos"):

- `increase(...[5m])` — cuánto creció el contador en los últimos **5 minutos** (la Y)
- `sum(...)` — agrega las réplicas y los tipos de operación en un solo número
- `> 20` — el umbral (la X)

Cambiar X o Y es editar esa línea del ConfigMap y volver a aplicar.

### Dashboard de Grafana

Seis paneles, provisionados por ConfigMap (no hay que configurar nada a mano):

1. **Estado de las alertas** — *state timeline* sobre `ALERTS{...}`, muestra la franja pasando a
   `pending` y después a `firing`.
2. **Ventana de la alerta: operaciones** — la expresión exacta de la alerta, con línea de umbral en 20.
3. **Ventana de la alerta: inválidas** — ídem, desglosada por `motivo`, umbral en 5.
4. **Operaciones por minuto**
5. **Por tipo de operación**
6. **Por entorno (blue/green)** — al conmutar el Service de la sección 4, el tráfico salta de una
   serie a la otra.

### Despliegue

Los pasos 1 a 3 de la sección 4 no cambian, salvo que las imágenes ahora son `1.1` y `2.1` (la
instrumentación cambió el contenido de la imagen, así que cambió el tag). Después:

```bash
kubectl apply -f monitoring/
```

```bash
kubectl rollout status deploy/prometheus
```

```bash
kubectl rollout status deploy/grafana
```

Accesos (cada uno necesita su propia terminal con el túnel abierto):

```bash
minikube service prometheus --url
```

```bash
minikube service grafana --url
```

Grafana pide usuario y contraseña: **`admin` / `devops2026`**, que salen del Secret `grafana-admin`.

### Demo

1. Verificar que Prometheus encontró los pods: en su UI, **Status → Targets**, tienen que figurar
   los 4 pods de la calculadora en `UP`.
2. Generar carga:

```bash
.\scripts\generar-carga.ps1 -Url http://127.0.0.1:<puerto-del-tunel>
```

3. En Prometheus → **Alerts**: las dos alertas pasan a `Pending` y ~30 s después a `Firing`.
4. En Grafana: la franja de estado se pone roja y las curvas cruzan la línea de umbral.

> **Importante:** generá la carga *después* de que Prometheus haya hecho al menos un scrape.
> `increase()` mide el crecimiento **entre muestras**: si el contador ya estaba alto la primera vez
> que Prometheus lo vio, no hay crecimiento que medir y la alerta nunca salta. Es el error más fácil
> de cometer al probar esto.

### Decisiones técnicas

- **El contador va dentro de `resultado()`.** Esa función ya era el único punto por el que pasaban
  las cinco operaciones, así que una sola línea instrumenta todo. Los errores usan el mismo patrón
  con `rechazar()`.

- **RBAC para Prometheus.** `ServiceAccount` + `ClusterRole` + `ClusterRoleBinding` con permisos de
  lectura sobre pods, services y endpoints. Sin esto, Prometheus no puede consultar la API de
  Kubernetes y no descubre ningún target.

- **Descubrimiento por anotaciones.** Los pods llevan `prometheus.io/scrape: "true"` y Prometheus
  filtra por esa anotación con `relabel_configs`. La alternativa era listar las IPs a mano, que se
  rompe en cuanto un pod se reinicia.

- **Un `Secret` para la clave de Grafana**, en vez de ponerla en el Deployment. En un proyecto real
  ese archivo no se versionaría; acá la contraseña es de demo y está documentada a propósito.

- **Sin Alertmanager.** Alertmanager se ocupa de *rutear y entregar* notificaciones (mail, Slack,
  PagerDuty). Como el requerimiento era visualizar, Prometheus alcanza: publica el estado de cada
  alerta como la métrica `ALERTS`, que Grafana consulta igual que cualquier otra.

- **`emptyDir` para los datos de Prometheus.** Las métricas se pierden si el pod se reinicia.
  Alcanza para la demo; en producción iría un `PersistentVolume`.

### Alcance

Esta entrega cubre **detección y visualización** de alertas. No cubre **notificación**: nadie recibe
un mensaje cuando una alerta salta. Agregarlo es sumar un `monitoring/alertmanager.yaml` y un bloque
`alerting:` en la configuración de Prometheus apuntando a él.

### Nota sobre `increase()`

Los valores pueden salir con decimales: `30.3` operaciones en vez de `30`. No es un error de la
instrumentación — `increase()` **extrapola** sobre los bordes de la ventana cuando las muestras no
caen justo en los extremos. Es el comportamiento documentado de Prometheus para contadores.

---

## 7. Seguridad DevSecOps (Entrega 3)

| Área       | Herramienta                     | Reporte                                                            | Antes                           | Después                    |
|------------|---------------------------------|--------------------------------------------------------------------|---------------------------------|----------------------------|
| Código     | pip-audit (en vez de npm audit) | [`reports/npm-audit.txt`](reports/npm-audit.txt)                   | 7 vulnerabilidades en starlette | 0                          |
| Código     | Semgrep 1.181.1                 | [`reports/semgrep.txt`](reports/semgrep.txt)                       | 6 hallazgos                     | 0                          |
| Imagen     | Trivy 0.76.1                    | [`reports/trivyreport.txt`](reports/trivyreport.txt)               | 47 HIGH, 0 CRITICAL             | 0 (de cualquier severidad) |
| Kubernetes | Kyverno 1.19.2                  | [`reports/kyverno-validacion.txt`](reports/kyverno-validacion.txt) | —                               | 3 políticas en `Deny`      |
| Kubernetes | KubeLinter 0.8.3                | [`reports/kubelinter.txt`](reports/kubelinter.txt)                 | 8 errores                       | 0                          |
| Runtime    | Falco 0.45.1                    | [`reports/falco-event.log`](reports/falco-event.log)               | —                               | shell detectada            |

Trivy, Semgrep y KubeLinter se corren como contenedores de Docker, así que no hace falta instalarlos.

### 7.1 Seguridad en el código

**`npm audit` no aplica a este proyecto:** la calculadora es Python, no hay `package.json` ni
`package-lock.json` (npm responde `ENOLOCK`). Se usó **pip-audit**, el equivalente para Python, y su
salida se guardó en `reports/npm-audit.txt` (el nombre que pide la consigna), junto con la de
`npm audit` como evidencia.

```bash
pip install pip-audit
```

```bash
pip-audit -r app/v2/requirements.txt
```

Las 7 vulnerabilidades estaban en **starlette 0.41.3**, que no figuraba en `requirements.txt`: la
traía FastAPI como dependencia. Se subió `fastapi` a 0.162.0 y se fijó `starlette==1.10.0` de forma
explícita. Se verificó que todos los endpoints responden igual (200/400/404/422 y métricas).

**Semgrep** (análisis estático con reglas de Python, Dockerfile, Kubernetes, secretos y auditoría):

```bash
docker run --rm -v "${PWD}:/src" -w /src semgrep/semgrep:1.181.1 semgrep scan --config p/python --config p/dockerfile --config p/kubernetes --config p/secrets --config p/security-audit --metrics=off app k8s monitoring
```

El código Python no tuvo hallazgos. Los 6 eran de los manifiestos (contenedores sin `runAsNonRoot` y
con el filesystem escribible) y se corrigieron. Lo que se decidió mantener está justificado al
principio de `reports/semgrep.txt`.

### 7.2 Seguridad en la imagen

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.76.1 image --severity HIGH,CRITICAL calculadora:2.2
```

La imagen anterior (`python:3.12-slim`, Debian) tenía **47 HIGH**: 3 de starlette y **44 de paquetes
de Debian sin parche disponible** (util-linux, ncurses, systemd…). Como no había versión corregida, la
única forma real de resolverlas era no tener esos paquetes. Los Dockerfiles ahora:

- Usan **`python:3.12.16-alpine3.24`** con build **multi-stage**: las dependencias se instalan en un
  virtualenv en la primera etapa y a la imagen final solo se copia el venv. Pasó de 144 MB a 82 MB.
- Sacan `pip` y `setuptools` de la imagen final.
- Corren con un **UID numérico (10001)**. Tiene que ser un número: con un nombre (`USER app`)
  Kubernetes no puede verificar `runAsNonRoot` y no arranca el pod.

Como cambió el contenido, las imágenes pasan a **`calculadora:1.2`** y **`calculadora:2.2`**.

### 7.3 Seguridad en Kubernetes

Conviene darle más recursos a minikube, porque se suman Kyverno y Falco:

```bash
minikube start --cpus=4 --memory=6144
```

**Instalar Kyverno:**

```bash
kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.19.2/install.yaml
```

```bash
kubectl -n kyverno rollout status deploy/kyverno-admission-controller
```

**Aplicar las políticas:**

```bash
kubectl apply -f kyverno/politicas/
```

| Archivo                   | Política                                                                                              |
|---------------------------|-------------------------------------------------------------------------------------------------------|
| `01-prohibir-latest.yaml` | Rechaza `:latest` y también imágenes sin tag (`nginx` = `nginx:latest`). Se permiten digests `@sha256`. |
| `02-exigir-recursos.yaml` | Exige `requests` **y** `limits` de `cpu` **y** `memory` en cada contenedor.                           |
| `03-prohibir-root.yaml`   | Exige `runAsNonRoot: true` (del pod o del contenedor) y rechaza `runAsUser: 0`.                       |

Se escribieron como **`ValidatingPolicy`** (CEL) y no como `ClusterPolicy`, porque en Kyverno 1.19
`ClusterPolicy` está deprecada. Las tres están en modo `Deny` (bloquean, no solo avisan) y con
`autogen` para Deployments, StatefulSets, Jobs, etc.: el rechazo ocurre al aplicar el Deployment y no
recién cuando el ReplicaSet intenta crear los pods. Excluyen los namespaces de sistema (`kube-system`,
`kyverno`, `falco`).

**Validación con un manifiesto no conforme:**

```bash
kubectl apply -f kyverno/pruebas/no-conforme.yaml
```

```
Error from server: ... denied the request: Policy prohibir-tag-latest failed: No se permite la etiqueta latest ni imagenes sin tag. Contenedores: app (calculadora:latest)
Error from server: ... denied the request: Policy exigir-requests-limits failed: Todos los contenedores deben declarar requests y limits de cpu y memory. Contenedores: app
Error from server: ... denied the request: Policy prohibir-root failed: Los contenedores no pueden correr como root: ...
Error from server: ... Policy prohibir-tag-latest failed ...; Policy exigir-requests-limits failed ...; Policy prohibir-root failed ...
```

Como control positivo, un pod que cumple las tres es aceptado:

```bash
kubectl apply -f kyverno/pruebas/conforme.yaml
```

Un detalle que salió de la prueba: **los Deployments de la entrega anterior también eran rechazados**
por la política 3, porque no declaraban `runAsNonRoot`. Ahora todos los manifiestos de `k8s/` y
`monitoring/` tienen:

```yaml
securityContext:               # del pod
  runAsNonRoot: true
  runAsUser: 10001
  seccompProfile: { type: RuntimeDefault }
...
securityContext:               # del contenedor
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities: { drop: [ALL] }
```

**KubeLinter:**

```bash
docker run --rm -v "${PWD}:/src" -w /src stackrox/kube-linter:v0.8.3 lint k8s monitoring
```

De 8 errores a `No lint errors found!`. Además del `securityContext`, pedía `podAntiAffinity` en los
Deployments de 2 réplicas: se usó `preferred` y no `required`, porque minikube tiene un solo nodo y con
`required` la segunda réplica quedaría en `Pending`.

### 7.4 Seguridad en tiempo de ejecución (Falco)

Requiere Helm (`winget install Helm.Helm`).

```bash
helm install falco falco --repo https://falcosecurity.github.io/charts --version 9.2.1 -n falco --create-namespace -f falco/values.yaml
```

```bash
kubectl -n falco rollout status ds/falco
```

`falco/values.yaml` usa el driver **`modern_ebpf`**: no necesita compilar un módulo de kernel y
funciona con el kernel de WSL2 que usa minikube en Windows.

**Acción sospechosa:** abrir una shell interactiva dentro de un pod de la calculadora.

```bash
kubectl get pods -l app=calculadora
```

```bash
kubectl exec -it <pod-calculadora> -- sh
```

**Ver la alerta** (en otra terminal):

```bash
kubectl -n falco logs ds/falco -c falco | Select-String "Terminal shell"
```

```
Notice A shell was spawned in a container with an attached terminal | ... user_uid=10001 process=sh
command=sh terminal=34816 ... k8s_pod_name=calculadora-green-5c9b6ccd8d-k6htr k8s_ns_name=default
```

Salta la regla **`Terminal shell in container`**, que viene en las reglas por defecto de Falco. El log
completo está en `reports/falco-event.log`. Ahí también se ve que un `cat /etc/shadow` desde esa shell
falla con *Permission denied*: como el contenedor ya no corre como root, el atacante puede hacer menos.

> En minikube con driver docker, Falco ve todo el kernel de WSL2, así que también registra eventos de
> otros contenedores de Docker Desktop. Para el reporte se filtraron solo los de la calculadora.

### 7.5 Decisiones técnicas

- **Arreglar la causa en lugar de aceptar el riesgo.** Las 44 CVE de Debian no tenían parche. En vez
  de documentarlas como riesgo aceptado se cambió la base de la imagen, y desaparecieron.
- **Versiones fijas en todas las herramientas** (Kyverno 1.19.2, chart de Falco 9.2.1, Trivy 0.76.1, KubeLinter
  0.8.3, Semgrep 1.181.1), por la misma razón por la que la política 1 prohíbe `latest`.
- **Lo que se mantiene** (justificado en los reportes): el `HEALTHCHECK` que pide Trivy en el
  Dockerfile (LOW; Kubernetes lo ignora y ya hay readiness/liveness probes), el bind de uvicorn a
  `0.0.0.0` (necesario dentro de un contenedor) y la clave de demo de Grafana en el Secret.
