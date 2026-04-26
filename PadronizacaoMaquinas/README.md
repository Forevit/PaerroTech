<<<<<<< HEAD
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
├── 📁 ScriptsMikrotik          → Scripts de FailOver + LoadBalance
├── 📁 Scripts/                 → Utilitários diversos
└── README.md

````

---

## 🚀 Como utilizar

### 🔹 Execução remota (rápida)

```powershell
irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/<folder>/<script>.ps1 | iex
````

> ⚠️ Executar como administrador
> ⚠️ Utilize apenas scripts confiáveis
=======
# 🖥️ Padronização de Máquinas

Scripts responsáveis pela preparação completa de estações de trabalho em ambiente corporativo.

---

## 📌 Descrição

Esta pasta contém o script de **padronização automática de máquinas Windows**, utilizado para agilizar o processo de entrega de equipamentos e garantir conformidade com o ambiente da empresa.

O script executa diversas configurações essenciais de forma automatizada, reduzindo o tempo de setup e evitando erros manuais.

---

## ⚙️ Funcionalidades

- Definição de hostname
- Ingresso automático no domínio
- Criação e configuração do administrador local
- Instalação de softwares essenciais via Winget:
  - Google Chrome
  - Mozilla Firefox
  - Java
  - AnyDesk
  - Adobe Reader
  - WinRAR
- Instalação do GLPI Agent
- Instalação do Microsoft Office 2021
- Instalação de drivers por fabricante:
  - Dell
  - Lenovo
  - HP
- Execução de Windows Update em segundo plano
- Sistema de logs detalhado
- Execução por etapas com retomada automática após reboot

---

## 🚀 Como executar

### 🔹 Execução remota

```powershell
irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/PadronizacaoMaquinas/padronizacao.ps1 | iex
````

> ⚠️ Executar como administrador
> ⚠️ Utilizar apenas em ambiente corporativo confiável
>>>>>>> dc51c9c (add validacao versao Windows)

---

### 🔹 Execução local

<<<<<<< HEAD
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
=======
```powershell
git clone https://github.com/Forevit/PaerroTech.git
cd PaerroTech/PadronizacaoMaquinas
.\padronizacao.ps1
>>>>>>> dc51c9c (add validacao versao Windows)
```

---

<<<<<<< HEAD
## 🛠️ Padrão de desenvolvimento

Scripts devem seguir:

* ✔ Nome descritivo
* ✔ Comentários explicativos
* ✔ Tratamento de erro (`try/catch`)
* ✔ Sistema de logs
* ✔ Execução segura
=======
## 🔄 Fluxo de execução

O script é dividido em etapas:

1. Hostname + ingresso no domínio *(requer reboot)*
2. Configuração do administrador local
3. Instalação de aplicativos
4. Instalação do GLPI Agent
5. Instalação do Office + drivers
6. Ativação do sistema

✔️ O script continua automaticamente após reinicialização
✔️ O estado é salvo no registro do Windows

---

## 📝 Logs

Os logs são armazenados em:

```
C:\Users\Public\Documents\Logs\Padronizacao\
```

Contêm:

* Status de execução
* Erros detalhados
* Saída de comandos
>>>>>>> dc51c9c (add validacao versao Windows)

---

## 🔐 Segurança

<<<<<<< HEAD
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
=======
* Credenciais armazenadas temporariamente via **DPAPI**
* Remoção automática após uso
* Nenhuma senha salva em texto plano
* Execução elevada automática (UAC)

---

## ⚠️ Atenção

* O script realiza alterações críticas no sistema
* Pode reiniciar a máquina automaticamente
* Deve ser utilizado apenas por técnicos autorizados
* Requer acesso ao domínio corporativo

---

## 🛠️ Requisitos

* Windows 10/11
* PowerShell 5.1 ou superior
* Acesso à internet
* Permissão de administrador
* Credenciais válidas de domínio

---

## 📄 Arquivos desta pasta

```
padronizacao.ps1
Paerro-Setup.exe (opcional)
```

---

## 👨‍💻 Responsável
>>>>>>> dc51c9c (add validacao versao Windows)

**Eduardo Ferreira**

Suporte Técnico Junior
<<<<<<< HEAD

---

## ⚠️ Uso interno

Este repositório é destinado ao uso interno da equipe PaerroTech.
O uso externo deve ser previamente autorizado.
=======
>>>>>>> dc51c9c (add validacao versao Windows)
