# ============================================================
#  SCRIPT DE PADRONIZAÇÃO DE MÁQUINA CORPORATIVA
#  by Eduardo Ferreira | Paerro Tecnologia
# ============================================================

# ============================================================
# AUTO-ELEVAÇÃO
# ============================================================
$scriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($scriptPath) -or -not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    Write-Error "Este script precisa ser executado como arquivo .ps1. Baixe-o para um arquivo e execute com PowerShell -File; execução por irm | iex não permite retomada segura."
    exit 2
}
$scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $hostExe)) { throw 'Windows PowerShell 5.1 não foi encontrado.' }
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        $elevated = Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList $arguments -PassThru -ErrorAction Stop
        if (-not $elevated) { throw 'O Windows não iniciou o processo elevado.' }
    } catch {
        Write-Error "Não foi possível elevar o script. Confirme a aprovação do UAC e tente novamente. Detalhe: $($_.Exception.GetType().Name)"
        exit 3
    }
    exit 0
}

# ============================================================
# SISTEMA DE LOGS
# ============================================================
$logRaiz = "C:\Users\Public\Documents\Logs"
$logDir  = "$logRaiz\Padronizacao"
$regPath = "HKLM:\SOFTWARE\Padronizacao"
$script:hasIssues = $false
New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null }
$runId = (Get-ItemProperty -Path $regPath -Name RunId -ErrorAction SilentlyContinue).RunId
$logFile = (Get-ItemProperty -Path $regPath -Name LogFile -ErrorAction SilentlyContinue).LogFile
if ([string]::IsNullOrWhiteSpace($runId) -or [string]::IsNullOrWhiteSpace($logFile) -or -not (Test-Path -LiteralPath (Split-Path -Parent $logFile))) {
    $runId = [guid]::NewGuid().ToString()
    $logFile = Join-Path $logDir ("padronizacao_{0}_{1}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'), $runId.Substring(0,8))
    Set-ItemProperty -Path $regPath -Name RunId -Value $runId -ErrorAction Stop
    Set-ItemProperty -Path $regPath -Name LogFile -Value $logFile -ErrorAction Stop
}

function Write-Log {
    param(
        [string]$Mensagem,
        [ValidateSet("INFO","SUCCESS","ERROR","WARN","STEP","OK","ERRO","AVISO","ETAPA")]
        [string]$Tipo = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $safeMessage = [string]$Mensagem
    $safeMessage = $safeMessage -replace '(?i)((?:password|senha|credential|credencial)(?:\s+\w+)?\s*[:=]\s*)(?:"[^"]*"|''[^'']*''|[^\s;]+)', '$1[REDACTED]'
    if ($Tipo -in @('ERROR','ERRO','WARN','AVISO')) { $script:hasIssues = $true }
    $linha = "[$timestamp] [RunId=$runId] [$Tipo] $safeMessage"

    $linha | Out-File -FilePath $logFile -Append -Encoding UTF8 -ErrorAction Stop

    switch ($Tipo) {
        { $_ -in "ETAPA", "STEP" } { Write-Host "`n$linha" -ForegroundColor Cyan }
        { $_ -in "OK", "SUCCESS" } { Write-Host $linha -ForegroundColor Green }
        { $_ -in "ERRO", "ERROR" } { Write-Host $linha -ForegroundColor Red }
        { $_ -in "AVISO", "WARN" } { Write-Host $linha -ForegroundColor Yellow }
        default { Write-Host $linha -ForegroundColor White }
    }
}

function Write-LogErro {
    param([string]$Mensagem, [System.Management.Automation.ErrorRecord]$Excecao)
    Write-Log $Mensagem "ERROR"
    if ($Excecao) {
        Write-Log "Exceção: $($Excecao.Exception.GetType().FullName); detalhe: $($Excecao.Exception.Message)" "ERROR"
        Write-Log "Linha: $($Excecao.InvocationInfo.ScriptLineNumber)" "ERROR"
    }
}

# ============================================================
# CONTROLE DE ETAPAS / RETOMADA APÓS REBOOT
# ============================================================
$totalEtapas = 9
$regPath = "HKLM:\SOFTWARE\Padronizacao"

function Get-Etapa {
    if (Test-Path $regPath) {
        return (Get-ItemProperty -Path $regPath -Name "Etapa" -ErrorAction SilentlyContinue).Etapa
    }
    return 0
}

function Set-Etapa {
    param([int]$Numero)
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name "Etapa" -Value $Numero -ErrorAction Stop
}

function Get-DadoSalvo {
    param([string]$Chave)
    if (Test-Path $regPath) {
        return (Get-ItemProperty -Path $regPath -Name $Chave -ErrorAction SilentlyContinue).$Chave
    }
    return $null
}

function Set-DadoSalvo {
    param([string]$Chave, [string]$Valor)
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name $Chave -Value $Valor -ErrorAction Stop
}

function Set-RunOnce {
    if ([string]::IsNullOrWhiteSpace($scriptPath) -or -not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Arquivo de retomada inválido: o script não existe em '$scriptPath'."
    }
    Set-DadoSalvo "ScriptPath" $scriptPath
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershellExe)) { throw 'Windows PowerShell 5.1 não foi encontrado para a retomada.' }
    $cmd = "`"$powershellExe`" -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
                     -Name "!Padronizacao" `
                     -Value $cmd -ErrorAction Stop

    Write-Log "RunOnce configurado para '$scriptPath'; o prefixo ! mantém o valor até a inicialização do processo. A execução remove o valor após validar a retomada." "INFO"
}

