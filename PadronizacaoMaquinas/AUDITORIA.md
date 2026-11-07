# Auditoria técnica — Padronização de Máquinas

## 1. Resumo executivo

A auditoria identificou defeitos no início por conteúdo em memória, na retomada via `RunOnce`, no avanço prematuro de etapa, na seleção de controlador de domínio, na execução assíncrona de Windows Update e no tratamento de falhas de instaladores. As correções foram implementadas em `audit/padronizacao-reboot-domain`. Foram executadas verificações estáticas e testes unitários com mocks neste host Windows 10 com PowerShell 7.6.5 e Windows PowerShell 5.1; não foram executados ingresso real, reinicialização, alterações de registro de produção, instalações, ou testes contra Active Directory.

## 2. Problemas e evidências

| Evidência no código anterior | Conclusão | Certeza |
|---|---|---|
| `MyInvocation.MyCommand.Path` usava fallback para `Process.MainModule.FileName` | Em execução `irm | iex`, `$PSCommandPath`/caminho do comando podem estar vazios; o fallback aponta para `powershell.exe`, que era salvo e passado a `-File` como se fosse `.ps1`. | Causa confirmada pelo fluxo do código; comportamento de cada host deve ser conferido em versões suportadas. |
| Elevação sempre montava `-File "$PSCommandPath"`, sem validar caminho nem capturar recusa UAC | Execução remota em memória não tinha arquivo para reabrir; falha UAC não tinha diagnóstico próprio. | Confirmado. |
| `Set-Etapa 3` vinha logo após `Add-Computer`/`Rename-Computer`, antes do reboot e sem validação posterior | Uma operação enviada podia ser registrada como concluída mesmo que hostname/domínio não estivessem aplicados depois do reinício. | Confirmado. |
| `RunOnce` não validava arquivo, usava nome sem `!`, e a retomada não verificava hostname/domínio real | Comando inválido podia ficar registrado; Windows consome RunOnce antes de executar por padrão, portanto uma falha de retomada perde a entrada. | Confirmado; detalhes do consumo seguem semântica documentada do Windows. |
| `Start-Job` fazia Windows Update e a etapa 4 era salva imediatamente | Jobs PowerShell vivem só no processo/sessão e não sobrevivem a reinicialização; etapa podia avançar antes do término. | Confirmado. |
| Funções Office/driver e etapas GLPI/Winget capturavam exceções e seguiam para `Set-Etapa` | Falha operacional podia resultar em mensagem final de concluído sem confirmação do produto. | Confirmado. |
| Etapa 1 usava `Get-LocalUser -Name "Administrador"` | O nome depende do idioma; a conta RID-500 pode ter outro nome. | Confirmado. |
| README afirmava Office 2021, DPAPI, criação de conta, retomada totalmente automática e listava pasta `Padronizacao-Maquinas/` | Documentação divergente do código e da estrutura real (`PadronizacaoMaquinas/`); não há persistência DPAPI de credencial nem ativação automatizada. | Confirmado. |

## 3. Correções implementadas

- Exigido um `.ps1` real e existente em `$PSCommandPath`; removido o fallback para o executável do PowerShell. Elevação passa o caminho validado a `-File`, captura erro UAC e interrompe sem privilégios.
- O README agora oferece comando remoto que baixa para `%ProgramData%\PaerroTech\Padronizacao\padronizacao.ps1`, verifica arquivo e sintaxe e executa como arquivo. A origem e o conteúdo remoto continuam sendo responsabilidade da distribuição aprovada.
- Estado passa a carregar `RunId` e o caminho do log, preservando o mesmo arquivo entre sessões. As linhas possuem data/hora, identificador, nível e mensagem; diretório de log é criado com erro terminante.
- A ação crítica fica registrada como `PendingAction` antes de rename/join. `RunOnce` usa `!Padronizacao`, exige arquivo existente e é removido explicitamente ao iniciar a retomada. A etapa 3 só avança após conferir hostname e domínio real via `Win32_ComputerSystem`.
- Antes de ingressar, resolve `_ldap._tcp.dc._msdcs.<domínio>`, tenta resolver DC e exige TCP/135, TCP/389 e TCP/445. O DC selecionado é passado em `Add-Computer -Server`; exceções e resultado `-PassThru` são tratados. Máquina em outro domínio é recusada. Máquina já no domínio desejado/hostname igual não é reingressada; para renomear no mesmo domínio usa `Rename-Computer -DomainCredential`.
- O trabalho de Windows Update passa a ocorrer em primeiro plano; nenhum estado de conclusão depende de `Start-Job` volátil.
- Office passa a exigir retorno zero e detecção posterior; instalador é limpo em `finally`. `winget`, Dell Update e MSI registram códigos de retorno. Falhas opcionais ficam explícitas como avisos para conferência.
- A conta interna de administrador é localizada pelo SID terminado em RID-500, sem assumir o nome localizado. Senha do domínio não é escrita no registro nem log; referências são descartadas após o uso, sem alegar remoção de cópias internas da memória.
- README e fluxograma foram alinhados ao comportamento real.

## 4. Causas ainda hipotéticas / riscos remanescentes

