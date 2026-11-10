"""Carga la variante de la app que se quiere probar.

Las dos versiones viven en archivos separados (app/v1/main.py y app/v2/main.py)
y ambas registran las mismas metricas en el registro global de
prometheus_client. Importar las dos en el mismo proceso explota con
"Duplicated timeseries in CollectorRegistry", asi que cada corrida de pytest
prueba una sola variante y el pipeline la ejecuta dos veces:

    APP_VARIANTE=v1 pytest tests/
    APP_VARIANTE=v2 pytest tests/
"""
import importlib.util
import os
import pathlib
import sys

import pytest
from fastapi.testclient import TestClient

VARIANTE = os.getenv("APP_VARIANTE", "v2")


@pytest.fixture(scope="session")
def variante():
    return VARIANTE


@pytest.fixture(scope="session")
def cliente():
    ruta = pathlib.Path(__file__).resolve().parent.parent / "app" / VARIANTE / "main.py"
    if not ruta.exists():
        pytest.fail(f"No existe {ruta}. APP_VARIANTE debe ser v1 o v2.")

    spec = importlib.util.spec_from_file_location(f"calculadora_{VARIANTE}", ruta)
    modulo = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = modulo
    spec.loader.exec_module(modulo)
    return TestClient(modulo.app)
