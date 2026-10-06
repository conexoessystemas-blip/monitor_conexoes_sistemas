<#
===============================================================================
  Script de Compilação Automatizada - Conexões Sistemas
  Compila monitoramento_conexoes.ps1 em monitoramento_conexoes.exe
===============================================================================
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$ps1Path = Join-Path $scriptDir "monitoramento_conexoes.ps1"
$exePath = Join-Path $scriptDir "monitoramento_conexoes.exe"
$icoPath = Join-Path $scriptDir "avatar.ico"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Conexões Sistemas - Compilador de Executável Oficial" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Write-Host "Módulo 'ps2exe' não encontrado. Instalando..." -ForegroundColor Yellow
    Install-Module ps2exe -Scope CurrentUser -Force -SkipPublisherCheck
}

Write-Host "Compilando: $ps1Path -> $exePath" -ForegroundColor Green

Invoke-ps2exe -inputFile $ps1Path `
              -outputFile $exePath `
              -iconFile $icoPath `
              -noConsole `
              -STA `
              -winFormsDPIAware `
              -requireAdmin `
              -title "Conexoes Sistemas - Monitoramento" `
              -description "Painel de Monitoramento de Servicos Conexoes Sistemas" `
              -company "Conexoes Sistemas" `
              -product "Monitoramento de Servicos" `
              -copyright "Conexoes Sistemas (c) 2026" `
              -version "3.0.0.0"

if (Test-Path $exePath) {
    $info = Get-Item $exePath
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host " COMPILAÇÃO CONCLUÍDA COM SUCESSO!" -ForegroundColor Green
    Write-Host " Executável: $($info.FullName) ($([Math]::Round($info.Length / 1KB, 1)) KB)" -ForegroundColor White
    Write-Host "==========================================================" -ForegroundColor Green
} else {
    Write-Host "ERRO: Falha na geração do executável." -ForegroundColor Red
}
