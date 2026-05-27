# ============================================================
#  PREVENTIVA CORPORATIVA - PADRONIZACAO DE MAQUINA
#  By Eduardo Ferreira
#  
# ============================================================

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipAdmin,
    [switch]$SkipWindowsUpdate,
    [switch]$SkipOfficeUpdate,
    [switch]$SkipWinget,
    [switch]$SkipDrivers,
    [switch]$SkipGLPI,
    [switch]$SkipProfiles,
    [switch]$SkipCleanup,
    [switch]$NoReboot,
    [int]$ProfileAgeMonths = 6,
    [int]$GLPITimeoutSeconds = 300
)

# ── Auto-elevacao ────────────────────────────────────────────
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")

if (-not $IsAdmin) {
    $Argumentos = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`""
    )

    foreach ($Parametro in $PSBoundParameters.Keys) {
        $Valor = $PSBoundParameters[$Parametro]

        if ($Valor -is [switch] -or $Valor -eq $true) {
            $Argumentos += "-$Parametro"
        }
        else {
            $Argumentos += "-$Parametro"
            $Argumentos += "$Valor"
        }
    }

    Start-Process PowerShell -Verb RunAs -ArgumentList $Argumentos
    exit
}

# ============================================================
# LOG ESTRUTURADO
# ============================================================

$BaseLog = "C:\Users\Public\Documents\Logs\Preventiva"
if (!(Test-Path $BaseLog)) {
    New-Item -ItemType Directory -Path $BaseLog -Force | Out-Null
}

$Data = Get-Date -Format "yyyy-MM-dd_HH-mm"
$LogFile = Join-Path $BaseLog "preventiva_$env:COMPUTERNAME`_$Data.log"

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mensagem,

        [ValidateSet("INFO", "OK", "ERRO", "ALERTA")]
        [string]$Nivel = "INFO"
    )

    $Linha = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Nivel] $Mensagem"
    Add-Content -Path $LogFile -Value $Linha -Encoding UTF8

    switch ($Nivel) {
        "OK"     { Write-Host $Mensagem -ForegroundColor Green }
        "ERRO"   { Write-Host $Mensagem -ForegroundColor Red }
        "ALERTA" { Write-Host $Mensagem -ForegroundColor Yellow }
        default  { Write-Host $Mensagem }
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Nome,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Acao
    )

    Write-Log "Iniciando etapa: $Nome" "INFO"

    try {
        & $Acao
        Write-Log "Etapa concluida: $Nome" "OK"
    }
    catch {
        Write-Log "Falha na etapa '$Nome': $($_.Exception.Message)" "ERRO"
    }
}

function Test-Internet {
    try {
        $Teste = Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
        return [bool]$Teste
    }
    catch {
        return $false
    }
}

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Convert-WmiDateSafe {
    param(
        [AllowNull()]
        [string]$WmiDate
    )

    if ([string]::IsNullOrWhiteSpace($WmiDate)) {
        return $null
    }

    try {
        return [Management.ManagementDateTimeConverter]::ToDateTime($WmiDate)
    }
    catch {
        return $null
    }
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [string]$SuccessMessage,
        [string]$ErrorMessage
    )

    $Process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow

    if ($Process.ExitCode -eq 0) {
        if ($SuccessMessage) { Write-Log $SuccessMessage "OK" }
    }
    else {
        $Mensagem = if ($ErrorMessage) { $ErrorMessage } else { "Comando retornou codigo $($Process.ExitCode): $FilePath" }
        Write-Log $Mensagem "ALERTA"
    }
}

function Invoke-ProcessWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [int]$TimeoutSeconds = 300,

        [string]$StepName = "Processo"
    )

    $Process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -NoNewWindow
    $Finished = $Process.WaitForExit($TimeoutSeconds * 1000)

    if (-not $Finished) {
        Write-Log "$StepName excedeu o timeout de $TimeoutSeconds segundos. Encerrando processo..." "ALERTA"
        try {
            Stop-Process -Id $Process.Id -Force -ErrorAction Stop
            Write-Log "$StepName encerrado por timeout" "ALERTA"
        }
        catch {
            Write-Log "Nao foi possivel encerrar $StepName: $($_.Exception.Message)" "ERRO"
        }
        return $false
    }

    if ($Process.ExitCode -eq 0) {
        Write-Log "$StepName finalizado com sucesso" "OK"
        return $true
    }

    Write-Log "$StepName finalizado com codigo $($Process.ExitCode)" "ALERTA"
    return $false
}