function Remove-Estado {
    Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
                        -Name "Padronizacao" `
                        -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
                        -Name "!Padronizacao" `
                        -ErrorAction SilentlyContinue
}

function Update-Progresso {
    param([int]$Numero, [string]$Status)
    $percentual = [math]::Round(($Numero / $totalEtapas) * 100)
    Write-Progress `
        -Activity "Padronização Corporativa — by Eduardo Ferreira" `
        -Status "Etapa $Numero/$totalEtapas — $Status" `
        -PercentComplete $percentual
}

function Complete-PendingAction {
    $pending = Get-DadoSalvo 'PendingAction'
    if ([string]::IsNullOrWhiteSpace($pending)) { return }
    $expectedName = Get-DadoSalvo 'Hostname'
    $expectedDomain = Get-DadoSalvo 'Dominio'
    $system = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $mismatch = $null
    if ($system.Name -ine $expectedName) { $mismatch = "hostname esperado '$expectedName', encontrado '$($system.Name)'" }
    if (-not $mismatch -and $pending -in @('JoinDomain','RenameDomainComputer') -and (-not $system.PartOfDomain -or $system.Domain -ine $expectedDomain)) {
        $mismatch = "domínio esperado '$expectedDomain', estado atual PartOfDomain=$($system.PartOfDomain), Domain='$($system.Domain)'"
    }
    if ($mismatch) {
        Write-Log "Retomada não confirmada ($mismatch). Etapa 3 reaberta para diagnóstico e nova decisão interativa; nenhum sucesso foi registrado." 'WARN'
        Set-Etapa 2
        Remove-ItemProperty -Path $regPath -Name PendingAction -ErrorAction SilentlyContinue
        return
    }
    Set-Etapa 3
    Remove-ItemProperty -Path $regPath -Name PendingAction -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name '!Padronizacao' -ErrorAction SilentlyContinue
    Write-Log "Ação '$pending' validada após reinicialização; etapa 3 confirmada." 'SUCCESS'
}

function Confirmar-Etapa {
    param([string]$NomeEtapa)
    $resposta = Read-Host "Deseja executar a etapa '$NomeEtapa'? (S/N)"
    return ($resposta -match '^[sS]')
}

# ============================================================
# FUNÇÕES DE PRÉ-VERIFICAÇÃO
# ============================================================
function Test-Internet {
    try {
        $dnsOk = Test-NetConnection -ComputerName "8.8.8.8" -Port 53 -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($dnsOk) { return $true }

        $webOk = Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
        return $webOk
    } catch {
        return $false
    }
}

function Get-DomainController {
    param([Parameter(Mandatory=$true)][string]$Domain)
    try {
        $records = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$Domain" -Type SRV -DnsOnly -ErrorAction Stop
        $targets = @($records | Where-Object { $_.NameTarget } | Sort-Object Priority | Select-Object -ExpandProperty NameTarget -Unique)
        if (-not $targets) { throw 'Nenhum registro SRV LDAP foi retornado.' }
    } catch {
        throw "Falha ao localizar controladores do domínio '$Domain' por DNS SRV. Tipo=$($_.Exception.GetType().Name); detalhe=$($_.Exception.Message)"
    }
    foreach ($target in $targets) {
        $dc = $target.TrimEnd('.')
        try {
            $addresses = [System.Net.Dns]::GetHostAddresses($dc)
            if (-not $addresses) { continue }
            $ports = @(135, 389, 445)
            $checks = @{}
            foreach ($port in $ports) { $checks[$port] = Test-NetConnection -ComputerName $dc -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue }
            if (($checks.Values | Where-Object { -not $_ }).Count -eq 0) { return $dc }
            $portSummary = ($checks.GetEnumerator() | Sort-Object Name | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ', '
            Write-Log "Controlador '$dc' resolveu para $($addresses -join ', '), portas TCP testadas: $portSummary." 'WARN'
        } catch {
            Write-Log "Falha de resolução/conectividade para controlador '$dc': $($_.Exception.Message)" 'WARN'
        }
    }
    throw "Os registros SRV de '$Domain' foram encontrados, mas nenhum controlador respondeu nas portas TCP/135, TCP/389 e TCP/445."
}

function Get-WindowsEdicao {
    return (Get-CimInstance Win32_OperatingSystem).Caption
}

function Test-WindowsPro {
    $edicao = Get-WindowsEdicao
    return ($edicao -match "Pro|Professional|Enterprise|Education")
}

function Test-OfficeInstalado {
    $officePaths = @(
        "$env:ProgramFiles\Microsoft Office\root\Office16\WINWORD.EXE",
        "$env:ProgramFiles(x86)\Microsoft Office\root\Office16\WINWORD.EXE",
        "$env:ProgramFiles\Microsoft Office\Office16\WINWORD.EXE",
        "$env:ProgramFiles(x86)\Microsoft Office\Office16\WINWORD.EXE"
    )

    foreach ($path in $officePaths) {
        if (Test-Path $path) { return $true }
    }

    $uninstallKeys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($key in $uninstallKeys) {
        $office = Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -match "Microsoft 365|Microsoft Office|Office LTSC|Office Professional|Office 2021|Office 2019"
        }
        if ($office) { return $true }
    }

    return $false
}

function Assert-HostnameValido {
    param([string]$Hostname)

    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        Write-Log "Hostname não pode ser vazio." "ERRO"
        return $false
    }

    if ($Hostname.Length -gt 15) {
        Write-Log "Hostname '$Hostname' excede 15 caracteres, que é o limite NetBIOS." "ERRO"
        return $false
    }

    if ($Hostname -notmatch '^[a-zA-Z0-9\-]+$') {
        Write-Log "Hostname '$Hostname' contém caracteres inválidos. Use apenas letras, números e hífen." "ERRO"
        return $false
    }

    if ($Hostname -match '^-|-$') {
        Write-Log "Hostname '$Hostname' não pode começar ou terminar com hífen." "ERRO"
        return $false
    }

    return $true
}

# ============================================================
# FUNÇÕES DE INSTALAÇÃO
# ============================================================
function Instalar-OfficeMicrosoft365 {
    $officeInstaller = Join-Path $env:TEMP 'OfficeSetup.exe'
    try {
        $officeUrl = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=O365ProPlusRetail&platform=x64&language=pt-br&version=O16GA"

        Write-Log "Baixando instalador Microsoft 365 Apps..." "INFO"
        Invoke-WebRequest -Uri $officeUrl -OutFile $officeInstaller -UseBasicParsing -ErrorAction Stop

        Write-Log "Iniciando instalação do Microsoft 365 Apps..." "INFO"
        $proc = Start-Process $officeInstaller -Wait -PassThru -ErrorAction Stop

        if ($proc.ExitCode -eq 0) {
            if (Test-OfficeInstalado) { Write-Log "Microsoft 365 Apps instalado e detectado." 'SUCCESS'; return $true }
            Write-Log "O instalador retornou sucesso, mas o Office não foi detectado na verificação posterior." 'ERROR'
            return $false
        } else {
            Write-Log "Instalador do Office retornou código $($proc.ExitCode)." 'WARN'
            return $false
        }

    } catch {
        Write-LogErro "Falha ao instalar Microsoft 365 Apps." $_
        return $false
    } finally {
        Remove-Item $officeInstaller -Force -ErrorAction SilentlyContinue
    }
}

function Instalar-DriversFabricante {
    $ok = $true
    try {
        $fabricante = (Get-CimInstance Win32_ComputerSystem).Manufacturer
        Write-Log "Fabricante detectado: $fabricante" "INFO"

        switch -Wildcard ($fabricante.ToLower()) {
            "*dell*" {
                Write-Log "Instalando Dell Command Update..." "INFO"
                $null = winget install --id Dell.CommandUpdate --silent --accept-package-agreements --accept-source-agreements 2>&1
                if ($LASTEXITCODE -ne 0) { throw "winget retornou código $LASTEXITCODE ao instalar Dell Command Update." }

                $dcu = "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe"
                if (Test-Path $dcu) {
                    Write-Log "Executando Dell Command Update..." "INFO"
                    $proc = Start-Process $dcu -ArgumentList "/applyUpdates -silent" -Wait -PassThru -ErrorAction Stop
                    if ($proc.ExitCode -ne 0) { throw "Dell Command Update retornou código $($proc.ExitCode)." }
                    Write-Log "Dell Command Update terminou com código zero." 'SUCCESS'
                } else {
                    Write-Log "dcu-cli.exe não encontrado. Execute manualmente se necessário." "AVISO"
                    $ok = $false
                }
            }

            "*lenovo*" {
                Write-Log "Instalando Lenovo System Update..." "INFO"
                $null = winget install --id Lenovo.SystemUpdate --silent --accept-package-agreements --accept-source-agreements 2>&1
                if ($LASTEXITCODE -ne 0) { throw "winget retornou código $LASTEXITCODE ao instalar Lenovo System Update." }
                Write-Log "Lenovo System Update instalado. Execute a aplicação manualmente para aplicar drivers pendentes." "AVISO"
            }

            default {
                Write-Log "Fabricante '$fabricante' não mapeado. Nenhum driver instalado automaticamente." "AVISO"
                $ok = $false
            }
        }
    } catch {
        Write-LogErro "Falha na instalação de drivers do fabricante." $_
        $ok = $false
    }
    return $ok
}

# ============================================================
# CABEÇALHO
# ============================================================
$etapaAtual = Get-Etapa

Clear-Host
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   PADRONIZAÇÃO DE MÁQUINA CORPORATIVA" -ForegroundColor Cyan
Write-Host "   by Eduardo Ferreira | Paerro Tecnologia" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

Write-Log "Script iniciado. Etapa atual: $etapaAtual" "INFO"
Write-Log "Log salvo em: $logFile" "INFO"

# RunOnce com prefixo ! é consumido somente depois de iniciar o processo. Removemos
# explicitamente ao iniciar para evitar repetição automática após uma retomada inválida.
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name '!Padronizacao' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'Padronizacao' -ErrorAction SilentlyContinue
try {
    Complete-PendingAction
    $etapaAtual = Get-Etapa
    if ($etapaAtual -ge 3) {
        $expectedName = Get-DadoSalvo 'Hostname'
        $expectedDomain = Get-DadoSalvo 'Dominio'
        $actualSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $stateMismatch = -not [string]::IsNullOrWhiteSpace($expectedName) -and $actualSystem.Name -ine $expectedName
        if (-not $stateMismatch -and $expectedDomain -and $expectedDomain -notin @('Não ingressado','Etapa pulada')) {
            $stateMismatch = -not $actualSystem.PartOfDomain -or $actualSystem.Domain -ine $expectedDomain
        }
        if ($stateMismatch) {
            Set-Etapa 2
            $etapaAtual = 2
            Write-Log "Estado legado/inconsistente detectado: hostname/domínio real não corresponde ao registro. Etapa 3 reaberta para nova validação interativa." 'WARN'
        }
    }
} catch {
    Write-LogErro 'Falha ao validar retomada após reinicialização; o progresso foi preservado para diagnóstico.' $_
    Write-Host 'A retomada não foi validada. Corrija a condição indicada no log e execute novamente o arquivo .ps1.' -ForegroundColor Red
    exit 4
}

if ($etapaAtual -gt 0) {
    Write-Log "Retomando a partir da etapa $etapaAtual após reboot." "AVISO"
}

# ============================================================
# ETAPA 1 — ADMINISTRADOR LOCAL
# ============================================================
if ($etapaAtual -lt 1) {
    Update-Progresso 1 "Administrador local"
    Write-Log "ETAPA 1 — Verificação da conta Administrador local" "ETAPA"

    try {
        $admin = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -match '-500$' } | Select-Object -First 1

        if (-not $admin) {
            Write-Log "A conta interna RID-500 não foi encontrada. A etapa foi ignorada sem habilitar outra conta administrativa." "WARN"
        } else {
            if (-not $admin.Enabled) {
                Enable-LocalUser -InputObject $admin -ErrorAction Stop
                Write-Log "Conta interna RID-500 habilitada conforme solicitação do técnico." "SUCCESS"
            } else {
                Write-Log "Conta interna RID-500 já está habilitada." "SUCCESS"
            }

            $alterarSenha = Read-Host "Deseja definir/alterar a senha da conta interna de administrador local? (S/N)"
            if ($alterarSenha -match '^[sS]') {
                do {
                    $adminPass        = Read-Host "Defina a senha da conta interna de administrador" -AsSecureString
                    $adminPassConfirm = Read-Host "Confirme a senha" -AsSecureString

                    $ptr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPass)
                    $ptr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPassConfirm)
                    $pass1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr1)
                    $pass2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr2)

                    if ($pass1 -ne $pass2) {
                        Write-Log "As senhas não coincidem. Tente novamente." "AVISO"
                    }

                    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr1)
                    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr2)
                } while ($pass1 -ne $pass2)

                # Respeita a política de expiração do domínio/dispositivo;
                # contas locais corporativas devem ter rotação gerenciada (ex.: Windows LAPS).
                try {
                    Set-LocalUser -InputObject $admin -Password $adminPass -ErrorAction Stop
                    Write-Log "Senha da conta interna de administrador definida." "OK"
                } finally {
                    $pass1 = $null; $pass2 = $null
                    $adminPass = $null; $adminPassConfirm = $null
                    [System.GC]::Collect()
                }
            }
        }
    } catch {
        Write-LogErro "Falha ao verificar/configurar Administrador local." $_
        Write-Log 'A etapa administrativa local não foi confirmada; o estado não será avançado.' 'ERROR'
        exit 9
    }

    Set-Etapa 1
}

# ============================================================
# ETAPA 2 — PRÉ-VERIFICAÇÃO: INTERNET, WINDOWS PRO E OFFICE
# ============================================================
if ($etapaAtual -lt 2) {
    Update-Progresso 2 "Pré-verificações"
    Write-Log "ETAPA 2 — Pré-verificações obrigatórias" "ETAPA"

    if (Test-Internet) {
        Write-Log "Internet OK." "OK"
        Set-DadoSalvo "InternetOK" "1"
    } else {
        Write-Log "Sem internet. Verifique rede, DNS ou proxy antes de continuar." "ERRO"
        pause
        exit 5
    }

    $edicao = Get-WindowsEdicao
    Write-Log "Edição do Windows detectada: $edicao" "INFO"

    if (Test-WindowsPro) {
        Write-Log "Windows compatível detectado: $edicao" "OK"
        Set-DadoSalvo "WindowsProOK" "1"
    } else {
        Write-Log "Windows não é Pro/Enterprise/Education. Upgrade necessário antes de continuar." "AVISO"

        Set-DadoSalvo "ScriptPath" $scriptPath
        Set-RunOnce

        Write-Host "`n============================================" -ForegroundColor Yellow
        Write-Host "   WINDOWS HOME DETECTADO" -ForegroundColor Yellow
        Write-Host "============================================" -ForegroundColor Yellow
        Write-Host "Após o upgrade e reinício, o script continuará automaticamente." -ForegroundColor Gray
        Write-Host "============================================`n" -ForegroundColor Yellow

        Write-Log "Upgrade Home -> Pro pendente. Faça o upgrade com uma licença válida pelos canais oficiais da Microsoft e execute novamente após o reboot." "AVISO"
        pause
        exit 6
    }

    if (Test-OfficeInstalado) {
        Write-Log "Microsoft Office já está instalado." "OK"
        Set-DadoSalvo "OfficeInstalado" "1"
    } else {
        Write-Log "Microsoft Office não encontrado. Instalação será executada na etapa de Office." "AVISO"
        Set-DadoSalvo "OfficeInstalado" "0"
    }

    Set-Etapa 2
}

