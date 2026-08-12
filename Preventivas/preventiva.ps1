# ============================================================
# AUTO-ELEVACAO
# ============================================================
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {

    Start-Process powershell `
        -Verb RunAs `
        -ArgumentList '-ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/Preventivas/preventiva.ps1 | iex"'

    return
}

# ── Forca UTF-8 para evitar mojibake na saida de comandos externos ──
chcp 65001 | Out-Null
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================
# LOGS
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

# ============================================================
# HELPERS GERAIS
# ============================================================

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
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

    $SenhasCoincidem = $false
    $Senha = $null

    while (-not $SenhasCoincidem) {
        $Senha1 = Read-Host "Digite a nova senha do Administrador local" -AsSecureString
        $Senha2 = Read-Host "Confirme a nova senha do Administrador local" -AsSecureString

        $BSTR1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Senha1)
        $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Senha2)
        $Plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)
        $Plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)

        if ($Plain1 -eq $Plain2 -and -not [string]::IsNullOrEmpty($Plain1)) {
            $SenhasCoincidem = $true
            $Senha = $Senha1
        } else {
            Write-Host "As senhas nao coincidem ou estao vazias! Tente novamente.`n" -ForegroundColor Red
        }
    }

    try {
        Set-LocalUser -Name $AdminAccount.Name -Password $Senha
        $script:Status_Admin = "OK"
        Write-Log "Senha do Administrador local atualizada" "OK"
    }
    catch {
        Write-Log "Erro ao definir senha do Administrador: $($_.Exception.Message)" "ERRO"
    }
    finally {
        if ($Senha) { $Senha.Dispose() }
    }
}

# ── Windows Update agora e 100% manual: abre a tela nativa e pausa
# ate o tecnico confirmar que verificou/baixou tudo (inclusive
# opcionais). Substitui toda a automacao via PSWindowsUpdate ──
function Invoke-WindowsUpdateStep {
    if ($SkipWindowsUpdate) {
        Write-Log "Windows Update ignorado por parametro" "ALERTA"
        $script:Status_WindowsUpdate = "IGNORADO"
        return
    }

    Write-Log "Abrindo tela do Windows Update para verificacao manual..." "INFO"

    try {
        Start-Process "ms-settings:windowsupdate"
        Write-Log "Tela do Windows Update aberta" "OK"
    }
    catch {
        Write-Log "Nao foi possivel abrir a tela do Windows Update: $($_.Exception.Message)" "ERRO"
        $script:Status_WindowsUpdate = "ERRO AO ABRIR"
        return
    }

    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "WINDOWS UPDATE - ACAO MANUAL" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "Verifique, baixe e instale as atualizacoes (inclusive as opcionais)." -ForegroundColor Gray
    Read-Host "Pressione ENTER quando terminar para continuar a preventiva"

    Write-Log "Windows Update concluido manualmente pelo tecnico" "OK"
    $script:Status_WindowsUpdate = "CONCLUIDO (MANUAL)"
}

# ── Office Update agora e manual: abre o Excel e o tecnico atualiza
# por Arquivo > Conta > Opcoes de Atualizacao > Atualizar Agora ──
function Invoke-OfficeUpdateStep {
    if ($SkipOfficeUpdate) {
        Write-Log "Office Update ignorado por parametro" "ALERTA"
        $script:Status_Office = "IGNORADO"
        return
    }

    $AppPathKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\EXCEL.EXE"
    $ExcelPath  = $null

    if (Test-Path $AppPathKey) {
        $ExcelPath = (Get-ItemProperty -Path $AppPathKey -ErrorAction SilentlyContinue).'(default)'
    }

    if (-not $ExcelPath -or -not (Test-Path $ExcelPath)) {
        Write-Log "Excel nao encontrado nesta maquina. Etapa de Office Update pulada" "ALERTA"
        $script:Status_Office = "NAO INSTALADO"
        return
    }

    Write-Log "Abrindo Excel para atualizacao manual do Office..." "INFO"
    Start-Process -FilePath $ExcelPath

    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "OFFICE UPDATE - ACAO MANUAL" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "No Excel: Arquivo > Conta > Opcoes de Atualizacao > Atualizar Agora." -ForegroundColor Gray
    Read-Host "Pressione ENTER quando terminar (pode fechar o Excel) para continuar"

    Write-Log "Office Update concluido manualmente pelo tecnico" "OK"
    $script:Status_Office = "CONCLUIDO (MANUAL)"
}

