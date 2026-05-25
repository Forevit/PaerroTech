<#
============================================================
 SCRIPT DE PADRONIZAÇÃO DE MÁQUINA CORPORATIVA
 Projeto: PaerroTech
 Autor: Eduardo Ferreira
 Versão: 3.0-refactor

 Objetivo:
 - Padronizar máquinas Windows 10/11 Pro
 - Reduzir falhas em execução remota via irm | iex
 - Permitir retomada após reboot usando cópia local do script
 - Melhorar logs, validações, Winget, GLPI Agent, Office e drivers
============================================================
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$SkipDomainJoin,
    [switch]$SkipOffice,
    [switch]$SkipDrivers,
    [switch]$SkipWindowsUpdate,
    [switch]$SkipGLPI,
    [switch]$SkipApps,
    [switch]$ResetState
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# CONFIGURAÇÕES GERAIS
# ============================================================
$Config = [ordered]@{
    ProjectName       = 'PaerroTech - Padronização Corporativa'
    RegPath           = 'HKLM:\SOFTWARE\PaerroTech\Padronizacao'
    RunOncePath       = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    RunOnceName       = 'PaerroTechPadronizacao'
    BaseDir           = "$env:ProgramData\PaerroTech\Padronizacao"
    LogRoot           = 'C:\Users\Public\Documents\Logs\Padronizacao'
    LocalScriptPath   = "$env:ProgramData\PaerroTech\Padronizacao\padronizacao.ps1"
    GLPIServer        = 'https://suporte.paerro.tech/front/inventory.php'
    GLPIAgentVersion  = '1.17'
    OfficeC2RUrl       = 'https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=O365ProPlusRetail&platform=x64&language=pt-br&version=O16GA'
    OfficeLanguage    = 'pt-br'
    TotalSteps        = 8
}

$DominiosClientes = [ordered]@{
    'apoio.local'     = @{ Nome = 'GrupoApoioCob';         Base = 'GAPC'; DominioLDAP = 'DC=apoio,DC=local' }
    'locus.local'     = @{ Nome = 'GrupoLocusEmpresarial'; Base = 'GLHE'; DominioLDAP = 'DC=locus,DC=local' }
    'topclean.local'  = @{ Nome = 'GrupoTopClean';         Base = 'GTPC'; DominioLDAP = 'DC=topclean,DC=local' }
    'gesquadra.local' = @{ Nome = 'GrupoEsquadra';         Base = 'GESQ'; DominioLDAP = 'DC=gesquadra,DC=local' }
    'gesquadra.com'   = @{ Nome = 'GrupoEsquadra';         Base = 'GESQ'; DominioLDAP = 'DC=gesquadra,DC=com' }
}

$TiposMaquina = [ordered]@{
    '1' = @{ Label = 'Notebook'; Sufixo = 'NTB' }
    '2' = @{ Label = 'Desktop';  Sufixo = 'DSK' }
}

$AppsWinget = @(
    @{ Id = 'Google.Chrome';                  Nome = 'Google Chrome' }
    @{ Id = 'Mozilla.Firefox';                Nome = 'Mozilla Firefox' }
    @{ Id = 'Oracle.JavaRuntimeEnvironment';  Nome = 'Java Runtime Environment' }
    @{ Id = 'AnyDesk.AnyDesk';                Nome = 'AnyDesk' }
    @{ Id = 'Adobe.Acrobat.Reader.64-bit';    Nome = 'Adobe Acrobat Reader' }
    @{ Id = 'RARLab.WinRAR';                  Nome = 'WinRAR' }
)

# ============================================================
# INICIALIZAÇÃO
# ============================================================
New-Item -ItemType Directory -Path $Config.BaseDir -Force | Out-Null
New-Item -ItemType Directory -Path $Config.LogRoot -Force | Out-Null
$Global:LogFile = Join-Path $Config.LogRoot "padronizacao_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO','OK','ERRO','AVISO','ETAPA')] [string]$Type = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Type, $Message
    $line | Out-File -FilePath $Global:LogFile -Append -Encoding UTF8

    switch ($Type) {
        'OK'    { Write-Host $line -ForegroundColor Green }
        'ERRO'  { Write-Host $line -ForegroundColor Red }
        'AVISO' { Write-Host $line -ForegroundColor Yellow }
        'ETAPA' { Write-Host "`n$line" -ForegroundColor Cyan }
        default { Write-Host $line -ForegroundColor White }
    }
}

