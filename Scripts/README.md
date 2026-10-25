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

## 📋 Scripts disponíveis

| Script | Descrição |
|---|---|
| `rustdesk.ps1` | Instala/atualiza RustDesk estável x64, verifica digest SHA-256 publicado no release oficial, configura o servidor PaerroTech pela CLI oficial, solicita senha oculta e tenta desinstalar AnyDesk sem apagar dados dos perfis. |

## RustDesk — execução e operação

Abra o **Windows PowerShell 5.1 como Administrador** e execute:

```powershell
irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/Scripts/rustdesk.ps1 | iex
```

O script verifica a elevação antes de iniciar downloads ou alterações. Se não estiver elevado, encerra com orientação para abrir uma sessão administrativa; ele não tenta elevar o conteúdo de `irm | iex`.

A execução apresenta oito etapas numeradas: permissões; ambiente e instalação existente; release e integridade; instalação; configuração local do servidor; comando de senha; validação local; e confirmação manual de conexão real. O resumo separa essas etapas da decisão sobre o AnyDesk. O log permanece em `C:\Users\Public\Documents\Logs\Outros\rustdesk_script.log`.

Se uma etapa essencial falhar, o script interrompe as etapas dependentes e preserva o AnyDesk para evitar perda de acesso remoto. Falhas essenciais lançam erro terminante (também sinalizado em `$LASTEXITCODE`); a conexão remota não confirmada e a impossibilidade segura de remover o AnyDesk são avisos, não falhas da configuração local. Ao executar com `irm | iex`, o script não fecha a sessão do PowerShell.

Na execução, o técnico digita e confirma a senha permanente em solicitações ocultas. A política deste script exige pelo menos oito caracteres. A senha não vai para o log ou para arquivo, mas é passada como argumento ao processo do RustDesk durante a aplicação; outros processos locais com permissões suficientes podem observar argumentos de processos. O código zero de `--password` confirma apenas o retorno da CLI, não a persistência da senha. Na etapa 8, o técnico precisa testar uma conexão real a partir de outro dispositivo e digitar `SIM`; pressionar Enter, responder de outra forma, ocorrer erro ou não haver entrada interativa preserva o AnyDesk. A leitura local das opções e o serviço `Running` não substituem esse teste.

O instalador é obtido do release estável mais recente do repositório oficial RustDesk. A sintaxe de `--config` foi conferida no código e nos testes oficiais da tag 1.5.0. O script interrompe a instalação/configuração se o release ou a instalação existente for posterior a 1.5.0, até que essa versão seja analisada. O script rejeita pré-lançamentos, verifica tamanho e compara SHA-256 com o digest publicado pela API do release. Se o digest estiver ausente ou não conferir, a instalação é interrompida. Uma versão já instalada igual ou superior ao release selecionado é mantida, sem downgrade.

Para detectar instalações existentes, o script consulta registros de desinstalação em HKLM 64/32-bit e HKCU da sessão atual, valida o publicador, o caminho do executável e a versão registrada contra a versão do arquivo; também verifica caminhos de instalação conhecidos. Uma assinatura Authenticode válida precisa identificar RustDesk/Purslane. Sem registro de desinstalação, o fallback aceita `InstallLocation` de `HKLM\SOFTWARE\RustDesk\InstallState\RustDesk` ou o caminho padrão `%ProgramFiles%\RustDesk\rustdesk.exe`, mas exige metadados RustDesk, versão legível e serviço automático `RustDesk` apontando para o mesmo binário com `--service`. Se o executável não tiver assinatura, antes de iniciar qualquer CLI o script compara seu SHA-256 com o digest do asset oficial da mesma versão; ausência de digest ou divergência interrompe o fluxo. O código upstream mostra que a instalação copia o executável de origem sem transformá-lo. Cópias portáteis e arquivos residuais sem essas evidências não são iniciados. Assinaturas inválidas/conflitantes, caminhos não padrão ou serviço ausente/incompatível interrompem o fluxo com as informações observadas e os requisitos que faltam. Uma instalação antiga fora do caminho padrão não é atualizada automaticamente porque o parâmetro de destino do instalador não foi validado.

