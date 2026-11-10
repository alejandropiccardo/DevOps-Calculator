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

## 6. Trazabilidad: el tag de la imagen es el commit

Cada build publica cuatro tags en DockerHub:

| Tag | Mutable | Para qué |
|---|---|---|
| `1.2-a1b2c3d` | no | v1 construida desde el commit `a1b2c3d`. **Es el que despliega Helm.** |
| `2.2-a1b2c3d` | no | idem v2 |
| `1.2` | sí | último build de v1. Comodidad para un `docker pull` a mano. |
| `2.2` | sí | idem v2 |

El tag se calcula en la etapa 1, después del `checkout`:

```groovy
env.COMMIT = sh(returnStdout: true, script: 'git rev-parse --short=7 HEAD').trim()
env.TAG_V1 = "1.2-${env.COMMIT}"
```

**Por qué el commit y no el número de build.** Con `1.2.${BUILD_NUMBER}` el tag es único pero no
dice nada: para saber qué código corre en el cluster hay que entrar a Jenkins, buscar ese build y
leer qué commit clonó — y si el build se borró por el `logRotator`, se perdió. Con el hash, el
camino es directo y en los dos sentidos:

```bash
kubectl get deploy calculadora-green -n obligatorio-grupo5 -o jsonpath='{..image}'
```

Eso devuelve `alepiccardo/calculadora:2.2-a1b2c3d`, y `git show a1b2c3d` es el código exacto.
De paso, volver a correr el pipeline sobre el mismo commit produce el mismo tag: mismo código,
misma imagen, en vez de una versión nueva que no cambió nada.

El número de build no se pierde: queda en la descripción del build de Jenkins
(`currentBuild.description`), junto al entorno al que se conmutó.

---

## 7. El despliegue blue/green desde el pipeline

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

## 8. Acceder a la app desplegada

La app se expone con un **Ingress** sobre el gateway APISIX del cluster:

```
https://calculadora-grupo5.reto-ucu.net/docs
```

`*.reto-ucu.net` es un DNS wildcard que resuelve al gateway, asi que no hay que registrar nada:
alcanza con elegir un host libre en `ingress.host` de los values.

> **Usar HTTPS, no HTTP.** El gateway sirve la app por 443 con certificado valido. El puerto 80
> de esa misma IP lo atiende otro servicio ajeno al cluster, asi que `http://` devuelve 200 con
> una pagina que no es la tuya: es facil confundirlo con un Ingress mal configurado. El Ingress apunta al **Service**,
no a los Deployments, asi que conmutar blue/green tambien cambia lo que sirve la URL publica, sin
tocar el Ingress.

Para verlo sin pasar por el gateway (util para aislar si un problema es del Ingress o de la app):

El Service es `ClusterIP` a propósito. La separación entre grupos en el cluster de la UCU es por
**namespace**: nosotros somos `obligatorio-grupo5`, de ahí el nombre del kubeconfig. El namespace
aísla los *nombres* de los objetos, así que varios grupos pueden tener un Service llamado
`calculadora` sin pisarse.

Un `nodePort`, en cambio, **no es namespaced**: se reserva en la IP de todos los nodos, por fuera de
cualquier namespace. Si nosotros pedimos el 30080 y otro grupo pide el mismo, el segundo Service no
se crea:

```
The Service "calculadora" is invalid: spec.ports[0].nodePort: Invalid value: 30080: provided port is already allocated
```

Con `ClusterIP` el Service solo existe adentro del cluster y se llega por `port-forward`, que es un
túnel por la API de Kubernetes y no reserva nada compartido. El chart igual soporta `NodePort`
(`service.tipo` y `service.nodePort` en los values), que es lo que se usaba en minikube.

La forma correcta de exponerlo con una URL propia por grupo sería un **Ingress** con host tipo
`calculadora-grupo5.<dominio>`: el hostname sí distingue grupos sobre un único puerto 80/443. El
ServiceAccount tiene permisos para crear Ingress, pero no sabemos qué controlador ni qué dominio
usa la cátedra, así que queda como la extensión natural cuando lo confirmen.

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

## 9. Problemas conocidos

**`kubectl` devuelve HTML de login.** Sin `KUBECONFIG`, kubectl va a `localhost:8080`, que dentro
del contenedor **es el propio Jenkins**. Significa que la credencial `kubeconfig-ucu` no se cargó.

**Semgrep o Snyk fallan sin hallazgos reales.** Revisar el informe completo en los artefactos: el
corte usa un umbral más estricto que el informe, así que puede frenar por algo que no aparece en
las primeras líneas.

**Snyk: `Failed to test pip project` (SNYK-CLI-0000).** El mensaje es genérico; la causa real sale
corriendo el mismo comando con `-d`. Hay dos trampas, y la etapa 3 resuelve las dos:

| Error con `-d` | Causa | Solución aplicada |
|---|---|---|
| `spawn python ENOENT` | el plugin de pip invoca `python` y la imagen solo trae `python3` | `--command="$PWD/.snyk-$v/bin/python"` |
| `Missing required packages` (422) | Snyk resuelve el árbol leyendo los paquetes **instalados**, no el `requirements.txt` | un venv por variante con las dependencias instaladas antes de escanear |

Para reproducirlo a mano dentro del contenedor:

```bash
docker exec -w /var/jenkins_home/workspace/<job> jenkins snyk test --file=app/v1/requirements.txt --package-manager=pip -d
```

**Los plugins fallan en cascada al instalarse, con decenas de errores rojos.** La causa raíz es una
sola y está en el log: `- Jenkins (X.Y.Z) or higher required`. El update center sirve siempre la
última versión de cada plugin, así que una imagen base vieja los rompe todos y el resto son
dependencias del primero que falló. Se arregla subiendo el `FROM` del
[`jenkins/Dockerfile`](../jenkins/Dockerfile) y reconstruyendo con el volumen limpio
(`docker compose down -v && docker compose build --no-cache`). Para ver la causa sin la cascada:

```bash
docker logs jenkins 2>&1 | grep "or higher required"
```

**`endpointslices.discovery.k8s.io is forbidden` en la etapa 6.** El despliegue salio bien; lo que
falla es el comando de diagnostico que sigue. El ServiceAccount del grupo no tiene permisos sobre
`discovery.k8s.io`, pero si sobre la API vieja `endpoints` (core/v1), que da la misma informacion.
La etapa usa esa, y ademas con `|| true`: un despliegue correcto no puede quedar en rojo porque
falte un permiso de lectura.

**La etapa 6 se queda 5 minutos y muere en el timeout.** No es lentitud: es la `ResourceQuota`
`student-quota` del namespace, que topea `requests.cpu` en **200m para todo el namespace**. Un
rolling update necesita cuota libre para crear el pod nuevo antes de matar al viejo; si la cuota
esta al tope, no crea nada, no mata nada, y se traba hasta el timeout. Para verlo:

```bash
kubectl describe resourcequota -n obligatorio-grupo5
```

```bash
kubectl get events -n obligatorio-grupo5 --sort-by=.lastTimestamp | grep FailedCreate
```

El chart lo evita por dos lados: `requests.cpu` de 25m (el default del `LimitRange` del namespace,
4 pods = 100m de 200m) y `maxSurge: 0`, que libera un pod antes de crear el reemplazo y por lo tanto
nunca necesita cuota extra.

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

## 10. Apagar Jenkins

```bash
cd jenkins && docker compose down
```

Los datos sobreviven en el volumen `jenkins_jenkins_home`. Para borrarlos también:
`docker compose down -v`.
