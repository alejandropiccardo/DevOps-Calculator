# 2. Orquestación y despliegue (Kubernetes)

El despliegue se hace con manifiestos de Kubernetes. Helm era opcional según la cátedra y no se usa para
la aplicación.

| Recurso                    | Archivo                                                    |
|----------------------------|------------------------------------------------------------|
| Deployment blue / green    | `k8s/deployment-blue.yaml`, `k8s/deployment-green.yaml`    |
| Service (NodePort)         | `k8s/service.yaml`                                         |
| ConfigMap por entorno      | `k8s/configmap.yaml`                                       |

No se usa Ingress: es un solo servicio HTTP y se accede por el NodePort.

## Paso a paso

Cargar las imágenes en minikube y desplegar:

```bash
minikube start --cpus=4 --memory=6144
minikube image load calculadora:1.2
minikube image load calculadora:2.2
kubectl apply -f k8s/
```

> Si las imágenes ya estaban en minikube, `image load` no reemplaza un tag existente. Borrarlas antes con
> `minikube ssh -- docker rmi -f calculadora:1.2 calculadora:2.2`. `scripts/iniciar.sh` ya lo hace.

## Verificación

Los pods iniciaron correctamente:

```
$ kubectl get pods -l app=calculadora
NAME                                 READY   STATUS    RESTARTS   AGE
calculadora-blue-86ccfcbff-5qjw2     1/1     Running   0          2m11s
calculadora-blue-86ccfcbff-pxcwr     1/1     Running   0          2m19s
calculadora-green-655f99497f-65qbp   1/1     Running   0          2m19s
calculadora-green-655f99497f-w6cmv   1/1     Running   0          2m11s
```

El servicio es accesible:

```
$ kubectl get svc calculadora
NAME          TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
calculadora   NodePort   10.104.85.27   <none>        80:30080/TCP   12d

$ kubectl port-forward svc/calculadora 18081:80
$ curl "http://127.0.0.1:18081/suma?a=2&b=3"
{"operacion":"suma","resultado":5.0,"version":"1.2","color":"blue"}
```
