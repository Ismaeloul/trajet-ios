# Levanta el laboratorio de diseño en la red local para verlo en el iPhone.
#   .\servir.ps1            -> puerto 7797
#   .\servir.ps1 -Port 8080
param([int]$Port = 7797)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "Hace falta Node.js (https://nodejs.org). No hay ninguna otra dependencia." -ForegroundColor Yellow
  exit 1
}

# Si el firewall de Windows pregunta, permite SOLO en redes privadas.
# Para hacerlo a mano (una vez, como administrador):
#   New-NetFirewallRule -DisplayName "Trajet design-lab" -Direction Inbound -Protocol TCP -LocalPort $Port -Profile Private -Action Allow
Write-Host "Si Windows pregunta por el firewall, permite solo en 'Redes privadas'." -ForegroundColor DarkGray

$env:PORT = $Port
node (Join-Path $root 'shared\servidor.js')