function Get-WindowsActivationStatus {
    try {
        $Status = cscript //nologo "$env:windir\System32\slmgr.vbs" /xpr 2>&1 | Out-String

        if ($Status -match "permanently activated|ativad[oa] permanentemente|permanente") {
            $script:Status_Windows = "OK"
            Write-Log "Windows ativado" "OK"
        }
        elseif ($Status -match "notification|not activated|nao esta ativado|não está ativado|expir") {
            $script:Status_Windows = "ALERTA"
            Write-Log "Windows possivelmente nao ativado: $($Status.Trim())" "ALERTA"
        }
        else {
            $script:Status_Windows = "VERIFICAR"
            Write-Log "Nao foi possivel confirmar ativacao do Windows. Retorno: $($Status.Trim())" "ALERTA"
        }
    }
    catch {
        $script:Status_Windows = "ERRO"
        throw
    }
}

function Get-OfficeActivationStatus {
    $script:Office_Ativado = "NAO"

    $OSPPPaths = @(
        "C:\Program Files\Microsoft Office\Office16\OSPP.VBS",
        "C:\Program Files (x86)\Microsoft Office\Office16\OSPP.VBS",
        "C:\Program Files\Microsoft Office\root\Office16\OSPP.VBS",
        "C:\Program Files (x86)\Microsoft Office\root\Office16\OSPP.VBS"
    )

    $EncontrouOffice = $false

    foreach ($Path in $OSPPPaths) {
        if (Test-Path $Path) {
            $EncontrouOffice = $true
            $Status = cscript //nologo $Path /dstatus 2>&1 | Out-String

            if ($Status -match "LICENSE STATUS:\s+---LICENSED---|STATUS DA LICENCA:\s+---LICENCIADO---|LICENSED") {
                $script:Office_Ativado = "SIM"
                break
            }
        }
    }

    if (-not $EncontrouOffice) {
        Write-Log "Office nao encontrado nos caminhos padrao do OSPP.VBS" "ALERTA"
    }
    else {
        Write-Log "Office ativado: $script:Office_Ativado" "INFO"
    }
}

function Set-LocalAdministrator {
    if ($SkipAdmin) {
        Write-Log "Etapa Administrador ignorada por parametro" "ALERTA"
        $script:Status_Admin = "IGNORADO"
        return
    }

    $script:Status_Admin = "ERRO"

    $AdminAccount = Get-LocalUser | Where-Object { $_.SID -like "S-1-5-*-500" } | Select-Object -First 1

    if (-not $AdminAccount) {
        Write-Log "Conta Administrador local nao encontrada" "ERRO"
        return
    }

    if (-not $AdminAccount.Enabled) {
        Enable-LocalUser -Name $AdminAccount.Name
        Write-Log "Conta Administrador habilitada: $($AdminAccount.Name)" "OK"
    }
    else {
        Write-Log "Conta Administrador ja estava habilitada: $($AdminAccount.Name)" "INFO"
    }

    $Senha = Read-Host "Digite a nova senha do Administrador local" -AsSecureString

    try {
        Set-LocalUser -Name $AdminAccount.Name -Password $Senha
        $script:Status_Admin = "OK"
        Write-Log "Senha do Administrador local atualizada" "OK"
    }
    finally {
        if ($Senha) { $Senha.Dispose() }
    }
}

