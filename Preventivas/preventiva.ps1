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
# LOG ESTRUTURADO
# ============================================================

$BaseLog = "C:\Users\Public\Documents\Logs\Preventiva"
if (!(Test-Path $BaseLog)) {
    New-Item -ItemType Directory -Path $BaseLog -Force | Out-Null
}

$Data = Get-Date -Format "yyyy-MM-dd_HH-mm"
$LogFile = "$BaseLog\preventiva_$env:COMPUTERNAME`_$Data.log"

function Write-Log {
    param(
        [string]$Mensagem,
        [string]$Nivel = "INFO"
    )

    $Linha = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Nivel] $Mensagem"
    Add-Content -Path $LogFile -Value $Linha

    switch ($Nivel) {
        "OK" { Write-Host $Mensagem -ForegroundColor Green }
        "ERRO" { Write-Host $Mensagem -ForegroundColor Red }
        "ALERTA" { Write-Host $Mensagem -ForegroundColor Yellow }
        default { Write-Host $Mensagem }
    }
}

Write-Log "===== INÍCIO DA PREVENTIVA =====" "INFO"


# ============================================================
# IDENTIFICAÇÃO DA MÁQUINA
# ============================================================

$Hostname = $env:COMPUTERNAME

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PREVENTIVA CORPORATIVA" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "HOSTNAME: $Hostname" -ForegroundColor Yellow
Write-Host "Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""


# ============================================================
# INTERNET CHECK
# ============================================================

$InternetOK = $false

try {
    Invoke-WebRequest "https://www.google.com" -TimeoutSec 5 | Out-Null
    $InternetOK = $true
    Write-Log "Conectividade com a internet OK" "OK"
} catch {
    Write-Log "Sem acesso à internet" "ALERTA"
}

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
    Write-Log "Administrador configurado" "OK"
} catch {
    Write-Log "Erro ao configurar Administrador: $_" "ERRO"
}

# ============================================================
# 2. WINDOWS STATUS
# ============================================================

$Status_Windows = "ERRO"

try {
    $WindowsAtivo = (cscript //nologo C:\Windows\System32\slmgr.vbs /xpr)

    if ($WindowsAtivo -match "permanently activated") {
        $Status_Windows = "OK"
        Write-Log "Windows ativado" "OK"
    } else {
        Write-Log "Windows não ativado" "ALERTA"
    }

    Write-Output $WindowsAtivo
} catch {
    Write-Log "Erro Windows status: $_" "ERRO"
}

# ============================================================
# 3. OFFICE
# ============================================================

$Office_Ativado = "NÃO"

try {
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
        }
    }

    Write-Log "Office status: $Office_Ativado" "INFO"

} catch {
    Write-Log "Erro Office: $_" "ERRO"
}

# ============================================================
# 4. WINDOWS UPDATE
# ============================================================

try {
    Install-Module PSWindowsUpdate -Force -Confirm:$false -ErrorAction SilentlyContinue
    Import-Module PSWindowsUpdate

    Write-Log "Executando Windows Update..." "INFO"
    Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot

    Write-Log "Windows Update concluído" "OK"
} catch {
    Write-Log "Erro Windows Update: $_" "ERRO"
}

# ============================================================
# 5. OFFICE UPDATE
# ============================================================

try {
    $OfficeC2R = "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"

    if (Test-Path $OfficeC2R) {
        Write-Log "Atualizando Office..." "INFO"
        Start-Process $OfficeC2R -ArgumentList "/update user displaylevel=false forceappshutdown=true" -Wait
    }
} catch {
    Write-Log "Erro Office Update: $_" "ERRO"
}

# ============================================================
# 6. WINGET
# ============================================================

try {
    Write-Log "Executando Winget upgrade..." "INFO"
    winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
} catch {
    Write-Log "Erro Winget: $_" "ERRO"
}

# ============================================================
# 7. DRIVERS (FABRICANTE)
# ============================================================

