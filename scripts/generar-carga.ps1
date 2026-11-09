<#
.SYNOPSIS
  Genera trafico contra la calculadora para disparar las alertas de Prometheus.

.DESCRIPTION
  Consulta primero que operaciones expone la version activa (blue no tiene raiz)
  y arma la carga en consecuencia, para que no se desperdicien requests en 404.

.EXAMPLE
  .\scripts\generar-carga.ps1 -Url http://127.0.0.1:57274
  .\scripts\generar-carga.ps1 -Url http://127.0.0.1:57274 -Validas 40 -Invalidas 12
#>
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$Validas = 30,     # umbral de DemasiadasOperaciones: 20 en 5 min
    [int]$Invalidas = 10    # umbral de DemasiadasOperacionesInvalidas: 5 en 5 min
)

# Que version esta sirviendo el Service en este momento
$info = curl.exe -s "$Url/" | ConvertFrom-Json
$tieneRaiz = $info.operaciones -contains "raiz"
Write-Host "Version activa: $($info.version) ($($info.color)) - raiz disponible: $tieneRaiz" -ForegroundColor Cyan

$ok  = @("suma?a=2&b=3", "resta?a=9&b=4", "multiplicacion?a=6&b=7", "division?a=10&b=2")
$mal = @("division?a=1&b=0", "suma?a=abc&b=3")

if ($tieneRaiz) {
    $ok  += "raiz?a=16"
    $mal += "raiz?a=-9"
}

Write-Host "Enviando $Validas operaciones validas ..." -ForegroundColor Cyan
for ($i = 0; $i -lt $Validas; $i++) { curl.exe -s -o NUL "$Url/$($ok[$i % $ok.Count])" }

Write-Host "Enviando $Invalidas operaciones invalidas ..." -ForegroundColor Yellow
for ($i = 0; $i -lt $Invalidas; $i++) { curl.exe -s -o NUL "$Url/$($mal[$i % $mal.Count])" }

Write-Host ""
Write-Host "Listo. Las alertas tardan ~45 s en pasar a FIRING." -ForegroundColor Green
Write-Host "  (evaluacion cada 15 s + 'for: 30s' en la regla)" -ForegroundColor DarkGray
Write-Host "  Prometheus: http://127.0.0.1:30090/alerts" -ForegroundColor Gray
Write-Host "  Grafana:    http://127.0.0.1:30030  (admin / devops2026)" -ForegroundColor Gray
