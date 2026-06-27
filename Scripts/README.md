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
| `rustdesk.ps1` | Remove o AnyDesk, instala o RustDesk e aplica a configuração do servidor próprio (`monitor.paerrotecnologia.com.br`) em perfil de usuário **e** LocalService. Valida integridade do `RustDesk2.toml` pós-restart e guia a definição da senha padrão de acesso não supervisionado via CLI. |


### Execução remota dos scripts disponíveis
- 🌐 **RustDesk**
```powershell
irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/Scripts/rustdesk.ps1 | iex
```


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

Os scripts desta pasta registram logs em:

```
C:\Users\Public\Documents\Logs\Outros\
```

Seguindo o padrão de logs definido no README principal do repositório.

---

## 🔐 Segurança

* ❌ Nunca embutir senhas de acesso remoto em texto plano no script ou no repositório
* ✔ Senhas padronizadas (ex: acesso não supervisionado) são definidas manualmente via CLI pelo técnico, nunca commitadas
* ✔ Validar scripts antes da execução
* ❌ Evitar fontes externas não confiáveis

---

## 👨‍💻 Responsável

**Eduardo Ferreira**

Suporte Técnico Júnior
