# 🛠️ README — Preventivas

````markdown
# 🛠️ Preventivas

<p align="center">
  <b>Manutenção • Estabilidade • Performance</b><br>
  Rotinas automatizadas para saúde do ambiente corporativo
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Status-Ativo-green">
  <img src="https://img.shields.io/badge/Tipo-Manutenção-blue">
  <img src="https://img.shields.io/badge/Execução-Periódica-orange">
  <img src="https://img.shields.io/badge/PowerShell-Automation-0078D6">
</p>

---

## 📌 Visão Geral

A pasta **Preventivas** contém scripts responsáveis por manter as máquinas corporativas atualizadas, limpas e operando com máximo desempenho.

Essas rotinas são fundamentais para:

- 🔧 Reduzir falhas e incidentes
- ⚡ Melhorar desempenho das máquinas
- 🔒 Garantir segurança e atualizações
- 📉 Diminuir volume de chamados

---

## ⚙️ O que os scripts fazem

- 🔄 Windows Update automático  
- 🧩 Atualização de drivers  
- 📦 Atualização de softwares via Winget  
- 🧹 Limpeza de disco e arquivos temporários  
- 👤 Remoção de perfis antigos  
- 🔍 Verificação de softwares essenciais  
- ☕ Atualização do Java  
- ⚙️ Ajustes básicos de sistema  

---

## 🚀 Como utilizar

### 🔹 Execução remota

```powershell
irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/Preventivas/<script>.ps1 | iex
````

---

### 🔹 Execução local

```powershell
cd Preventivas
.\preventiva.ps1
```

## 📝 Logs

Os logs seguem o padrão:

```
C:\Users\Public\Documents\Logs\Preventiva\
```

📌 Incluem:

* Status da execução
* Ações realizadas
* Possíveis erros

---

## ⚠️ Boas práticas

* ✔ Executar como administrador
* ✔ Rodar fora do horário crítico
* ✔ Validar scripts antes de produção
* ❌ Evitar execução manual desnecessária

---

## 🔐 Segurança

* Scripts não armazenam credenciais
* Execução controlada e segura
* Sem uso de dados sensíveis

---

## 📂 Estrutura esperada

```
Preventivas/
 ├── preventiva.ps1
 └── README.md
```

---

## 👨‍💻 Responsável

**Eduardo Ferreira**

Suporte Técnico Júnior

````
