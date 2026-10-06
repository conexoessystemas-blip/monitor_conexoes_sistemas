<#
===============================================================================
  Script de Instalação de Atalhos - Conexões Sistemas
  Cria atalhos na Área de Trabalho e na Inicialização do Windows (Startup)
===============================================================================
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$exePath = Join-Path $scriptDir "monitoramento_conexoes.exe"
$icoPath = Join-Path $scriptDir "avatar.ico"
$shell = New-Object -ComObject WScript.Shell

Write-Host "Criando atalhos para o Monitoramento Conexões Sistemas..." -ForegroundColor Cyan

# 1. Atalho na Inicialização do Windows
$startupDir = [Environment]::GetFolderPath("Startup")
$startupLnk = Join-Path $startupDir "Monitoramento Conexoes.lnk"
$sc1 = $shell.CreateShortcut($startupLnk)
$sc1.TargetPath = $exePath
$sc1.WorkingDirectory = $scriptDir
if (Test-Path $icoPath) { $sc1.IconLocation = $icoPath }
$sc1.Description = "Monitoramento Conexões Sistemas"
$sc1.Save()
Write-Host "✔ Atalho de inicialização criado: $startupLnk" -ForegroundColor Green

# 2. Atalho na Área de Trabalho
$desktopDir = [Environment]::GetFolderPath("Desktop")
$desktopLnk = Join-Path $desktopDir "Monitoramento Conexoes.lnk"
$sc2 = $shell.CreateShortcut($desktopLnk)
$sc2.TargetPath = $exePath
$sc2.WorkingDirectory = $scriptDir
if (Test-Path $icoPath) { $sc2.IconLocation = $icoPath }
$sc2.Description = "Monitoramento Conexões Sistemas"
$sc2.Save()
Write-Host "✔ Atalho na Área de Trabalho criado: $desktopLnk" -ForegroundColor Green

Write-Host "Instalação de atalhos finalizada com sucesso!" -ForegroundColor Green