function Invoke-WingetStep {
    if ($SkipWinget) {
        Write-Log "Winget ignorado por parametro" "ALERTA"
        $script:Status_Winget = "IGNORADO"
        return
    }

    if (-not (Test-CommandExists "winget")) {
        Write-Log "Winget NAO esta instalado nesta maquina (App Installer ausente). Verifique a Microsoft Store" "ERRO"
        $script:Status_Winget = "NAO INSTALADO"
        return
    }

    try {
        $WingetVersao = (winget --version 2>&1 | Out-String).Trim()
        Write-Log "Winget instalado e validado. Versao: $WingetVersao" "OK"
        $script:Status_Winget = "OK ($WingetVersao)"
    }
    catch {
        Write-Log "Winget foi encontrado no PATH, mas nao respondeu corretamente: $($_.Exception.Message)" "ALERTA"
        $script:Status_Winget = "RESPOSTA INVALIDA"
    }

    # ── Primeiro uso do winget na maquina exige aceite dos termos de licenca.
    # Sem essa flag em TODAS as chamadas (nao so na instalacao final), o
    # comando fica esperando aceite interativo que nunca chega e trava/falha ──
    Write-Log "Atualizando fontes do Winget (com aceite automatico de termos)..." "INFO"
    try {
        winget source update --accept-source-agreements | Out-Null
    }
    catch {
        Write-Log "Nao foi possivel atualizar fontes do Winget" "ALERTA"
    }

    Write-Log "Verificando aplicacoes pendentes de atualizacao..." "INFO"

    $ListaUpgrades = winget upgrade --accept-source-agreements | Out-String

    if ($ListaUpgrades -match "Nenhuma atualização encontrada" -or $ListaUpgrades -match "No updates found" -or [string]::IsNullOrWhiteSpace($ListaUpgrades)) {
        Write-Log "Todos os programas do Winget estao atualizados." "OK"
        return
    }

    Write-Host "`n=== ATUALIZACOES ENCONTRADAS PELO WINGET ===" -ForegroundColor Yellow
    Write-Host $ListaUpgrades
    Write-Host "===========================================" -ForegroundColor Yellow

    $Confirmacao = Read-Host "Deseja aplicar TODAS as atualizacoes listadas acima? (S/N)"

    if ($Confirmacao -match "^[sS]$") {
        Write-Log "Executando Winget upgrade --all..." "INFO"
        try {
            winget upgrade --all --accept-package-agreements --accept-source-agreements | Out-String | ForEach-Object {
                if ($_.Trim()) { Write-Log $_.Trim() "INFO" }
            }
            Write-Log "Winget finalizado com sucesso" "OK"
        }
        catch {
            Write-Log "Erro ao aplicar atualizacoes do Winget: $($_.Exception.Message)" "ERRO"
        }
    } else {
        Write-Log "Atualizacao do Winget abortada intencionalmente pelo tecnico" "ALERTA"
    }
}

function Invoke-DriverUpdateStep {
    if ($SkipDrivers) {
        Write-Log "Atualizacao de drivers ignorada por parametro" "ALERTA"
        return
    }

    $Fabricante = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    Write-Log "Fabricante: $Fabricante" "INFO"

    $NomeFerramenta = switch -Wildcard ($Fabricante) {
        "*Dell*"   { "Dell Command | Update" }
        "*Lenovo*" { "Lenovo Vantage / System Update" }
        default    { $null }
    }

    if (-not $NomeFerramenta) {
        Write-Log "Fabricante '$Fabricante' sem ferramenta de driver conhecida. Etapa pulada" "ALERTA"
        return
    }

    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "ATUALIZACAO DE DRIVERS - ACAO MANUAL" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "Abra '$NomeFerramenta' pelo Menu Iniciar e aplique as atualizacoes de driver disponiveis." -ForegroundColor Gray
    Read-Host "Pressione ENTER quando terminar (ou se a ferramenta nao estiver instalada) para continuar"

    Write-Log "Atualizacao de drivers concluida manualmente pelo tecnico ($NomeFerramenta)" "OK"
}

