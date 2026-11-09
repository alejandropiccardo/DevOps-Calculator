from fastapi import FastAPI, HTTPException, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
import os
import time

APP_VERSION = os.getenv("APP_VERSION", "1.2")
APP_COLOR = os.getenv("APP_COLOR", "blue")

OPERACIONES = ["suma", "resta", "multiplicacion", "division"]

app = FastAPI(title="Calculadora API", version=APP_VERSION)

# Metricas que Prometheus recolecta desde /metrics.
OPERACIONES_TOTAL = Counter(
    "calculadora_operaciones_total",
    "Operaciones resueltas correctamente",
    ["operacion", "version"],
)

ERRORES_TOTAL = Counter(
    "calculadora_errores_total",
    "Operaciones rechazadas por entrada invalida",
    ["operacion", "motivo", "version"],
)

# Latencia y volumen de peticiones HTTP (para RPS y latencia promedio en Grafana).
# El label "path" es la ruta declarada en la app, no la URL pedida: si no, cada
# URL inventada (404) crearia una serie nueva en Prometheus.
PETICIONES_SEGUNDOS = Histogram(
    "calculadora_peticiones_segundos",
    "Duracion de las peticiones HTTP",
    ["metodo", "path", "codigo", "version"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5),
)


def resultado(operacion: str, valor: float):
    """Unico punto de salida de las operaciones exitosas: aca se cuentan todas."""
    OPERACIONES_TOTAL.labels(operacion=operacion, version=APP_VERSION).inc()
    return {
        "operacion": operacion,
        "resultado": valor,
        "version": APP_VERSION,
        "color": APP_COLOR,
    }


def rechazar(operacion: str, motivo: str, detalle: str) -> HTTPException:
    """Cuenta la operacion invalida y devuelve la excepcion para que el caller la lance."""
    ERRORES_TOTAL.labels(
        operacion=operacion, motivo=motivo, version=APP_VERSION
    ).inc()
    return HTTPException(status_code=400, detail=detalle)


@app.exception_handler(RequestValidationError)
async def parametros_invalidos(request: Request, exc: RequestValidationError):
    """FastAPI valida los tipos antes de entrar al endpoint, asi que ese rechazo
    (422, por ejemplo a=abc) nunca pasa por rechazar(). Se cuenta aca."""
    ERRORES_TOTAL.labels(
        operacion=request.url.path.strip("/") or "desconocida",
        motivo="parametro_invalido",
        version=APP_VERSION,
    ).inc()
    return JSONResponse(
        status_code=422, content={"detail": jsonable_encoder(exc.errors())}
    )


@app.middleware("http")
async def medir_latencia(request: Request, call_next):
    inicio = time.perf_counter()
    respuesta = await call_next(request)
    # /metrics y /health no se miden: los consultan Prometheus y las probes del
    # kubelet cada pocos segundos y ensuciarian el RPS.
    if request.url.path not in ("/metrics", "/health"):
        ruta = request.scope.get("route")
        PETICIONES_SEGUNDOS.labels(
            metodo=request.method,
            path=ruta.path if ruta else "no_encontrada",
            codigo=str(respuesta.status_code),
            version=APP_VERSION,
        ).observe(time.perf_counter() - inicio)
    return respuesta


@app.get("/")
def root():
    return {
        "app": "calculadora",
        "version": APP_VERSION,
        "color": APP_COLOR,
        "operaciones": OPERACIONES,
    }


@app.get("/health")
def health():
    return {"status": "ok", "version": APP_VERSION, "color": APP_COLOR}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/suma")
def suma(a: float, b: float):
    return resultado("suma", a + b)


@app.get("/resta")
def resta(a: float, b: float):
    return resultado("resta", a - b)


@app.get("/multiplicacion")
def multiplicacion(a: float, b: float):
    return resultado("multiplicacion", a * b)


@app.get("/division")
def division(a: float, b: float):
    if b == 0:
        raise rechazar("division", "division_por_cero", "No se puede dividir entre cero")
    return resultado("division", a / b)
