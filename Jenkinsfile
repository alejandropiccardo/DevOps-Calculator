// Pipeline de integracion y entrega continua de la Calculadora API.
//
// Etapas (consigna punto 3.b):
//   1. Clonacion del repositorio
//   2. Analisis de codigo estatico con Semgrep
//   3. Escaneo de vulnerabilidades de dependencias con Snyk
//   4. Construccion y test de la aplicacion
//   5. Construccion y publicacion de la imagen Docker
//   6. Despliegue en Kubernetes con Helm
//
// Credenciales que espera en Jenkins (ver docs/06-jenkins.md):
//   dockerhub      Username with password  - usuario y token de DockerHub
//   snyk-token     Secret text             - token de https://app.snyk.io/account
//   kubeconfig-ucu Secret file             - el grupo5.yaml del cluster de la UCU

pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
    }

    parameters {
        choice(
            name: 'ENTORNO_ACTIVO',
            choices: ['blue', 'green'],
            description: 'A que entorno apunta el Service despues del despliegue (blue = v1, green = v2).'
        )
        booleanParam(
            name: 'DESPLEGAR',
            defaultValue: true,
            description: 'Desmarcar para correr solo CI (analisis, tests e imagen) sin tocar el cluster.'
        )
    }

    environment {
        IMAGEN    = 'alejandropiccardo/calculadora'
        NAMESPACE = 'obligatorio-grupo5'
        RELEASE   = 'calculadora'
        // TAG_V1 y TAG_V2 no se pueden definir aca: se calculan a partir del
        // hash del commit en la etapa 1, cuando ya existe el repo clonado.
    }

    stages {

        stage('1. Clonar repositorio') {
            steps {
                checkout scm
                script {
                    // El tag de la imagen sale del commit, no del numero de build.
                    // Asi la imagen que corre en el cluster se puede rastrear hasta
                    // el codigo exacto que la produjo, y volver a correr el pipeline
                    // sobre el mismo commit da el mismo tag (mismo codigo, misma
                    // imagen) en vez de una version nueva que no cambia nada.
                    env.COMMIT = sh(returnStdout: true, script: 'git rev-parse --short=7 HEAD').trim()
                    env.TAG_V1 = "1.2-${env.COMMIT}"
                    env.TAG_V2 = "2.2-${env.COMMIT}"
                    // Deja el commit visible en el historial de builds de Jenkins.
                    currentBuild.description = "${env.COMMIT} -> ${params.ENTORNO_ACTIVO}"
                }
                sh '''
                    mkdir -p reports
                    echo "Commit:  $(git rev-parse HEAD)"
                    echo "Rama:    ${GIT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
                    echo "Autor:   $(git log -1 --format='%an <%ae>')"
                    echo "Mensaje: $(git log -1 --format='%s')"
                    echo ""
                    echo "Imagenes que va a publicar este build:"
                    echo "  $IMAGEN:$TAG_V1"
                    echo "  $IMAGEN:$TAG_V2"
                '''
            }
        }

        stage('2. Analisis estatico (Semgrep)') {
            steps {
                // --error hace que Semgrep salga con codigo != 0 si encuentra algo,
                // y --severity ERROR limita el corte a los hallazgos criticos.
                // El informe completo (todas las severidades) se genera aparte para
                // que quede como evidencia aunque el build pase.
                sh '''
                    set +e
                    echo "--- Informe completo (todas las severidades) ---"
                    semgrep scan \
                        --config semgrep/reglas-python.yaml \
                        --config p/python --config p/dockerfile \
                        --config p/kubernetes --config p/secrets --config p/security-audit \
                        --metrics=off --no-git-ignore \
                        app k8s monitoring helm \
                        > reports/semgrep-ci.txt 2>&1
                    tail -40 reports/semgrep-ci.txt
                    set -e

                    echo ""
                    echo "--- Corte por hallazgos criticos (severidad ERROR) ---"
                    semgrep scan \
                        --config semgrep/reglas-python.yaml \
                        --config p/python --config p/dockerfile \
                        --config p/kubernetes --config p/secrets --config p/security-audit \
                        --metrics=off --no-git-ignore \
                        --severity ERROR --error \
                        app k8s monitoring helm
                '''
            }
        }

        stage('3. Dependencias (Snyk)') {
            steps {
                withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
                    sh '''
                        snyk auth "$SNYK_TOKEN" >/dev/null 2>&1

                        echo "--- Informe completo de dependencias ---"
                        set +e
                        for v in v1 v2; do
                            echo "===== app/$v ====="
                            snyk test \
                                --file=app/$v/requirements.txt \
                                --package-manager=pip \
                                --severity-threshold=low
                        done | tee reports/snyk-ci.txt
                        set -e

                        echo ""
                        echo "--- Corte por vulnerabilidades CRITICAS ---"
                        # snyk sale con codigo 1 si encuentra algo en el umbral o
                        # por encima: eso frena el pipeline, que es lo que pide la
                        # consigna (punto 3.e).
                        for v in v1 v2; do
                            echo "===== app/$v ====="
                            snyk test \
                                --file=app/$v/requirements.txt \
                                --package-manager=pip \
                                --severity-threshold=critical
                        done
                    '''
                }
            }
        }

        stage('4. Construccion y test') {
            steps {
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --quiet --upgrade pip
                    pip install --quiet -r app/v2/requirements.txt pytest httpx

                    # Las dos variantes se prueban en procesos separados: ambas
                    # registran las mismas metricas en el registro global de
                    # prometheus_client y chocarian en el mismo interprete.
                    APP_VARIANTE=v1 pytest tests/ -v --junitxml=reports/junit-v1.xml
                    APP_VARIANTE=v2 pytest tests/ -v --junitxml=reports/junit-v2.xml
                '''
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'reports/junit-*.xml'
                }
            }
        }

        stage('5. Imagen Docker') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub',
                    usernameVariable: 'DOCKER_USUARIO',
                    passwordVariable: 'DOCKER_TOKEN'
                )]) {
                    sh '''
                        echo "$DOCKER_TOKEN" | docker login -u "$DOCKER_USUARIO" --password-stdin

                        # Cada imagen lleva dos tags:
                        #   1.2-<commit>  inmutable, es el que despliega Helm
                        #   1.2           movil, apunta al ultimo build de esa
                        #                 version (comodidad para "docker pull"
                        #                 a mano; el cluster nunca lo usa)
                        docker build -t "$IMAGEN:$TAG_V1" -t "$IMAGEN:1.2" app/v1
                        docker build -t "$IMAGEN:$TAG_V2" -t "$IMAGEN:2.2" app/v2

                        docker push "$IMAGEN:$TAG_V1"
                        docker push "$IMAGEN:1.2"
                        docker push "$IMAGEN:$TAG_V2"
                        docker push "$IMAGEN:2.2"

                        docker logout
                    '''
                }
            }
        }

        stage('6. Despliegue con Helm') {
            when { expression { return params.DESPLEGAR } }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig-ucu', variable: 'KUBECONFIG')]) {
                    sh '''
                        helm lint helm/calculadora

                        helm upgrade --install "$RELEASE" helm/calculadora \
                            --namespace "$NAMESPACE" \
                            --set imagen.repositorio="$IMAGEN" \
                            --set imagen.pullPolicy=Always \
                            --set entornos.blue.tag="$TAG_V1" \
                            --set entornos.green.tag="$TAG_V2" \
                            --set entornoActivo="$ENTORNO_ACTIVO" \
                            --wait --timeout 5m

                        echo ""
                        echo "--- Estado del despliegue ---"
                        kubectl get deployments,pods,svc -n "$NAMESPACE" -l app=calculadora -L version
                        echo ""
                        echo "--- Endpoints activos (a que entorno enruta el Service) ---"
                        kubectl get endpointslice -n "$NAMESPACE" \
                            -l kubernetes.io/service-name=calculadora -o wide
                    '''
                }
            }
        }

        stage('7. Smoke test en el cluster') {
            when { expression { return params.DESPLEGAR } }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig-ucu', variable: 'KUBECONFIG')]) {
                    sh '''
                        # Se consulta el Service desde adentro del cluster: es el
                        # unico camino que refleja el selector real.
                        kubectl run smoke-$BUILD_NUMBER \
                            --namespace "$NAMESPACE" \
                            --image=curlimages/curl:8.11.1 \
                            --restart=Never --rm -i --quiet \
                            --command -- curl -sf http://calculadora/ \
                            | tee reports/smoke-test.txt
                        echo ""
                    '''
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true, fingerprint: true
        }
        success {
            echo "OK. Commit desplegado: ${env.COMMIT}"
            echo "Imagenes publicadas: ${IMAGEN}:${TAG_V1} y ${IMAGEN}:${TAG_V2}"
            echo "Entorno activo en el cluster: ${params.ENTORNO_ACTIVO}"
        }
        failure {
            echo 'El pipeline fallo. Revisar la etapa marcada en rojo.'
            echo 'Si fallo en Semgrep o Snyk, el detalle esta en los artefactos: reports/semgrep-ci.txt y reports/snyk-ci.txt'
        }
        cleanup {
            sh 'rm -rf .venv || true'
        }
    }
}
