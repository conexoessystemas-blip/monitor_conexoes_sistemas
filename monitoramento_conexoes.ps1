<#
===============================================================================
  CONEXÕES SYSTEMAS - PAINEL CENTRAL DE MONITORAMENTO DE SERVIÇOS
  Versão: 3.0 Ultra (Enterprise Edition)
  Repositório GitHub: conexoessystemas-blip/monitor_conexoes_sistemas
===============================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# -----------------------------------------------------------------------------
# 1. DIRETÓRIO BASE E CONFIGURAÇÕES DINÂMICAS (JSON)
# -----------------------------------------------------------------------------
function Obter-DiretorioBase {
    try {
        if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) { return $PSScriptRoot }
        if ($MyInvocation.MyCommand.Path) {
            $dir = Split-Path -Parent $MyInvocation.MyCommand.Path
            if ($dir -and (Test-Path $dir)) { return $dir }
        }
        $exePath = [System.Windows.Forms.Application]::ExecutablePath
        if ($exePath) {
            $dir = Split-Path -Parent $exePath
            if ($dir -and (Test-Path $dir)) { return $dir }
        }
        $startup = [System.Windows.Forms.Application]::StartupPath
        if ($startup -and (Test-Path $startup)) { return $startup }
        return (Get-Location).Path
    } catch {
        return (Get-Location).Path
    }
}

$script:BasePath   = Obter-DiretorioBase
$script:ConfigPath = Join-Path $script:BasePath "config.json"
$script:LogPath    = Join-Path $script:BasePath "monitoramento_log.txt"
$script:SenhaServicosProtegidos = "ConexõesSystemas"

# Privilégios de Administrador
$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Carregamento e Persistência do config.json
function Carregar-Configuracao {
    $padrao = @{
        Configuracoes = @{
            IntervaloSegundos  = 10
            AutoRecuperacao    = $true
            MaxTentativasAuto  = 3
            CooldownSegundos   = 60
            NotificacaoSonora  = $true
            NotificacaoBalao   = $true
            TimeoutPortaMs     = 1000
            WebhookUrl         = ""
        }
        Servicos = @(
            @{ Nome = "ServicoFiscal"; Titulo = "Serviço Fiscal"; Descricao = "Emissão e sincronização fiscal (NFC-e / SAT)"; Porta = 0; Protegido = $false },
            @{ Nome = "QualityPulser"; Titulo = "Quality Pulser Web"; Descricao = "Comunicação e automação de bombas de combustível Quality"; Porta = 0; Protegido = $false },
            @{ Nome = "srvIntegraWeb"; Titulo = "Integra Web"; Descricao = "Integração web e sincronização de dados de pista"; Porta = 0; Protegido = $false },
            @{ Nome = "ServicoAutomacao"; Titulo = "webPosto Automação"; Descricao = "Leitura e automação de pista webPosto"; Porta = 0; Protegido = $false },
            @{ Nome = "ServicoBaixaAutomatica"; Titulo = "webPosto Baixa Automática"; Descricao = "Rotina de baixa automática de pendências webPosto"; Porta = 0; Protegido = $false },
            @{ Nome = "ServicoPremmia"; Titulo = "Serviço Premmia"; Descricao = "Integração do programa de fidelidade Premmia"; Porta = 0; Protegido = $false },
            @{ Nome = "ServicoSemParar"; Titulo = "Serviço Sem Parar"; Descricao = "Identificação e pagamento Sem Parar abastecimento"; Porta = 0; Protegido = $false },
            @{ Nome = "ServicoShellBox"; Titulo = "Serviço Shell Box"; Descricao = "Pagamentos e fidelidade Shell Box"; Porta = 0; Protegido = $false },
            @{ Nome = "ServicoCofre"; Titulo = "Serviço Cofre"; Descricao = "Comunicação e monitoramento do cofre inteligente"; Porta = 0; Protegido = $false },
            @{ Nome = "ServicoMicroTerminal"; Titulo = "Micro Terminal"; Descricao = "Comunicação com terminais e teclados de pista"; Porta = 0; Protegido = $false },
            @{ Nome = "postgresql-x64-9.5"; Titulo = "PostgreSQL 9.5"; Descricao = "Banco de Dados relacional PostgreSQL v9.5"; Porta = 5432; Protegido = $true },
            @{ Nome = "postgresql-x64-12"; Titulo = "PostgreSQL 12"; Descricao = "Banco de Dados relacional PostgreSQL v12"; Porta = 5432; Protegido = $true }
        )
    }

    if (Test-Path $script:ConfigPath) {
        try {
            $jsonStr = Get-Content -Path $script:ConfigPath -Raw -Encoding UTF8
            $obj = $jsonStr | ConvertFrom-Json
            if ($obj -and $obj.Servicos) { return $obj }
        } catch {}
    }

    # Salva padrão se não existir
    try {
        $json = $padrao | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($script:ConfigPath, $json, (New-Object System.Text.UTF8Encoding($true)))
    } catch {}

    return (ConvertFrom-Json ($padrao | ConvertTo-Json -Depth 5))
}

function Salvar-Configuracao {
    param($ConfigObj)
    try {
        $json = $ConfigObj | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($script:ConfigPath, $json, (New-Object System.Text.UTF8Encoding($true)))
        return $true
    } catch {
        return $false
    }
}

$script:ConfigData = Carregar-Configuracao
$script:TentativasAutoRecuperacao = @{}
$script:UltimoEstadoServicos = @{} # Para detectar quedas recentes

# -----------------------------------------------------------------------------
# 2. LOG ROTATIVO INTELIGENTE
# -----------------------------------------------------------------------------
function Escrever-Log {
    param(
        [string]$Mensagem,
        [string]$Nivel = "INFO" # INFO, SUCESSO, AVISO, ERRO
    )

    try {
        if (Test-Path $script:LogPath) {
            $item = Get-Item $script:LogPath -ErrorAction SilentlyContinue
            if ($item -and $item.Length -gt 2097152) {
                $backupLog = Join-Path $script:BasePath "monitoramento_log_anterior.txt"
                Move-Item -Path $script:LogPath -Destination $backupLog -Force -ErrorAction SilentlyContinue
            }
        }

        $timestamp = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
        $linha = "[$timestamp] [$Nivel] $Mensagem"
        Add-Content -Path $script:LogPath -Value $linha -Encoding UTF8
    } catch {}
}

function Abrir-LogBlocoNotas {
    try {
        if (-not (Test-Path $script:LogPath)) {
            New-Item -Path $script:LogPath -ItemType File -Force | Out-Null
            Escrever-Log "Log inicializado." "INFO"
        }
        Start-Process notepad.exe $script:LogPath
    } catch {}
}

