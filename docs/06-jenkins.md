# Integración y entrega continua con Jenkins

Pipeline que clona el repo, analiza el código, escanea dependencias, corre los tests, publica la
imagen y despliega en Kubernetes con Helm. Definido en [`Jenkinsfile`](../Jenkinsfile).

---

## 1. Qué hace el pipeline

| # | Etapa | Herramienta | Corta el pipeline si... |
|---|---|---|---|
| 1 | Clonar repositorio | git | no puede clonar |
| 2 | Análisis estático | Semgrep | hay hallazgos de severidad `ERROR` |
| 3 | Dependencias | Snyk | hay vulnerabilidades **críticas** |
| 4 | Construcción y test | pytest | falla algún test |
| 5 | Imagen Docker | docker | falla el build o el push |
| 6 | Despliegue | Helm | el rollout no queda listo en 5 min |
| 7 | Smoke test | kubectl + curl | el Service no responde |

Las etapas 2 y 3 generan **dos informes**: uno completo con todas las severidades (queda archivado
como evidencia aunque el build pase) y otro restringido a lo crítico, que es el que decide si el
pipeline sigue o se detiene. Así se cumple el punto 3.e de la consigna sin perder visibilidad de
los hallazgos menores.

---

## 2. Levantar Jenkins

No hace falta instalar nada: Jenkins corre en un contenedor con todas las herramientas adentro.

```bash
cd jenkins
```

```bash
docker compose up -d --build
```

La primera vez tarda varios minutos (construye una imagen de ~2 GB). Cuando termina:

```bash
docker compose ps
```

La interfaz queda en **http://localhost:8081**.

> Se usa el puerto 8081 y no el 8080 porque el 8080 se usa para el `port-forward` de la calculadora.

### Por qué una imagen propia y no `jenkins/jenkins` pelado

El [`jenkins/Dockerfile`](../jenkins/Dockerfile) agrega Docker CLI, kubectl, Helm, Semgrep, Snyk y
pytest. La razón de instalarlos **dentro** en vez de correrlos como contenedores:

Jenkins corre en un contenedor y usa el socket de Docker del host. Un `docker run -v $(pwd):/src`
se interpreta contra el filesystem **del host**, no del contenedor de Jenkins, así que el workspace
no existiría y el escaneo correría sobre una carpeta vacía. `docker build` en cambio sí funciona,
porque el CLI lee el contexto y se lo manda al daemon por el socket. Por eso el socket se usa solo
para construir y publicar imágenes.

---

## 3. Configuración inicial

### 3.1 Desbloquear

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Pegá esa contraseña en la pantalla de bienvenida.

> En Git Bash sobre Windows, si el comando falla con una ruta rara tipo
> `C:/Program Files/Git/var/...`, antepone `MSYS_NO_PATHCONV=1`.

### 3.2 Plugins y usuario

1. **Install suggested plugins** — tarda unos minutos. Trae Git, Pipeline y Credentials Binding,
   que es todo lo que necesita este pipeline.
2. Creá el usuario administrador.
3. Dejá la URL que propone (`http://localhost:8081/`).

### 3.3 Credenciales

**Manage Jenkins → Credentials → System → Global credentials → Add Credentials.** Hay que crear
tres, y los IDs tienen que ser exactamente estos porque el `Jenkinsfile` los busca por nombre:

| ID | Tipo | Contenido |
|---|---|---|
| `dockerhub` | Username with password | Usuario de DockerHub y un **Access Token** (no la contraseña) |
| `snyk-token` | Secret text | Token de https://app.snyk.io/account |
| `kubeconfig-ucu` | Secret file | El archivo `grupo5.yaml` del cluster de la UCU |

- El token de DockerHub se crea en *Account Settings → Personal access tokens*, con permiso
  **Read & Write**.
- El de Snyk es gratis: cuenta → *Account Settings → Auth Token*.
- El kubeconfig **no se versiona**: contiene un token de acceso al cluster. Se sube solo acá.

