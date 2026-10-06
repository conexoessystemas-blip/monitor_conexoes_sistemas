# 🚀 Monitoramento Conexões Sistemas (v3.0 Ultra)

> **Painel Central Avançado de Monitoramento em Tempo Real, Telemetria e Auto-Recuperação de Serviços para Postos de Combustíveis, PDVs e Automação Comercial.**

![Status](https://img.shields.io/badge/Status-Estável%20v3.0%20Ultra-success?style=for-the-badge)
![Plataforma](https://img.shields.io/badge/Plataforma-Windows%2010%20%2F%2011%20%2F%20Server-blue?style=for-the-badge)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%2F%20.NET-informational?style=for-the-badge)
![Segurança](https://img.shields.io/badge/Segurança-UAC%20Admin%20Elevated-red?style=for-the-badge)

---

## 📋 Visão Geral

O **Monitor Conexões Sistemas** é uma solução de missão crítica desenvolvida especificamente para garantir a disponibilidade ininterrupta dos serviços vitais que operam em postos de combustíveis e empresas atendidas pela **Conexões Sistemas**.

Ele monitora continuamente o ciclo de vida dos serviços do Windows (Fiscais, Automação de Bombas, Fidelidade, TEF, Pagamentos e Bancos de Dados), fornecendo auto-recuperação inteligente (*self-healing*), telemetria em tempo real (PID, Consumo de RAM, Uptime), testes de porta TCP e alertas visuais e sonoros para os operadores e técnicos de suporte.

---

## ✨ Principais Funcionalidades

### 🛡️ 1. Motor de Auto-Recuperação Inteligente (*Self-Healing*)
- Detecta automaticamente quando um serviço configurado como automático cai.
- Executa tentativas graduais de reinício com **limite de tentativas (max 3)** e **tempo de resfriamento (*cooldown* de 60s)**.
- **Proteção anti-loop**: se um serviço estiver com falha irrecuperável ou configuração corrompida, o sistema suspende as tentativas e emite alerta visual sem travar o computador nem gerar logs infinitos.
- Diferencia com precisão serviços `DESATIVADOS` no Windows de serviços com falha, disponibilizando ação de **"Habilitar & Iniciar"** em um único clique.

### 📊 2. Telemetria e Conectividade em Tempo Real
- **Consumo de Memória (RAM em MB)** e **PID (ID do Processo)** de cada serviço ativo.
- **Tempo de Atividade (*Uptime*)** contínuo de cada serviço.
- **Teste de Portas TCP (Socket Ping)**: valida se serviços que escutam em portas de rede (ex: PostgreSQL na porta `5432`) estão de fato aceitando conexões.

### ⚙️ 3. Configuração Dinâmica via `config.json`
- Todos os serviços, portas de rede, tempos de varredura e limites de recuperação são configurados em arquivo JSON externo.
- Permite adicionar, editar e remover serviços sem tocar no código-fonte.
- **Gerenciador de Serviços na Interface**: botão **"➕ Adicionar"** que lista serviços instalados no Windows para cadastro rápido em tela.

### 📑 4. Gerador de Diagnóstico Completo em 1 Clique
- Botão **"📊 Diagnóstico"**: coleta instantaneamente informações de CPU, memória RAM total/livre, espaço em disco (Drive C:), versão do Windows, estado de todos os serviços e os 30 últimos logs, abrindo o relatório formatado no Bloco de Notas para envio rápido ao suporte da Conexões Sistemas.

### 🔔 5. Notificações e Bandeja do Sistema (*System Tray*)
- Minimiza para a bandeja do Windows (ao lado do relógio), liberando espaço na barra de tarefas.
- Alertas em balão (*Balloon Tooltips*) e aviso sonoro sutil quando um serviço essencial cair.
- Menu de contexto na bandeja para ações rápidas: Abrir Painel, Atualizar, Reiniciar Todos, Ver Logs e Exportar Diagnóstico.

### 🔒 6. Segurança e Proteção de Bancos de Dados (PostgreSQL)
- Bancos de dados relacionais (`postgresql-x64-9.5`, `postgresql-x64-12`) contam com proteção por senha com interface de texto mascarado (`***`), prevenindo paradas acidentais durante rotinas manuais ou reinícios em lote.

---

## 📦 Serviços Suportados Nativamente

| Serviço | Nome do Sistema | Finalidade / Descrição | Porta | Protegido |
| :--- | :--- | :--- | :---: | :---: |
| **Serviço Fiscal** | `ServicoFiscal` | Emissão de NFC-e, SAT e rotinas fiscais | - | Não |
| **Quality Pulser Web** | `QualityPulser` | Sincronização e controle de bombas Quality | - | Não |
| **Integra Web** | `srvIntegraWeb` | Sincronização web e dados da pista | - | Não |
| **webPosto Automação** | `ServicoAutomacao` | Leitura e comunicação de pista webPosto | - | Não |
| **webPosto Baixa Automática** | `ServicoBaixaAutomatica` | Baixa automática de pendências webPosto | - | Não |
| **Serviço Premmia** | `ServicoPremmia` | Integração do programa de fidelidade Premmia | - | Não |
| **Serviço Sem Parar** | `ServicoSemParar` | Identificação e pagamento Sem Parar abastecimento | - | Não |
| **Serviço Shell Box** | `ServicoShellBox` | Pagamentos e fidelidade Shell Box | - | Não |
| **Serviço Cofre** | `ServicoCofre` | Comunicação com o cofre inteligente | - | Não |
| **Micro Terminal** | `ServicoMicroTerminal` | Terminais e teclados de pista | - | Não |
| **PostgreSQL 9.5** | `postgresql-x64-9.5` | Banco de Dados relacional PostgreSQL v9.5 | 5432 | 🔒 Sim |
| **PostgreSQL 12** | `postgresql-x64-12` | Banco de Dados relacional PostgreSQL v12 | 5432 | 🔒 Sim |

---

## 🛠️ Estrutura do Repositório

```text
├── monitoramento_conexoes.exe         # Executável compilado de alta performance (DPI Aware, RequireAdmin)
├── monitoramento_conexoes.exe.config  # Configuração de DPI e .NET Framework para a interface
├── monitoramento_conexoes.ps1         # Código-fonte principal em PowerShell com arquitetura assíncrona
├── config.json                        # Arquivo de configuração de serviços e parâmetros operacionais
├── abrir_monitoramento.vbs            # Inicializador em VBScript sem janela de terminal
├── avatar.ico                         # Ícone institucional Conexões Sistemas
├── build.ps1                          # Script de compilação automatizada com Invoke-ps2exe
├── instalar_servico_startup.ps1       # Script para criar atalhos na Área de Trabalho e Inicialização
├── .gitignore                         # Filtro de logs e arquivos temporários
└── README.md                          # Documentação técnica do projeto
```

---

## 🚀 Como Executar

### Opção 1: Executável Direto (Recomendado)
Execute `monitoramento_conexoes.exe` com duplo clique. Ele solicitará permissão de Administrador (UAC) e iniciará com suporte a alta resolução e integração na bandeja do sistema.

### Opção 2: Via PowerShell
Abra o PowerShell como Administrador e execute:
```powershell
powershell -ExecutionPolicy Bypass -STA -File .\monitoramento_conexoes.ps1
```

### Opção 3: Modo Silencioso (VBS)
Execute `abrir_monitoramento.vbs` para abrir sem qualquer janela preta de console.

---

## 🔨 Como Compilar

Para gerar um novo executável a partir do código-fonte `monitoramento_conexoes.ps1`:
```powershell
.\build.ps1
```
O script usará o módulo `ps2exe` com parâmetros de manifesto de administrador, ícone institucional e DPI awareness.

---

## 📌 Como Instalar na Máquina do Cliente

Para configurar a inicialização automática e atalho na área de trabalho em um cliente novo:
```powershell
powershell -ExecutionPolicy Bypass -File .\instalar_servico_startup.ps1
```

---

## 👨‍💻 Desenvolvido por

**Conexões Sistemas**  
*Soluções em Tecnologia e Automação para Postos e Varejo*  
Repositório: [conexoessystemas-blip/monitor_conexoes_sistemas](https://github.com/conexoessystemas-blip/monitor_conexoes_sistemas)
