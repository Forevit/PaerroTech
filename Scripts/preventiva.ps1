# ============================================================
#  PREVENTIVA CORPORATIVA - PADRONIZAÇÃO DE MÁQUINA
#  By Eduardo Ferreira
# ============================================================

# ── Auto-elevação ────────────────────────────────────────────
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process PowerShell -Verb RunAs "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# ============================================================
# LOG
# ============================================================

$BaseLog = "C:\Users\Public\Documents\Logs\Preventiva"
if (!(Test-Path $BaseLog)) {
    New-Item -ItemType Directory -Path $BaseLog -Force | Out-Null
}

$Data = Get-Date -Format "yyyy-MM-dd_HH-mm"
$LogFile = "$BaseLog\preventiva_$Data.txt"

Start-Transcript -Path $LogFile -Append

Write-Host "Iniciando preventiva..." -ForegroundColor Cyan

# ============================================================
# 1. ADMINISTRADOR LOCAL
# ============================================================

$Status_Admin = "ERRO"

try {
    net user Administrador /active:yes

    $Senha = Read-Host "Digite a nova senha do Administrador" -AsSecureString
    $SenhaPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Senha)
    )

    net user Administrador $SenhaPlain

    $Status_Admin = "OK"
    Write-Host "Administrador configurado." -ForegroundColor Green
} catch {
    Write-Host "Erro ao configurar Administrador." -ForegroundColor Red
}

# ============================================================
# 2. ATIVAÇÃO DO WINDOWS
# ============================================================

$Status_Windows = "ERRO"