---

## 4. Crear el job

1. **New Item** → nombre `calculadora-cicd` → tipo **Pipeline** → OK.
2. En **Pipeline**:
   - *Definition*: `Pipeline script from SCM`
   - *SCM*: `Git`
   - *Repository URL*: `https://github.com/alejandropiccardo/DevOps-Calculator.git`
   - *Branch Specifier*: `*/entrega4`
   - *Script Path*: `Jenkinsfile`
3. **Save**.

El repositorio es público, así que no hace falta credencial para clonarlo.

---

## 5. Ejecutar

**Build with Parameters**:

| Parámetro | Para qué |
|---|---|
| `ENTORNO_ACTIVO` | `blue` (v1, sin raíz) o `green` (v2, con raíz). Es el despliegue blue/green. |
| `DESPLEGAR` | Desmarcado corre solo CI, sin tocar el cluster. Útil para probar el pipeline. |

Conviene que la **primera corrida sea con `DESPLEGAR` desmarcado**, para validar las etapas 1 a 5
sin arriesgar el cluster compartido.

Cada build deja en **Artifacts**: `reports/semgrep-ci.txt`, `reports/snyk-ci.txt`,
`reports/junit-*.xml` y `reports/smoke-test.txt`. Los tests además aparecen en la pestaña
**Test Result** gracias al paso `junit`.

---

## 6. El despliegue blue/green desde el pipeline

El chart deja **los dos entornos corriendo** y el Service apunta a uno. Cambiar de versión en
producción es volver a correr el pipeline con el otro valor de `ENTORNO_ACTIVO`, o directamente:

```bash
helm upgrade calculadora helm/calculadora -n obligatorio-grupo5 --reuse-values --set entornoActivo=green
```

Rollback:

```bash
helm rollback calculadora -n obligatorio-grupo5
```

Para ver a qué entorno enruta el Service sin mirar los values:

```bash
kubectl get svc calculadora -n obligatorio-grupo5 -o jsonpath='{.metadata.annotations}'
```

---

## 7. Acceder a la app desplegada

El Service es `ClusterIP` a propósito: el cluster de la UCU es compartido entre grupos y un
`nodePort` fijo chocaría con otro equipo.

```bash
export KUBECONFIG=$HOME/.kube/ucu.yaml
```

```bash
kubectl port-forward -n obligatorio-grupo5 svc/calculadora 8080:80
```

```bash
curl http://127.0.0.1:8080/
```

---

## 8. Problemas conocidos

**`kubectl` devuelve HTML de login.** Sin `KUBECONFIG`, kubectl va a `localhost:8080`, que dentro
del contenedor **es el propio Jenkins**. Significa que la credencial `kubeconfig-ucu` no se cargó.

**Semgrep o Snyk fallan sin hallazgos reales.** Revisar el informe completo en los artefactos: el
corte usa un umbral más estricto que el informe, así que puede frenar por algo que no aparece en
las primeras líneas.

**`docker: permission denied` en la etapa 5.** El contenedor tiene que correr como root para
escribir en el socket del host. Es lo que hace el `Dockerfile` (`USER root`) y es aceptable en un
laboratorio local; en producción se usaría un agente dedicado en el grupo `docker`, no el
controlador como root.

**Docker Desktop no arranca** con un error tipo `remove ...\dockerInference: The file cannot be
accessed by the system`. Son sockets huérfanos que Windows no deja borrar. La solución es renombrar
la carpeta que los contiene (Docker la recrea):

```bash
mv "$LOCALAPPDATA/Docker/run" "$LOCALAPPDATA/Docker/run.roto"
```

Puede haber más de una: el mensaje de error dice cuál.

---

## 9. Apagar Jenkins

```bash
cd jenkins && docker compose down
```

Los datos sobreviven en el volumen `jenkins_jenkins_home`. Para borrarlos también:
`docker compose down -v`.
