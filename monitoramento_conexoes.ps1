Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

[System.Windows.Forms.Application]::EnableVisualStyles()

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

$script:BasePath = Obter-DiretorioBase
$script:LogPath = Join-Path $script:BasePath "monitoramento_log.txt"
$script:SenhaServicosProtegidos = "ConexõesSystemas"
$script:ServicosProtegidos = @(
    "postgresql-x64-9.5",
    "postgresql-x64-12"
)

$servicos = @(
    "ServicoFiscal",
    "QualityPulser",
    "srvIntegraWeb",
    "ServicoAutomacao",
    "ServicoPremmia",
    "ServicoSemParar",
    "ServicoShellBox",
    "ServicoCofre",
    "ServicoMicroTerminal",
    "ServicoBaixaAutomatica",
    "postgresql-x64-9.5",
    "postgresql-x64-12"
)

# Controle interno para evitar tentativas em loop e travamentos
$script:FalhasRecentes = @{}

function Escrever-Log {
    param([string]$Mensagem)
    try {
        $linha = "[{0}] {1}" -f (Get-Date -Format "dd/MM/yyyy HH:mm:ss"), $Mensagem
        Add-Content -Path $script:LogPath -Value $linha -Encoding UTF8
    } catch {}
}

function Obter-ImagemAvatar {
    $possiveisImagens = @(
        (Join-Path $script:BasePath "avatar.png"),
        (Join-Path $script:BasePath "avatar.jpg"),
        (Join-Path $script:BasePath "avatar.jpeg"),
        (Join-Path $script:BasePath "avatar.ico")
    )

    foreach ($img in $possiveisImagens) {
        if ($img -and (Test-Path $img)) { return $img }
    }
    return $null
}

function Solicitar-SenhaProtecao {
    return [Microsoft.VisualBasic.Interaction]::InputBox(
        "Digite a senha para reiniciar este serviço protegido:",
        "Conexões Systemas",
        ""
    )
}