$WindowsAtivo = (cscript //nologo C:\Windows\System32\slmgr.vbs /xpr)

if ($WindowsAtivo -match "permanently activated") {
    $Status_Windows = "OK"
}

Write-Output $WindowsAtivo

# ============================================================
# 3. OFFICE
# ============================================================

$Office_Status = "NÃO INSTALADO"
$Office_Tipo = "DESCONHECIDO"
$Office_Ativado = "NÃO"

$OfficeReg = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* ,
                             HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
                             -ErrorAction SilentlyContinue |
Where-Object { $_.DisplayName -like "*Office*" }

if ($OfficeReg) {
    $Office_Status = "INSTALADO"
}

$C2R = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
if ($C2R) {
    $Office_Tipo = "Microsoft 365 / Click-to-Run"
}

$OSPPPaths = @(
    "C:\Program Files\Microsoft Office\Office16\OSPP.VBS",
    "C:\Program Files (x86)\Microsoft Office\Office16\OSPP.VBS",
    "C:\Program Files\Microsoft Office\root\Office16\OSPP.VBS",
    "C:\Program Files (x86)\Microsoft Office\root\Office16\OSPP.VBS"
)

foreach ($path in $OSPPPaths) {
    if (Test-Path $path) {
        $status = cscript //nologo $path /dstatus

        if ($status -match "LICENSE STATUS:\s+---LICENSED---") {
            $Office_Ativado = "SIM"
        }
        elseif ($status -match "NOTIFICATIONS") {
            $Office_Ativado = "IRREGULAR"
        }
    }
}

# ============================================================
# 4. WINDOWS UPDATE
# ============================================================

$Status_Update = "OK"

try {
    Install-Module PSWindowsUpdate -Force -Confirm:$false -ErrorAction SilentlyContinue
    Import-Module PSWindowsUpdate
    Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot
} catch {
    $Status_Update = "ERRO"
}

# ============================================================
# 5. OFFICE UPDATE
# ============================================================

try {
    $OfficeC2R = "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"

    if (Test-Path $OfficeC2R) {
        Start-Process $OfficeC2R -ArgumentList "/update user displaylevel=false forceappshutdown=true" -Wait
    }
} catch {}

# ============================================================
# 6. WINGET
# ============================================================

try {
    winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
} catch {}

# ============================================================
# 7. DRIVERS
# ============================================================

$Lenovo = "C:\Program Files (x86)\Lenovo\System Update\tvsu.exe"
if (Test-Path $Lenovo) {
    Start-Process $Lenovo -ArgumentList "/CM -search A -action INSTALL -noicon -includerebootpackages 3" -Wait
}

$Dell = "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe"
if (Test-Path $Dell) {
    Start-Process $Dell -ArgumentList "/applyUpdates -silent" -Wait
}

# ============================================================
# 8. GLPI AGENT
# ============================================================

$GLPI_Status = "NÃO INSTALADO"
$GLPI_Servico = "INEXISTENTE"
$GLPI_Comunicacao = "FALHA"

$GLPIService = Get-Service -Name "glpi-agent" -ErrorAction SilentlyContinue

if ($GLPIService) {
    $GLPI_Status = "INSTALADO"

    if ($GLPIService.Status -eq "Running") {
        $GLPI_Servico = "RODANDO"
    } else {
        Start-Service glpi-agent
        Start-Sleep 3

        if ((Get-Service glpi-agent).Status -eq "Running") {
            $GLPI_Servico = "INICIADO"
        } else {
            $GLPI_Servico = "ERRO"
        }
    }

    $GLPIServer = "http://suporte.paerro.tech/front/inventory.php"

    try {
        $Response = Invoke-WebRequest -Uri $GLPIServer -UseBasicParsing -TimeoutSec 10
        if ($Response.StatusCode -eq 200) {
            $GLPI_Comunicacao = "OK"
        }
    } catch {}

    $GLPIExe = "C:\Program Files\GLPI-Agent\glpi-agent.exe"
    if (Test-Path $GLPIExe) {
        & $GLPIExe --force
    }
}

# ============================================================
# 9. LIMPEZA DE USUÁRIOS (FILTRO + CONFIRMAÇÃO)
# ============================================================

$Status_Perfis = "OK"

try {
    $UsuarioAtual = $env:USERNAME

    $Perfis = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.LastUseTime -lt (Get-Date).AddDays(-90) -and
        $_.Special -eq $false -and
        $_.LocalPath -like "C:\Users\*" -and
        $_.LocalPath -notmatch "\\Administrador$" -and
        $_.LocalPath -notmatch "\\Default" -and
        $_.LocalPath -notmatch "\\Public" -and
        $_.LocalPath -notmatch "\\All Users" -and
        $_.LocalPath -notmatch "\\Default User" -and
        $_.LocalPath -notmatch "\\$UsuarioAtual$"
    }

    if ($Perfis) {
        $Lista = $Perfis | ForEach-Object {
            [PSCustomObject]@{
                Usuario   = $_.LocalPath
                UltimoUso = [Management.ManagementDateTimeConverter]::ToDateTime($_.LastUseTime)
            }
        }

        $Lista | Format-Table -AutoSize

        $Confirmacao = Read-Host "Deseja remover esses perfis? (S/N)"

        if ($Confirmacao -match "^[sS]$") {
            foreach ($Perfil in $Perfis) {
                Remove-CimInstance $Perfil
            }
        } else {
            $Status_Perfis = "CANCELADO"
        }
    }
} catch {
    $Status_Perfis = "ERRO"
}

# ============================================================
# 10. LIMPEZA DE DISCO
# ============================================================

$Status_Limpeza = "OK"

try {
    cleanmgr /sagerun:1
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    $Status_Limpeza = "ERRO"
}

# ============================================================
# CHECKLIST FINAL
# ============================================================

$Licenca_OK = $true

if ($Status_Windows -ne "OK") { $Licenca_OK = $false }
if ($Office_Ativado -ne "SIM") { $Licenca_OK = $false }

Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "CHECKLIST FINAL" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

Write-Host "Administrador: $Status_Admin"
Write-Host "Windows: $Status_Windows"
Write-Host "Office: $Office_Status | Ativado: $Office_Ativado"
Write-Host "GLPI: $GLPI_Status | Serviço: $GLPI_Servico | Comunicação: $GLPI_Comunicacao"
Write-Host "Updates: $Status_Update"
Write-Host "Perfis: $Status_Perfis"
Write-Host "Limpeza: $Status_Limpeza"

Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "LICENCIAMENTO" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

if ($Licenca_OK) {
    Write-Host "Licenciamento OK." -ForegroundColor Green
} else {
    Write-Host "PENDENTE: Ativar Windows e/ou Office." -ForegroundColor Yellow
}

Stop-Transcript