function Invoke-WindowsUpdateStep {
    if ($SkipWindowsUpdate) {
        Write-Log "Windows Update ignorado por parametro" "ALERTA"
        return
    }

    if (-not $script:InternetOK) {
        Write-Log "Windows Update ignorado: sem internet" "ALERTA"
        return
    }

    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Write-Log "Instalando provider NuGet..." "INFO"
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        }

        $Repositorio = Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue
        if ($Repositorio -and $Repositorio.InstallationPolicy -ne "Trusted") {
            Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
        }

        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-Log "Instalando modulo PSWindowsUpdate..." "INFO"
            Install-Module PSWindowsUpdate -Force -AllowClobber -Confirm:$false -Scope AllUsers
        }

        Import-Module PSWindowsUpdate -Force

        Write-Log "Procurando e instalando atualizacoes do Windows..." "INFO"
        Get-WindowsUpdate -MicrosoftUpdate -Install -AcceptAll -IgnoreReboot -ErrorAction Stop | Out-String | ForEach-Object {
            if ($_.Trim()) { Write-Log $_.Trim() "INFO" }
        }
    }
    catch {
        Write-Log "Falha via PSWindowsUpdate. Tentando iniciar busca pelo UsoClient..." "ALERTA"
        try {
            if (Test-CommandExists "UsoClient.exe") {
                Start-Process UsoClient.exe -ArgumentList "StartScan" -NoNewWindow
                Start-Process UsoClient.exe -ArgumentList "StartDownload" -NoNewWindow
                Start-Process UsoClient.exe -ArgumentList "StartInstall" -NoNewWindow
                Write-Log "UsoClient acionado para Windows Update" "OK"
            }
            else {
                throw "UsoClient.exe nao encontrado"
            }
        }
        catch {
            Write-Log "Erro Windows Update: $($_.Exception.Message)" "ERRO"
        }
    }
}

function Invoke-OfficeUpdateStep {
    if ($SkipOfficeUpdate) {
        Write-Log "Office Update ignorado por parametro" "ALERTA"
        return
    }

    $OfficeC2RPaths = @(
        "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe",
        "C:\Program Files (x86)\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
    )

    $OfficeC2R = $OfficeC2RPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($OfficeC2R) {
        Write-Log "Atualizando Office Click-to-Run..." "INFO"
        Invoke-NativeCommand -FilePath $OfficeC2R -Arguments @("/update", "user", "displaylevel=false", "forceappshutdown=true") -SuccessMessage "Office Update acionado" -ErrorMessage "Office Update retornou erro"
    }
    else {
        Write-Log "OfficeC2RClient.exe nao encontrado" "ALERTA"
    }
}

function Invoke-WingetStep {
    if ($SkipWinget) {
        Write-Log "Winget ignorado por parametro" "ALERTA"
        return
    }

    if (-not $script:InternetOK) {
        Write-Log "Winget ignorado: sem internet" "ALERTA"
        return
    }

    if (-not (Test-CommandExists "winget")) {
        Write-Log "Winget nao encontrado. Verifique o App Installer/Microsoft Store" "ALERTA"
        return
    }

    Write-Log "Atualizando fontes do Winget..." "INFO"
    try {
        winget source update | Out-String | ForEach-Object {
            if ($_.Trim()) { Write-Log $_.Trim() "INFO" }
        }
    }
    catch {
        Write-Log "Nao foi possivel atualizar fontes do Winget: $($_.Exception.Message)" "ALERTA"
    }

    Write-Log "Executando Winget upgrade --all..." "INFO"
    try {
        winget upgrade --all --silent --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-String | ForEach-Object {
            if ($_.Trim()) { Write-Log $_.Trim() "INFO" }
        }
        Write-Log "Winget finalizado" "OK"
    }
    catch {
        Write-Log "Erro Winget: $($_.Exception.Message)" "ERRO"
    }
}