# ============================================================
# ETAPA 3 — HOSTNAME / DOMÍNIO OPCIONAL
# ============================================================
if ($etapaAtual -lt 3) {
    Update-Progresso 3 "Hostname e domínio"
    Write-Log "ETAPA 3 — Hostname e domínio" "ETAPA"

    Write-Host "`nEscolha uma opção:" -ForegroundColor Yellow
    Write-Host "  [1] Alterar hostname e ingressar no domínio" -ForegroundColor White
    Write-Host "  [2] Apenas alterar hostname" -ForegroundColor White
    Write-Host "  [3] Pular hostname e domínio" -ForegroundColor Gray

    $opcaoDominio = Read-Host "Digite a opção"

    try {
        switch ($opcaoDominio) {
            "1" {
                do {
                    $novoHostname = Read-Host "Digite o novo hostname"
                    $hostnameValido = Assert-HostnameValido $novoHostname
                } while (-not $hostnameValido)

                $dominio = Read-Host "Digite o domínio. Ex: apoio.local, locus.local, gesquadra.com"
                $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
                if ($computer.PartOfDomain -and $computer.Domain -ine $dominio) {
                    throw "Esta máquina já pertence ao domínio '$($computer.Domain)'. Remova-a do domínio atual pelo procedimento aprovado antes de ingressar em '$dominio'."
                }
                if ($computer.PartOfDomain -and $computer.Domain -ieq $dominio -and $computer.Name -ieq $novoHostname) {
                    Set-DadoSalvo "Hostname" $novoHostname
                    Set-DadoSalvo "Dominio" $dominio
                    Write-Log "Máquina já pertence ao domínio desejado e já possui o hostname '$novoHostname'; nenhuma alteração necessária." 'SUCCESS'
                    Set-Etapa 3
                    break
                }
                $dc = Get-DomainController -Domain $dominio
                Write-Log "Controlador selecionado: $dc (registros SRV resolvidos e TCP/135, TCP/389 e TCP/445 acessíveis). Kerberos/UDP e RPC dinâmico dependem das regras de rede do ambiente." 'INFO'
                try {
                    $existingDnsName = Resolve-DnsName -Name "$novoHostname.$dominio" -Type A -DnsOnly -ErrorAction Stop
                    if ($existingDnsName) { Write-Log "O nome DNS '$novoHostname.$dominio' já resolve; confirme se o registro/objeto de computador existente pode ser reutilizado antes do ingresso." 'WARN' }
                } catch { Write-Log "Nenhum registro A para '$novoHostname.$dominio' foi encontrado; essa consulta não substitui a verificação do objeto de computador no Active Directory." 'INFO' }
                $domAdmin = Read-Host "Usuário do domínio com permissão para adicionar máquinas"
                $domPass = Read-Host "Senha do usuário do domínio" -AsSecureString
                $credencial = New-Object System.Management.Automation.PSCredential($domAdmin, $domPass)

                Set-DadoSalvo "Hostname" $novoHostname
                Set-DadoSalvo "Dominio" $dominio
                if ($computer.PartOfDomain) {
                    Set-DadoSalvo 'PendingAction' 'RenameDomainComputer'
                    Set-RunOnce
                    Rename-Computer -NewName $novoHostname -DomainCredential $credencial -Force -ErrorAction Stop
                } else {
                    Set-DadoSalvo 'PendingAction' 'JoinDomain'
                    Set-RunOnce
                    $joinResult = Add-Computer -DomainName $dominio -Server $dc -Credential $credencial -NewName $novoHostname -Force -PassThru -ErrorAction Stop
                    if ($joinResult -and $joinResult.PSObject.Properties['HasSucceeded'] -and -not $joinResult.HasSucceeded) {
                        throw "Add-Computer indicou que o ingresso não foi concluído no controlador '$dc'."
                    }
                }
                Write-Log "Operação de hostname/domínio enviada. O progresso só será confirmado após validação depois da reinicialização." 'INFO'
                $credencial = $null; $domPass = $null
                [System.GC]::Collect()
                Start-Sleep -Seconds 3
                Restart-Computer -Force -ErrorAction Stop
                exit 0
            }

            "2" {
                do {
                    $novoHostname = Read-Host "Digite o novo hostname"
                    $hostnameValido = Assert-HostnameValido $novoHostname
                } while (-not $hostnameValido)

                if ($env:COMPUTERNAME -ieq $novoHostname) {
                    Set-DadoSalvo "Hostname" $novoHostname
                    Set-DadoSalvo "Dominio" "Não ingressado"
                    Write-Log "Hostname já é '$novoHostname'; nenhuma renomeação nem reboot necessário." 'SUCCESS'
                    Set-Etapa 3
                    break
                }

                Set-DadoSalvo "Hostname" $novoHostname
                Set-DadoSalvo "Dominio" "Não ingressado"
                Set-DadoSalvo 'PendingAction' 'RenameComputer'
                Set-RunOnce
                Rename-Computer -NewName $novoHostname -Force -ErrorAction Stop
                Write-Log "Hostname alterado para '$novoHostname'." "OK"
                Write-Log "Reiniciando para aplicar hostname..." "INFO"
                Start-Sleep -Seconds 3
                Restart-Computer -Force -ErrorAction Stop
                exit 0
            }

            default {
                Set-DadoSalvo "Hostname" $env:COMPUTERNAME
                Set-DadoSalvo "Dominio" "Etapa pulada"
                Write-Log "Etapa de hostname/domínio pulada pelo técnico." "AVISO"
            }
        }
    } catch {
        $credencial = $null; $domPass = $null; $domAdmin = $null
        [System.GC]::Collect()
        Remove-ItemProperty -Path $regPath -Name 'PendingAction' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name '!Padronizacao' -ErrorAction SilentlyContinue
        Write-LogErro "Falha na etapa de hostname/domínio." $_
        Write-Log "Diagnóstico: revise DNS SRV, resolução de nome, portas TCP/135, 389 e 445, credenciais/permissões, domínio atual e conflitos de conta ou hostname. Kerberos/UDP e RPC dinâmico também dependem das regras de rede do ambiente. Nenhuma senha foi registrada." "WARN"
        pause
        exit 8
    }

    Set-Etapa 3
}

