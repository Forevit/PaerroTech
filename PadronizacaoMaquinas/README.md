# Padronização de Máquinas

Automação interativa para preparar estações Windows da PaerroTech. O script mantém as nove etapas e exige uma sessão interativa de técnico. Execute em Windows 10/11 com Windows PowerShell 5.1, conta com privilégios administrativos e acesso à rede corporativa. A elevação por UAC é tentada automaticamente quando o arquivo é iniciado sem esses privilégios.

## Execução recomendada

Baixe/clone o repositório e inicie o arquivo como arquivo PowerShell:

```powershell
git clone https://github.com/Forevit/PaerroTech.git
Set-Location .\PaerroTech\PadronizacaoMaquinas
.\padronizacao.ps1
```

Para execução remota, use uma sessão PowerShell elevada. O comando abaixo salva o arquivo em local persistente no ProgramData, verifica se o download não está vazio e se o PowerShell consegue analisá-lo, e então executa o arquivo. Esse caminho permanece disponível ao `RunOnce` depois de reiniciar:

```powershell
$installDir = Join-Path $env:ProgramData 'PaerroTech\Padronizacao'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
$scriptPath = Join-Path $installDir 'padronizacao.ps1'
$downloadPath = "$scriptPath.download"
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Forevit/PaerroTech/main/PadronizacaoMaquinas/padronizacao.ps1' -OutFile $downloadPath -UseBasicParsing -ErrorAction Stop
if (-not (Test-Path -LiteralPath $downloadPath -PathType Leaf) -or (Get-Item $downloadPath).Length -eq 0) { throw 'Download vazio ou inexistente.' }
$tokens = $null; $parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($downloadPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) { Remove-Item $downloadPath -Force; throw "Script baixado contém erros de sintaxe: $($parseErrors[0].Message)" }
Move-Item -LiteralPath $downloadPath -Destination $scriptPath -Force
$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$process = Start-Process -FilePath $powershellExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Wait -PassThru -ErrorAction Stop
if ($process.ExitCode -ne 0) { throw "A execução terminou com código $($process.ExitCode). Consulte o log em C:\Users\Public\Documents\Logs\Padronizacao\." }
```

O formato `irm URL | iex` diretamente com o conteúdo de `padronizacao.ps1` não é suportado. O script principal precisa de `$PSCommandPath` para a elevação e retomada. O bloco acima preserva a experiência remota, mas salva e executa o `.ps1` como arquivo. Baixe apenas de uma origem aprovada pela equipe.

## Etapas

1. Verifica a conta interna de administrador local pelo SID RID-500. Se a conta estiver desabilitada, o script habilita a conta RID-500, como fazia anteriormente com o nome localizado; a troca de senha é opcional, solicitada pelo técnico e lida como SecureString.
2. Verifica conectividade externa, edição Windows (Pro/Enterprise/Education) e presença do Office.
3. Permite trocar hostname e, opcionalmente, ingressar no domínio. O script resolve registros DNS SRV, verifica resolução do DC e conectividade TCP/135, TCP/389 e TCP/445 antes de chamar `Add-Computer`; Kerberos/UDP e RPC dinâmico dependem das regras de rede do ambiente.
4. Opcionalmente instala atualizações com `PSWindowsUpdate` em primeiro plano. O processo não fica em job volátil.
5. Tenta instalar Chrome, Firefox, Java 8, AnyDesk, Acrobat Reader e WinRAR via WinGet; códigos de saída diferentes de zero ficam como avisos para conferência.
6. Opcionalmente instala GLPI Agent 1.17 x64.
7. Instala Microsoft 365 Apps x64 em português do Brasil quando não detectado e verifica novamente a presença do Office.
8. Opcionalmente instala/usa a ferramenta do fabricante Dell ou Lenovo. A ferramenta Lenovo é instalada; a aplicação das atualizações Lenovo permanece manual.
9. Orienta a ativação pelos canais oficiais. O script não ativa licenças automaticamente.

Falhas de conectividade, edição Windows incompatível, ausência de WinGet e falha na etapa de hostname/domínio interrompem a execução. Instalações opcionais e alguns instaladores de terceiros registram o código/erro e permitem a continuação, deixando indicação de verificação manual no log. Não interprete uma mensagem de instalação iniciada como prova de instalação concluída.

## Retomada e logs

Quando uma mudança de hostname/domínio precisa reiniciar, o script grava a ação pendente e um caminho de arquivo validado, configura `HKLM\...\RunOnce` como `!Padronizacao` e reinicia. O prefixo `!` faz o Windows remover o valor após o comando ser iniciado; o script também o remove explicitamente no início da retomada para não criar um ciclo de tentativas após erro. A retomada ocorre no próximo logon de usuário com privilégios suficientes e continua interativa. Não é uma tarefa `SYSTEM`.

A ação só avança para a etapa 3 depois que o hostname e, no ingresso, o domínio são conferidos com `Win32_ComputerSystem` após o reboot. Se hostname ou domínio não confirmar, a etapa 3 é reaberta, o log registra o estado esperado e encontrado, e o técnico pode corrigir a causa e decidir novamente no fluxo interativo.

O estado fica em `HKLM\SOFTWARE\Padronizacao`; senha não é armazenada ali. O mesmo caminho de log e identificador de execução são reutilizados após reinicialização. Logs ficam em `C:\Users\Public\Documents\Logs\Padronizacao\`.

## Diagnóstico de ingresso no domínio

Consulte o log mais recente e diferencie as verificações: registros `_ldap._tcp.dc._msdcs.<domínio>` ausentes apontam para resolução/discovery DNS; hostname do controlador sem resolução aponta para DNS do DC; falha em TCP/135, TCP/389 ou TCP/445 aponta para conectividade/firewall/serviço; registros e portas acessíveis com `Add-Computer` falhando indicam que também devem ser verificados credenciais, permissões de ingresso, política de reutilização de conta, nome/conta de computador existente e estado de confiança/domínio atual. A mensagem informa tipo e contexto da exceção sem registrar a senha digitada.

Uma máquina já no domínio desejado e com o hostname solicitado é mantida sem reingresso. Máquina em outro domínio é recusada para evitar uma troca implícita; use o processo aprovado para desassociá-la antes. Nome DNS/conta já existente pode depender de permissões e políticas do Active Directory e deve ser investigado com o administrador do domínio.

## Arquivos

- `padronizacao.ps1`: script interativo.
- `padronizacao_script_flowchart.svg`: fluxo resumido.
- `AUDITORIA.md`: evidências, mudanças, testes e limitações desta auditoria.
- `Paerro-Setup.exe` e `Paerro-Setup.ico`: artefatos existentes do projeto; não são necessários para executar diretamente o script.