function Invoke-DriverUpdateStep {
    if ($SkipDrivers) {
        Write-Log "Atualizacao de drivers ignorada por parametro" "ALERTA"
        return
    }

    $Fabricante = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    Write-Log "Fabricante: $Fabricante" "INFO"

    if ($Fabricante -like "*Lenovo*") {
        $LenovoPaths = @(
            "C:\Program Files (x86)\Lenovo\System Update\tvsu.exe",
            "C:\Program Files\Lenovo\System Update\tvsu.exe"
        )

        $Lenovo = $LenovoPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($Lenovo) {
            Write-Log "Executando Lenovo System Update..." "INFO"
            Invoke-NativeCommand -FilePath $Lenovo -Arguments @("/CM", "-search", "A", "-action", "INSTALL", "-noicon", "-includerebootpackages", "3") -SuccessMessage "Lenovo System Update finalizado" -ErrorMessage "Lenovo System Update retornou erro"
        }
        else {
            Write-Log "Lenovo System Update nao encontrado. Instale manualmente ou via pacote homologado" "ALERTA"
        }
    }
    elseif ($Fabricante -like "*Dell*") {
        $DellPaths = @(
            "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe",
            "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe"
        )

        $Dell = $DellPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($Dell) {
            Write-Log "Executando Dell Command Update..." "INFO"
            Invoke-NativeCommand -FilePath $Dell -Arguments @("/applyUpdates", "-silent") -SuccessMessage "Dell Command Update finalizado" -ErrorMessage "Dell Command Update retornou erro"
        }
        else {
            Write-Log "Dell Command Update nao encontrado. Instale manualmente ou via pacote homologado" "ALERTA"
        }
    }
    else {
        Write-Log "Fabricante sem rotina automatizada de drivers neste script" "ALERTA"
    }
}

function Invoke-GLPIStep {
    if ($SkipGLPI) {
        Write-Log "GLPI ignorado por parametro" "ALERTA"
        return
    }

    $GLPIService = Get-Service -Name "glpi-agent" -ErrorAction SilentlyContinue

    if (-not $GLPIService) {
        Write-Log "GLPI Agent nao instalado" "ALERTA"
        return
    }

    Write-Log "GLPI Agent instalado" "OK"

    if ($GLPIService.Status -ne "Running") {
        Start-Service -Name "glpi-agent"
        Write-Log "Servico GLPI Agent iniciado" "OK"
    }

    $GLPIExePaths = @(
        "C:\Program Files\GLPI-Agent\glpi-agent.exe",
        "C:\Program Files (x86)\GLPI-Agent\glpi-agent.exe"
    )

    $GLPIExe = $GLPIExePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($GLPIExe) {
        Write-Log "Forcando inventario GLPI com timeout de $GLPITimeoutSeconds segundos..." "INFO"
        Invoke-ProcessWithTimeout -FilePath $GLPIExe -Arguments @("--force") -TimeoutSeconds $GLPITimeoutSeconds -StepName "Inventario GLPI"
    }
    else {
        Write-Log "Executavel do GLPI Agent nao encontrado" "ALERTA"
    }
}

