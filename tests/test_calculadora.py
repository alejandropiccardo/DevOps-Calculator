"""Tests de la Calculadora API.

Corren contra la variante indicada por APP_VARIANTE (v1 por defecto v2).
La diferencia entre versiones se verifica explicitamente en test_raiz_*.
"""
import pytest


# --- endpoints de servicio --------------------------------------------------

def test_root_declara_version_y_operaciones(cliente, variante):
    r = cliente.get("/")
    assert r.status_code == 200
    cuerpo = r.json()
    assert cuerpo["app"] == "calculadora"
    assert cuerpo["version"].startswith("1." if variante == "v1" else "2.")
    assert cuerpo["color"] == ("blue" if variante == "v1" else "green")
    assert {"suma", "resta", "multiplicacion", "division"} <= set(cuerpo["operaciones"])


def test_health_responde_ok(cliente):
    r = cliente.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_metrics_expone_formato_prometheus(cliente):
    r = cliente.get("/metrics")
    assert r.status_code == 200
    assert "text/plain" in r.headers["content-type"]
    assert "calculadora_operaciones_total" in r.text


# --- operaciones validas ----------------------------------------------------

@pytest.mark.parametrize(
    "operacion,params,esperado",
    [
        ("suma", {"a": 2, "b": 3}, 5.0),
        ("suma", {"a": -4, "b": 4}, 0.0),
        ("suma", {"a": 0.5, "b": 0.25}, 0.75),
        ("resta", {"a": 9, "b": 4}, 5.0),
        ("resta", {"a": 3, "b": 10}, -7.0),
        ("multiplicacion", {"a": 6, "b": 7}, 42.0),
        ("multiplicacion", {"a": 5, "b": 0}, 0.0),
        ("division", {"a": 10, "b": 2}, 5.0),
        ("division", {"a": 7, "b": 2}, 3.5),
    ],
)
def test_operaciones_devuelven_el_resultado_correcto(cliente, operacion, params, esperado):
    r = cliente.get(f"/{operacion}", params=params)
    assert r.status_code == 200
    cuerpo = r.json()
    assert cuerpo["operacion"] == operacion
    assert cuerpo["resultado"] == pytest.approx(esperado)


def test_la_respuesta_identifica_que_version_respondio(cliente, variante):
    """Es lo que hace visible el switch blue/green en produccion."""
    cuerpo = cliente.get("/suma", params={"a": 1, "b": 1}).json()
    assert "version" in cuerpo and "color" in cuerpo
    assert cuerpo["color"] == ("blue" if variante == "v1" else "green")


# --- operaciones invalidas --------------------------------------------------

def test_division_por_cero_devuelve_400(cliente):
    r = cliente.get("/division", params={"a": 1, "b": 0})
    assert r.status_code == 400
    assert "cero" in r.json()["detail"].lower()


@pytest.mark.parametrize("valor", ["abc", "", "1,5"])
def test_parametro_no_numerico_devuelve_422(cliente, valor):
    r = cliente.get("/suma", params={"a": valor, "b": 3})
    assert r.status_code == 422


def test_falta_un_parametro_obligatorio_devuelve_422(cliente):
    assert cliente.get("/suma", params={"a": 2}).status_code == 422


# --- diferencia entre versiones ---------------------------------------------

def test_raiz_solo_existe_en_v2(cliente, variante):
    r = cliente.get("/raiz", params={"a": 9})
    if variante == "v1":
        assert r.status_code == 404, "v1 no debe exponer /raiz"
    else:
        assert r.status_code == 200
        assert r.json()["resultado"] == pytest.approx(3.0)


def test_raiz_de_negativo_devuelve_400(cliente, variante):
    if variante == "v1":
        pytest.skip("v1 no tiene /raiz")
    r = cliente.get("/raiz", params={"a": -4})
    assert r.status_code == 400


# --- las metricas se incrementan de verdad ----------------------------------

def _leer_contador(texto, nombre, **labels):
    """Busca una serie en la salida de /metrics y devuelve su valor."""
    for linea in texto.splitlines():
        if not linea.startswith(nombre) or linea.endswith("_created"):
            continue
        if all(f'{k}="{v}"' in linea for k, v in labels.items()):
            return float(linea.rsplit(" ", 1)[1])
    return 0.0


def test_una_operacion_exitosa_incrementa_el_contador(cliente):
    antes = _leer_contador(cliente.get("/metrics").text,
                           "calculadora_operaciones_total", operacion="multiplicacion")
    cliente.get("/multiplicacion", params={"a": 3, "b": 3})
    despues = _leer_contador(cliente.get("/metrics").text,
                             "calculadora_operaciones_total", operacion="multiplicacion")
    assert despues == antes + 1


def test_una_operacion_invalida_incrementa_el_contador_de_errores(cliente):
    antes = _leer_contador(cliente.get("/metrics").text,
                           "calculadora_errores_total", motivo="division_por_cero")
    cliente.get("/division", params={"a": 1, "b": 0})
    despues = _leer_contador(cliente.get("/metrics").text,
                             "calculadora_errores_total", motivo="division_por_cero")
    assert despues == antes + 1