function Write-ErrorLog {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [Parameter()] $ErrorRecord
    )

    Write-Log $Message 'ERRO'
    if ($ErrorRecord) {
        Write-Log "Detalhe: $($ErrorRecord.Exception.Message)" 'ERRO'
        if ($ErrorRecord.InvocationInfo) {
            Write-Log "Linha: $($ErrorRecord.InvocationInfo.ScriptLineNumber)" 'ERRO'
        }
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
    if (Test-IsAdmin) { return }

    Write-Host 'Reabrindo script como administrador...' -ForegroundColor Yellow

    $path = Ensure-LocalScriptCopy
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$path`""
    )
    exit
}

function Ensure-RegistryPath {
    if (-not (Test-Path $Config.RegPath)) {
        New-Item -Path $Config.RegPath -Force | Out-Null
    }
}

function Get-StateValue {
    param([Parameter(Mandatory)] [string]$Name, [object]$Default = $null)
    if (-not (Test-Path $Config.RegPath)) { return $Default }
    $prop = Get-ItemProperty -Path $Config.RegPath -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $prop) { return $Default }
    return $prop.$Name
}

function Set-StateValue {
    param([Parameter(Mandatory)] [string]$Name, [Parameter(Mandatory)] [object]$Value)
    Ensure-RegistryPath
    Set-ItemProperty -Path $Config.RegPath -Name $Name -Value $Value
}

function Get-Step {
    return [int](Get-StateValue -Name 'Step' -Default 0)
}

function Set-Step {
    param([Parameter(Mandatory)] [int]$Step)
    Set-StateValue -Name 'Step' -Value $Step
}

function Clear-State {
    Remove-Item -Path $Config.RegPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $Config.RunOncePath -Name $Config.RunOnceName -ErrorAction SilentlyContinue
}

function Ensure-LocalScriptCopy {
    <#
      Motivo:
      Quando o script roda por irm | iex, $PSCommandPath pode vir vazio.
      Para retomada após reboot funcionar, criamos uma cópia local persistente.
    #>

    New-Item -ItemType Directory -Path $Config.BaseDir -Force | Out-Null

    $currentPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($currentPath)) {
        $currentPath = $MyInvocation.MyCommand.Path
    }

    if (-not [string]::IsNullOrWhiteSpace($currentPath) -and (Test-Path $currentPath)) {
        Copy-Item -Path $currentPath -Destination $Config.LocalScriptPath -Force
    }
    else {
        $rawUrl = 'https://raw.githubusercontent.com/Forevit/PaerroTech/main/PadronizacaoMaquinas/padronizacao.ps1'
        try {
            Invoke-WebRequest -Uri $rawUrl -OutFile $Config.LocalScriptPath -UseBasicParsing -ErrorAction Stop
        }
        catch {
            throw "Não foi possível salvar uma cópia local do script. Execute localmente ou verifique acesso ao GitHub. Erro: $($_.Exception.Message)"
        }
    }

    Unblock-File -Path $Config.LocalScriptPath -ErrorAction SilentlyContinue
    Set-StateValue -Name 'LocalScriptPath' -Value $Config.LocalScriptPath
    return $Config.LocalScriptPath
}

function Set-RunOnceResume {
    $path = Get-StateValue -Name 'LocalScriptPath' -Default $Config.LocalScriptPath
    if (-not (Test-Path $path)) {
        $path = Ensure-LocalScriptCopy
    }

    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$path`""
    Set-ItemProperty -Path $Config.RunOncePath -Name $Config.RunOnceName -Value $cmd
    Write-Log "RunOnce configurado para retomar: $cmd" 'OK'
}