function Remove-OldProfilesStep {
    if ($SkipProfiles) {
        Write-Log "Limpeza de perfis ignorada por parametro" "ALERTA"
        return
    }

    $UsuarioAtual = $env:USERNAME
    $Limite = (Get-Date).AddMonths(-$ProfileAgeMonths)
    $PerfisCandidatos = @()

    $Perfis = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.Special -eq $false -and
        $_.Loaded -eq $false -and
        $_.LocalPath -like "C:\Users\*" -and
        $_.LocalPath -notmatch "\\Administrador$" -and
        $_.LocalPath -notmatch "\\Administrator$" -and
        $_.LocalPath -notmatch "\\Default" -and
        $_.LocalPath -notmatch "\\Public" -and
        $_.LocalPath -notmatch "\\$UsuarioAtual$"
    }

    foreach ($Perfil in $Perfis) {
        $UltimoUso = Convert-WmiDateSafe -WmiDate $Perfil.LastUseTime

        if (-not $UltimoUso) {
            Write-Log "Perfil ignorado por LastUseTime invalido ou vazio: $($Perfil.LocalPath)" "ALERTA"
            continue
        }

        if ($UltimoUso -lt $Limite) {
            $PerfisCandidatos += [PSCustomObject]@{
                PerfilObj = $Perfil
                Usuario   = $Perfil.LocalPath
                UltimoUso = $UltimoUso
                Carregado = $Perfil.Loaded
            }
        }
    }

    if (-not $PerfisCandidatos -or $PerfisCandidatos.Count -eq 0) {
        Write-Log "Nenhum perfil sem login ha mais de $ProfileAgeMonths meses encontrado para remocao" "OK"
        return
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "PERFIS QUE PODEM SER REMOVIDOS" -ForegroundColor Yellow
    Write-Host "Critério: usuarios sem login ha mais de $ProfileAgeMonths meses" -ForegroundColor Yellow
    Write-Host "Data limite: $($Limite.ToString('dd/MM/yyyy HH:mm'))" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow

    $PerfisCandidatos |
        Select-Object Usuario, UltimoUso, Carregado |
        Sort-Object UltimoUso |
        Format-Table -AutoSize

    Write-Log "Perfis candidatos a remocao:" "ALERTA"
    foreach ($Item in ($PerfisCandidatos | Sort-Object UltimoUso)) {
        Write-Log "Candidato: $($Item.Usuario) | Ultimo uso: $($Item.UltimoUso) | Carregado: $($Item.Carregado)" "ALERTA"
    }

    Write-Host ""
    Write-Host "ATENCAO: revise a lista acima antes de confirmar." -ForegroundColor Red
    Write-Host "A remocao apagará o perfil local do Windows, incluindo arquivos locais do usuario." -ForegroundColor Red
    Write-Host ""

    $Confirmacao = Read-Host "Digite APAGAR para confirmar a remocao desses perfis ou qualquer outra coisa para cancelar"

    if ($Confirmacao -ne "APAGAR") {
        Write-Log "Remocao de perfis cancelada pelo tecnico" "ALERTA"
        return
    }

    foreach ($Item in $PerfisCandidatos) {
        $Perfil = $Item.PerfilObj

        try {
            if ($PSCmdlet.ShouldProcess($Perfil.LocalPath, "Remover perfil sem login ha mais de $ProfileAgeMonths meses")) {
                Remove-CimInstance $Perfil -ErrorAction Stop
                Write-Log "Perfil removido: $($Perfil.LocalPath) | Ultimo uso: $($Item.UltimoUso)" "OK"
            }
        }
        catch {
            Write-Log "Erro ao remover perfil $($Perfil.LocalPath): $($_.Exception.Message)" "ERRO"
        }
    }
}

function Invoke-CleanupStep {
    if ($SkipCleanup) {
        Write-Log "Limpeza de disco ignorada por parametro" "ALERTA"
        return
    }

    Write-Log "Executando limpeza de temporarios..." "INFO"

    $TempPaths = @(
        "C:\Windows\Temp\*",
        "$env:TEMP\*"
    )

    foreach ($Path in $TempPaths) {
        try {
            Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Temporarios limpos: $Path" "OK"
        }
        catch {
            Write-Log "Falha ao limpar $Path: $($_.Exception.Message)" "ALERTA"
        }
    }

    Write-Log "Executando DISM StartComponentCleanup..." "INFO"
    Invoke-NativeCommand -FilePath "Dism.exe" -Arguments @("/online", "/Cleanup-Image", "/StartComponentCleanup", "/Quiet") -SuccessMessage "Limpeza de componentes concluida" -ErrorMessage "DISM retornou erro na limpeza de componentes"

    $OSInfo = Get-CimInstance Win32_OperatingSystem
    $BuildNumber = [int]$OSInfo.BuildNumber
    $Caption = $OSInfo.Caption

    if ($Caption -like "*Windows 11*" -and $BuildNumber -ge 22621) {
        Write-Log "Nota: CleanMgr pode nao executar corretamente em Windows 11 22H2+; limpeza principal ja foi feita via temporarios e DISM" "ALERTA"
    }

    $CleanMgr = Join-Path $env:windir "System32\cleanmgr.exe"
    if (Test-Path $CleanMgr) {
        Write-Log "Executando CleanMgr /verylowdisk..." "INFO"
        try {
            Start-Process -FilePath $CleanMgr -ArgumentList "/verylowdisk" -Wait -NoNewWindow
            Write-Log "CleanMgr finalizado" "OK"
        }
        catch {
            Write-Log "CleanMgr falhou: $($_.Exception.Message)" "ALERTA"
        }
    }
    else {
        Write-Log "CleanMgr nao encontrado neste Windows. Use Storage Sense/Storage Settings manualmente se necessario" "ALERTA"
    }
}