function Invoke-GLPIStep {
    if ($SkipGLPI) {
        Write-Log "GLPI ignorado por parametro" "ALERTA"
        return
    }

    $GLPIService = Get-Service -Name "glpi-agent" -ErrorAction SilentlyContinue

    if (-not $GLPIService) {
        Write-Log "GLPI Agent nao instalado nesta maquina" "ALERTA"
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

    if (-not $GLPIExe) {
        Write-Log "Executavel do GLPI Agent nao encontrado" "ALERTA"
        return
    }

    Write-Log "Abrindo console para forcar inventario GLPI manualmente..." "INFO"
    Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoExit", "-Command", "& '$GLPIExe' --force")

    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "GLPI AGENT - ACAO MANUAL" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "Confirme no console que o inventario foi enviado, depois feche a janela." -ForegroundColor Gray
    Read-Host "Pressione ENTER quando terminar para continuar"

    Write-Log "Inventario GLPI concluido manualmente pelo tecnico" "OK"
}

# ── Limpeza de disco agora e manual: abre o Cleanmgr (ou a tela de
# Armazenamento como fallback) e pausa ate o tecnico confirmar ──
function Invoke-CleanupStep {
    if ($SkipCleanup) {
        Write-Log "Limpeza de disco ignorada por parametro" "ALERTA"
        return
    }

    Write-Log "Abrindo Limpeza de Disco para execucao manual..." "INFO"

    $CleanMgr = Join-Path $env:windir "System32\cleanmgr.exe"

    try {
        if (Test-Path $CleanMgr) {
            Start-Process -FilePath $CleanMgr
            Write-Log "Cleanmgr aberto" "OK"
        }
        else {
            Start-Process "ms-settings:storagesense"
            Write-Log "Cleanmgr nao encontrado; tela de Armazenamento aberta como alternativa" "ALERTA"
        }
    }
    catch {
        Write-Log "Nao foi possivel abrir a limpeza de disco: $($_.Exception.Message)" "ERRO"
        return
    }

    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "LIMPEZA DE DISCO - ACAO MANUAL" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "Selecione os itens e limpe manualmente." -ForegroundColor Gray
    Read-Host "Pressione ENTER quando terminar para continuar a preventiva"

    Write-Log "Limpeza de disco concluida manualmente pelo tecnico" "OK"
}

# ============================================================
# INICIO DO FLUXO PRINCIPAL
# ============================================================

Write-Log "===== INICIO DA PREVENTIVA =====" "INFO"

$Hostname = $env:COMPUTERNAME
$script:Status_Admin         = "NAO EXECUTADO"
$script:Status_Windows       = "NAO VERIFICADO"
$script:Status_WindowsUpdate = "NAO VERIFICADO"
$script:Status_Winget        = "NAO VERIFICADO"
$script:Status_Office        = "NAO VERIFICADO"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PREVENTIVA CORPORATIVA" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "HOSTNAME: $Hostname" -ForegroundColor Yellow
Write-Host "Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor Gray
Write-Host "Log: $LogFile" -ForegroundColor Gray
Write-Host "Windows Update, Office Update, Drivers, GLPI e Limpeza de Disco: etapas manuais" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Invoke-Step -Nome "Administrador local" -Acao { Set-LocalAdministrator }
Invoke-Step -Nome "Status de ativacao do Windows" -Acao { Get-WindowsActivationStatus }
Invoke-Step -Nome "Windows Update" -Acao { Invoke-WindowsUpdateStep }
Invoke-Step -Nome "Office Update" -Acao { Invoke-OfficeUpdateStep }
Invoke-Step -Nome "Atualizacao de softwares via Winget" -Acao { Invoke-WingetStep }
Invoke-Step -Nome "Atualizacao de drivers" -Acao { Invoke-DriverUpdateStep }
Invoke-Step -Nome "GLPI Agent" -Acao { Invoke-GLPIStep }
Invoke-Step -Nome "Limpeza de disco" -Acao { Invoke-CleanupStep }

# ============================================================
# CHECKLIST FINAL
# ============================================================

Write-Log "===== CHECKLIST FINAL =====" "INFO"

Write-Host ""
Write-Host "STATUS FINAL" -ForegroundColor Cyan
Write-Host "Windows: $script:Status_Windows"
Write-Host "Office: $script:Status_Office"
Write-Host "Admin: $script:Status_Admin"
Write-Host "Windows Update: $script:Status_WindowsUpdate"
Write-Host "Winget: $script:Status_Winget"
Write-Host "Log: $LogFile"

if ($script:Status_Windows -ne "OK") {
    Write-Host ""
    Write-Host "AVISO: LICENCIAMENTO DO WINDOWS PENDENTE OU NAO CONFIRMADO" -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "LICENCIAMENTO OK" -ForegroundColor Green
}

Write-Log "===== FIM DA PREVENTIVA =====" "INFO"
