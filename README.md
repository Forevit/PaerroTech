# 🧪 PaerroTech - Ambiente de Teste

<p align="center">
  <b>Automação • Padronização • Infraestrutura</b><br>
  Ambiente de validação de scripts antes de produção
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Status-Em%20Teste-yellow">
  <img src="https://img.shields.io/badge/PowerShell-Automation-blue">
  <img src="https://img.shields.io/badge/Windows-Suporte-0078D6">
  <img src="https://img.shields.io/badge/Branch-ambienteTeste-lightgrey">
</p>

---

## 📌 Visão Geral

Este branch **`ambienteTeste`** faz parte do repositório **PaerroTech** e é destinado exclusivamente para testes e validação de scripts de automação antes da publicação em produção.

Aqui são realizados testes de:

- 🖥️ Scripts de padronização de máquinas
- 🔧 Rotinas de manutenção preventiva
- ⚙️ Automação de tarefas de suporte
- 🌐 Ajustes e validações de rede
- 📦 Scripts experimentais

---

## 🧭 Navegação

- [📂 Estrutura](#-estrutura-do-repositório)
- [🚀 Como usar](#-como-utilizar)
- [⚙️ Filosofia](#-filosofia-do-ambiente)
- [🧠 Boas práticas](#-boas-práticas)
- [🔐 Segurança](#-segurança)
- [📈 Evolução](#-evolução)

---

## 🗂️ Estrutura do Repositório

```

📁 PaerroTech
├── 📁 Padronizacao-Maquinas/
├── 📁 Preventivas/
│   └── 📁 ambienteTeste/   → Scripts em validação
├── 📁 ScriptsMikrotik/
├── 📁 Scripts/
└── README.md

````

---

## 🚀 Como utilizar

### 🔹 Execução via Git

```bash
git clone https://github.com/Forevit/PaerroTech.git
cd PaerroTech
git checkout ambienteTeste
````

---

### 🔹 Execução de scripts PowerShell

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force

.\nome-do-script.ps1
```

> ⚠️ Sempre executar como Administrador

---

## ⚙️ Filosofia do ambiente

Este branch segue três princípios:

### ⚡ Teste seguro

Validação de scripts antes de produção

### 📏 Controle de mudanças

Evitar impactos em máquinas reais

### 🔒 Isolamento

Ambiente separado do fluxo principal

---

## 🧠 Boas práticas

* ✔ Testar antes de promover para produção
* ✔ Usar logs durante execução
* ✔ Documentar alterações feitas
* ✔ Manter scripts organizados por função
* ❌ Evitar execução em máquinas críticas

---

## 📝 Padrão de logs

Os testes devem registrar logs em:

```
C:\Users\Public\Documents\Logs\
```

Estrutura recomendada:

```
Logs/
 ├── Preventiva/
 ├── Testes/
 └── Debug/
```

---

## 🛠️ Padrão de desenvolvimento

Scripts neste ambiente devem conter:

* ✔ Nome claro e descritivo
* ✔ Comentários no código
* ✔ Tratamento de erro (`try/catch`)
* ✔ Registro de logs
* ✔ Execução segura e validada

---

## 🔐 Segurança

* ❌ Não usar credenciais hardcoded
* ✔ Validar antes de executar em produção
* ✔ Utilizar apenas fontes internas confiáveis
* ❌ Evitar scripts externos sem revisão

---

## 📈 Evolução

Este ambiente é temporário e serve como etapa de validação.

Futuras melhorias planejadas:

* 📦 Pipeline de CI/CD para scripts PowerShell
* 🧪 Testes automatizados de scripts
* 📊 Relatórios de execução
* 🚀 Promoção automática para produção

---

## 🤝 Contribuição

1. Criar branch baseada em `ambienteTeste`
2. Realizar testes locais
3. Validar execução
4. Abrir Pull Request para `main`

---

## 👨‍💻 Autor

**Eduardo Ferreira**

Equipe de Suporte Técnico - PaerroTech

---

## ⚠️ Uso interno

Este ambiente é exclusivamente interno e destinado apenas para testes controlados de automação.