# ============================================================
# ETAPA 4 — WINDOWS UPDATE EM BACKGROUND
# ============================================================
if ($etapaAtual -lt 4) {
    Update-Progresso 4 "Windows Update"
    Write-Log "ETAPA 4 — Windows Update" "ETAPA"

    if (Confirmar-Etapa "Windows Update") {
        try {
            if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                Write-Log "Instalando módulo PSWindowsUpdate..." "INFO"
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
                Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -Confirm:$false | Out-Null
            }

            Import-Module PSWindowsUpdate -Force

            Write-Log "Instalação de atualizações iniciada em primeiro plano; aguarde o comando concluir." "INFO"
            $wuResult = Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -Verbose -ErrorAction Stop
            if ($wuResult) { $wuResult | Select-Object -First 20 | ForEach-Object { Write-Log ($_ | Out-String).Trim() 'INFO' } }
            Write-Log "O cmdlet de Windows Update retornou sem erro terminante." 'SUCCESS'
        } catch {
            Write-LogErro "Falha ao iniciar Windows Update." $_
            Write-Log "Continuando sem Windows Update." "AVISO"
        }
    } else {
        Write-Log "Windows Update pulado pelo técnico." "AVISO"
    }

    Set-Etapa 4
}

# ============================================================
# ETAPA 5 — APLICATIVOS PADRÃO VIA WINGET
# ============================================================
if ($etapaAtual -lt 5) {
    Update-Progresso 5 "Aplicativos padrão"
    Write-Log "ETAPA 5 — Instalação de aplicativos padrão" "ETAPA"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Winget não encontrado. Instale o App Installer pela Microsoft Store e execute novamente." "ERRO"
        pause
        exit 7
    }

    $apps = @(
        @{ Id = "Google.Chrome";                 Nome = "Google Chrome" },
        @{ Id = "Mozilla.Firefox";               Nome = "Mozilla Firefox" },
        @{ Id = "Oracle.JavaRuntimeEnvironment"; Nome = "Java 8 JRE" },
        @{ Id = "AnyDesk.AnyDesk";               Nome = "AnyDesk" },
        @{ Id = "Adobe.Acrobat.Reader.64-bit";   Nome = "Adobe Acrobat Reader" },
        @{ Id = "RARLab.WinRAR";                 Nome = "WinRAR" }
    )

    foreach ($app in $apps) {
        try {
            Write-Log "Instalando/verificando $($app.Nome)..." "INFO"
            $resultado = winget install --id $app.Id --silent --accept-package-agreements --accept-source-agreements 2>&1
            $resultado | Select-Object -First 8 | ForEach-Object { Write-Log ([string]$_) 'INFO' }

            $appExitCode = $LASTEXITCODE
            if ($appExitCode -eq 0) {
                Write-Log "$($app.Nome): winget terminou com código zero." 'SUCCESS'
            } else {
                Write-Log "$($app.Nome) retornou código $appExitCode; item marcado para verificação manual." 'WARN'
            }
        } catch {
            Write-LogErro "Erro ao instalar $($app.Nome)." $_
        }
    }

    Set-Etapa 5
}

