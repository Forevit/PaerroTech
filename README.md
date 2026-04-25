# 🏢 PaerroTech

<p align="center">
  <b>Automação • Padronização • Infraestrutura</b><br>
  Soluções internas para otimizar operações de TI
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Status-Em%20Produção-green">
  <img src="https://img.shields.io/badge/PowerShell-Automation-blue">
  <img src="https://img.shields.io/badge/Windows-Suporte-0078D6">
  <img src="https://img.shields.io/badge/License-Uso%20Interno-red">
</p>

---

## 📌 Visão Geral

A **PaerroTech** é o repositório central de automações da equipe de TI, desenvolvido para padronizar processos, reduzir tempo operacional e aumentar a eficiência no suporte técnico.

Este ambiente reúne scripts utilizados no dia a dia para:

- 🖥️ Padronização de máquinas
- 🔧 Manutenção preventiva
- 🌐 Diagnóstico de rede
- ⚙️ Automação de tarefas repetitivas
- 📦 Deploy de aplicações

---

## 🧭 Navegação

- [📂 Estrutura](#-estrutura-do-repositório)
- [🚀 Como usar](#-como-utilizar)
- [📜 Padrões](#-padrão-de-desenvolvimento)
- [🔐 Segurança](#-segurança)
- [📈 Evolução](#-evolução)

---

## 🗂️ Estrutura do Repositório

```

📁 PaerroTech
├── 📁 Padronizacao-Maquinas/   → Setup completo de estações
├── 📁 Preventivas/             → Rotinas de manutenção
├── 📁 Scripts/                 → Utilitários diversos
├── 📁 Automacoes/              → Integrações e fluxos
├── 📁 Rede/                    → Ferramentas de diagnóstico
└── README.md

````

---

## 🚀 Como utilizar

### 🔹 Execução remota (rápida)

```powershell
irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/<script>.ps1 | iex
````

> ⚠️ Executar como administrador
> ⚠️ Utilize apenas scripts confiáveis

---

### 🔹 Execução local

```bash
git clone https://github.com/Forevit/PaerroTech.git
cd PaerroTech
```

Depois, navegue até o diretório desejado e execute o script.

---

## ⚙️ Filosofia do Projeto

Este repositório segue três princípios:

### ⚡ Automação

Reduzir tarefas manuais e repetitivas

### 📏 Padronização

Garantir consistência entre máquinas e ambientes

### 🔒 Segurança

Executar tudo com controle e boas práticas

---

## 🧠 Boas práticas

* Executar scripts como **Administrador**
* Validar antes de rodar em produção
* Preferir scripts já existentes
* Documentar alterações
* Evitar execução de fontes externas

---

## 📝 Padrão de Logs

Todos os scripts devem registrar logs em:

```
C:\Users\Public\Documents\Logs\
```

Estrutura esperada:

```
Logs/
 ├── Padronizacao/
 ├── Preventiva/
 └── Outros/
```

---

## 🛠️ Padrão de desenvolvimento

Scripts devem seguir:

* ✔ Nome descritivo
* ✔ Comentários explicativos
* ✔ Tratamento de erro (`try/catch`)
* ✔ Sistema de logs
* ✔ Execução segura

---

## 🔐 Segurança

* ❌ Nunca salvar senhas em texto plano
* ✔ Utilizar métodos seguros (DPAPI)
* ✔ Validar scripts antes da execução
* ❌ Evitar fontes externas não confiáveis

---

## 📈 Evolução

Este projeto está em constante desenvolvimento.

Planejamentos futuros:

* 📦 Deploy automatizado em rede
* 🖥️ Interface gráfica para scripts
* 📊 Telemetria e relatórios
* ☁️ Centralização em ambiente web

---

## 🤝 Contribuição

1. Crie uma branch
2. Faça suas alterações
3. Abra um Pull Request

---

## 👨‍💻 Autor

**Eduardo Ferreira**

Suporte Técnico Junior

---

## ⚠️ Uso interno

Este repositório é destinado ao uso interno da equipe PaerroTech.
O uso externo deve ser previamente autorizado.
