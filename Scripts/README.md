# 🔧 PaerroTech

Scripts e automações para padronização de máquinas corporativas.

---

## 📌 Sobre o projeto

O **PaerroTech** é um projeto voltado para automação de processos de suporte técnico, com foco em **padronização de ambientes Windows corporativos**.

O script principal executa uma sequência completa de configuração da máquina, incluindo ingresso em domínio, instalação de softwares, drivers, Office e integração com ferramentas de inventário.

---

## ⚙️ Funcionalidades

- Ingresso automático no domínio
- Definição de hostname
- Criação e configuração do administrador local
- Instalação de softwares essenciais via Winget
- Instalação do GLPI Agent
- Instalação do Microsoft Office (ODT)
- Instalação de drivers por fabricante (Dell, Lenovo, HP)
- Windows Update em background
- Sistema de logs detalhado
- Execução por etapas com retomada automática após reboot

---

## 🚀 Execução

### 🔹 Execução remota (recomendado)

```powershell
irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/padronizacao.ps1 | iex
