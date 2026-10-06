from fastapi import FastAPI, HTTPException, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest
import math
import os

APP_VERSION = os.getenv("APP_VERSION", "2.1")
APP_COLOR = os.getenv("APP_COLOR", "green")

OPERACIONES = ["suma", "resta", "multiplicacion", "division", "raiz"]

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


@app.get("/raiz")
def raiz(a: float):
    if a < 0:
        raise rechazar(
            "raiz", "raiz_negativa", "No existe raiz cuadrada real de un numero negativo"
        )
    return resultado("raiz", math.sqrt(a))
