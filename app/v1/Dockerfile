# --- Etapa 1: instalar dependencias en un virtualenv -------------------------
FROM python:3.12.16-alpine3.24 AS build

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
# Se desinstala pip del venv una vez usado: no hace falta en runtime.
RUN pip install --no-cache-dir -r requirements.txt \
    && pip uninstall -y pip

# --- Etapa 2: imagen final ---------------------------------------------------
# Alpine en lugar de python:3.12-slim (Debian): la base Debian traia 44 CVEs HIGH
# sin parche (util-linux, ncurses, systemd...) que la app no usa. Ver
# reports/trivyreport.txt.
FROM python:3.12.16-alpine3.24

# pip y setuptools no se necesitan en runtime: se sacan para achicar la
# superficie de ataque.
RUN pip uninstall -y pip setuptools 2>/dev/null; \
    adduser -D -H -u 10001 app

COPY --from=build /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY main.py .

# UID numerico: Kubernetes solo puede verificar runAsNonRoot si el usuario de la
# imagen es un numero (con un nombre no sabe si es root o no).
USER 10001

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
