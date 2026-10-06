# 🖥️ CONEXÕES SYSTEMAS - MONITORAMENTO AO VIVO

> **Painel Oficial de Monitoramento de Serviços e Conexões para Postos e Varejo.**

![Status](https://img.shields.io/badge/Status-Oficial%20Est%C3%A1vel-success?style=for-the-badge)
![Plataforma](https://img.shields.io/badge/Plataforma-Windows-blue?style=for-the-badge)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%2F%20Windows%20Forms-informational?style=for-the-badge)

---

## 📋 Visão Geral

Painel oficial da **Conexões Systemas** para monitoramento contínuo em tempo real dos serviços vitais de automação, pista, fiscal e banco de dados.

A interface mantém fielmente a identidade visual original do sistema com os cards de status (**ONLINE**, **OFFLINE**, **NÃO INSTALADO**), avatar de suporte técnico, botões de ação direta e tabela de indicadores.

---

## 🛠️ Correções e Melhorias Internas Aplicadas

- **Fim do congelamento da interface ("Não Respondendo"):** As verificações e reinícios utilizam `DoEvents` e pausas não obstrutivas, garantindo que a tela nunca congele.
- **Prevenção de loop em serviços com falha:** O sistema detecta serviços desativados no Windows (`Disabled`) ou que falharam ao iniciar, evitando tentativas repetitivas a cada 10 segundos e impedindo o acúmulo excessivo de logs.
- **Elevação Administrativa Nativa (UAC):** Executável compilado com manifesto de Administrador para garantir permissões de iniciar e parar serviços do Windows sem erros de acesso negado.
- **Segurança de Bancos de Dados (PostgreSQL):** Proteção por senha administrativa nos serviços críticos (`postgresql-x64-9.5` e `postgresql-x64-12`).
- **Codificação UTF-8 com BOM:** Garante compatibilidade total de acentuação e caracteres com o PowerShell 5.1.

---

## 📦 Lista de Serviços Monitorados

1. **ServicoFiscal**
2. **QualityPulser**
3. **srvIntegraWeb**
4. **ServicoAutomacao**
5. **ServicoBaixaAutomatica**
6. **ServicoPremmia**
7. **ServicoSemParar**
8. **ServicoShellBox**
9. **ServicoCofre**
10. **ServicoMicroTerminal**
11. **postgresql-x64-9.5** 🔒 *(Protegido por senha)*
12. **postgresql-x64-12** 🔒 *(Protegido por senha)*

---

## 🚀 Como Executar

- **Executável Oficial:** Execute `monitoramento_conexoes.exe`.
- **PowerShell:** Execute `powershell -ExecutionPolicy Bypass -STA -File .\monitoramento_conexoes.ps1`.
- **Modo Silencioso:** Execute `abrir_monitoramento.vbs`.

---

## 🔨 Compilação

Para compilar o executável oficial `.exe`:
```powershell
.\build.ps1
```