function Show-Header {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' PADRONIZAÇÃO DE MÁQUINA CORPORATIVA' -ForegroundColor Cyan
    Write-Host ' by Eduardo Ferreira' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host "Hostname atual: $env:COMPUTERNAME" -ForegroundColor Yellow
    Write-Host "Log: $Global:LogFile" -ForegroundColor Gray
    Write-Host '============================================================' -ForegroundColor Cyan
}

function Update-StepProgress {
    param([int]$Step, [string]$Status)
    $percent = [math]::Round(($Step / $Config.TotalSteps) * 100)
    Write-Progress -Activity $Config.ProjectName -Status "Etapa $Step/$($Config.TotalSteps) - $Status" -PercentComplete $percent
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)] [int]$Number,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [scriptblock]$Action
    )

    $current = Get-Step
    if ($current -ge $Number) {
        Write-Log "Etapa $Number já concluída: $Name" 'INFO'
        return
    }

    Update-StepProgress -Step $Number -Status $Name
    Write-Log "ETAPA $Number - $Name" 'ETAPA'

    try {
        & $Action
        Set-Step -Step $Number
        Write-Log "Etapa $Number concluída: $Name" 'OK'
    }
    catch {
        Write-ErrorLog "Falha na etapa $Number: $Name" $_
        Write-Host "`nA execução foi pausada. Verifique o log acima antes de continuar." -ForegroundColor Yellow
        Pause
        exit 1
    }
}

# ============================================================
# VALIDAÇÕES E UTILITÁRIOS
# ============================================================
function Assert-HostnameValid {
    param([Parameter(Mandatory)] [string]$Hostname)

    if ([string]::IsNullOrWhiteSpace($Hostname)) { throw 'Hostname não pode ser vazio.' }
    if ($Hostname.Length -gt 15) { throw "Hostname '$Hostname' excede 15 caracteres, limite NetBIOS." }
    if ($Hostname -notmatch '^[a-zA-Z0-9-]+$') { throw "Hostname '$Hostname' contém caracteres inválidos. Use letras, números e hífen." }
    if ($Hostname -match '^-|-$') { throw "Hostname '$Hostname' não pode começar ou terminar com hífen." }
    return $true
}

function Get-NextHostnameFromLDAP {
    param(
        [Parameter(Mandatory)] [string]$Base,
        [Parameter(Mandatory)] [string]$DomainDN,
        [Parameter(Mandatory)] [string]$Suffix
    )

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainDN")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.Filter = "(&(objectCategory=computer)(name=$Base$Suffix*))"
        [void]$searcher.PropertiesToLoad.Add('name')
        $results = $searcher.FindAll()

        $names = @($results | ForEach-Object { $_.Properties['name'][0] })
        if ($names.Count -eq 0) {
            return @{ Suggestion = "${Base}${Suffix}0001"; Existing = @() }
        }

        $numbers = @($names | ForEach-Object {
            if ($_ -match '(\d+)$') { [int]$Matches[1] }
        }) | Sort-Object

        $next = 1
        if ($numbers.Count -gt 0) {
            $next = (($numbers | Measure-Object -Maximum).Maximum + 1)
        }

        return @{
            Suggestion = ("{0}{1}{2:D4}" -f $Base, $Suffix, $next)
            Existing   = ($names | Sort-Object)
        }
    }
    catch {
        Write-Log "Falha na consulta LDAP: $($_.Exception.Message)" 'AVISO'
        return $null
    }
}

function Resolve-WingetPath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending

    if ($candidates) { return $candidates[0].FullName }
    return $null
}