function Validar-SenhaServicoProtegido {
    param([string]$Nome)

    if ($script:ServicosProtegidos -contains $Nome) {
        $senhaDigitada = Solicitar-SenhaProtecao

        if ([string]::IsNullOrWhiteSpace($senhaDigitada)) {
            Escrever-Log "Operação cancelada no serviço protegido '$Nome'."
            [System.Windows.Forms.MessageBox]::Show(
                "Operação cancelada.",
                "Conexões Systemas",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return $false
        }

        if ($senhaDigitada -ne $script:SenhaServicosProtegidos) {
            Escrever-Log "Senha incorreta para serviço protegido '$Nome'."
            [System.Windows.Forms.MessageBox]::Show(
                "Senha incorreta para o serviço protegido '$Nome'.",
                "Conexões Systemas",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return $false
        }

        Escrever-Log "Senha validada com sucesso para '$Nome'."
    }

    return $true
}

function Obter-StatusServico {
    param([string]$Nome)

    $svc = Get-Service -Name $Nome -ErrorAction SilentlyContinue

    if (-not $svc) {
        return [PSCustomObject]@{
            Nome   = $Nome
            Status = "NAO INSTALADO"
            Cor    = [System.Drawing.Color]::Silver
            Tipo   = "NAO_INSTALADO"
        }
    }

    if ($svc.Status -eq 'Running') {
        if ($script:FalhasRecentes.ContainsKey($Nome)) {
            $script:FalhasRecentes.Remove($Nome)
        }
        return [PSCustomObject]@{
            Nome   = $Nome
            Status = "ONLINE"
            Cor    = [System.Drawing.Color]::LimeGreen
            Tipo   = "ONLINE"
        }
    }

    if ($script:ServicosProtegidos -contains $Nome) {
        return [PSCustomObject]@{
            Nome   = $Nome
            Status = "OFFLINE"
            Cor    = [System.Drawing.Color]::Red
            Tipo   = "OFFLINE"
        }
    }

    # Se o serviço estiver desativado no Windows, reporta como desativado sem tentar iniciar
    if ($svc.StartType -eq 'Disabled') {
        return [PSCustomObject]@{
            Nome   = $Nome
            Status = "DESATIVADO"
            Cor    = [System.Drawing.Color]::Orange
            Tipo   = "OFFLINE"
        }
    }

    # Se já tentou iniciar e falhou, não congela a interface a cada 10s
    if ($script:FalhasRecentes.ContainsKey($Nome)) {
        return [PSCustomObject]@{
            Nome   = $Nome
            Status = "FALHA AO REINICIAR"
            Cor    = [System.Drawing.Color]::Red
            Tipo   = "OFFLINE"
        }
    }

    try {
        Start-Service -Name $Nome -ErrorAction Stop
        Start-Sleep -Milliseconds 600
        $svc = Get-Service -Name $Nome -ErrorAction SilentlyContinue

        if ($svc -and $svc.Status -eq 'Running') {
            Escrever-Log "Serviço '$Nome' iniciado automaticamente com sucesso."
            return [PSCustomObject]@{
                Nome   = $Nome
                Status = "REINICIADO COM SUCESSO"
                Cor    = [System.Drawing.Color]::DodgerBlue
                Tipo   = "ONLINE"
            }
        } else {
            $script:FalhasRecentes[$Nome] = $true
            Escrever-Log "Falha ao iniciar automaticamente o serviço '$Nome'."
            return [PSCustomObject]@{
                Nome   = $Nome
                Status = "FALHA AO REINICIAR"
                Cor    = [System.Drawing.Color]::Red
                Tipo   = "OFFLINE"
            }
        }
    } catch {
        $script:FalhasRecentes[$Nome] = $true
        Escrever-Log "Erro ao iniciar automaticamente '$Nome': $($_.Exception.Message)"
        return [PSCustomObject]@{
            Nome   = $Nome
            Status = "FALHA AO REINICIAR"
            Cor    = [System.Drawing.Color]::Red
            Tipo   = "OFFLINE"
        }
    }
}

function Reiniciar-ServicoIndividual {
    param([string]$Nome)

    try {
        if (-not (Validar-SenhaServicoProtegido -Nome $Nome)) { return }

        $svc = Get-Service -Name $Nome -ErrorAction SilentlyContinue

        if (-not $svc) {
            Escrever-Log "Tentativa de ação no serviço '$Nome', mas ele não está instalado."
            [System.Windows.Forms.MessageBox]::Show(
                "O serviço '$Nome' não está instalado.",
                "Conexões Systemas",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        # Reseta o controle de falhas para permitir nova tentativa
        if ($script:FalhasRecentes.ContainsKey($Nome)) {
            $script:FalhasRecentes.Remove($Nome)
        }

        # Se estiver desativado, habilita
        if ($svc.StartType -eq 'Disabled') {
            Set-Service -Name $Nome -StartupType Automatic -ErrorAction SilentlyContinue
        }

        if ($svc.Status -eq 'Running') {
            Restart-Service -Name $Nome -Force -ErrorAction Stop
            Escrever-Log "Serviço '$Nome' reiniciado manualmente."
        } else {
            Start-Service -Name $Nome -ErrorAction Stop
            Escrever-Log "Serviço '$Nome' iniciado manualmente."
        }

        Start-Sleep -Milliseconds 800
        Atualizar-Painel
    } catch {
        Escrever-Log "Falha ao reiniciar/iniciar '$Nome': $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao reiniciar o serviço '$Nome'.`n$($_.Exception.Message)",
            "Conexões Systemas",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Reiniciar-TodosServicos {
    foreach ($srv in $servicos) {
        try {
            if ($script:ServicosProtegidos -contains $srv) {
                if (-not (Validar-SenhaServicoProtegido -Nome $srv)) {
                    Escrever-Log "Serviço protegido '$srv' ignorado no reinício em lote."
                    continue
                }
            }

            # Reseta falha para tentar reiniciar
            if ($script:FalhasRecentes.ContainsKey($srv)) {
                $script:FalhasRecentes.Remove($srv)
            }

            $svc = Get-Service -Name $srv -ErrorAction SilentlyContinue
            if ($svc) {
                if ($svc.Status -eq 'Running') {
                    Restart-Service -Name $srv -Force -ErrorAction SilentlyContinue
                    Escrever-Log "Serviço '$srv' reiniciado em lote."
                } else {
                    if ($svc.StartType -ne 'Disabled') {
                        Start-Service -Name $srv -ErrorAction SilentlyContinue
                        Escrever-Log "Serviço '$srv' iniciado em lote."
                    }
                }
            } else {
                Escrever-Log "Serviço '$srv' não instalado durante rotina em lote."
            }
        } catch {
            Escrever-Log "Erro em lote no serviço '$srv': $($_.Exception.Message)"
        }
        [System.Windows.Forms.Application]::DoEvents()
    }

    Start-Sleep -Milliseconds 800
    Atualizar-Painel
}

function Abrir-Log {
    try {
        if (-not (Test-Path $script:LogPath)) {
            New-Item -Path $script:LogPath -ItemType File -Force | Out-Null
        }
        Start-Process notepad.exe $script:LogPath | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Não foi possível abrir o log.",
            "Conexões Systemas"
        ) | Out-Null
    }
}

function Configurar-InicioComWindows {
    try {
        $startupFolder = [Environment]::GetFolderPath("Startup")
        $atalhoPath = Join-Path $startupFolder "Monitoramento Conexoes.lnk"
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($atalhoPath)

        $exeAtual = [System.Windows.Forms.Application]::ExecutablePath
        if (-not $exeAtual -or -not (Test-Path $exeAtual)) {
            $vbsPath = Join-Path $script:BasePath "abrir_monitoramento.vbs"
            if (Test-Path $vbsPath) {
                $shortcut.TargetPath = $vbsPath
                $shortcut.WorkingDirectory = $script:BasePath
                $shortcut.Save()
                Escrever-Log "Atalho VBS criado para iniciar com Windows: $atalhoPath"
                [System.Windows.Forms.MessageBox]::Show(
                    "Configurado para iniciar com Windows.",
                    "Conexões Systemas",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
                return
            }
        }

        $shortcut.TargetPath = $exeAtual
        $shortcut.WorkingDirectory = Split-Path -Parent $exeAtual
        $shortcut.Save()

        Escrever-Log "Atalho criado para iniciar com Windows: $atalhoPath"
        [System.Windows.Forms.MessageBox]::Show(
            "Configurado para iniciar com Windows.",
            "Conexões Systemas",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {
        Escrever-Log "Falha ao configurar início com Windows: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Não foi possível configurar o início com Windows.`n$($_.Exception.Message)",
            "Conexões Systemas",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

$imgPath = Obter-ImagemAvatar

$form = New-Object System.Windows.Forms.Form
$form.Text = "CONEXOES SYSTEMAS - MONITORAMENTO AO VIVO"
$form.Size = New-Object System.Drawing.Size(1360, 780)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(8, 18, 40)
$form.ForeColor = [System.Drawing.Color]::White
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Icon = $null

if ($imgPath -and (Test-Path $imgPath) -and $imgPath.EndsWith(".ico")) {
    try {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($imgPath)
    } catch {}
}

$topBar = New-Object System.Windows.Forms.Panel
$topBar.Size = New-Object System.Drawing.Size(1360, 70)
$topBar.Location = New-Object System.Drawing.Point(0, 0)
$topBar.BackColor = [System.Drawing.Color]::FromArgb(5, 14, 32)
$form.Controls.Add($topBar)

$titulo = New-Object System.Windows.Forms.Label
$titulo.Text = "CONEXOES SYSTEMAS - MONITORAMENTO AO VIVO"
$titulo.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$titulo.AutoSize = $true
$titulo.Location = New-Object System.Drawing.Point(25, 18)
$topBar.Controls.Add($titulo)

$relogioTopo = New-Object System.Windows.Forms.Label
$relogioTopo.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$relogioTopo.AutoSize = $true
$relogioTopo.Location = New-Object System.Drawing.Point(1030, 25)
$topBar.Controls.Add($relogioTopo)

$cardAvatar = New-Object System.Windows.Forms.Panel
$cardAvatar.Location = New-Object System.Drawing.Point(20, 90)
$cardAvatar.Size = New-Object System.Drawing.Size(280, 250)
$cardAvatar.BackColor = [System.Drawing.Color]::FromArgb(18, 32, 66)
$form.Controls.Add($cardAvatar)

$picture = New-Object System.Windows.Forms.PictureBox
$picture.Location = New-Object System.Drawing.Point(20, 20)
$picture.Size = New-Object System.Drawing.Size(240, 180)
$picture.SizeMode = "Zoom"
$picture.BorderStyle = "FixedSingle"
$picture.BackColor = [System.Drawing.Color]::FromArgb(12, 25, 55)

if ($imgPath -and (Test-Path $imgPath)) {
    try { $picture.Image = [System.Drawing.Image]::FromFile($imgPath) } catch {}
}

$cardAvatar.Controls.Add($picture)

$lblAvatar = New-Object System.Windows.Forms.Label
$lblAvatar.Text = "SUPORTE TECNICO"
$lblAvatar.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$lblAvatar.AutoSize = $true
$lblAvatar.Location = New-Object System.Drawing.Point(62, 210)
$cardAvatar.Controls.Add($lblAvatar)

$cardResumo = New-Object System.Windows.Forms.Panel
$cardResumo.Location = New-Object System.Drawing.Point(320, 90)
$cardResumo.Size = New-Object System.Drawing.Size(1010, 190)
$cardResumo.BackColor = [System.Drawing.Color]::FromArgb(18, 32, 66)
$form.Controls.Add($cardResumo)

$subtitulo = New-Object System.Windows.Forms.Label
$subtitulo.Text = "Painel de serviços com atualização automática, reinício individual e log"
$subtitulo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$subtitulo.AutoSize = $true
$subtitulo.Location = New-Object System.Drawing.Point(25, 18)
$cardResumo.Controls.Add($subtitulo)

$lblOnline = New-Object System.Windows.Forms.Label
$lblOnline.Text = "ONLINE: 0"
$lblOnline.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$lblOnline.ForeColor = [System.Drawing.Color]::LimeGreen
$lblOnline.AutoSize = $true
$lblOnline.Location = New-Object System.Drawing.Point(25, 55)
$cardResumo.Controls.Add($lblOnline)

$lblOffline = New-Object System.Windows.Forms.Label
$lblOffline.Text = "OFFLINE: 0"
$lblOffline.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$lblOffline.ForeColor = [System.Drawing.Color]::Red
$lblOffline.AutoSize = $true
$lblOffline.Location = New-Object System.Drawing.Point(250, 55)
$cardResumo.Controls.Add($lblOffline)

$lblNaoInst = New-Object System.Windows.Forms.Label
$lblNaoInst.Text = "NAO INSTALADO: 0"
$lblNaoInst.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$lblNaoInst.ForeColor = [System.Drawing.Color]::Silver
$lblNaoInst.AutoSize = $true
$lblNaoInst.Location = New-Object System.Drawing.Point(500, 55)
$cardResumo.Controls.Add($lblNaoInst)

$btnAtualizar = New-Object System.Windows.Forms.Button
$btnAtualizar.Text = "ATUALIZAR AGORA"
$btnAtualizar.Size = New-Object System.Drawing.Size(170, 40)
$btnAtualizar.Location = New-Object System.Drawing.Point(25, 110)
$btnAtualizar.FlatStyle = "Flat"
$btnAtualizar.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnAtualizar.ForeColor = [System.Drawing.Color]::White
$btnAtualizar.Cursor = "Hand"
$cardResumo.Controls.Add($btnAtualizar)

$btnReiniciar = New-Object System.Windows.Forms.Button
$btnReiniciar.Text = "REINICIAR TODOS"
$btnReiniciar.Size = New-Object System.Drawing.Size(170, 40)
$btnReiniciar.Location = New-Object System.Drawing.Point(215, 110)
$btnReiniciar.FlatStyle = "Flat"
$btnReiniciar.BackColor = [System.Drawing.Color]::FromArgb(200, 60, 60)
$btnReiniciar.ForeColor = [System.Drawing.Color]::White
$btnReiniciar.Cursor = "Hand"
$cardResumo.Controls.Add($btnReiniciar)

$btnLog = New-Object System.Windows.Forms.Button
$btnLog.Text = "ABRIR LOG"
$btnLog.Size = New-Object System.Drawing.Size(150, 40)
$btnLog.Location = New-Object System.Drawing.Point(405, 110)
$btnLog.FlatStyle = "Flat"
$btnLog.BackColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
$btnLog.ForeColor = [System.Drawing.Color]::White
$btnLog.Cursor = "Hand"
$cardResumo.Controls.Add($btnLog)

$btnStartup = New-Object System.Windows.Forms.Button
$btnStartup.Text = "INICIAR COM WINDOWS"
$btnStartup.Size = New-Object System.Drawing.Size(220, 40)
$btnStartup.Location = New-Object System.Drawing.Point(575, 110)
$btnStartup.FlatStyle = "Flat"
$btnStartup.BackColor = [System.Drawing.Color]::FromArgb(50, 120, 80)
$btnStartup.ForeColor = [System.Drawing.Color]::White
$btnStartup.Cursor = "Hand"
$cardResumo.Controls.Add($btnStartup)

$btnFechar = New-Object System.Windows.Forms.Button
$btnFechar.Text = "FECHAR"
$btnFechar.Size = New-Object System.Drawing.Size(140, 40)
$btnFechar.Location = New-Object System.Drawing.Point(815, 110)
$btnFechar.FlatStyle = "Flat"
$btnFechar.BackColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
$btnFechar.ForeColor = [System.Drawing.Color]::White
$btnFechar.Cursor = "Hand"
$cardResumo.Controls.Add($btnFechar)

$lblUltimaAcao = New-Object System.Windows.Forms.Label
$lblUltimaAcao.Text = "Ultima ação: aguardando monitoramento"
$lblUltimaAcao.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$lblUltimaAcao.AutoSize = $true
$lblUltimaAcao.Location = New-Object System.Drawing.Point(25, 160)
$cardResumo.Controls.Add($lblUltimaAcao)

$cardTabela = New-Object System.Windows.Forms.Panel
$cardTabela.Location = New-Object System.Drawing.Point(20, 360)
$cardTabela.Size = New-Object System.Drawing.Size(1290, 360)
$cardTabela.AutoScroll = $true
$cardTabela.BackColor = [System.Drawing.Color]::FromArgb(18, 32, 66)
$form.Controls.Add($cardTabela)

$header1 = New-Object System.Windows.Forms.Label
$header1.Text = "SERVICO"
$header1.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$header1.AutoSize = $true
$header1.Location = New-Object System.Drawing.Point(30, 18)
$cardTabela.Controls.Add($header1)

$header2 = New-Object System.Windows.Forms.Label
$header2.Text = "STATUS"
$header2.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$header2.AutoSize = $true
$header2.Location = New-Object System.Drawing.Point(500, 18)
$cardTabela.Controls.Add($header2)

$header3 = New-Object System.Windows.Forms.Label
$header3.Text = "INDICADOR"
$header3.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$header3.AutoSize = $true
$header3.Location = New-Object System.Drawing.Point(900, 18)
$cardTabela.Controls.Add($header3)

$header4 = New-Object System.Windows.Forms.Label
$header4.Text = "ACAO"
$header4.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$header4.AutoSize = $true
$header4.Location = New-Object System.Drawing.Point(1040, 18)
$cardTabela.Controls.Add($header4)

$linhaTopo = New-Object System.Windows.Forms.Panel
$linhaTopo.Size = New-Object System.Drawing.Size(1210, 1)
$linhaTopo.Location = New-Object System.Drawing.Point(25, 45)
$linhaTopo.BackColor = [System.Drawing.Color]::FromArgb(70, 90, 130)
$cardTabela.Controls.Add($linhaTopo)

$script:linhas = @()

for ($i = 0; $i -lt $servicos.Count; $i++) {
    $y = 60 + ($i * 30)
    $nomeServico = $servicos[$i]

    $nome = New-Object System.Windows.Forms.Label
    $nome.Text = $nomeServico
    $nome.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $nome.AutoSize = $false
    $nome.Size = New-Object System.Drawing.Size(360, 24)
    $nome.Location = New-Object System.Drawing.Point(30, $y)
    $cardTabela.Controls.Add($nome)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = "Verificando..."
    $status.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $status.AutoSize = $false
    $status.Size = New-Object System.Drawing.Size(320, 24)
    $status.Location = New-Object System.Drawing.Point(500, $y)
    $cardTabela.Controls.Add($status)

    $indicador = New-Object System.Windows.Forms.Panel
    $indicador.Size = New-Object System.Drawing.Size(18, 18)
    $indicador.Location = New-Object System.Drawing.Point(940, ($y + 2))
    $indicador.BackColor = [System.Drawing.Color]::Silver
    $cardTabela.Controls.Add($indicador)

    $btnLinha = New-Object System.Windows.Forms.Button
    $btnLinha.Text = "REINICIAR"
    $btnLinha.Size = New-Object System.Drawing.Size(130, 24)
    $btnLinha.Location = New-Object System.Drawing.Point(1030, ($y - 1))
    $btnLinha.FlatStyle = "Flat"
    $btnLinha.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnLinha.ForeColor = [System.Drawing.Color]::White
    $btnLinha.Tag = $nomeServico
    $btnLinha.Cursor = "Hand"
    $btnLinha.Add_Click({
        param($sender, $eventArgs)
        Reiniciar-ServicoIndividual -Nome $sender.Tag
    })
    $cardTabela.Controls.Add($btnLinha)

    $sep = New-Object System.Windows.Forms.Panel
    $sep.Size = New-Object System.Drawing.Size(1210, 1)
    $sep.Location = New-Object System.Drawing.Point(25, ($y + 26))
    $sep.BackColor = [System.Drawing.Color]::FromArgb(45, 60, 95)
    $cardTabela.Controls.Add($sep)

    $script:linhas += [PSCustomObject]@{
        Servico     = $nomeServico
        NomeLabel   = $nome
        StatusLabel = $status
        Indicador   = $indicador
        Botao       = $btnLinha
        Tipo        = ""
    }
}

$rodape = New-Object System.Windows.Forms.Label
$rodape.Text = "Atualizacao automatica a cada 10 segundos"
$rodape.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Italic)
$rodape.AutoSize = $true
$rodape.Location = New-Object System.Drawing.Point(20, 730)
$form.Controls.Add($rodape)

function Atualizar-Painel {
    $relogioTopo.Text = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")

    $online = 0
    $offline = 0
    $naoInst = 0

    foreach ($linha in $script:linhas) {
        $resultado = Obter-StatusServico -Nome $linha.Servico
        $linha.StatusLabel.Text = $resultado.Status
        $linha.StatusLabel.ForeColor = $resultado.Cor
        $linha.Indicador.BackColor = $resultado.Cor
        $linha.Tipo = $resultado.Tipo

        if ($linha.Botao) {
            $ehProtegido = $script:ServicosProtegidos -contains $linha.Servico

            switch ($resultado.Tipo) {
                "ONLINE" {
                    $linha.Botao.Text = if ($ehProtegido) { "REINICIAR 🔒" } else { "REINICIAR" }
                    $linha.Botao.Enabled = $true
                    $linha.Botao.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
                }
                "OFFLINE" {
                    $linha.Botao.Text = if ($ehProtegido) { "INICIAR 🔒" } else { "INICIAR" }
                    $linha.Botao.Enabled = $true
                    $linha.Botao.BackColor = [System.Drawing.Color]::FromArgb(200, 60, 60)
                }
                "NAO_INSTALADO" {
                    $linha.Botao.Text = "INDISPONIVEL"
                    $linha.Botao.Enabled = $false
                    $linha.Botao.BackColor = [System.Drawing.Color]::Gray
                }
            }
        }

        switch ($resultado.Tipo) {
            "ONLINE" { $online++ }
            "OFFLINE" { $offline++ }
            "NAO_INSTALADO" { $naoInst++ }
        }

        [System.Windows.Forms.Application]::DoEvents()
    }

    $lblOnline.Text = "ONLINE: $online"
    $lblOffline.Text = "OFFLINE: $offline"
    $lblNaoInst.Text = "NAO INSTALADO: $naoInst"
    $lblUltimaAcao.Text = "Ultima ação: painel atualizado em " + (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
}

$btnAtualizar.Add_Click({
    Escrever-Log "Atualização manual executada."
    Atualizar-Painel
})

$btnReiniciar.Add_Click({
    Escrever-Log "Rotina manual de reinício geral iniciada."
    Reiniciar-TodosServicos
})

$btnLog.Add_Click({ Abrir-Log })
$btnStartup.Add_Click({ Configurar-InicioComWindows })

$btnFechar.Add_Click({
    Escrever-Log "Painel encerrado pelo usuário."
    $form.Close()
})

Escrever-Log "Painel iniciado."
Atualizar-Painel

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 10000
$timer.Add_Tick({ Atualizar-Painel })
$timer.Start()

[void]$form.ShowDialog()