# ============================================================
# ETAPA 6 — GLPI AGENT OPCIONAL
# ============================================================
if ($etapaAtual -lt 6) {
    Update-Progresso 6 "GLPI Agent"
    Write-Log "ETAPA 6 — GLPI Agent" "ETAPA"

    if (Confirmar-Etapa "Instalar GLPI Agent") {
        try {
            $glpiUrl    = "https://github.com/glpi-project/glpi-agent/releases/download/1.17/GLPI-Agent-1.17-x64.msi"
            $glpiServer = "https://suporte.paerro.tech/front/inventory.php"
            $glpiMsi    = "$env:TEMP\glpi-agent.msi"

            Write-Log "Baixando GLPI Agent..." "INFO"
            Invoke-WebRequest -Uri $glpiUrl -OutFile $glpiMsi -UseBasicParsing -ErrorAction Stop

            Write-Log "Instalando GLPI Agent..." "INFO"
            $proc = Start-Process msiexec.exe -ArgumentList "/i `"$glpiMsi`" /quiet /norestart SERVER_URL=`"$glpiServer`"" -Wait -PassThru

            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                Write-Log "GLPI Agent instalado. Servidor: $glpiServer" "OK"
            } else {
                Write-Log "msiexec retornou código $($proc.ExitCode)." "WARN"
            }

            Remove-Item $glpiMsi -Force -ErrorAction SilentlyContinue
        } catch {
            Write-LogErro "Falha ao instalar GLPI Agent." $_
        }
    } else {
        Write-Log "Instalação do GLPI Agent pulada pelo técnico." "AVISO"
    }

    Set-Etapa 6
}