function Test-PendingReboot {
    $RebootKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    )

    if (Test-Path $RebootKeys[0]) { return $true }
    if (Test-Path $RebootKeys[1]) { return $true }

    try {
        $PendingFileRename = Get-ItemProperty -Path $RebootKeys[2] -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($PendingFileRename) { return $true }
    }
    catch { }

    return $false
}

# ============================================================
# INICIO
# ============================================================

Write-Log "===== INICIO DA PREVENTIVA =====" "INFO"

$Hostname = $env:COMPUTERNAME
$script:Status_Admin = "NAO EXECUTADO"
$script:Status_Windows = "NAO VERIFICADO"
$script:Office_Ativado = "NAO VERIFICADO"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PREVENTIVA CORPORATIVA" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "HOSTNAME: $Hostname" -ForegroundColor Yellow
Write-Host "Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor Gray
Write-Host "Log: $LogFile" -ForegroundColor Gray
Write-Host "Remocao de perfis: usuarios sem login ha mais de $ProfileAgeMonths meses" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$script:InternetOK = Test-Internet
if ($script:InternetOK) {
    Write-Log "Conectividade com a internet OK" "OK"
}
else {
    Write-Log "Sem acesso a internet. Etapas online podem ser ignoradas ou falhar" "ALERTA"
}

Invoke-Step -Nome "Administrador local" -Acao { Set-LocalAdministrator }
Invoke-Step -Nome "Status de ativacao do Windows" -Acao { Get-WindowsActivationStatus }
Invoke-Step -Nome "Status de ativacao do Office" -Acao { Get-OfficeActivationStatus }
Invoke-Step -Nome "Windows Update" -Acao { Invoke-WindowsUpdateStep }
Invoke-Step -Nome "Office Update" -Acao { Invoke-OfficeUpdateStep }
Invoke-Step -Nome "Atualizacao de softwares via Winget" -Acao { Invoke-WingetStep }
Invoke-Step -Nome "Atualizacao de drivers" -Acao { Invoke-DriverUpdateStep }
Invoke-Step -Nome "GLPI Agent" -Acao { Invoke-GLPIStep }
Invoke-Step -Nome "Limpeza de perfis antigos" -Acao { Remove-OldProfilesStep }
Invoke-Step -Nome "Limpeza de disco" -Acao { Invoke-CleanupStep }

# ============================================================
# CHECKLIST FINAL
# ============================================================

Write-Log "===== CHECKLIST FINAL =====" "INFO"

Write-Host ""
Write-Host "STATUS FINAL" -ForegroundColor Cyan
Write-Host "Windows: $script:Status_Windows"
Write-Host "Office: $script:Office_Ativado"
Write-Host "Admin: $script:Status_Admin"
Write-Host "Log: $LogFile"

if ($script:Status_Windows -ne "OK" -or $script:Office_Ativado -ne "SIM") {
    Write-Host ""
    Write-Host "AVISO: LICENCIAMENTO PENDENTE OU NAO CONFIRMADO (Windows/Office)" -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "LICENCIAMENTO OK" -ForegroundColor Green
}

if (Test-PendingReboot) {
    Write-Log "Reinicializacao pendente detectada" "ALERTA"
    Write-Host ""
    Write-Host "REINICIALIZACAO PENDENTE" -ForegroundColor Yellow

    if (-not $NoReboot) {
        if ((Read-Host "Deseja reiniciar agora? (S/N)") -match "^[sS]$") {
            Write-Log "Reinicio autorizado pelo tecnico" "INFO"
            Restart-Computer -Force
        }
        else {
            Write-Log "Reinicio pendente nao executado pelo tecnico" "ALERTA"
        }
    }
    else {
        Write-Log "Reinicio automatico ignorado por parametro -NoReboot" "ALERTA"
    }
}
else {
    Write-Log "Nenhuma reinicializacao pendente detectada" "OK"
}

Write-Log "===== FIM DA PREVENTIVA =====" "INFO"