function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$Name
    )

    $winget = Resolve-WingetPath
    if (-not $winget) {
        throw 'Winget não encontrado. Instale/atualize o App Installer pela Microsoft Store.'
    }

    Write-Log "Instalando/validando $Name via Winget..." 'INFO'

    $args = @(
        'install',
        '--id', $Id,
        '--exact',
        '--silent',
        '--disable-interactivity',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    $output = & $winget @args 2>&1
    $exit = $LASTEXITCODE
    $output | Out-File -FilePath $Global:LogFile -Append -Encoding UTF8

    # 0 = OK
    # -1978335189 geralmente indica pacote já instalado ou estado equivalente em algumas versões do winget
    if ($exit -eq 0 -or $exit -eq -1978335189) {
        Write-Log "$Name OK." 'OK'
    }
    else {
        Write-Log "$Name retornou código $exit. Verifique o log." 'AVISO'
    }
}

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [string]$OutFile
    )

    Write-Log "Baixando: $Uri" 'INFO'
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
    if (-not (Test-Path $OutFile)) { throw "Download não gerou arquivo: $OutFile" }
}

function Install-GLPIAgent {
    $version = $Config.GLPIAgentVersion
    $url = "https://github.com/glpi-project/glpi-agent/releases/download/$version/GLPI-Agent-$version-x64.msi"
    $msi = Join-Path $env:TEMP "GLPI-Agent-$version-x64.msi"

    Invoke-DownloadFile -Uri $url -OutFile $msi

    $arguments = @(
        '/i', "`"$msi`"",
        '/quiet',
        '/norestart',
        "SERVER=`"$($Config.GLPIServer)`"",
        "RUNNOW=1"
    ) -join ' '

    Write-Log 'Instalando GLPI Agent...' 'INFO'
    $proc = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Instalação do GLPI Agent retornou código $($proc.ExitCode)."
    }

    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    Write-Log "GLPI Agent instalado. Servidor: $($Config.GLPIServer)" 'OK'
}

function Install-OfficeC2R {
    <#
      Instalação do Office/Microsoft 365 Apps via instalador Click-to-Run direto.
      Este método é mais simples que ODT, mas dá menos controle de produto/canal.
      Para ambiente corporativo 100% silencioso e padronizado, ODT ainda é mais previsível.
    #>

    $officeDir = Join-Path $env:TEMP 'PaerroTech_OfficeC2R'
    New-Item -ItemType Directory -Path $officeDir -Force | Out-Null

    $installer = Join-Path $officeDir 'OfficeSetup.exe'
    Invoke-DownloadFile -Uri $Config.OfficeC2RUrl -OutFile $installer

    if (-not (Test-Path $installer)) {
        throw 'Instalador do Office não foi baixado corretamente.'
    }

    Write-Log 'Instalando Office/Microsoft 365 Apps via Click-to-Run. Esta etapa pode demorar.' 'INFO'

    $proc = Start-Process -FilePath $installer -ArgumentList '/quiet' -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        Write-Log "Instalador retornou código $($proc.ExitCode). Tentando execução sem argumento silencioso." 'AVISO'
        $proc = Start-Process -FilePath $installer -Wait -PassThru
    }

    Write-Log 'Instalador do Office finalizado. Verifique ativação/licença conforme política da empresa.' 'OK'
}

function Install-ManufacturerDrivers {
    $manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    Write-Log "Fabricante detectado: $manufacturer" 'INFO'

    switch -Wildcard ($manufacturer.ToLower()) {
        '*dell*' {
            Invoke-WingetInstall -Id 'Dell.CommandUpdate' -Name 'Dell Command Update'
            $dcuPaths = @(
                "$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe",
                "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
            )
            $dcu = $dcuPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($dcu) {
                Write-Log 'Executando Dell Command Update...' 'INFO'
                Start-Process $dcu -ArgumentList '/applyUpdates -silent -reboot=disable' -Wait
                Write-Log 'Dell Command Update finalizado.' 'OK'
            }
            else {
                Write-Log 'Dell Command Update instalado, mas dcu-cli.exe não foi localizado.' 'AVISO'
            }
        }
        '*lenovo*' {
            Invoke-WingetInstall -Id 'Lenovo.SystemUpdate' -Name 'Lenovo System Update'
            Write-Log 'Lenovo System Update instalado. Aplicação automática pode exigir TVSU/CLI conforme modelo.' 'AVISO'
        }
        '*hp*' {
            Invoke-WingetInstall -Id 'HP.HPSupportAssistant' -Name 'HP Support Assistant'
        }
        default {
            Write-Log "Fabricante '$manufacturer' não mapeado para driver automático." 'AVISO'
        }
    }
}

