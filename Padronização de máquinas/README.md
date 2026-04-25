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
irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/Padronizacao-Maquinas/padronizacao.ps1 | iex
````

> ⚠️ Executar como administrador
> ⚠️ Utilizar apenas em ambiente corporativo confiável

---

### 🔹 Execução local

```powershell
git clone https://github.com/Forevit/PaerroTech.git
cd PaerroTech/Padronizacao-Maquinas
.\padronizacao.ps1
```

---

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

---

## 🔐 Segurança

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

**Eduardo Ferreira**

Suporte Técnico Junior
