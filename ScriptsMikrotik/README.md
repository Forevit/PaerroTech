# 📡 ScriptsMikrotik

<p align="center">
  <b>Failover • Load Balance • Automação MikroTik</b><br>
  Scripts internos para padronização de redes RouterOS
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Status-Em%20Produção-green">
  <img src="https://img.shields.io/badge/Mikrotik-RouterOS-blue">
  <img src="https://img.shields.io/badge/Network-Automation-orange">
  <img src="https://img.shields.io/badge/License-Uso%20Interno-red">
</p>

---

## 📌 Visão Geral

O **ScriptsMikrotik** é um módulo do ecossistema da **PaerroTech**, desenvolvido para automatizar configurações críticas em roteadores MikroTik, garantindo padronização e confiabilidade em ambientes de rede.

Os scripts cobrem cenários essenciais de infraestrutura WAN, como:

- 🌐 Criação de rotas estáticas via DHCP
- 🔁 Failover entre links de internet
- ⚖️ Load balancing entre múltiplos links
- 🧠 Compatibilidade com RouterOS v6 e v7

---

## 🧭 Navegação

- [📂 Estrutura](#-estrutura-do-repositório)
- [🚀 Como usar](#-como-utilizar)
- [📡 Scripts disponíveis](#-scripts-disponíveis)
- [⚙️ Filosofia](#️-filosofia-do-projeto)
- [🔐 Segurança](#-segurança)
- [📈 Evolução](#-evolução)

---

## 🗂️ Estrutura do Repositório

```

📁 ScriptsMikrotik
├── 📄 SCRIPT CRIA ROTA ESTATICA DHCP - ROUTEROS V6
├── 📄 SCRIPT CRIA ROTA ESTATICA DHCP - ROUTEROS V7
├── 📄 SCRIPT FAILOVER - ROUTEROS V6
├── 📄 SCRIPT FAILOVER - ROUTEROS V7
├── 📄 SCRIPT FAILOVER E LOADBALANCE - ROUTEROS V6
├── 📄 SCRIPT FAILOVER E LOADBALANCE - ROUTEROS V7 (ATT)
└── README.md

````

---

## 🚀 Como utilizar

### 🔹 Execução no MikroTik

1. Acesse o roteador via **Winbox, WebFig ou SSH**
2. Abra o **Terminal**
3. Cole o script correspondente ao cenário desejado
4. Ajuste interfaces WAN/LAN se necessário

---

### ⚠️ Antes de executar

- ✔ Verificar versão do RouterOS (v6 ou v7)
- ✔ Validar interfaces WAN e LAN
- ✔ Confirmar link ativo de internet
- ✔ Realizar backup da configuração atual
- ⚠️ Evitar execução em produção sem teste prévio

---

## 📡 Scripts disponíveis

### 🌐 Rotas Estáticas via DHCP

- SCRIPT CRIA ROTA ESTATICA DHCP - ROUTEROS V6  
- SCRIPT CRIA ROTA ESTATICA DHCP - ROUTEROS V7  

📌 Automatiza a criação de rotas default dinâmicas baseadas em gateway DHCP.

---

### 🔁 Failover

- SCRIPT FAILOVER - ROUTEROS V6  
- SCRIPT FAILOVER - ROUTEROS V7  

📌 Monitora múltiplos links e realiza troca automática em caso de falha.

---

### ⚖️ Failover + Load Balance

- SCRIPT FAILOVER E LOADBALANCE - ROUTEROS V6  
- SCRIPT FAILOVER E LOADBALANCE - ROUTEROS V7 (ATT)

📌 Distribui tráfego entre links ativos com fallback automático em caso de queda.

---

## ⚙️ Filosofia do Projeto

Este módulo segue três princípios:

### ⚡ Automação

Reduzir configuração manual em roteadores MikroTik

### 📏 Padronização

Garantir consistência entre ambientes de rede

### 🔒 Confiabilidade

Minimizar falhas humanas em configurações críticas

---

## 🔐 Segurança

- ❌ Nunca aplicar scripts sem revisão
- ✔ Sempre validar interfaces e rotas antes da execução
- ✔ Utilizar backup antes de mudanças
- ❌ Evitar execução em produção sem validação

---

## 📈 Evolução

O módulo está em constante evolução dentro da **PaerroTech**.

Próximas melhorias previstas:

- 📊 Monitoramento automático de links WAN
- 🧠 Detecção inteligente de falhas de conexão
- ☁️ Central de gerenciamento de roteadores MikroTik
- 📡 Integração com ferramentas de monitoramento (Zabbix / Grafana)

---

## 🤝 Contribuição

1. Criar branch
2. Implementar melhoria ou novo script
3. Testar em ambiente controlado
4. Abrir Pull Request

---

## 👨‍💻 Autor

**Eduardo Ferreira**  
Suporte Técnico Junior

---

## ⚠️ Uso interno

Este repositório é destinado ao uso interno da equipe **PaerroTech**.  
O uso externo deve ser previamente autorizado.
