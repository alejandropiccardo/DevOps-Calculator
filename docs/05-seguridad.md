# 5. Seguridad integrada (DevSecOps)

## 5.1 Análisis estático (Semgrep)

```bash
./scripts/escanear-semgrep.sh
```

Además de los rulesets `p/python`, `p/dockerfile`, `p/kubernetes`, `p/secrets` y `p/security-audit`, se
aplican tres reglas propias para Python en [`semgrep/reglas-python.yaml`](../semgrep/reglas-python.yaml):

| Regla                          | Detecta                                   | CWE    |
|--------------------------------|-------------------------------------------|--------|
| `calculadora-eval-exec`        | `eval()` / `exec()`                       | CWE-95 |
| `calculadora-subprocess-shell` | `subprocess` con `shell=True`             | CWE-78 |
| `calculadora-fastapi-debug`    | `FastAPI(debug=True)`                     | CWE-489|

Resultado actual:

```
Ran 258 rules on 13 files: 0 findings.
```

Los 6 hallazgos originales eran de los manifiestos (`run-as-non-root` y `writable-filesystem-container`) y se
corrigieron con `securityContext`. Las justificaciones de lo que se mantiene y el antes/después están en
[`reports/semgrep-report.txt`](../reports/semgrep-report.txt).

## 5.2 Escaneo de dependencias (Snyk)

Requiere un token de una cuenta de Snyk: https://app.snyk.io/account

```bash
SNYK_TOKEN=xxxx ./scripts/escanear-snyk.sh
```

El resultado se guarda en `reports/snyk-report.txt`.

Resultado para `app/v1` y `app/v2`:

```
Tested 15 dependencies for known issues, found 0 issues, 0 vulnerable paths.
Open Security issues: 0
```

No hay vulnerabilidades críticas abiertas. El antecedente es `starlette 0.41.3`, con 7 vulnerabilidades según
`pip-audit` ([`reports/npm-audit.txt`](../reports/npm-audit.txt)); se corrigió actualizando a `fastapi 0.162.0` y
fijando `starlette 1.10.0`.

## 5.3 Políticas de Kubernetes (Kyverno)

Kyverno 1.19.2 con cuatro `ValidatingPolicy` en modo `Deny`, en [`kyverno/politicas/`](../kyverno/politicas):

| # | Política                 | Rechaza                                                           |
|---|--------------------------|-------------------------------------------------------------------|
| 1 | `prohibir-tag-latest`    | Imágenes `latest` o sin tag                                       |
| 2 | `exigir-requests-limits` | Contenedores sin requests y limits de CPU y memoria               |
| 3 | `prohibir-root`          | Contenedores como root                                            |
| 4 | `prohibir-privilegiados` | `privileged: true` o `allowPrivilegeEscalation: true`             |

```bash
./scripts/validar-kyverno.sh
```

Resultado (`reports/kyverno-validation.log`): los 5 objetos no conformes se rechazan, el pod conforme se
acepta y los manifiestos del proyecto pasan el dry-run en el servidor.

```
admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy prohibir-tag-latest failed: ...
admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy exigir-requests-limits failed: ...
admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy prohibir-root failed: ...
admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy prohibir-privilegiados failed: ...

pod/prueba-conforme created
```

## 5.4 Seguridad en tiempo de ejecución (Falco)

Falco 0.45.1, instalado con el chart oficial (driver `modern_ebpf`). Requiere Helm solo para este paso:

```bash
helm install falco falco --repo https://falcosecurity.github.io/charts --version 9.2.1 -n falco --create-namespace -f falco/values.yaml
```

Disparar el evento y guardar la alerta:

```bash
./scripts/disparar-falco.sh
```

**Evento detectado:** el Pod [`prueba-falco`](../falco/prueba-falco.yaml) ejecuta `find /etc -name id_rsa`,
lo mismo que haría un atacante que busca claves privadas dentro de un contenedor comprometido. No se abre
ningún shell: `find` es directamente el comando del contenedor. Falco lo detecta con la regla por defecto
**Search Private Keys or Passwords**, prioridad Warning.

```
Warning Grep private keys or passwords activities found | evt_type=execve user_uid=10001 process=find
proc_exepath=/bin/busybox parent=containerd-shim command=find /etc -name id_rsa terminal=0
container_image_repository=calculadora container_image_tag=2.2 k8s_pod_name=prueba-falco
```

La alerta completa está en [`reports/falco-event.log`](../reports/falco-event.log).