function Start-WindowsUpdateTask {
    Write-Log 'Preparando Windows Update em segundo plano...' 'INFO'

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        }

        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -Confirm:$false | Out-Null
        }

        Import-Module PSWindowsUpdate -Force
        Write-Log 'Iniciando busca/instalação de updates. Reboot ignorado nesta etapa.' 'INFO'
        Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -Verbose 2>&1 | Out-File -FilePath $Global:LogFile -Append -Encoding UTF8
        Write-Log 'Windows Update finalizado ou sem atualizações pendentes.' 'OK'
    }
    catch {
        Write-Log "Windows Update falhou, mas a padronização continuará: $($_.Exception.Message)" 'AVISO'
    }
}

function Test-WindowsEdition {
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log "Sistema detectado: $($os.Caption)" 'INFO'

    if ($os.Caption -like '*Home*') {
        Write-Log 'Windows Home detectado. É necessário upgrade para Pro antes de domínio.' 'AVISO'
        Write-Host "`nEsta máquina está com Windows Home. Faça upgrade para Pro e execute novamente." -ForegroundColor Yellow
        Set-StateValue -Name 'WindowsEditionChecked' -Value 0
        Pause
        exit 1
    }

    Set-StateValue -Name 'WindowsEditionChecked' -Value 1
    Write-Log 'Edição do Windows compatível.' 'OK'
}

function Configure-LocalAdministrator {
    $adminName = 'Administrador'
    $user = Get-LocalUser -Name $adminName -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-Log "Conta '$adminName' não encontrada. Tentando localizar SID RID-500." 'AVISO'
        $user = Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' } | Select-Object -First 1
        if (-not $user) { throw 'Não foi possível localizar a conta Administrador local.' }
        $adminName = $user.Name
    }

    do {
        $pass1 = Read-Host "Defina a senha para a conta '$adminName'" -AsSecureString
        $pass2 = Read-Host 'Confirme a senha' -AsSecureString

        $bstr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1)
        $bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2)
        try {
            $plain1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr1)
            $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2)
            $match = ($plain1 -eq $plain2)
        }
        finally {
            if ($bstr1 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1) }
            if ($bstr2 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2) }
        }

        if (-not $match) { Write-Log 'As senhas não coincidem. Tente novamente.' 'AVISO' }
    } while (-not $match)

    Enable-LocalUser -Name $adminName -ErrorAction SilentlyContinue
    Set-LocalUser -Name $adminName -Password $pass1 -PasswordNeverExpires $true
    Write-Log "Conta '$adminName' habilitada/configurada." 'OK'
}

