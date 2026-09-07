from fastapi import FastAPI, HTTPException
import os

APP_VERSION = os.getenv("APP_VERSION", "1.0")
APP_COLOR = os.getenv("APP_COLOR", "blue")

OPERACIONES = ["suma", "resta", "multiplicacion", "division"]

app = FastAPI(title="Calculadora API", version=APP_VERSION)


def resultado(operacion: str, valor: float):
    return {
        "operacion": operacion,
        "resultado": valor,
        "version": APP_VERSION,
        "color": APP_COLOR,
    }


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
        raise HTTPException(status_code=400, detail="No se puede dividir entre cero")
    return resultado("division", a / b)
