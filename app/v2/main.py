from fastapi import FastAPI, HTTPException
import math
import os

APP_VERSION = os.getenv("APP_VERSION", "2.0")
APP_COLOR = os.getenv("APP_COLOR", "green")

OPERACIONES = ["suma", "resta", "multiplicacion", "division", "raiz"]

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


@app.get("/raiz")
def raiz(a: float):
    if a < 0:
        raise HTTPException(
            status_code=400, detail="No existe raiz cuadrada real de un numero negativo"
        )
    return resultado("raiz", math.sqrt(a))