try {
    $Fabricante = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    Write-Log "Fabricante: $Fabricante" "INFO"

    if ($Fabricante -like "*Lenovo*") {

        $Lenovo = "C:\Program Files (x86)\Lenovo\System Update\tvsu.exe"

        if (Test-Path $Lenovo) {
            Write-Log "Executando Lenovo Update..." "INFO"
            Start-Process $Lenovo -ArgumentList "/CM -search A -action INSTALL -noicon -includerebootpackages 3" -Wait
        } else {
            Write-Log "Lenovo Update não encontrado" "ALERTA"
            if ((Read-Host "Deseja instalar Lenovo System Update? (S/N)") -match "^[sS]$") {
                Write-Log "Instalação manual necessária" "ALERTA"
            }
        }
    }

    elseif ($Fabricante -like "*Dell*") {

        $Dell = "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe"

        if (Test-Path $Dell) {
            Write-Log "Executando Dell Update..." "INFO"
            Start-Process $Dell -ArgumentList "/applyUpdates -silent" -Wait
        } else {
            Write-Log "Dell Update não encontrado" "ALERTA"
            if ((Read-Host "Deseja instalar Dell Command Update? (S/N)") -match "^[sS]$") {
                Write-Log "Instalação manual necessária" "ALERTA"
            }
        }
    }

} catch {
    Write-Log "Erro Drivers: $_" "ERRO"
}

# ============================================================
# 8. GLPI AGENT
# ============================================================

try {
    $GLPIService = Get-Service -Name "glpi-agent" -ErrorAction SilentlyContinue

    if ($GLPIService) {
        Write-Log "GLPI Agent instalado" "OK"

        if ($GLPIService.Status -ne "Running") {
            Start-Service glpi-agent
        }

        $GLPIExe = "C:\Program Files\GLPI-Agent\glpi-agent.exe"

        if (Test-Path $GLPIExe) {
            Write-Log "Forçando inventário GLPI..." "INFO"
            & $GLPIExe --force
        }
    }

} catch {
    Write-Log "Erro GLPI: $_" "ERRO"
}

# ============================================================
# 9. LIMPEZA DE PERFIS (>90 dias)
# ============================================================

try {
    $UsuarioAtual = $env:USERNAME

    $Perfis = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.LastUseTime -lt (Get-Date).AddDays(-90) -and
        $_.Special -eq $false -and
        $_.LocalPath -like "C:\Users\*" -and
        $_.LocalPath -notmatch "\\Administrador$" -and
        $_.LocalPath -notmatch "\\Default" -and
        $_.LocalPath -notmatch "\\Public" -and
        $_.LocalPath -notmatch "\\$UsuarioAtual$"
    }

    if ($Perfis) {

        $Lista = foreach ($Perfil in $Perfis) {

            $Tamanho = (Get-ChildItem $Perfil.LocalPath -Recurse -ErrorAction SilentlyContinue |
                Measure-Object Length -Sum).Sum / 1GB

            [PSCustomObject]@{
                Usuario   = $Perfil.LocalPath
                UltimoUso = [Management.ManagementDateTimeConverter]::ToDateTime($Perfil.LastUseTime)
                TamanhoGB = "{0:N2}" -f $Tamanho
            }
        }

        $Lista | Format-Table -AutoSize

        if ((Read-Host "Remover perfis antigos? (S/N)") -match "^[sS]$") {
            foreach ($Perfil in $Perfis) {
                Remove-CimInstance $Perfil
                Write-Log "Perfil removido: $($Perfil.LocalPath)" "OK"
            }
        }
    }

} catch {
    Write-Log "Erro perfis: $_" "ERRO"
}

# ============================================================
# 10. LIMPEZA DE DISCO
# ============================================================

try {
    Write-Log "Executando limpeza de disco..." "INFO"

    cleanmgr /sagerun:1
    Dism.exe /online /Cleanup-Image /StartComponentCleanup /Quiet

    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Log "Limpeza concluída" "OK"

} catch {
    Write-Log "Erro limpeza: $_" "ERRO"
}

# ============================================================
# CHECKLIST FINAL
# ============================================================

Write-Log "===== CHECKLIST FINAL =====" "INFO"

Write-Host ""
Write-Host "STATUS FINAL" -ForegroundColor Cyan
Write-Host "Windows: $Status_Windows"
Write-Host "Office: $Office_Ativado"
Write-Host "Admin: $Status_Admin"

if ($Status_Windows -ne "OK" -or $Office_Ativado -ne "SIM") {
    Write-Host ""
    Write-Host "⚠ LICENCIAMENTO PENDENTE (Windows/Office)" -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "✔ LICENCIAMENTO OK" -ForegroundColor Green
}

Write-Log "===== FIM DA PREVENTIVA =====" "INFO"