# ============================================================
# ETAPA 7 — MICROSOFT OFFICE
# ============================================================
if ($etapaAtual -lt 7) {
    Update-Progresso 7 "Microsoft Office"
    Write-Log "ETAPA 7 — Microsoft Office" "ETAPA"

    if (Test-OfficeInstalado) {
        Write-Log "Office já está instalado. Pulando instalação." "OK"
        Set-DadoSalvo "OfficeInstalado" "1"
    } else {
        Write-Log "Office não encontrado. Instalando via link C2R Microsoft 365 Apps." "AVISO"
        if (Instalar-OfficeMicrosoft365) { Set-DadoSalvo 'OfficeInstalado' '1' } else { Set-DadoSalvo 'OfficeInstalado' '0' }
    }

    Set-Etapa 7
}

# ============================================================
# ETAPA 8 — DRIVERS DO FABRICANTE
# ============================================================
if ($etapaAtual -lt 8) {
    Update-Progresso 8 "Drivers"
    Write-Log "ETAPA 8 — Drivers do fabricante" "ETAPA"

    if (Confirmar-Etapa "Instalar/atualizar drivers do fabricante") {
        if (-not (Instalar-DriversFabricante)) { Set-DadoSalvo 'DriversStatus' 'Verificação manual necessária' }
    } else {
        Write-Log "Etapa de drivers pulada pelo técnico." "AVISO"
    }

    Set-Etapa 8
}