function Limpar-LogArquivo {
    try {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Deseja realmente limpar todo o histórico de logs?",
            "Limpar Logs",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            Set-Content -Path $script:LogPath -Value "" -Encoding UTF8
            Escrever-Log "Histórico de logs limpo pelo usuário." "AVISO"
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

# -----------------------------------------------------------------------------
# 3. IMAGEM DO AVATAR / LOGOTIPO
# -----------------------------------------------------------------------------
function Obter-ImagemAvatar {
    $candidatos = @(
        (Join-Path $script:BasePath "avatar.png"),
        (Join-Path $script:BasePath "avatar.ico"),
        (Join-Path $script:BasePath "avatar.jpg"),
        (Join-Path $script:BasePath "avatar.jpeg")
    )
    foreach ($c in $candidatos) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

# -----------------------------------------------------------------------------
# 4. TESTE DE CONECTIVIDADE DE PORTA TCP (SOCKET RÁPIDO)
# -----------------------------------------------------------------------------
function Testar-PortaTCP {
    param(
        [string]$HostAlvo = "127.0.0.1",
        [int]$Porta,
        [int]$TimeoutMs = 800
    )

    if ($Porta -le 0) { return $null }

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($HostAlvo, $Porta, $null, $null)
        $success = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($success -and $tcpClient.Connected) {
            $tcpClient.EndConnect($asyncResult)
            $tcpClient.Close()
            return $true
        }
        $tcpClient.Close()
        return $false
    } catch {
        return $false
    }
}

# -----------------------------------------------------------------------------
# 5. TELEMETRIA DO PROCESSO DO SERVIÇO (RAM, PID, UPTIME)
# -----------------------------------------------------------------------------
function Obter-TelemetriaProcesso {
    param([string]$NomeServico)

    try {
        $wmi = Get-CimInstance -ClassName Win32_Service -Filter "Name='$NomeServico'" -ErrorAction SilentlyContinue
        if ($wmi -and $wmi.ProcessId -gt 0) {
            $proc = Get-Process -Id $wmi.ProcessId -ErrorAction SilentlyContinue
            if ($proc) {
                $ramMb = [Math]::Round(($proc.WorkingSet64 / 1MB), 1)
                $uptimeSpan = (Get-Date) - $proc.StartTime
                $uptimeStr = ""
                if ($uptimeSpan.Days -gt 0) { $uptimeStr += "$($uptimeSpan.Days)d " }
                if ($uptimeSpan.Hours -gt 0) { $uptimeStr += "$($uptimeSpan.Hours)h " }
                $uptimeStr += "$($uptimeSpan.Minutes)m"

                return [PSCustomObject]@{
                    PID      = $proc.Id
                    RAM_MB   = $ramMb
                    Uptime   = $uptimeStr
                    Sucesso  = $true
                }
            }
        }
    } catch {}

    return $null
}

# -----------------------------------------------------------------------------
# 6. DIÁLOGO DE SENHA SEGURO (MASCARADO)
# -----------------------------------------------------------------------------
function Solicitar-SenhaComMascara {
    param([string]$NomeServico)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Autenticação Necessária - Conexões Sistemas"
    $dlg.Size = New-Object System.Drawing.Size(430, 220)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(20, 27, 45)
    $dlg.ForeColor = [System.Drawing.Color]::White

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "O serviço '$NomeServico' é crítico e protegido por senha.`nDigite a senha administrativa para prosseguir:"
    $lbl.Location = New-Object System.Drawing.Point(20, 15)
    $lbl.Size = New-Object System.Drawing.Size(380, 45)
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(25, 75)
    $txt.Size = New-Object System.Drawing.Size(360, 26)
    $txt.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $txt.UseSystemPasswordChar = $true
    $dlg.Controls.Add($txt)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Confirmar"
    $btnOk.Location = New-Object System.Drawing.Point(180, 125)
    $btnOk.Size = New-Object System.Drawing.Size(100, 32)
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.FlatStyle = "Flat"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($btnOk)

    $btnCan = New-Object System.Windows.Forms.Button
    $btnCan.Text = "Cancelar"
    $btnCan.Location = New-Object System.Drawing.Point(290, 125)
    $btnCan.Size = New-Object System.Drawing.Size(95, 32)
    $btnCan.BackColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
    $btnCan.ForeColor = [System.Drawing.Color]::White
    $btnCan.FlatStyle = "Flat"
    $btnCan.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCan)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCan

    $res = $dlg.ShowDialog()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        return $txt.Text
    }
    return $null
}

function Validar-SenhaServicoProtegido {
    param([string]$Nome)

    $item = $script:ConfigData.Servicos | Where-Object { $_.Nome -eq $Nome }
    if ($item -and $item.Protegido) {
        $digitada = Solicitar-SenhaComMascara -NomeServico $item.Titulo
        if ([string]::IsNullOrEmpty($digitada)) {
            Escrever-Log "Operação cancelada pelo usuário no serviço protegido '$Nome'." "AVISO"
            return $false
        }
        if ($digitada -ne $script:SenhaServicosProtegidos) {
            Escrever-Log "Tentativa com senha incorreta para o serviço protegido '$Nome'." "ERRO"
            [System.Windows.Forms.MessageBox]::Show("Senha incorreta para o serviço protegido.", "Acesso Negado", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return $false
        }
        Escrever-Log "Senha confirmada com sucesso para o serviço '$Nome'." "SUCESSO"
    }
    return $true
}

# -----------------------------------------------------------------------------
# 7. GERENCIAMENTO DE PRIVILÉGIOS (ELEVATION)
# -----------------------------------------------------------------------------
function Reiniciar-ComoAdministrador {
    try {
        $exePath = [System.Windows.Forms.Application]::ExecutablePath
        if ($exePath -and (Test-Path $exePath) -and $exePath -notmatch "powershell") {
            Start-Process -FilePath $exePath -Verb RunAs
        } else {
            $scriptPath = $MyInvocation.MyCommand.Path
            if (-not $scriptPath) { $scriptPath = Join-Path $script:BasePath "monitoramento_conexoes.ps1" }
            Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$scriptPath`"" -Verb RunAs
        }
        [System.Windows.Forms.Application]::Exit()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Não foi possível obter permissões de Administrador: $($_.Exception.Message)", "Conexões Sistemas", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
}

# -----------------------------------------------------------------------------
# 8. INÍCIO COM WINDOWS (STARTUP)
# -----------------------------------------------------------------------------
function Obter-CaminhoAtalhoStartup {
    $startupFolder = [Environment]::GetFolderPath("Startup")
    return (Join-Path $startupFolder "Monitoramento Conexoes.lnk")
}

function Verificar-InicioComWindows {
    return (Test-Path (Obter-CaminhoAtalhoStartup))
}

function Alternar-InicioComWindows {
    $atalhoPath = Obter-CaminhoAtalhoStartup
    try {
        if (Test-Path $atalhoPath) {
            Remove-Item -Path $atalhoPath -Force
            Escrever-Log "Inicialização automática com o Windows desativada." "INFO"
            return $false
        } else {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($atalhoPath)
            
            $exeAtual = [System.Windows.Forms.Application]::ExecutablePath
            if ($exeAtual -and (Test-Path $exeAtual) -and $exeAtual -notmatch "powershell") {
                $shortcut.TargetPath = $exeAtual
                $shortcut.WorkingDirectory = Split-Path -Parent $exeAtual
            } else {
                $vbsPath = Join-Path $script:BasePath "abrir_monitoramento.vbs"
                if (Test-Path $vbsPath) {
                    $shortcut.TargetPath = $vbsPath
                    $shortcut.WorkingDirectory = $script:BasePath
                } else {
                    $ps1Path = Join-Path $script:BasePath "monitoramento_conexoes.ps1"
                    $shortcut.TargetPath = "powershell.exe"
                    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$ps1Path`""
                    $shortcut.WorkingDirectory = $script:BasePath
                }
            }
            $iconPath = Obter-ImagemAvatar
            if ($iconPath -and $iconPath.EndsWith(".ico")) {
                $shortcut.IconLocation = $iconPath
            }
            $shortcut.Save()
            Escrever-Log "Inicialização automática com o Windows ativada em: $atalhoPath" "SUCESSO"
            return $true
        }
    } catch {
        return (Verificar-InicioComWindows)
    }
}