function Select-HostnameAndDomain {
    <#
      Novo fluxo:
      - O técnico digita diretamente o domínio DNS do cliente.
      - Se o domínio estiver cadastrado em $DominiosClientes, o script usa Base e LDAP automaticamente.
      - Se o domínio não estiver cadastrado, o técnico ainda consegue informar o hostname manualmente.
    #>

    do {
        $domainDns = Read-Host 'Digite o domínio do cliente. Ex: apoio.local, locus.local, gesquadra.com'
        $domainDns = $domainDns.Trim().ToLower()

        if ([string]::IsNullOrWhiteSpace($domainDns)) {
            Write-Log 'Domínio não pode ser vazio.' 'ERRO'
            $domainValid = $false
            continue
        }

        if ($domainDns -notmatch '^[a-z0-9.-]+\.[a-z]{2,}$') {
            Write-Log "Domínio '$domainDns' parece inválido. Exemplo válido: apoio.local" 'ERRO'
            $domainValid = $false
            continue
        }

        $domainValid = $true
    } while (-not $domainValid)

    $suggestion = $null
    $cliente = $null

    if ($DominiosClientes.Contains($domainDns)) {
        $cliente = $DominiosClientes[$domainDns]
        Write-Log "Cliente identificado: $($cliente.Nome)" 'OK'
        Write-Log "Base de hostname: $($cliente.Base)" 'INFO'

        Write-Host "`nTipo de máquina:`n" -ForegroundColor Yellow
        foreach ($key in $TiposMaquina.Keys) {
            $type = $TiposMaquina[$key]
            Write-Host " [$key] $($type.Label) ($($cliente.Base)$($type.Sufixo)0001)" -ForegroundColor White
        }

        do {
            $typeChoice = Read-Host 'Digite o número do tipo de máquina'
            if (-not $TiposMaquina.Contains($typeChoice)) {
                Write-Log 'Tipo de máquina inválido.' 'ERRO'
                $typeValid = $false
            }
            else {
                $typeValid = $true
            }
        } while (-not $typeValid)

        $type = $TiposMaquina[$typeChoice]
        $ldapResult = Get-NextHostnameFromLDAP -Base $cliente.Base -DomainDN $cliente.DominioLDAP -Suffix $type.Sufixo

        if ($ldapResult) {
            $suggestion = $ldapResult.Suggestion
            Write-Host "`nPróximo hostname sugerido: $suggestion" -ForegroundColor Green
            Write-Log "Hostname sugerido: $suggestion" 'OK'
        }
        else {
            $suggestion = "{0}{1}0001" -f $cliente.Base, $type.Sufixo
            Write-Host "`nNão foi possível consultar o LDAP. Sugestão inicial: $suggestion" -ForegroundColor Yellow
            Write-Log "Sugestão sem LDAP: $suggestion" 'AVISO'
        }
    }
    else {
        Write-Log "Domínio '$domainDns' não está cadastrado na tabela interna. Hostname será manual." 'AVISO'
        Write-Host "`nDomínio não cadastrado na tabela do script." -ForegroundColor Yellow
        Write-Host 'Você ainda poderá digitar o hostname manualmente.' -ForegroundColor Yellow
    }

    do {
        if ($suggestion) {
            $inputName = Read-Host "Usar '$suggestion'? Enter para confirmar ou digite outro hostname"
            $hostname = if ([string]::IsNullOrWhiteSpace($inputName)) { $suggestion } else { $inputName.Trim().ToUpper() }
        }
        else {
            $hostname = (Read-Host 'Digite o novo hostname').Trim().ToUpper()
        }

        try {
            [void](Assert-HostnameValid -Hostname $hostname)
            $valid = $true
        }
        catch {
            Write-Log $_.Exception.Message 'ERRO'
            $valid = $false
        }
    } while (-not $valid)

    Set-StateValue -Name 'Hostname' -Value $hostname
    Set-StateValue -Name 'DomainDNS' -Value $domainDns
    if ($cliente) {
        Set-StateValue -Name 'Cliente' -Value $cliente.Nome
    }

    return @{ Hostname = $hostname; DomainDNS = $domainDns }
}