# ============================================================
# ETAPA 9 — ATIVAÇÃO OFFICE + WINDOWS
# ============================================================
if ($etapaAtual -lt 9) {
    Update-Progresso 9 "Ativação Office e Windows"
    Write-Log "ETAPA 9 — Ativação Office e Windows" "ETAPA"

    Write-Host "`n============================================" -ForegroundColor Yellow
    Write-Host "   ATIVAÇÃO / LICENCIAMENTO" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Yellow

    Write-Host "Conclua a ativação do Windows e do Office usando licenças válidas e os canais oficiais da organização/Microsoft." -ForegroundColor Yellow
    Write-Log "Ativação delegada ao processo de licenciamento da organização; nenhum código remoto foi executado." "AVISO"

    Set-Etapa 9
}

# Windows Update é executado em primeiro plano na etapa 4. Jobs do PowerShell não
# sobrevivem a reinicializações; por isso não há job em memória a aguardar aqui.

# ============================================================
# RESUMO FINAL
# ============================================================
$novoHostname = Get-DadoSalvo "Hostname"
$dominio = Get-DadoSalvo "Dominio"
$officeStatus = if (Test-OfficeInstalado) { "Instalado" } else { "Não detectado" }
$windowsEdicao = Get-WindowsEdicao

Write-Progress -Activity "Padronização Corporativa" -Completed

Write-Log "============================================" "INFO"
$resumoTipo = if ($script:hasIssues) { 'WARN' } else { 'SUCCESS' }
$resumoTexto = if ($script:hasIssues) { 'PADRONIZAÇÃO CONCLUÍDA COM AVISOS — revise o log' } else { 'PADRONIZAÇÃO CONCLUÍDA' }
Write-Log $resumoTexto $resumoTipo
Write-Log "Hostname : $novoHostname" "INFO"
Write-Log "Domínio  : $dominio" "INFO"
Write-Log "Windows  : $windowsEdicao" "INFO"
Write-Log "Office   : $officeStatus" "INFO"
Write-Log "Log salvo em: $logFile" "INFO"
Write-Log "============================================" "INFO"

Remove-Estado

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "   $resumoTexto" -ForegroundColor Cyan
Write-Host "   Hostname : $novoHostname" -ForegroundColor White
Write-Host "   Domínio  : $dominio" -ForegroundColor White
Write-Host "   Windows  : $windowsEdicao" -ForegroundColor White
Write-Host "   Office   : $officeStatus" -ForegroundColor White
Write-Host "   Log      : $logFile" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

pause