# -----------------------------------------------------------------------------
# 9. GERADOR DE DIAGNÓSTICO DO SERVIDOR ("EXPORTAR DIAGNÓSTICO")
# -----------------------------------------------------------------------------
function Gerar-RelatorioDiagnostico {
    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $diagFile = Join-Path $script:BasePath "diagnostico_conexoes_$timestamp.txt"

        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("===============================================================================")
        [void]$sb.AppendLine("         CONEXÕES SISTEMAS - DIAGNÓSTICO TÉCNICO DE AMBIENTE")
        [void]$sb.AppendLine("         Data de Emissão: $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))")
        [void]$sb.AppendLine("===============================================================================")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("[1. DADOS DA MÁQUINA E SISTEMA]")
        [void]$sb.AppendLine("Nome do Computador : $env:COMPUTERNAME")
        [void]$sb.AppendLine("Usuário Atual      : $env:USERNAME")
        [void]$sb.AppendLine("Modo Administrador : $(if ($script:IsAdmin) { 'SIM' } else { 'NÃO (Executando como Padrão)' })")
        
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            [void]$sb.AppendLine("Sistema Operacional: $($os.Caption) ($($os.OSArchitecture)) Build $($os.BuildNumber)")
            $ramLivre = [Math]::Round(($os.FreePhysicalMemory / 1024), 1)
            $ramTotal = [Math]::Round(($os.TotalVisibleMemorySize / 1024), 1)
            [void]$sb.AppendLine("Memória RAM        : $ramLivre MB Livres de $ramTotal MB Total")
        }

        $disco = Get-PSDrive -Name C -ErrorAction SilentlyContinue
        if ($disco) {
            $livreGb = [Math]::Round(($disco.Free / 1GB), 2)
            $totalGb = [Math]::Round((($disco.Used + $disco.Free) / 1GB), 2)
            [void]$sb.AppendLine("Espaço em Disco C: : $livreGb GB Livres de $totalGb GB Total")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("[2. STATUS DOS SERVIÇOS DO AMBIENTE]")
        [void]$sb.AppendLine(("{0,-25} {1,-15} {2,-15} {3,-20}" -f "NOME SERVIÇO", "STATUS", "INICIALIZAÇÃO", "TELEMETRIA/PORTA"))
        [void]$sb.AppendLine("-" * 80)

        foreach ($srv in $script:ConfigData.Servicos) {
            $dados = Obter-DadosServico -Nome $srv.Nome -PortaConfig $srv.Porta
            $teleStr = ""
            if ($dados.Telemetria) {
                $teleStr = "PID:$($dados.Telemetria.PID) RAM:$($dados.Telemetria.RAM_MB)MB"
            }
            if ($srv.Porta -gt 0) {
                $teleStr += " [TCP:$($srv.Porta) $($dados.PortaStatus)]"
            }
            [void]$sb.AppendLine(("{0,-25} {1,-15} {2,-15} {3,-20}" -f $srv.Nome, $dados.Status, $dados.StartType, $teleStr))
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("[3. ÚLTIMOS EVENTOS DE LOG]")
        [void]$sb.AppendLine("-" * 80)
        if (Test-Path $script:LogPath) {
            $linhasLog = Get-Content -Path $script:LogPath -Tail 30 -Encoding UTF8 -ErrorAction SilentlyContinue
            foreach ($l in $linhasLog) {
                [void]$sb.AppendLine($l)
            }
        } else {
            [void]$sb.AppendLine("Nenhum log registrado.")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("===============================================================================")
        [void]$sb.AppendLine("Suporte Técnico Conexões Sistemas • Fim do Relatório")
        [void]$sb.AppendLine("===============================================================================")

        [System.IO.File]::WriteAllText($diagFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
        Escrever-Log "Diagnóstico técnico exportado com sucesso em: $diagFile" "SUCESSO"
        Start-Process notepad.exe $diagFile
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Falha ao gerar diagnóstico: $($_.Exception.Message)", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

# -----------------------------------------------------------------------------
# 10. MOTOR DE ESTADO DE SERVIÇOS E RECUPERAÇÃO INTELIGENTE
# -----------------------------------------------------------------------------
function Obter-DadosServico {
    param(
        [string]$Nome,
        [int]$PortaConfig = 0
    )

    $svc = Get-Service -Name $Nome -ErrorAction SilentlyContinue

    if (-not $svc) {
        return [PSCustomObject]@{
            Nome          = $Nome
            Status        = "NÃO INSTALADO"
            Tipo          = "NAO_INSTALADO"
            StartType     = "Inexistente"
            Cor           = [System.Drawing.Color]::FromArgb(148, 163, 184)
            CorFundoPill  = [System.Drawing.Color]::FromArgb(30, 41, 59)
            PodeReiniciar = $false
            PodeIniciar   = $false
            TextoBotao    = "INDISPONÍVEL"
            CorBotao      = [System.Drawing.Color]::FromArgb(75, 85, 99)
            Telemetria    = $null
            PortaStatus   = ""
        }
    }

    $startType = $svc.StartType.ToString()

    # 1. Serviço ONLINE
    if ($svc.Status -eq 'Running') {
        if ($script:TentativasAutoRecuperacao.ContainsKey($Nome)) {
            $script:TentativasAutoRecuperacao.Remove($Nome)
        }

        $tele = Obter-TelemetriaProcesso -NomeServico $Nome
        $portaStr = ""
        if ($PortaConfig -gt 0) {
            $aberta = Testar-PortaTCP -Porta $PortaConfig
            $portaStr = if ($aberta) { "OK" } else { "FECHADA" }
        }

        return [PSCustomObject]@{
            Nome          = $Nome
            Status        = "ONLINE"
            Tipo          = "ONLINE"
            StartType     = $startType
            Cor           = [System.Drawing.Color]::FromArgb(16, 185, 129)
            CorFundoPill  = [System.Drawing.Color]::FromArgb(6, 78, 59)
            PodeReiniciar = $true
            PodeIniciar   = $false
            TextoBotao    = "REINICIAR"
            CorBotao      = [System.Drawing.Color]::FromArgb(37, 99, 235)
            Telemetria    = $tele
            PortaStatus   = $portaStr
        }
    }

    # 2. Serviço Desativado no Windows
    if ($startType -eq 'Disabled') {
        return [PSCustomObject]@{
            Nome          = $Nome
            Status        = "DESATIVADO"
            Tipo          = "DESATIVADO"
            StartType     = "Desativado"
            Cor           = [System.Drawing.Color]::FromArgb(245, 158, 11)
            CorFundoPill  = [System.Drawing.Color]::FromArgb(120, 53, 15)
            PodeReiniciar = $false
            PodeIniciar   = $true
            TextoBotao    = "HABILITAR & INICIAR"
            CorBotao      = [System.Drawing.Color]::FromArgb(217, 119, 6)
            Telemetria    = $null
            PortaStatus   = ""
        }
    }

    # 3. Serviço Parado / Offline (Verifica se auto-recupera)
    $itemCfg = $script:ConfigData.Servicos | Where-Object { $_.Nome -eq $Nome }
    $ehProtegido = $itemCfg -and $itemCfg.Protegido

    $cfg = $script:ConfigData.Configuracoes
    if ($cfg.AutoRecuperacao -and (-not $ehProtegido) -and ($startType -eq 'Automatic') -and $script:IsAdmin) {
        $agora = Get-Date
        $registro = $script:TentativasAutoRecuperacao[$Nome]

        $deveTentar = $false
        if (-not $registro) {
            $deveTentar = $true
            $script:TentativasAutoRecuperacao[$Nome] = @{ Tentativas = 1; UltimaTentativa = $agora }
        } else {
            $segundosDesdeUltima = ($agora - $registro.UltimaTentativa).TotalSeconds
            if ($registro.Tentativas -lt $cfg.MaxTentativasAuto -and $segundosDesdeUltima -ge $cfg.CooldownSegundos) {
                $deveTentar = $true
                $registro.Tentativas++
                $registro.UltimaTentativa = $agora
            }
        }

        if ($deveTentar) {
            Escrever-Log "Tentativa automática de recuperação ($($script:TentativasAutoRecuperacao[$Nome].Tentativas)/$($cfg.MaxTentativasAuto)) para o serviço '$Nome'..." "AVISO"
            try {
                Start-Service -Name $Nome -ErrorAction Stop
                Start-Sleep -Milliseconds 800
                $svcAtual = Get-Service -Name $Nome -ErrorAction SilentlyContinue
                if ($svcAtual -and $svcAtual.Status -eq 'Running') {
                    Escrever-Log "Serviço '$Nome' recuperado automaticamente com sucesso!" "SUCESSO"
                    $script:TentativasAutoRecuperacao.Remove($Nome)
                    return [PSCustomObject]@{
                        Nome          = $Nome
                        Status        = "RECUPERADO"
                        Tipo          = "ONLINE"
                        StartType     = $startType
                        Cor           = [System.Drawing.Color]::FromArgb(59, 130, 246)
                        CorFundoPill  = [System.Drawing.Color]::FromArgb(30, 58, 138)
                        PodeReiniciar = $true
                        PodeIniciar   = $false
                        TextoBotao    = "REINICIAR"
                        CorBotao      = [System.Drawing.Color]::FromArgb(37, 99, 235)
                        Telemetria    = (Obter-TelemetriaProcesso -NomeServico $Nome)
                        PortaStatus   = ""
                    }
                }
            } catch {
                Escrever-Log "Falha na tentativa de recuperação do serviço '$Nome': $($_.Exception.Message)" "ERRO"
            }
        }
    }

    $statusExibicao = "OFFLINE"
    if ($script:TentativasAutoRecuperacao.ContainsKey($Nome)) {
        $tent = $script:TentativasAutoRecuperacao[$Nome].Tentativas
        if ($tent -ge $cfg.MaxTentativasAuto) {
            $statusExibicao = "FALHA CRÍTICA ($tent/$($cfg.MaxTentativasAuto))"
        }
    }

    return [PSCustomObject]@{
        Nome          = $Nome
        Status        = $statusExibicao
        Tipo          = "OFFLINE"
        StartType     = $startType
        Cor           = [System.Drawing.Color]::FromArgb(239, 68, 68)
        CorFundoPill  = [System.Drawing.Color]::FromArgb(127, 29, 29)
        PodeReiniciar = $false
        PodeIniciar   = $true
        TextoBotao    = "INICIAR"
        CorBotao      = [System.Drawing.Color]::FromArgb(220, 38, 38)
        Telemetria    = $null
        PortaStatus   = ""
    }
}

function Executar-AcaoServico {
    param([string]$Nome)

    if (-not (Validar-SenhaServicoProtegido -Nome $Nome)) { return }

    if (-not $script:IsAdmin) {
        $resp = [System.Windows.Forms.MessageBox]::Show(
            "O gerenciamento de serviços exige privilégios de Administrador.`nDeseja reiniciar o aplicativo como Administrador agora?",
            "Permissão Insuficiente",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($resp -eq [System.Windows.Forms.DialogResult]::Yes) { Reiniciar-ComoAdministrador }
        return
    }

    try {
        $svc = Get-Service -Name $Nome -ErrorAction SilentlyContinue
        if (-not $svc) {
            [System.Windows.Forms.MessageBox]::Show("Serviço '$Nome' não está instalado neste sistema.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        if ($svc.StartType -eq 'Disabled') {
            Escrever-Log "Alterando inicialização do serviço '$Nome' para Automático..." "INFO"
            Set-Service -Name $Nome -StartupType Automatic -ErrorAction Stop
        }

        if ($svc.Status -eq 'Running') {
            Escrever-Log "Reiniciando serviço '$Nome'..." "INFO"
            Restart-Service -Name $Nome -Force -ErrorAction Stop
            Escrever-Log "Serviço '$Nome' reiniciado com sucesso pelo usuário." "SUCESSO"
        } else {
            Escrever-Log "Iniciando serviço '$Nome'..." "INFO"
            Start-Service -Name $Nome -ErrorAction Stop
            Escrever-Log "Serviço '$Nome' iniciado com sucesso pelo usuário." "SUCESSO"
        }

        if ($script:TentativasAutoRecuperacao.ContainsKey($Nome)) {
            $script:TentativasAutoRecuperacao.Remove($Nome)
        }

        Atualizar-Painel
    } catch {
        Escrever-Log "Erro ao executar ação no serviço '$Nome': $($_.Exception.Message)" "ERRO"
        [System.Windows.Forms.MessageBox]::Show("Falha ao executar ação no serviço '$Nome':`n$($_.Exception.Message)", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

function Reiniciar-TodosOsServicos {
    if (-not $script:IsAdmin) {
        $resp = [System.Windows.Forms.MessageBox]::Show("O gerenciamento em lote de serviços exige privilégios de Administrador.`nDeseja reiniciar o aplicativo como Administrador?", "Permissão Insuficiente", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($resp -eq [System.Windows.Forms.DialogResult]::Yes) { Reiniciar-ComoAdministrador }
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show("Deseja realmente reiniciar todos os serviços instalados agora?`nServiços protegidos (bancos de dados) serão solicitados com senha.", "Confirmação de Reinício Geral", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Escrever-Log "Iniciando rotina de reinício em lote..." "INFO"

    foreach ($item in $script:ConfigData.Servicos) {
        $nome = $item.Nome
        try {
            $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
            if (-not $svc) { continue }

            if ($item.Protegido) {
                if (-not (Validar-SenhaServicoProtegido -Nome $nome)) {
                    Escrever-Log "Serviço protegido '$nome' ignorado no lote por cancelamento de senha." "AVISO"
                    continue
                }
            }

            if ($svc.Status -eq 'Running') {
                Restart-Service -Name $nome -Force -ErrorAction SilentlyContinue
                Escrever-Log "Serviço '$nome' reiniciado no lote." "SUCESSO"
            } else {
                if ($svc.StartType -ne 'Disabled') {
                    Start-Service -Name $nome -ErrorAction SilentlyContinue
                    Escrever-Log "Serviço '$nome' iniciado no lote." "SUCESSO"
                }
            }
        } catch {
            Escrever-Log "Erro ao processar serviço '$nome' no lote: $($_.Exception.Message)" "ERRO"
        }
    }

    Atualizar-Painel
    [System.Windows.Forms.MessageBox]::Show("Rotina de reinício geral concluída com sucesso!", "Conexões Sistemas", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

# -----------------------------------------------------------------------------
# 11. GERENCIADOR DE SERVIÇOS (MODAL "ADICIONAR NOVO SERVIÇO")
# -----------------------------------------------------------------------------
function Abrir-ModalAdicionarServico {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Adicionar Serviço ao Monitoramento - Conexões Sistemas"
    $dlg.Size = New-Object System.Drawing.Size(480, 420)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(18, 28, 56)
    $dlg.ForeColor = [System.Drawing.Color]::White

    $criarLabel = {
        param($txt, $x, $y)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $txt
        $l.Location = New-Object System.Drawing.Point($x, $y)
        $l.AutoSize = $true
        $l.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $dlg.Controls.Add($l)
    }

    & $criarLabel "Nome do Serviço no Windows (Service Name):" 20 15
    $cboNome = New-Object System.Windows.Forms.ComboBox
    $cboNome.Location = New-Object System.Drawing.Point(20, 38)
    $cboNome.Size = New-Object System.Drawing.Size(420, 26)
    $cboNome.DropDownStyle = "DropDown"
    # Preenche com serviços locais do Windows para conveniência
    try {
        $locais = Get-Service | Select-Object -ExpandProperty Name | Sort-Object
        $cboNome.Items.AddRange($locais)
    } catch {}
    $dlg.Controls.Add($cboNome)

    & $criarLabel "Título Amigável de Exibição:" 20 75
    $txtTitulo = New-Object System.Windows.Forms.TextBox
    $txtTitulo.Location = New-Object System.Drawing.Point(20, 98)
    $txtTitulo.Size = New-Object System.Drawing.Size(420, 26)
    $dlg.Controls.Add($txtTitulo)

    & $criarLabel "Descrição do Serviço:" 20 135
    $txtDesc = New-Object System.Windows.Forms.TextBox
    $txtDesc.Location = New-Object System.Drawing.Point(20, 158)
    $txtDesc.Size = New-Object System.Drawing.Size(420, 26)
    $dlg.Controls.Add($txtDesc)

    & $criarLabel "Porta TCP de Rede (Opcional - ex: 5432):" 20 195
    $txtPorta = New-Object System.Windows.Forms.TextBox
    $txtPorta.Location = New-Object System.Drawing.Point(20, 218)
    $txtPorta.Size = New-Object System.Drawing.Size(120, 26)
    $txtPorta.Text = "0"
    $dlg.Controls.Add($txtPorta)

    $chkProt = New-Object System.Windows.Forms.CheckBox
    $chkProt.Text = "Proteger com Senha Administrativa (PostgreSQL/Crítico)"
    $chkProt.Location = New-Object System.Drawing.Point(20, 260)
    $chkProt.Size = New-Object System.Drawing.Size(420, 26)
    $chkProt.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Controls.Add($chkProt)

    $btnSalvar = New-Object System.Windows.Forms.Button
    $btnSalvar.Text = "💾 Adicionar Serviço"
    $btnSalvar.Location = New-Object System.Drawing.Point(190, 315)
    $btnSalvar.Size = New-Object System.Drawing.Size(140, 36)
    $btnSalvar.FlatStyle = "Flat"
    $btnSalvar.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
    $btnSalvar.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnSalvar)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancelar"
    $btnCancel.Location = New-Object System.Drawing.Point(340, 315)
    $btnCancel.Size = New-Object System.Drawing.Size(100, 36)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCancel)

    $btnSalvar.Add_Click({
        $nome = $cboNome.Text.Trim()
        $tit  = $txtTitulo.Text.Trim()
        $desc = $txtDesc.Text.Trim()
        $porta = 0
        [int]::TryParse($txtPorta.Text.Trim(), [ref]$porta) | Out-Null

        if ([string]::IsNullOrWhiteSpace($nome)) {
            [System.Windows.Forms.MessageBox]::Show("Informe o nome do serviço no Windows.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        if ([string]::IsNullOrWhiteSpace($tit)) { $tit = $nome }
        if ([string]::IsNullOrWhiteSpace($desc)) { $desc = "Serviço personalizado monitorado" }

        # Checa duplicidade
        $jaExiste = $script:ConfigData.Servicos | Where-Object { $_.Nome -eq $nome }
        if ($jaExiste) {
            [System.Windows.Forms.MessageBox]::Show("Este serviço já está na lista de monitoramento.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        $novo = [PSCustomObject]@{
            Nome      = $nome
            Titulo    = $tit
            Descricao = $desc
            Porta     = $porta
            Protegido = $chkProt.Checked
        }

        $script:ConfigData.Servicos = @($script:ConfigData.Servicos) + $novo
        Salvar-Configuracao -ConfigObj $script:ConfigData
        Escrever-Log "Novo serviço '$nome' adicionado ao monitoramento." "SUCESSO"
        $dlg.Close()

        [System.Windows.Forms.MessageBox]::Show("Serviço adicionado com sucesso! Reinicie o painel para recarregar o grid completo.", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    })

    $dlg.ShowDialog() | Out-Null
}

# -----------------------------------------------------------------------------
# 12. VISUALIZADOR DE LOGS INTEGRADO
# -----------------------------------------------------------------------------
function Abrir-JanelaLogs {
    $dlgLog = New-Object System.Windows.Forms.Form
    $dlgLog.Text = "Histórico de Logs - Conexões Sistemas"
    $dlgLog.Size = New-Object System.Drawing.Size(960, 600)
    $dlgLog.StartPosition = "CenterParent"
    $dlgLog.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $dlgLog.ForeColor = [System.Drawing.Color]::White

    $barTopo = New-Object System.Windows.Forms.Panel
    $barTopo.Dock = "Top"
    $barTopo.Height = 55
    $barTopo.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $dlgLog.Controls.Add($barTopo)

    $lblTit = New-Object System.Windows.Forms.Label
    $lblTit.Text = "REGISTRO DE EVENTOS EM TEMPO REAL"
    $lblTit.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblTit.Location = New-Object System.Drawing.Point(15, 16)
    $lblTit.AutoSize = $true
    $barTopo.Controls.Add($lblTit)

    $btnLimpar = New-Object System.Windows.Forms.Button
    $btnLimpar.Text = "🗑️ Limpar Log"
    $btnLimpar.Location = New-Object System.Drawing.Point(530, 12)
    $btnLimpar.Size = New-Object System.Drawing.Size(120, 32)
    $btnLimpar.FlatStyle = "Flat"
    $btnLimpar.BackColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
    $btnLimpar.ForeColor = [System.Drawing.Color]::White
    $barTopo.Controls.Add($btnLimpar)

    $btnNotepad = New-Object System.Windows.Forms.Button
    $btnNotepad.Text = "📄 Bloco de Notas"
    $btnNotepad.Location = New-Object System.Drawing.Point(660, 12)
    $btnNotepad.Size = New-Object System.Drawing.Size(150, 32)
    $btnNotepad.FlatStyle = "Flat"
    $btnNotepad.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
    $btnNotepad.ForeColor = [System.Drawing.Color]::White
    $barTopo.Controls.Add($btnNotepad)

    $btnRecarregar = New-Object System.Windows.Forms.Button
    $btnRecarregar.Text = "🔄 Atualizar"
    $btnRecarregar.Location = New-Object System.Drawing.Point(820, 12)
    $btnRecarregar.Size = New-Object System.Drawing.Size(100, 32)
    $btnRecarregar.FlatStyle = "Flat"
    $btnRecarregar.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
    $btnRecarregar.ForeColor = [System.Drawing.Color]::White
    $barTopo.Controls.Add($btnRecarregar)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Dock = "Fill"
    $txtLog.Multiline = $true
    $txtLog.ReadOnly = $true
    $txtLog.ScrollBars = "Both"
    $txtLog.WordWrap = $false
    $txtLog.BackColor = [System.Drawing.Color]::FromArgb(10, 15, 30)
    $txtLog.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $txtLog.Font = New-Object System.Drawing.Font("Consolas", 9.5)
    $dlgLog.Controls.Add($txtLog)

    $carregarLog = {
        if (Test-Path $script:LogPath) {
            $conteudo = Get-Content -Path $script:LogPath -Tail 500 -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($conteudo) {
                $txtLog.Text = [string]::Join("`r`n", $conteudo)
                $txtLog.SelectionStart = $txtLog.Text.Length
                $txtLog.ScrollToCaret()
            } else {
                $txtLog.Text = "Nenhum registro encontrado."
            }
        }
    }

    $btnRecarregar.Add_Click($carregarLog)
    $btnNotepad.Add_Click({ Abrir-LogBlocoNotas })
    $btnLimpar.Add_Click({
        if (Limpar-LogArquivo) { & $carregarLog }
    })

    & $carregarLog
    $dlgLog.ShowDialog() | Out-Null
}

# -----------------------------------------------------------------------------
# 13. CONSTRUÇÃO DA INTERFACE GRÁFICA PRINCIPAL (MODERNA & RESPONSIVA)
# -----------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "CONEXÕES SISTEMAS • MONITORAMENTO DE CONEXÕES & SERVIÇOS v3.0"
$form.Size = New-Object System.Drawing.Size(1300, 820)
$form.MinimumSize = New-Object System.Drawing.Size(1150, 720)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(11, 19, 43)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

$caminhoIcone = Obter-ImagemAvatar
if ($caminhoIcone -and (Test-Path $caminhoIcone) -and $caminhoIcone.EndsWith(".ico")) {
    try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($caminhoIcone) } catch {}
}

# --- HEADER / TOPO ---
$panelTopo = New-Object System.Windows.Forms.Panel
$panelTopo.Dock = "Top"
$panelTopo.Height = 85
$panelTopo.BackColor = [System.Drawing.Color]::FromArgb(18, 28, 56)
$form.Controls.Add($panelTopo)

$picLogo = New-Object System.Windows.Forms.PictureBox
$picLogo.Size = New-Object System.Drawing.Size(70, 70)
$picLogo.Location = New-Object System.Drawing.Point(20, 8)
$picLogo.SizeMode = "Zoom"
$picLogo.BackColor = [System.Drawing.Color]::Transparent
if ($caminhoIcone -and (Test-Path $caminhoIcone)) {
    try { $picLogo.Image = [System.Drawing.Image]::FromFile($caminhoIcone) } catch {}
}
$panelTopo.Controls.Add($picLogo)

$lblTitulo = New-Object System.Windows.Forms.Label
$lblTitulo.Text = "CONEXÕES SISTEMAS"
$lblTitulo.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblTitulo.ForeColor = [System.Drawing.Color]::White
$lblTitulo.Location = New-Object System.Drawing.Point(100, 14)
$lblTitulo.AutoSize = $true
$panelTopo.Controls.Add($lblTitulo)

$lblSubtitulo = New-Object System.Windows.Forms.Label
$lblSubtitulo.Text = "Painel Avançado de Monitoramento • Automação, PDV e Banco de Dados"
$lblSubtitulo.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblSubtitulo.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$lblSubtitulo.Location = New-Object System.Drawing.Point(102, 45)
$lblSubtitulo.AutoSize = $true
$panelTopo.Controls.Add($lblSubtitulo)

$badgeAdmin = New-Object System.Windows.Forms.Label
$badgeAdmin.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$badgeAdmin.Size = New-Object System.Drawing.Size(190, 28)
$badgeAdmin.Location = New-Object System.Drawing.Point(830, 28)
$badgeAdmin.TextAlign = "MiddleCenter"
$badgeAdmin.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
if ($script:IsAdmin) {
    $badgeAdmin.Text = "🛡️ MODO ADMINISTRADOR"
    $badgeAdmin.BackColor = [System.Drawing.Color]::FromArgb(6, 78, 59)
    $badgeAdmin.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
} else {
    $badgeAdmin.Text = "⚠️ MODO PADRÃO"
    $badgeAdmin.BackColor = [System.Drawing.Color]::FromArgb(120, 53, 15)
    $badgeAdmin.ForeColor = [System.Drawing.Color]::FromArgb(251, 191, 36)
    $badgeAdmin.Cursor = "Hand"
    $badgeAdmin.Add_Click({ Reiniciar-ComoAdministrador })
}
$panelTopo.Controls.Add($badgeAdmin)

$lblRelogio = New-Object System.Windows.Forms.Label
$lblRelogio.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblRelogio.Text = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
$lblRelogio.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
$lblRelogio.ForeColor = [System.Drawing.Color]::FromArgb(96, 165, 250)
$lblRelogio.Location = New-Object System.Drawing.Point(1040, 31)
$lblRelogio.AutoSize = $true
$panelTopo.Controls.Add($lblRelogio)

# --- KPI CARDS DE MÉTRICAS ---
$panelCards = New-Object System.Windows.Forms.Panel
$panelCards.Dock = "Top"
$panelCards.Height = 90
$panelCards.BackColor = [System.Drawing.Color]::FromArgb(14, 23, 49)
$panelCards.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
$form.Controls.Add($panelCards)

function Criar-CardMetrica {
    param([string]$Tit, [string]$Val, [System.Drawing.Color]$Cor, [int]$X)
    $p = New-Object System.Windows.Forms.Panel
    $p.Size = New-Object System.Drawing.Size(225, 68)
    $p.Location = New-Object System.Drawing.Point($X, 10)
    $p.BackColor = [System.Drawing.Color]::FromArgb(24, 35, 68)

    $lblVal = New-Object System.Windows.Forms.Label
    $lblVal.Text = $Val
    $lblVal.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $lblVal.ForeColor = $Cor
    $lblVal.Location = New-Object System.Drawing.Point(15, 6)
    $lblVal.AutoSize = $true
    $p.Controls.Add($lblVal)

    $lblTit = New-Object System.Windows.Forms.Label
    $lblTit.Text = $Tit
    $lblTit.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblTit.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    $lblTit.Location = New-Object System.Drawing.Point(16, 42)
    $lblTit.AutoSize = $true
    $p.Controls.Add($lblTit)

    $panelCards.Controls.Add($p)
    return $lblVal
}

$lblCardOnline   = Criar-CardMetrica -Tit "SERVIÇOS ONLINE"       -Val "0" -Cor ([System.Drawing.Color]::FromArgb(16, 185, 129)) -X 20
$lblCardOffline  = Criar-CardMetrica -Tit "SERVIÇOS OFFLINE"      -Val "0" -Cor ([System.Drawing.Color]::FromArgb(239, 68, 68))  -X 265
$lblCardDesat    = Criar-CardMetrica -Tit "DESATIVADOS NO WINDOWS" -Val "0" -Cor ([System.Drawing.Color]::FromArgb(245, 158, 11))  -X 510
$lblCardNaoInst  = Criar-CardMetrica -Tit "NÃO INSTALADOS"       -Val "0" -Cor ([System.Drawing.Color]::FromArgb(148, 163, 184)) -X 755
$lblCardTotal    = Criar-CardMetrica -Tit "TOTAL MONITORADO"     -Val "$($script:ConfigData.Servicos.Count)" -Cor ([System.Drawing.Color]::FromArgb(96, 165, 250)) -X 1000

# --- BARRA DE FERRAMENTAS / AÇÕES RÁPIDAS ---
$panelToolbar = New-Object System.Windows.Forms.Panel
$panelToolbar.Dock = "Top"
$panelToolbar.Height = 60
$panelToolbar.BackColor = [System.Drawing.Color]::FromArgb(18, 28, 56)
$panelToolbar.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
$form.Controls.Add($panelToolbar)

$txtFiltro = New-Object System.Windows.Forms.TextBox
$txtFiltro.Size = New-Object System.Drawing.Size(210, 28)
$txtFiltro.Location = New-Object System.Drawing.Point(20, 16)
$txtFiltro.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$txtFiltro.BackColor = [System.Drawing.Color]::FromArgb(11, 19, 43)
$txtFiltro.ForeColor = [System.Drawing.Color]::White
$panelToolbar.Controls.Add($txtFiltro)

$lblDicaFiltro = New-Object System.Windows.Forms.Label
$lblDicaFiltro.Text = "🔍 Filtrar..."
$lblDicaFiltro.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$lblDicaFiltro.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$lblDicaFiltro.Location = New-Object System.Drawing.Point(235, 20)
$lblDicaFiltro.AutoSize = $true
$panelToolbar.Controls.Add($lblDicaFiltro)

$btnAtualizar = New-Object System.Windows.Forms.Button
$btnAtualizar.Text = "🔄 Atualizar"
$btnAtualizar.Size = New-Object System.Drawing.Size(105, 36)
$btnAtualizar.Location = New-Object System.Drawing.Point(320, 12)
$btnAtualizar.FlatStyle = "Flat"
$btnAtualizar.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$btnAtualizar.ForeColor = [System.Drawing.Color]::White
$btnAtualizar.Cursor = "Hand"
$btnAtualizar.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$panelToolbar.Controls.Add($btnAtualizar)

$btnReiniciarTodos = New-Object System.Windows.Forms.Button
$btnReiniciarTodos.Text = "⚡ Reiniciar Todos"
$btnReiniciarTodos.Size = New-Object System.Drawing.Size(130, 36)
$btnReiniciarTodos.Location = New-Object System.Drawing.Point(435, 12)
$btnReiniciarTodos.FlatStyle = "Flat"
$btnReiniciarTodos.BackColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
$btnReiniciarTodos.ForeColor = [System.Drawing.Color]::White
$btnReiniciarTodos.Cursor = "Hand"
$btnReiniciarTodos.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$panelToolbar.Controls.Add($btnReiniciarTodos)

$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.Text = "Auto-Recuperação"
$chkAuto.Checked = $script:ConfigData.Configuracoes.AutoRecuperacao
$chkAuto.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
$chkAuto.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$chkAuto.Size = New-Object System.Drawing.Size(150, 30)
$chkAuto.Location = New-Object System.Drawing.Point(575, 15)
$chkAuto.Cursor = "Hand"
$chkAuto.Add_CheckedChanged({
    $script:ConfigData.Configuracoes.AutoRecuperacao = $chkAuto.Checked
    Salvar-Configuracao -ConfigObj $script:ConfigData
})
$panelToolbar.Controls.Add($chkAuto)

$btnAddServico = New-Object System.Windows.Forms.Button
$btnAddServico.Text = "➕ Adicionar"
$btnAddServico.Size = New-Object System.Drawing.Size(100, 36)
$btnAddServico.Location = New-Object System.Drawing.Point(735, 12)
$btnAddServico.FlatStyle = "Flat"
$btnAddServico.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnAddServico.ForeColor = [System.Drawing.Color]::White
$btnAddServico.Cursor = "Hand"
$btnAddServico.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnAddServico.Add_Click({ Abrir-ModalAdicionarServico })
$panelToolbar.Controls.Add($btnAddServico)

$btnDiag = New-Object System.Windows.Forms.Button
$btnDiag.Text = "📊 Diagnóstico"
$btnDiag.Size = New-Object System.Drawing.Size(115, 36)
$btnDiag.Location = New-Object System.Drawing.Point(845, 12)
$btnDiag.FlatStyle = "Flat"
$btnDiag.BackColor = [System.Drawing.Color]::FromArgb(139, 92, 246) # Roxo Moderno
$btnDiag.ForeColor = [System.Drawing.Color]::White
$btnDiag.Cursor = "Hand"
$btnDiag.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDiag.Add_Click({ Gerar-RelatorioDiagnostico })
$panelToolbar.Controls.Add($btnDiag)

$btnLogs = New-Object System.Windows.Forms.Button
$btnLogs.Text = "📜 Logs"
$btnLogs.Size = New-Object System.Drawing.Size(85, 36)
$btnLogs.Location = New-Object System.Drawing.Point(970, 12)
$btnLogs.FlatStyle = "Flat"
$btnLogs.BackColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
$btnLogs.ForeColor = [System.Drawing.Color]::White
$btnLogs.Cursor = "Hand"
$btnLogs.Add_Click({ Abrir-JanelaLogs })
$panelToolbar.Controls.Add($btnLogs)

$btnStartup = New-Object System.Windows.Forms.Button
$statusStartup = Verificar-InicioComWindows
$btnStartup.Text = if ($statusStartup) { "🚀 Startup: ON" } else { "🚀 Startup: OFF" }
$btnStartup.Size = New-Object System.Drawing.Size(115, 36)
$btnStartup.Location = New-Object System.Drawing.Point(1065, 12)
$btnStartup.FlatStyle = "Flat"
$btnStartup.BackColor = if ($statusStartup) { [System.Drawing.Color]::FromArgb(6, 95, 70) } else { [System.Drawing.Color]::FromArgb(55, 65, 81) }
$btnStartup.ForeColor = [System.Drawing.Color]::White
$btnStartup.Cursor = "Hand"
$btnStartup.Add_Click({
    $novo = Alternar-InicioComWindows
    $btnStartup.Text = if ($novo) { "🚀 Startup: ON" } else { "🚀 Startup: OFF" }
    $btnStartup.BackColor = if ($novo) { [System.Drawing.Color]::FromArgb(6, 95, 70) } else { [System.Drawing.Color]::FromArgb(55, 65, 81) }
})
$panelToolbar.Controls.Add($btnStartup)

$btnTray = New-Object System.Windows.Forms.Button
$btnTray.Text = "🔽 Ocultar"
$btnTray.Size = New-Object System.Drawing.Size(80, 36)
$btnTray.Location = New-Object System.Drawing.Point(1190, 12)
$btnTray.FlatStyle = "Flat"
$btnTray.BackColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
$btnTray.ForeColor = [System.Drawing.Color]::White
$btnTray.Cursor = "Hand"
$panelToolbar.Controls.Add($btnTray)

# --- CABEÇALHO DA TABELA ---
$panelGridHeader = New-Object System.Windows.Forms.Panel
$panelGridHeader.Dock = "Top"
$panelGridHeader.Height = 35
$panelGridHeader.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$form.Controls.Add($panelGridHeader)

$h1 = New-Object System.Windows.Forms.Label
$h1.Text = "SERVIÇO / DESCRIÇÃO"
$h1.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$h1.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$h1.Location = New-Object System.Drawing.Point(30, 8)
$h1.AutoSize = $true
$panelGridHeader.Controls.Add($h1)

$h2 = New-Object System.Windows.Forms.Label
$h2.Text = "INICIALIZAÇÃO / TELEMETRIA"
$h2.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$h2.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$h2.Location = New-Object System.Drawing.Point(520, 8)
$h2.AutoSize = $true
$panelGridHeader.Controls.Add($h2)

$h3 = New-Object System.Windows.Forms.Label
$h3.Text = "STATUS DO SERVIÇO"
$h3.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$h3.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$h3.Location = New-Object System.Drawing.Point(780, 8)
$h3.AutoSize = $true
$panelGridHeader.Controls.Add($h3)

$h4 = New-Object System.Windows.Forms.Label
$h4.Text = "AÇÃO MANUAL"
$h4.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$h4.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$h4.Location = New-Object System.Drawing.Point(1070, 8)
$h4.AutoSize = $true
$panelGridHeader.Controls.Add($h4)

# --- RODAPÉ / STATUS BAR ---
$panelRodape = New-Object System.Windows.Forms.Panel
$panelRodape.Dock = "Bottom"
$panelRodape.Height = 35
$panelRodape.BackColor = [System.Drawing.Color]::FromArgb(10, 16, 35)
$form.Controls.Add($panelRodape)

$lblStatusAcao = New-Object System.Windows.Forms.Label
$lblStatusAcao.Text = "Pronto. Monitoramento em execução a cada $($script:ConfigData.Configuracoes.IntervaloSegundos)s."
$lblStatusAcao.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Italic)
$lblStatusAcao.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$lblStatusAcao.Location = New-Object System.Drawing.Point(20, 8)
$lblStatusAcao.AutoSize = $true
$panelRodape.Controls.Add($lblStatusAcao)

$lblCreditos = New-Object System.Windows.Forms.Label
$lblCreditos.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$lblCreditos.Text = "Conexões Sistemas v3.0 Ultra • GitHub: conexoessystemas-blip/monitor_conexoes_sistemas"
$lblCreditos.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblCreditos.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblCreditos.Location = New-Object System.Drawing.Point(750, 8)
$lblCreditos.AutoSize = $true
$panelRodape.Controls.Add($lblCreditos)

# --- CORPO ROLÁVEL COM A LISTA DE CARDS DE SERVIÇOS ---
$panelScroll = New-Object System.Windows.Forms.Panel
$panelScroll.Dock = "Fill"
$panelScroll.AutoScroll = $true
$panelScroll.BackColor = [System.Drawing.Color]::FromArgb(11, 19, 43)
$form.Controls.Add($panelScroll)

$script:ComponentesLinhas = @()
$posY = 10

foreach ($servico in $script:ConfigData.Servicos) {
    $rowPanel = New-Object System.Windows.Forms.Panel
    $rowPanel.Size = New-Object System.Drawing.Size(1240, 52)
    $rowPanel.Location = New-Object System.Drawing.Point(15, $posY)
    $rowPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $rowPanel.BackColor = [System.Drawing.Color]::FromArgb(20, 31, 60)
    $panelScroll.Controls.Add($rowPanel)

    $dot = New-Object System.Windows.Forms.Panel
    $dot.Size = New-Object System.Drawing.Size(10, 10)
    $dot.Location = New-Object System.Drawing.Point(15, 21)
    $dot.BackColor = [System.Drawing.Color]::Silver
    $rowPanel.Controls.Add($dot)

    $lblNome = New-Object System.Windows.Forms.Label
    $lblNome.Text = $servico.Titulo
    $lblNome.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
    $lblNome.ForeColor = [System.Drawing.Color]::White
    $lblNome.Location = New-Object System.Drawing.Point(35, 6)
    $lblNome.AutoSize = $true
    $rowPanel.Controls.Add($lblNome)

    if ($servico.Protegido) {
        $lblLock = New-Object System.Windows.Forms.Label
        $lblLock.Text = "🔒"
        $lblLock.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $lblLock.Location = New-Object System.Drawing.Point(260, 8)
        $lblLock.AutoSize = $true
        $rowPanel.Controls.Add($lblLock)
    }

    $lblDesc = New-Object System.Windows.Forms.Label
    $descCompleta = "$($servico.Nome) • $($servico.Descricao)"
    if ($servico.Porta -gt 0) { $descCompleta += " • Porta TCP: $($servico.Porta)" }
    $lblDesc.Text = $descCompleta
    $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $lblDesc.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    $lblDesc.Location = New-Object System.Drawing.Point(36, 29)
    $lblDesc.AutoSize = $true
    $rowPanel.Controls.Add($lblDesc)

    $lblStartType = New-Object System.Windows.Forms.Label
    $lblStartType.Text = "Verificando..."
    $lblStartType.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblStartType.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 225)
    $lblStartType.Location = New-Object System.Drawing.Point(505, 10)
    $lblStartType.AutoSize = $true
    $rowPanel.Controls.Add($lblStartType)

    $lblTelemetria = New-Object System.Windows.Forms.Label
    $lblTelemetria.Text = ""
    $lblTelemetria.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblTelemetria.ForeColor = [System.Drawing.Color]::FromArgb(96, 165, 250)
    $lblTelemetria.Location = New-Object System.Drawing.Point(505, 29)
    $lblTelemetria.AutoSize = $true
    $rowPanel.Controls.Add($lblTelemetria)

    $pillStatus = New-Object System.Windows.Forms.Label
    $pillStatus.Text = "VERIFICANDO"
    $pillStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $pillStatus.Size = New-Object System.Drawing.Size(180, 26)
    $pillStatus.Location = New-Object System.Drawing.Point(770, 13)
    $pillStatus.TextAlign = "MiddleCenter"
    $pillStatus.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $pillStatus.ForeColor = [System.Drawing.Color]::Silver
    $rowPanel.Controls.Add($pillStatus)

    $btnAcao = New-Object System.Windows.Forms.Button
    $btnAcao.Text = "..."
    $btnAcao.Size = New-Object System.Drawing.Size(160, 30)
    $btnAcao.Location = New-Object System.Drawing.Point(1050, 11)
    $btnAcao.FlatStyle = "Flat"
    $btnAcao.BackColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
    $btnAcao.ForeColor = [System.Drawing.Color]::White
    $btnAcao.Cursor = "Hand"
    $btnAcao.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnAcao.Tag = $servico.Nome
    $btnAcao.Add_Click({
        param($s, $e)
        Executar-AcaoServico -Nome $s.Tag
    })
    $rowPanel.Controls.Add($btnAcao)

    $script:ComponentesLinhas += [PSCustomObject]@{
        ServicoConfig = $servico
        Container     = $rowPanel
        Dot           = $dot
        NomeLabel     = $lblNome
        DescLabel     = $lblDesc
        StartType     = $lblStartType
        Telemetria    = $lblTelemetria
        PillStatus    = $pillStatus
        BotaoAcao     = $btnAcao
    }

    $posY += 58
}

# -----------------------------------------------------------------------------
# 14. ATUALIZAÇÃO DO PAINEL
# -----------------------------------------------------------------------------
$script:EstaAtualizando = $false

function Atualizar-Painel {
    if ($script:EstaAtualizando) { return }
    $script:EstaAtualizando = $true

    try {
        $lblRelogio.Text = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")

        $cntOnline   = 0
        $cntOffline  = 0
        $cntDesat    = 0
        $cntNaoInst  = 0

        $termoFiltro = $txtFiltro.Text.Trim().ToLower()

        foreach ($linha in $script:ComponentesLinhas) {
            $nomeSrv = $linha.ServicoConfig.Nome
            $portaCfg = if ($linha.ServicoConfig.Porta) { $linha.ServicoConfig.Porta } else { 0 }
            $dados = Obter-DadosServico -Nome $nomeSrv -PortaConfig $portaCfg

            # Detecção de queda de serviço para som e alerta
            $anterior = $script:UltimoEstadoServicos[$nomeSrv]
            if ($anterior -eq "ONLINE" -and $dados.Tipo -eq "OFFLINE") {
                Escrever-Log "ALERTA: Serviço '$nomeSrv' caiu e agora está OFFLINE!" "AVISO"
                if ($script:ConfigData.Configuracoes.NotificacaoSonora) {
                    try { [System.Media.SystemSounds]::Exclamation.Play() } catch {}
                }
                if ($script:ConfigData.Configuracoes.NotificacaoBalao -and $trayIcon) {
                    $trayIcon.ShowBalloonTip(4000, "Alerta de Serviço", "O serviço '$($linha.ServicoConfig.Titulo)' caiu!", [System.Windows.Forms.ToolTipIcon]::Warning)
                }
            }
            $script:UltimoEstadoServicos[$nomeSrv] = $dados.Tipo

            # Filtro de busca
            $corresponde = $true
            if ($termoFiltro -ne "") {
                $textoBusca = "$($linha.ServicoConfig.Nome) $($linha.ServicoConfig.Titulo) $($dados.Status)".ToLower()
                if ($textoBusca -notmatch [regex]::Escape($termoFiltro)) { $corresponde = $false }
            }
            $linha.Container.Visible = $corresponde

            $linha.StartType.Text       = $dados.StartType
            $linha.PillStatus.Text      = $dados.Status
            $linha.PillStatus.ForeColor = $dados.Cor
            $linha.PillStatus.BackColor = $dados.CorFundoPill
            $linha.Dot.BackColor        = $dados.Cor

            # Telemetria
            if ($dados.Telemetria) {
                $t = $dados.Telemetria
                $linha.Telemetria.Text = "PID: $($t.PID) • RAM: $($t.RAM_MB) MB • Uptime: $($t.Uptime)"
                if ($dados.PortaStatus -ne "") {
                    $linha.Telemetria.Text += " • Porta TCP $($portaCfg): $($dados.PortaStatus)"
                }
            } else {
                $linha.Telemetria.Text = ""
            }

            $linha.BotaoAcao.Text      = $dados.TextoBotao
            $linha.BotaoAcao.BackColor = $dados.CorBotao
            $linha.BotaoAcao.Enabled   = ($dados.PodeReiniciar -or $dados.PodeIniciar)

            if ($linha.ServicoConfig.Protegido -and $dados.PodeReiniciar) {
                $linha.BotaoAcao.Text = "REINICIAR 🔒"
            }

            switch ($dados.Tipo) {
                "ONLINE"        { $cntOnline++ }
                "OFFLINE"       { $cntOffline++ }
                "DESATIVADO"    { $cntDesat++ }
                "NAO_INSTALADO" { $cntNaoInst++ }
            }

            [System.Windows.Forms.Application]::DoEvents()
        }

        $lblCardOnline.Text  = "$cntOnline"
        $lblCardOffline.Text = "$cntOffline"
        $lblCardDesat.Text   = "$cntDesat"
        $lblCardNaoInst.Text = "$cntNaoInst"

        $lblStatusAcao.Text = "Última verificação: " + (Get-Date).ToString("HH:mm:ss") + " • $cntOnline Online | $cntOffline Offline"
    } catch {
        Escrever-Log "Erro durante atualização do painel: $($_.Exception.Message)" "ERRO"
    } finally {
        $script:EstaAtualizando = $false
    }
}

# -----------------------------------------------------------------------------
# 15. EVENTOS E SYSTEM TRAY
# -----------------------------------------------------------------------------
$txtFiltro.Add_TextChanged({ Atualizar-Painel })
$btnAtualizar.Add_Click({
    Escrever-Log "Atualização manual solicitada." "INFO"
    Atualizar-Painel
})
$btnReiniciarTodos.Add_Click({ Reiniciar-TodosOsServicos })

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Text = "Conexões Sistemas - Monitoramento"
if ($form.Icon) { $trayIcon.Icon = $form.Icon }

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$mOpen = $trayMenu.Items.Add("Abrir Painel")
$mOpen.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$mOpen.Add_Click({
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.BringToFront()
})

$mRefresh = $trayMenu.Items.Add("Atualizar Serviços")
$mRefresh.Add_Click({ Atualizar-Painel })

$trayMenu.Items.Add("-") | Out-Null

$mRestartAll = $trayMenu.Items.Add("Reiniciar Todos os Serviços")
$mRestartAll.Add_Click({ Reiniciar-TodosOsServicos })

$mLogs = $trayMenu.Items.Add("Visualizar Logs")
$mLogs.Add_Click({ Abrir-JanelaLogs })

$mDiag = $trayMenu.Items.Add("Exportar Diagnóstico")
$mDiag.Add_Click({ Gerar-RelatorioDiagnostico })

$trayMenu.Items.Add("-") | Out-Null

$mExit = $trayMenu.Items.Add("Encerrar Monitoramento")
$mExit.Add_Click({
    $trayIcon.Visible = $false
    Escrever-Log "Monitoramento finalizado pelo menu da bandeja." "INFO"
    $form.Close()
})

$trayIcon.ContextMenuStrip = $trayMenu
$trayIcon.Visible = $true

$trayIcon.Add_DoubleClick({
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.BringToFront()
})

$btnTray.Add_Click({
    $form.Hide()
    $trayIcon.ShowBalloonTip(3000, "Conexões Sistemas", "O monitoramento continua ativo em segundo plano.", [System.Windows.Forms.ToolTipIcon]::Info)
})

$form.Add_FormClosing({
    param($s, $e)
    if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
        $msg = [System.Windows.Forms.MessageBox]::Show(
            "Deseja fechar totalmente o monitoramento ou mantê-lo rodando na bandeja?`n`n[Sim] = Fechar Totalmente`n[Não] = Manter Ativo na Bandeja",
            "Conexões Sistemas",
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($msg -eq [System.Windows.Forms.DialogResult]::Cancel) {
            $e.Cancel = $true
        }
        elseif ($msg -eq [System.Windows.Forms.DialogResult]::No) {
            $e.Cancel = $true
            $form.Hide()
            $trayIcon.ShowBalloonTip(3000, "Conexões Sistemas", "O monitoramento continua ativo na bandeja.", [System.Windows.Forms.ToolTipIcon]::Info)
        }
        else {
            $trayIcon.Visible = $false
            Escrever-Log "Painel encerrado pelo usuário." "INFO"
        }
    } else {
        $trayIcon.Visible = $false
    }
})

# -----------------------------------------------------------------------------
# 16. INICIALIZAÇÃO E TIMER
# -----------------------------------------------------------------------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = ($script:ConfigData.Configuracoes.IntervaloSegundos * 1000)
$timer.Add_Tick({ Atualizar-Painel })

Escrever-Log "Painel de Monitoramento v3.0 Ultra iniciado. Privilégios: $(if ($script:IsAdmin) { 'Administrador' } else { 'Usuário Padrão' })." "SUCESSO"
Atualizar-Painel
$timer.Start()

[void]$form.ShowDialog()
