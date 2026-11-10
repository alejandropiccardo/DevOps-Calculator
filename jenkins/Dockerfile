# Imagen de Jenkins con todo lo que necesita el pipeline ya instalado.
#
# Por que las herramientas van DENTRO de la imagen y no se corren como
# contenedores (docker run semgrep/semgrep ...):
#   Jenkins corre dentro de un contenedor y usa el socket de Docker del host.
#   Un "docker run -v $(pwd):/src" se interpreta contra el filesystem del HOST,
#   no contra el del contenedor de Jenkins, asi que el workspace no existiria y
#   el escaneo correria sobre una carpeta vacia.
#   "docker build" en cambio si funciona, porque el CLI lee el contexto y se lo
#   manda al daemon por el socket. Por eso el socket se usa solo para
#   build/push, y Semgrep, Snyk, kubectl y Helm van instalados aca.
FROM jenkins/jenkins:2.516.1-lts-jdk17

USER root

ARG KUBECTL_VERSION=v1.29.5
ARG HELM_VERSION=v3.16.3

# --- Docker CLI (solo el cliente: el daemon es el del host) ------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg python3 python3-venv python3-pip \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && chmod a+r /etc/apt/keyrings/docker.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli \
 && rm -rf /var/lib/apt/lists/*

# --- kubectl (misma minor que el cluster de la UCU: v1.29) ------------------
RUN curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && chmod +x /usr/local/bin/kubectl \
 && kubectl version --client

# --- Helm -------------------------------------------------------------------
RUN curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
      | tar xz -C /tmp \
 && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
 && chmod +x /usr/local/bin/helm \
 && rm -rf /tmp/linux-amd64 \
 && helm version --short

# --- Semgrep (analisis estatico) y pytest -----------------------------------
RUN pip3 install --no-cache-dir --break-system-packages \
      semgrep==1.181.1 pytest==8.3.4 httpx==0.28.1

# --- Snyk CLI (escaneo de dependencias) -------------------------------------
RUN curl -fsSLo /usr/local/bin/snyk https://static.snyk.io/cli/latest/snyk-linux \
 && chmod +x /usr/local/bin/snyk \
 && snyk --version

# Se queda como root a proposito: Jenkins necesita escribir en el socket de
# Docker montado desde el host, que pertenece a root. Es aceptable en un
# entorno de laboratorio local; en produccion se usaria un agente dedicado con
# el grupo docker y no el controlador corriendo como root.
USER root