- Sem um domínio de laboratório, não é possível confirmar se uma falha histórica específica foi DNS, firewall, credencial, permissão delegada, política de reutilização de conta, SPN/hostname ou objeto preexistente. O código novo diferencia discovery DNS, resolução/conectividade do DC e exceções do `Add-Computer`, mas detalhes finais dependem do evento/servidor e logs do AD.
- Test-NetConnection em 135/389/445 verifica portas TCP, não valida autenticação LDAP, RPC dinâmico, Kerberos/UDP 88, relógio, Global Catalog, política de firewall nem fluxo completo de `Add-Computer`. Ambientes podem exigir portas/regras adicionais.
- Não há resolução automática de conflito de objetos de computador existentes. A equipe de domínio deve verificar propriedade e política antes de reutilizar/remover contas.
- RunOnce executa no próximo logon de usuário e a retomada é interativa; desligar, nenhum logon ou perfil sem privilégios impede a retomada. Uma divergência de hostname/domínio reabre a etapa 3, limpa a ação pendente e registra o diagnóstico no log para uma nova decisão interativa.
- O estado e caminho do log ficam em HKLM, mas a implementação ainda não define ACLs próprias para o arquivo de log. A proteção de credenciais é por não persistência/sanitização, não por criptografia de log.
- WinGet pode retornar sucesso antes de a equipe verificar funcionalmente cada aplicativo; Lenovo System Update permanece manual. A etapa opcional registra código e deixa checagem manual quando há falha.
- O download remoto do README usa HTTPS e valida sintaxe/não vazio, sem pin de hash ou assinatura. Para controle rigoroso, prefira versão revisada/assinada e execução local.

## 5. Compatibilidade

O README e APIs indicam Windows 10/11 e Windows PowerShell 5.1. O código usa comandos nativos dessas plataformas (`Resolve-DnsName`, `Test-NetConnection`, `Get-CimInstance`, `Add-Computer`, `Rename-Computer`, `Get-LocalUser`). Análise sintática e testes unitários com mocks executados em Windows 10 build 26300 com PowerShell 7.6.5 e Windows PowerShell 5.1. Ainda requer validação integrada em cliente limpo e domínio de laboratório.

## 6. Diagnóstico de domínio

1. Confirme se `_ldap._tcp.dc._msdcs.<domínio>` tem resposta SRV e se cada `NameTarget` resolve.
2. Verifique conectividade TCP/135, TCP/389 e TCP/445 para o controlador registrado no log; confirme firewall, VPN e serviços do DC. Kerberos/UDP 88 e RPC dinâmico precisam estar autorizados para o ingresso completo, mas não são validados por `Test-NetConnection` aqui.
3. Se discovery e portas passarem, verifique horário/Kerberos, credencial digitada, permissão de adicionar/reutilizar computadores, quota/políticas do domínio e existência/ACL do objeto de computador.
4. Confirme que a máquina não pertence a outro domínio e valide o hostname (até 15 caracteres NetBIOS, letras/números/hífen).
5. Após reboot, compare `Win32_ComputerSystem.Name`, `PartOfDomain` e `Domain` com os valores no log e no estado. Não avance o registro manualmente antes de conferir o estado real.
6. Consulte logs de NetSetup/Directory Service no cliente/controlador para eventos do horário do RunId; o log do script deliberadamente não contém senha.

## 7. Plano e resultados de testes

- [x] Análise sintática via `System.Management.Automation.Language.Parser` no PowerShell 7.6.5 e Windows PowerShell 5.1.
- [x] Inspeção estática da lógica de caminho, retomada, domínio e ausência de `Start-Job`.
- [x] Testes unitários com mocks: validação de hostname; descoberta DNS e seleção de DC; portas fechadas; falha de registro SRV; validação pós-reboot para domínio confirmado e rejeição de domínio não confirmado.
- [x] Leitura XML do fluxograma e `git diff --check` (sem erros de whitespace).
- [ ] Execução do script sem admin e elevação/UAC: não realizada; alteraria fluxo interativo/registro e exige sessão de validação apropriada.
- [ ] Inicialização de arquivo e geração/execução de RunOnce com reboot real: não realizada.
- [ ] Teste integrado de estados do registro HKLM/RunOnce e reinicialização real: não executado; a validação da função de retomada foi feita com mocks em memória.
- [ ] Ingresso já configurado, DC indisponível, falha de autenticação e validação pós-reboot em AD: não realizados; ambiente sem domínio de laboratório.
- [ ] Instalação real de Windows Update, WinGet, Office, GLPI e drivers: não realizada.
- [x] PowerShell 5.1: análise sintática e testes unitários com mocks passaram; execução administrativa integrada não foi realizada.
- [x] Coerência documental: README e SVG revisados contra etapas e mensagens do script.

Não se simulou sucesso de ingresso em domínio nem se executaram operações administrativas da tarefa. A análise sintática aprovada não equivale a teste de integração.

## 8. Limitações do ambiente e revisão

O ambiente tem Windows 10, PowerShell 7.6.5 e Windows PowerShell 5.1, mas o script não foi executado de ponta a ponta em um cliente limpo e o host não está conectado a um Active Directory de laboratório. Portanto ele não pode confirmar reinício, persistência RunOnce, permissões de domínio, instaladores ou políticas corporativas. Revisar a branch `audit/padronizacao-reboot-domain`, validar primeiro em VM descartável ligada a um domínio de teste e só então aprovar implantação. `main` não foi alterada.
