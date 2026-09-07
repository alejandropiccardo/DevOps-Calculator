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
| **blue**  | `calculadora:1.0` | 1.0     | suma, resta, multiplicación, división  |
| **green** | `calculadora:2.0` | 2.0     | idem + raíz cuadrada     |

El cambio mínimo entre versiones es el agregado del endpoint `/raiz`. Todos los endpoints de la v1 siguen funcionando igual en la v2.

### Endpoints

| Método | Endpoint                  | v1 (blue) | v2 (green) | Descripción                          |
|--------|---------------------------|-----------|------------|--------------------------------------|
| GET    | `/`                       | sí        | sí         | Versión, color y operaciones activas |
| GET    | `/health`                 | sí        | sí         | Usado por las probes de Kubernetes   |
| GET    | `/suma?a=2&b=3`           | sí        | sí         | a + b                                |
| GET    | `/resta?a=5&b=2`          | sí        | sí         | a - b                                |
| GET    | `/multiplicacion?a=3&b=4` | sí        | sí         | a * b                                |
| GET    | `/division?a=10&b=2`      | sí        | sí         | a / b (400 si b = 0)                 |
| GET    | `/raiz?a=9`               | **404**   | sí         | raíz de a (400 si a < 0)             |

Toda respuesta incluye los campos `version` y `color`, así se ve al instante qué entorno está
atendiendo el pedido:

```json
{"operacion":"suma","resultado":5.0,"version":"1.0","color":"blue"}
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
│   ├── deployment-blue.yaml    # Deployment blue  -> calculadora:1.0
│   ├── deployment-green.yaml   # Deployment green -> calculadora:2.0
│   └── service.yaml            # Service NodePort con selector conmutable
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
docker build -t calculadora:1.0 app/v1
```

```bash
docker build -t calculadora:2.0 app/v2
```

### Paso 2 — Cargar las imágenes en minikube

minikube corre en su propio nodo y no ve las imágenes del Docker local, por lo que hay que
cargarlas explícitamente:

```bash
minikube image load calculadora:1.0
```

```bash
minikube image load calculadora:2.0
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
{"app":"calculadora","version":"1.0","color":"blue","operaciones":["suma","resta","multiplicacion","division"]}
{"operacion":"suma","resultado":5.0,"version":"1.0","color":"blue"}
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
{"app":"calculadora","version":"2.0","color":"green","operaciones":["suma","resta","multiplicacion","division","raiz"]}
{"operacion":"raiz","resultado":3.0,"version":"2.0","color":"green"}
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

## 6. CI/CD — Pipeline de GitHub Actions (Entrega 2)

El workflow [.github/workflows/docker-publish.yml](.github/workflows/docker-publish.yml) construye
las imágenes de la aplicación y las publica en DockerHub automáticamente.

**Se dispara** con cada `push` a la branch `entrega2`, y también a mano desde la pestaña *Actions*
de GitHub (`workflow_dispatch`).

**Qué hace**, para cada una de las dos versiones en paralelo:

1. `actions/checkout@v4` — baja el código del repo al runner.
2. `docker/setup-buildx-action@v3` — habilita Buildx, que es lo que usa el paso de build.
3. `docker/login-action@v3` — se autentica contra DockerHub con los secrets del repositorio.
4. `docker/build-push-action@v6` — construye la imagen desde el `Dockerfile` de esa versión y la
   sube.

**Imágenes que publica:**

| Build context | Tag publicado                    |
|---------------|----------------------------------|
| `app/v1`      | `<usuario>/calculadora:1.0`      |
| `app/v2`      | `<usuario>/calculadora:2.0`      |

### Por qué un `matrix` y no un build único

El proyecto necesita **las dos imágenes disponibles al mismo tiempo**, porque el despliegue
blue/green de la sección 4 corre v1 y v2 en paralelo en el cluster. Un `strategy.matrix` recorre las
dos carpetas con los mismos cuatro pasos, en dos jobs paralelos.

La consecuencia práctica es que agregar una versión futura es **agregar una entrada a la lista**,
sin tocar los pasos ni mover archivos entre carpetas:

```yaml
strategy:
  matrix:
    include:
      - path: app/v1
        tag: "1.0"
      - path: app/v2
        tag: "2.0"
```

Se descartó la alternativa de mantener una carpeta `latest/` con la versión vigente y archivar las
anteriores: el historial de versiones ya lo provee git, y blue/green necesita construir las dos
versiones activamente, con lo cual ninguna es realmente un "archivo".

### Configuración requerida

Dos *repository secrets* en GitHub (Settings → Secrets and variables → Actions):

| Secret                | Valor                                            |
|-----------------------|--------------------------------------------------|
| `DOCKERHUB_USERNAME`  | usuario de DockerHub                             |
| `DOCKERHUB_TOKEN`     | *Access Token* de DockerHub (no la contraseña)   |

> En los logs de Actions el nombre de la imagen aparece como `***/calculadora:1.0`: GitHub enmascara
> automáticamente todo valor que provenga de un secret. Es el comportamiento esperado, no un error.
