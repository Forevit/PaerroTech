# 📜 Scripts

<p align="center">
  <b>Utilitários • Diagnóstico • Ferramentas rápidas</b><br>
  Scripts auxiliares para o dia a dia do suporte técnico
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Status-Ativo-green">
  <img src="https://img.shields.io/badge/Tipo-Utilitário-blue">
  <img src="https://img.shields.io/badge/Uso-Sob%20Demanda-orange">
  <img src="https://img.shields.io/badge/PowerShell-Scripts-0078D6">
</p>

---

## 📌 Visão Geral

A pasta **Scripts** reúne utilitários e ferramentas pontuais para suporte técnico, diagnóstico e automações que não se encaixam nas pastas dedicadas (`Padronizacao-Maquinas/`, `Preventivas/`, `ScriptsMikrotik/`).

---

## 🧠 Objetivo

Centralizar scripts úteis para:

- 🔍 Diagnóstico de problemas
- ⚡ Execução de tarefas rápidas
- 🛠️ Suporte técnico no dia a dia
- 📊 Coleta de informações
- 🌐 Implantação e configuração de ferramentas de acesso remoto

---

## 📋 Scripts disponíveis

| Script | Descrição |
|---|---|
| `rustdesk.ps1` | Instala/atualiza o RustDesk 1.4.9, verifica o SHA-256 publicado pelo projeto, configura o servidor próprio nos perfis do usuário interativo e LocalService, reinicia e valida o serviço e solicita a senha permanente via CLI. |


### Execução remota dos scripts disponíveis
- 🌐 **RustDesk**
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/Scripts/rustdesk.ps1 | iex"
```

Abra o PowerShell **como Administrador** antes de executar o comando remoto. Para execução local, execute `rustdesk.ps1` em uma sessão elevada. A elevação automática não é usada quando o script chega por `irm | iex`, pois o conteúdo seria baixado novamente durante a elevação.


> Novos scripts serão listados aqui conforme adicionados.

---

## 🚀 Como utilizar

### 🔹 Execução remota (rápida)

```powershell
irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/Scripts/<script>.ps1 | iex
```

> ⚠️ Executar como administrador
> ⚠️ Utilize apenas scripts confiáveis

### 🔹 Execução local

```powershell
cd Scripts
.\nome-do-script.ps1
```

---

## ⚠️ Boas práticas

* Executar como **Administrador** (quando necessário)
* Validar o script antes do uso, principalmente os que alteram configuração de acesso remoto
* Evitar execução em produção sem análise
* Confirmar variáveis de configuração (URLs, servidores, versões) antes de distribuir em massa

---

## 📝 Logs

O script RustDesk registra logs em:

```
C:\Users\Public\Documents\Logs\Outros\
```

Seguindo o padrão de logs definido no README principal do repositório.

---

## 🔐 Segurança

* ❌ Nunca embutir senhas de acesso remoto em texto plano no script ou no repositório
* ✔ Na execução interativa, a senha é solicitada sem eco no terminal
* ✔ Em automações, o script aceita `RUSTDESK_PASSWORD` no ambiente; um GitHub Secret só é disponibilizado a um workflow do Actions que o injete nessa variável (por exemplo, em um self-hosted runner autorizado)
* ⚠️ O comando CLI do RustDesk recebe a senha como argumento de processo; restrinja quem pode inspecionar processos no dispositivo e use uma senha única por máquina
* ✔ Validar scripts antes da execução
* ❌ Evitar fontes externas não confiáveis

---

## 👨‍💻 Responsável

**Eduardo Ferreira**

Suporte Técnico Júnior