function Join-DomainAndRename {
    if ($SkipDomainJoin) {
        Write-Log 'Ingresso no domínio ignorado por parâmetro -SkipDomainJoin.' 'AVISO'
        return
    }

    $selection = Select-HostnameAndDomain
    $domainUser = Read-Host 'Usuário do domínio com permissão para adicionar máquina. Ex: dominio\usuario'
    $domainPass = Read-Host 'Senha do usuário do domínio' -AsSecureString
    $credential = [pscredential]::new($domainUser, $domainPass)

    Ensure-LocalScriptCopy | Out-Null
    Set-RunOnceResume

    Write-Log "Adicionando máquina ao domínio '$($selection.DomainDNS)' com hostname '$($selection.Hostname)'..." 'INFO'

    Add-Computer `
        -DomainName $selection.DomainDNS `
        -Credential $credential `
        -NewName $selection.Hostname `
        -Force `
        -ErrorAction Stop

    Write-Log 'Máquina adicionada ao domínio. Reiniciando para aplicar.' 'OK'
    Set-Step -Step 2
    Start-Sleep -Seconds 5
    Restart-Computer -Force
    exit
}

# ============================================================
# EXECUÇÃO PRINCIPAL
# ============================================================
try {
    if ($ResetState) {
        Clear-State
        Write-Host 'Estado anterior limpo.' -ForegroundColor Yellow
    }

    Ensure-Admin
    Ensure-LocalScriptCopy | Out-Null
    Show-Header

    Write-Log 'Script iniciado.' 'INFO'
    Write-Log "Etapa atual: $(Get-Step)" 'INFO'
    Write-Log "Log salvo em: $Global:LogFile" 'INFO'

    Invoke-Step -Number 1 -Name 'Pré-validação do Windows e configuração do Administrador Local' -Action {
        Test-WindowsEdition
        Configure-LocalAdministrator
    }

    Invoke-Step -Number 2 -Name 'Ingresso no domínio e renomeação da máquina' -Action {
        Join-DomainAndRename
    }

    Invoke-Step -Number 3 -Name 'Instalação de aplicativos essenciais via Winget' -Action {
        if ($SkipApps) {
            Write-Log 'Instalação de aplicativos ignorada por parâmetro -SkipApps.' 'AVISO'
            return
        }
        foreach ($app in $AppsWinget) {
            Invoke-WingetInstall -Id $app.Id -Name $app.Nome
        }
    }

    Invoke-Step -Number 4 -Name 'Instalação do GLPI Agent' -Action {
        if ($SkipGLPI) {
            Write-Log 'GLPI Agent ignorado por parâmetro -SkipGLPI.' 'AVISO'
            return
        }
        Install-GLPIAgent
    }

    Invoke-Step -Number 5 -Name 'Instalação do Office via Click-to-Run' -Action {
        if ($SkipOffice) {
            Write-Log 'Office ignorado por parâmetro -SkipOffice.' 'AVISO'
            return
        }
        Install-OfficeC2R
    }

    Invoke-Step -Number 6 -Name 'Drivers do fabricante' -Action {
        if ($SkipDrivers) {
            Write-Log 'Drivers ignorados por parâmetro -SkipDrivers.' 'AVISO'
            return
        }
        Install-ManufacturerDrivers
    }

    Invoke-Step -Number 7 -Name 'Windows Update' -Action {
        if ($SkipWindowsUpdate) {
            Write-Log 'Windows Update ignorado por parâmetro -SkipWindowsUpdate.' 'AVISO'
            return
        }
        Start-WindowsUpdateTask
    }

    Invoke-Step -Number 8 -Name 'Finalização' -Action {
        Write-Log 'Etapa de ativação/licenciamento ainda deve ser definida conforme política interna.' 'AVISO'
    }

    Write-Progress -Activity $Config.ProjectName -Completed
    Remove-ItemProperty -Path $Config.RunOncePath -Name $Config.RunOnceName -ErrorAction SilentlyContinue

    $finalHostname = Get-StateValue -Name 'Hostname' -Default $env:COMPUTERNAME
    $finalDomain = Get-StateValue -Name 'DomainDNS' -Default '(não informado)'

    Write-Log '============================================================' 'INFO'
    Write-Log 'PADRONIZAÇÃO CONCLUÍDA' 'OK'
    Write-Log "Hostname: $finalHostname" 'INFO'
    Write-Log "Domínio: $finalDomain" 'INFO'
    Write-Log "Log: $Global:LogFile" 'INFO'
    Write-Log '============================================================' 'INFO'

    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host ' PADRONIZAÇÃO CONCLUÍDA!' -ForegroundColor Cyan
    Write-Host " Hostname: $finalHostname" -ForegroundColor White
    Write-Host " Domínio: $finalDomain" -ForegroundColor White
    Write-Host " Log: $Global:LogFile" -ForegroundColor Gray
    Write-Host '============================================================' -ForegroundColor Cyan

    # Limpa somente ao final para permitir troubleshooting antes, se necessário.
    Clear-State
    Pause
}
catch {
    Write-ErrorLog 'Erro fatal na execução principal.' $_
    Write-Host "`nErro fatal. Verifique o log: $Global:LogFile" -ForegroundColor Red
    Pause
    exit 1
}