O formato CSV sem nomes de campo não é usado. Na versão estável 1.5.0, `core_main.rs` encaminha o argumento de `--config` a `get_custom_server_from_string`; `custom_server.rs` reconhece os campos separados por vírgulas `host=`, `key=`, `api=` e `relay=`, com `host=` necessário para gravar opções. Os testes dessa tag cobrem `host=`, `key=` e `relay=`. O script usa `host=monitor.paerrotecnologia.com.br:21116,key=...,relay=monitor.paerrotecnologia.com.br:21117` e compara as opções por `--option`: a CLI recebe o nome da opção como argumento separado, e os nomes de leitura são `custom-rendezvous-server`, `key` e `relay-server`. Em 1.5.0, uma opção desconhecida produz saída vazia, e uma consulta sem instalação/privilégios pode imprimir uma mensagem sem sinalizar erro no código de saída. Por isso, o script captura saída e código diretamente do processo e exige que a saída seja exatamente o valor esperado; o log registra código de saída, tamanhos e classificação da saída, nunca seu conteúdo (que pode conter a chave). A gramática confirmada está no [código upstream da tag 1.5.0](https://github.com/rustdesk/rustdesk/blob/1.5.0/src/custom_server.rs), no [tratamento CLI de `--option`](https://github.com/rustdesk/rustdesk/blob/1.5.0/src/core_main.rs) e no [fallback do caminho de instalação Windows](https://github.com/rustdesk/rustdesk/blob/1.5.0/src/platform/windows.rs).

O serviço é instalado, se necessário, iniciado e confirmado como `Running` antes da configuração. Após executar `--config`, o script consulta `--option` para verificar host, chave e relay efetivamente lidos pelo cliente. Isso não comprova, por si só, o tráfego ao servidor nem a persistência após reinicialização. Na VM, confira em **Settings → Network** o ID Server `monitor.paerrotecnologia.com.br:21116`, o Relay `monitor.paerrotecnologia.com.br:21117` e a chave pública; depois estabeleça uma conexão de teste e confirme que o dispositivo aparece no servidor PaerroTech. Reinicie serviço e computador, repita a conferência e a conexão. A persistência não é declarada pelo script como comprovada sem esse teste.

O script usa a CLI oficial em vez de escrever TOML diretamente. O código do RustDesk 1.5.0 encaminha as opções por IPC à configuração ativa e a grava através de `Config::set_options`; a localização do arquivo é derivada do contexto de configuração do processo. A implementação consultada não foi suficiente para provar que escrever `RustDesk2.toml` em `LocalService` seria o método correto para todos os contextos do serviço Windows, então o script não edita TOML manualmente.

### Conectividade

É necessário acesso HTTPS ao `api.github.com` e `github.com` para consultar o release e obter o instalador. O equipamento também precisa alcançar `monitor.paerrotecnologia.com.br` nas portas configuradas para rendezvous (`21116`) e relay (`21117`), conforme firewall, DNS e regras de rede locais.

### AnyDesk

O AnyDesk só é considerado para remoção depois que a instalação foi verificada, host/chave/relay foram conferidos localmente, o comando da senha retornou zero e o técnico confirmou explicitamente uma conexão real digitando `SIM`. Essa confirmação é uma declaração manual do técnico; o script não consegue observar nem provar a sessão remota. Em contexto não interativo o AnyDesk permanece instalado. Se a conexão não funcionar, a confirmação não ocorrer ou qualquer etapa essencial falhar, o AnyDesk é preservado. O resumo não afirma que acesso remoto está funcionando sem a confirmação manual.

Para desinstalar, o script só executa `QuietUninstallString` quando ele é um comando direto, inclui seus próprios argumentos, aponta para um executável AnyDesk existente e tem assinatura válida do fornecedor. Os argumentos registrados são usados sem alterações. Não acrescenta opções ao comando. Se houver apenas `UninstallString` normal, um comando intermediário (como MSI ou outro launcher), argumentos ausentes ou assinatura não validável, o comando não é executado e o técnico recebe orientação para remover manualmente pelas Configurações do Windows. Falhas na remoção são avisos separados e não desfazem uma instalação funcional do RustDesk. O script não apaga dados de usuários, encerra processos à força nem remove serviços à força.

Após tentar a remoção, as verificações se limitam a entradas de desinstalação em HKLM 64/32-bit e HKCU da sessão atual, além de processos e serviços identificados como AnyDesk. Quando não encontra evidências, o resumo declara esse escopo: registros HKCU de outros perfis e cópias portáteis inativas não são pesquisados, portanto a mensagem não afirma ausência global do AnyDesk.

### Logs e testes operacionais

O log é gravado em:

```text
C:\Users\Public\Documents\Logs\Outros\rustdesk_script.log
```

O resumo final separa instalação/versão, servidor e opções locais, estado do serviço, retorno da CLI de senha sem confirmação de persistência, conexão remota confirmada ou pendente e resultado do AnyDesk. Senhas e argumentos que as contenham não são registrados. Teste primeiro em uma máquina virtual descartável, cobrindo instalação limpa, atualização, serviço, configuração, senha, confirmação manual e cenários de preservação do AnyDesk antes de usar em equipamento de cliente.

## 🚀 Uso dos demais scripts

Execução remota:

```powershell
irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/Scripts/<script>.ps1 | iex
```

Execução local:

```powershell
cd Scripts
.\nome-do-script.ps1
```

## ⚠️ Boas práticas

* Executar como **Administrador** quando necessário.
* Validar os scripts antes da execução, principalmente os que alteram configuração de acesso remoto.
* Testar em máquina virtual antes de utilizar em produção.
* Confirmar conectividade e dados operacionais antes de distribuir.

## 👨‍💻 Responsável

**Eduardo Ferreira**

Suporte Técnico Júnior
