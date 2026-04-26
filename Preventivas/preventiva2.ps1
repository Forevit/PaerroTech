# ============================================================
#  PREVENTIVA CORPORATIVA - PADRONIZAÇÃO DE MÁQUINA
#  By Eduardo Ferreira
#  v2.0 — TUI, DryRun, Runspaces, Segurança, Inventário
# ============================================================

param(
    [string]$Cliente    = "",
    [string]$Tecnico    = "",
    [switch]$Silent,
    [switch]$DryRun,
    [switch]$SkipUpdates,
    [switch]$SkipCleaning
)

# ── Auto-elevação ────────────────────────────────────────────
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Cliente)     { $args += " -Cliente `"$Cliente`"" }
    if ($Tecnico)     { $args += " -Tecnico `"$Tecnico`"" }
    if ($Silent)      { $args += " -Silent" }
    if ($DryRun)      { $args += " -DryRun" }
    if ($SkipUpdates) { $args += " -SkipUpdates" }
    if ($SkipCleaning){ $args += " -SkipCleaning" }
    Start-Process PowerShell -Verb RunAs $args
    exit
}

# ============================================================
#  CONFIGURAÇÕES GLOBAIS
# ============================================================

$Script:Version   = "2.0"
$Script:StartTime = Get-Date
$Script:Hostname  = $env:COMPUTERNAME
$Script:BaseLog   = "C:\Users\Public\Documents\Logs\Preventiva"
$Script:Data      = Get-Date -Format "yyyy-MM-dd_HH-mm"
$Script:LogFile   = "$($Script:BaseLog)\preventiva_$($Script:Hostname)_$($Script:Data).log"

# Share de rede para centralizar logs (ajuste conforme ambiente)
$Script:ShareLogs = "\\servidor\Preventivas"   # deixe vazio "" para desabilitar

# Resultado acumulado de cada etapa (para o relatório final)
$Script:Resultados = [System.Collections.Generic.List[PSCustomObject]]::new()

# ============================================================
#  INICIALIZAÇÃO DO LOG
# ============================================================

if (!(Test-Path $Script:BaseLog)) {
    New-Item -ItemType Directory -Path $Script:BaseLog -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Mensagem,
        [string]$Nivel = "INFO"
    )
    $Linha = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Nivel] $Mensagem"
    Add-Content -Path $Script:LogFile -Value $Linha
}

Write-Log "===== INÍCIO DA PREVENTIVA v$($Script:Version) =====" "INFO"
Write-Log "Cliente: $Cliente | Técnico: $Tecnico | DryRun: $DryRun | Silent: $Silent" "INFO"

# ============================================================
#  TUI — INTERFACE VISUAL NO CONSOLE
# ============================================================

# Etapas definidas (ordem de exibição)
$Script:Etapas = [ordered]@{
    "Admin"      = @{ Label = "Administrador local";          Status = "AGUARD" }
    "Windows"    = @{ Label = "Licença Windows";              Status = "AGUARD" }
    "Office"     = @{ Label = "Licença Office";               Status = "AGUARD" }
    "Defender"   = @{ Label = "Windows Defender";             Status = "AGUARD" }
    "WinUpdate"  = @{ Label = "Windows Update";               Status = "AGUARD" }
    "OffUpdate"  = @{ Label = "Office Update";                Status = "AGUARD" }
    "Winget"     = @{ Label = "Winget upgrade";               Status = "AGUARD" }
    "Drivers"    = @{ Label = "Drivers do fabricante";        Status = "AGUARD" }
    "GLPI"       = @{ Label = "GLPI Agent";                   Status = "AGUARD" }
    "Perfis"     = @{ Label = "Limpeza de perfis antigos";    Status = "AGUARD" }
    "Disco"      = @{ Label = "Limpeza de disco";             Status = "AGUARD" }
    "Softwares"  = @{ Label = "Inventário de softwares";      Status = "AGUARD" }
    "Bateria"    = @{ Label = "Saúde da bateria";             Status = "AGUARD" }
    "Reboot"     = @{ Label = "Reboot pendente";              Status = "AGUARD" }
    "Usuarios"   = @{ Label = "Auditoria de usuários";        Status = "AGUARD" }
}

$Script:TUI_StartLine = 0

function TUI-Init {
    Clear-Host

    $dryTag = if ($DryRun) { " [DRY RUN - sem alterações]" } else { "" }

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║        PREVENTIVA CORPORATIVA  v$($Script:Version)              ║" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "  ║  HOST   : $($Script:Hostname.PadRight(42))║" -ForegroundColor Cyan
    Write-Host "  ║  DATA   : $(( Get-Date -Format 'dd/MM/yyyy HH:mm').PadRight(42))║" -ForegroundColor Cyan
    Write-Host "  ║  CLIENTE: $($Cliente.PadRight(42))║" -ForegroundColor Cyan
    Write-Host "  ║  TECNICO: $($Tecnico.PadRight(42))║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host ""
        Write-Host "  ⚠  MODO DRY RUN — nenhuma alteração será feita" -ForegroundColor Yellow
    }
    Write-Host ""

    foreach ($chave in $Script:Etapas.Keys) {
        $label = $Script:Etapas[$chave].Label
        Write-Host "  [ ] $($label.PadRight(40)) AGUARDANDO" -ForegroundColor DarkGray
    }

    Write-Host ""
    $Script:TUI_StartLine = [Console]::CursorTop - ($Script:Etapas.Count + 1)
}

function TUI-Update {
    param([string]$Chave, [string]$NovoStatus, [string]$Detalhe = "")

    $Script:Etapas[$Chave].Status = $NovoStatus

    $index = [Array]::IndexOf(($Script:Etapas.Keys | ForEach-Object { $_ }), $Chave)
    $linha = $Script:TUI_StartLine + $index

    $savedTop  = [Console]::CursorTop
    $savedLeft = [Console]::CursorLeft

    [Console]::SetCursorPosition(0, $linha)

    $label = $Script:Etapas[$Chave].Label.PadRight(40)

    switch ($NovoStatus) {
        "OK"      {
            Write-Host "  [" -NoNewline -ForegroundColor DarkGray
            Write-Host "✔" -NoNewline -ForegroundColor Green
            Write-Host "] $label " -NoNewline -ForegroundColor Gray
            Write-Host "OK     $Detalhe".PadRight(20) -ForegroundColor Green
        }
        "ERRO"    {
            Write-Host "  [" -NoNewline -ForegroundColor DarkGray
            Write-Host "✖" -NoNewline -ForegroundColor Red
            Write-Host "] $label " -NoNewline -ForegroundColor Gray
            Write-Host "ERRO   $Detalhe".PadRight(20) -ForegroundColor Red
        }
        "ALERTA"  {
            Write-Host "  [" -NoNewline -ForegroundColor DarkGray
            Write-Host "!" -NoNewline -ForegroundColor Yellow
            Write-Host "] $label " -NoNewline -ForegroundColor Gray
            Write-Host "ALERTA $Detalhe".PadRight(20) -ForegroundColor Yellow
        }
        "SKIP"    {
            Write-Host "  [" -NoNewline -ForegroundColor DarkGray
            Write-Host "-" -NoNewline -ForegroundColor DarkGray
            Write-Host "] $label " -NoNewline -ForegroundColor DarkGray
            Write-Host "SKIP   $Detalhe".PadRight(20) -ForegroundColor DarkGray
        }
        "EXEC"    {
            Write-Host "  [" -NoNewline -ForegroundColor DarkGray
            Write-Host "~" -NoNewline -ForegroundColor Cyan
            Write-Host "] $label " -NoNewline -ForegroundColor Gray
            Write-Host "EXEC...".PadRight(20) -ForegroundColor Cyan
        }
    }

    [Console]::SetCursorPosition($savedLeft, $savedTop)
}

function TUI-Log {
    param([string]$Mensagem, [string]$Cor = "Gray")
    $linhaLog = $Script:TUI_StartLine + $Script:Etapas.Count + 2
    [Console]::SetCursorPosition(0, $linhaLog)
    Write-Host "  $Mensagem".PadRight(60) -ForegroundColor $Cor
}

function Registrar {
    param(
        [string]$Etapa,
        [string]$Status,
        [string]$Detalhe = ""
    )
    $Script:Resultados.Add([PSCustomObject]@{
        Etapa   = $Etapa
        Status  = $Status
        Detalhe = $Detalhe
    })
    Write-Log "$Etapa — $Status — $Detalhe" $Status
    TUI-Update -Chave $Etapa -NovoStatus $Status -Detalhe $Detalhe
}

# ============================================================
#  SNAPSHOT DE HARDWARE (antes de tudo)
# ============================================================

function Get-HardwareInfo {
    $cs  = Get-CimInstance Win32_ComputerSystem
    $os  = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bios= Get-CimInstance Win32_BIOS

    $discos = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } | ForEach-Object {
        $total = [math]::Round(($_.Used + $_.Free) / 1GB, 1)
        $livre = [math]::Round($_.Free / 1GB, 1)
        "$($_.Name): ${livre}GB livres de ${total}GB"
    }

    $ips = (Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object { $_.InterfaceAlias -notmatch "Loopback" } |
            Select-Object -ExpandProperty IPAddress) -join ", "

    $ram_total = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $ram_livre = [math]::Round($os.FreePhysicalMemory / 1MB / 1024, 1)

    return [PSCustomObject]@{
        Fabricante     = $cs.Manufacturer
        Modelo         = $cs.Model
        NumSerie       = $bios.SerialNumber
        CPU            = $cpu.Name.Trim()
        RAM_Total_GB   = $ram_total
        RAM_Livre_GB   = $ram_livre
        Discos         = $discos -join " | "
        SO             = $os.Caption
        Build          = $os.BuildNumber
        IPs            = $ips
        Uptime_Dias    = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
    }
}

# ============================================================
#  INTERNET CHECK
# ============================================================

function Test-Internet {
    try {
        Invoke-WebRequest "https://www.google.com" -TimeoutSec 5 | Out-Null
        Write-Log "Conectividade OK" "OK"
        return $true
    } catch {
        Write-Log "Sem acesso à internet" "ALERTA"
        return $false
    }
}

# ============================================================
#  1. ADMINISTRADOR LOCAL  (SecureString segura — sem Marshal)
# ============================================================

function Set-AdminLocal {
    TUI-Update "Admin" "EXEC"
    try {
        if ($DryRun) {
            Registrar "Admin" "SKIP" "DryRun"
            return
        }

        net user Administrador /active:yes 2>&1 | Out-Null

        if ($Silent) {
            # Em modo silencioso, a senha deve vir de variável de ambiente ou cofre
            $SenhaEnv = [System.Environment]::GetEnvironmentVariable("PREV_ADMIN_PASS", "Machine")
            if ($SenhaEnv) {
                $Senha = ConvertTo-SecureString $SenhaEnv -AsPlainText -Force
            } else {
                Write-Log "PREV_ADMIN_PASS não definida — senha do Admin ignorada" "ALERTA"
                Registrar "Admin" "ALERTA" "Sem senha no env"
                return
            }
        } else {
            $Senha = Read-Host "Nova senha do Administrador" -AsSecureString
        }

        # ✅ Usa LocalAccounts — SecureString nunca vira texto plano
        Set-LocalUser -Name "Administrador" -Password $Senha
        Registrar "Admin" "OK"
    } catch {
        Registrar "Admin" "ERRO" $_.Exception.Message
    }
}

# ============================================================
#  2. WINDOWS STATUS
# ============================================================

function Get-WindowsStatus {
    TUI-Update "Windows" "EXEC"
    try {
        $saida = cscript //nologo C:\Windows\System32\slmgr.vbs /xpr 2>&1
        if ($saida -match "permanently activated") {
            Registrar "Windows" "OK" "Ativado"
        } else {
            Registrar "Windows" "ALERTA" "Não ativado"
        }
    } catch {
        Registrar "Windows" "ERRO" $_.Exception.Message
    }
}

# ============================================================
#  3. OFFICE
# ============================================================

function Get-OfficeStatus {
    TUI-Update "Office" "EXEC"
    try {
        $paths = @(
            "C:\Program Files\Microsoft Office\Office16\OSPP.VBS",
            "C:\Program Files (x86)\Microsoft Office\Office16\OSPP.VBS",
            "C:\Program Files\Microsoft Office\root\Office16\OSPP.VBS",
            "C:\Program Files (x86)\Microsoft Office\root\Office16\OSPP.VBS"
        )
        $ativado = $false
        $versao  = ""

        foreach ($p in $paths) {
            if (Test-Path $p) {
                $s = cscript //nologo $p /dstatus 2>&1
                if ($s -match "LICENSE STATUS:\s+---LICENSED---") { $ativado = $true }
                if ($s -match "(?i)Microsoft Office.*?(\d{4})") { $versao = $Matches[1] }
            }
        }

        # Versão via registro
        $regVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue).VersionToReport

        $detalhe = if ($ativado) { "Ativado" } else { "Não ativado" }
        if ($regVer) { $detalhe += " | $regVer" }

        Registrar "Office" (if ($ativado) { "OK" } else { "ALERTA" }) $detalhe
    } catch {
        Registrar "Office" "ERRO" $_.Exception.Message
    }
}

# ============================================================
#  4. WINDOWS DEFENDER
# ============================================================

function Get-DefenderStatus {
    TUI-Update "Defender" "EXEC"
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop

        $ativo    = $mp.AntivirusEnabled
        $atualiz  = $mp.AntivirusSignatureAge -le 3   # definições com até 3 dias
        $scanDias = [math]::Round(((Get-Date) - $mp.FullScanEndTime).TotalDays)

        $detalhe = "Definições: $($mp.AntivirusSignatureVersion) | Último scan: ${scanDias}d atrás"

        if ($ativo -and $atualiz) {
            Registrar "Defender" "OK" $detalhe
        } elseif (!$ativo) {
            Registrar "Defender" "ERRO" "Defender DESABILITADO"
        } else {
            Registrar "Defender" "ALERTA" "Definições desatualizadas ($($mp.AntivirusSignatureAge)d)"
        }
    } catch {
        Registrar "Defender" "ALERTA" "Não verificado (AV terceiro?)"
    }
}

# ============================================================
#  BLOCO PARALELO — Updates (WinUpdate + OffUpdate + Winget)
# ============================================================

function Start-UpdatesParalelo {
    if ($SkipUpdates) {
        Registrar "WinUpdate" "SKIP" "SkipUpdates"
        Registrar "OffUpdate" "SKIP" "SkipUpdates"
        Registrar "Winget"    "SKIP" "SkipUpdates"
        return
    }

    TUI-Update "WinUpdate" "EXEC"
    TUI-Update "OffUpdate" "EXEC"
    TUI-Update "Winget"    "EXEC"

    TUI-Log "Rodando Windows Update, Office Update e Winget em paralelo..." "Cyan"

    # ── Job 1: Windows Update ──────────────────────────────
    $jobWU = Start-Job -ScriptBlock {
        param($dry)
        try {
            if ($dry) { return @{ Status="SKIP"; Detalhe="DryRun" } }
            Install-Module PSWindowsUpdate -Force -Confirm:$false -Scope AllUsers -ErrorAction SilentlyContinue
            Import-Module PSWindowsUpdate -ErrorAction Stop
            $updates = Get-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop
            if (!$dry) { Install-WindowsUpdate -AcceptAll -IgnoreReboot -Confirm:$false | Out-Null }
            return @{ Status="OK"; Detalhe="$($updates.Count) update(s)" }
        } catch {
            return @{ Status="ERRO"; Detalhe=$_.Exception.Message }
        }
    } -ArgumentList $DryRun

    # ── Job 2: Office Update ───────────────────────────────
    $jobOff = Start-Job -ScriptBlock {
        param($dry)
        try {
            $exe = "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
            if (!(Test-Path $exe)) { return @{ Status="ALERTA"; Detalhe="ClickToRun não encontrado" } }
            if (!$dry) { Start-Process $exe -ArgumentList "/update user displaylevel=false forceappshutdown=true" -Wait }
            return @{ Status=(if($dry){"SKIP"}else{"OK"}); Detalhe=(if($dry){"DryRun"}else{"Atualizado"}) }
        } catch {
            return @{ Status="ERRO"; Detalhe=$_.Exception.Message }
        }
    } -ArgumentList $DryRun

    # ── Job 3: Winget ──────────────────────────────────────
    $jobWG = Start-Job -ScriptBlock {
        param($dry)
        try {
            if ($dry) { return @{ Status="SKIP"; Detalhe="DryRun" } }
            $r = winget upgrade --all --silent --accept-source-agreements --accept-package-agreements 2>&1
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) {
                return @{ Status="ALERTA"; Detalhe="Exit code $LASTEXITCODE" }
            }
            return @{ Status="OK"; Detalhe="Concluído" }
        } catch {
            return @{ Status="ERRO"; Detalhe=$_.Exception.Message }
        }
    } -ArgumentList $DryRun

    # Aguarda os três jobs
    $jobs = @($jobWU, $jobOff, $jobWG)
    $chaves = @("WinUpdate", "OffUpdate", "Winget")

    Wait-Job -Job $jobs | Out-Null

    for ($i = 0; $i -lt $jobs.Count; $i++) {
        $resultado = Receive-Job -Job $jobs[$i]
        Registrar $chaves[$i] $resultado.Status $resultado.Detalhe
        Remove-Job -Job $jobs[$i]
    }

    TUI-Log "" "Gray"
}

# ============================================================
#  8. DRIVERS (FABRICANTE)
# ============================================================

function Update-Drivers {
    TUI-Update "Drivers" "EXEC"
    try {
        $fab = (Get-CimInstance Win32_ComputerSystem).Manufacturer

        if ($fab -like "*Lenovo*") {
            $exe = "C:\Program Files (x86)\Lenovo\System Update\tvsu.exe"
            if (Test-Path $exe) {
                if (!$DryRun) { Start-Process $exe -ArgumentList "/CM -search A -action INSTALL -noicon -includerebootpackages 3" -Wait }
                Registrar "Drivers" (if($DryRun){"SKIP"}else{"OK"}) "Lenovo System Update"
            } else {
                Registrar "Drivers" "ALERTA" "Lenovo Update não instalado"
            }
        }
        elseif ($fab -like "*Dell*") {
            $exe = "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe"
            if (Test-Path $exe) {
                if (!$DryRun) { Start-Process $exe -ArgumentList "/applyUpdates -silent" -Wait }
                Registrar "Drivers" (if($DryRun){"SKIP"}else{"OK"}) "Dell Command Update"
            } else {
                Registrar "Drivers" "ALERTA" "Dell Command Update não instalado"
            }
        }
        elseif ($fab -like "*HP*" -or $fab -like "*Hewlett*") {
            $exe = "${env:ProgramFiles}\HP\HP Support Framework\HPSF.exe"
            if (Test-Path $exe) {
                if (!$DryRun) { Start-Process $exe -ArgumentList "/s /o" -Wait }
                Registrar "Drivers" (if($DryRun){"SKIP"}else{"OK"}) "HP Support Assistant"
            } else {
                Registrar "Drivers" "ALERTA" "HP Support Assistant não instalado"
            }
        }
        elseif ($fab -like "*Acer*") {
            Registrar "Drivers" "ALERTA" "Acer — atualizar via Care Center manualmente"
        }
        else {
            Registrar "Drivers" "ALERTA" "Fabricante não mapeado: $fab"
        }
    } catch {
        Registrar "Drivers" "ERRO" $_.Exception.Message
    }
}

# ============================================================
#  9. GLPI AGENT
# ============================================================

function Invoke-GLPIAgent {
    TUI-Update "GLPI" "EXEC"
    try {
        $svc = Get-Service -Name "glpi-agent" -ErrorAction SilentlyContinue
        if (!$svc) {
            Registrar "GLPI" "ALERTA" "Serviço não encontrado"
            return
        }
        if ($svc.Status -ne "Running") { Start-Service glpi-agent }
        $exe = "C:\Program Files\GLPI-Agent\glpi-agent.exe"
        if (Test-Path $exe) {
            if (!$DryRun) {
                $proc = Start-Process $exe -ArgumentList "--force" -Wait -PassThru
                Registrar "GLPI" (if($proc.ExitCode -eq 0){"OK"}else{"ALERTA"}) "ExitCode: $($proc.ExitCode)"
            } else {
                Registrar "GLPI" "SKIP" "DryRun"
            }
        } else {
            Registrar "GLPI" "ALERTA" "glpi-agent.exe não encontrado"
        }
    } catch {
        Registrar "GLPI" "ERRO" $_.Exception.Message
    }
}

# ============================================================
#  10. LIMPEZA DE PERFIS (>90 dias)
# ============================================================

function Remove-PerfisAntigos {
    TUI-Update "Perfis" "EXEC"
    try {
        if ($SkipCleaning) { Registrar "Perfis" "SKIP" "SkipCleaning"; return }

        $usuAtual = $env:USERNAME
        $perfis = Get-CimInstance Win32_UserProfile | Where-Object {
            $_.LastUseTime -lt (Get-Date).AddDays(-90) -and
            $_.Special -eq $false -and
            $_.LocalPath -like "C:\Users\*" -and
            $_.LocalPath -notmatch "\\Administrador$" -and
            $_.LocalPath -notmatch "\\Default" -and
            $_.LocalPath -notmatch "\\Public" -and
            $_.LocalPath -notmatch "\\$usuAtual$"
        }

        if (!$perfis) {
            Registrar "Perfis" "OK" "Nenhum perfil antigo"
            return
        }

        $lista = $perfis | ForEach-Object {
            $tam = (Get-ChildItem $_.LocalPath -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object Length -Sum).Sum / 1GB
            "$($_.LocalPath) ($([math]::Round($tam,1))GB)"
        }

        $confirma = $true
        if (!$Silent -and !$DryRun) {
            $linhaLog = $Script:TUI_StartLine + $Script:Etapas.Count + 3
            [Console]::SetCursorPosition(0, $linhaLog)
            Write-Host "  Perfis encontrados:" -ForegroundColor Yellow
            $lista | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkYellow }
            $resp = Read-Host "  Remover perfis antigos? (S/N)"
            $confirma = $resp -match "^[sS]$"
        }

        if ($confirma -and !$DryRun) {
            $perfis | ForEach-Object { Remove-CimInstance $_ }
            Registrar "Perfis" "OK" "$($perfis.Count) removido(s)"
        } elseif ($DryRun) {
            Registrar "Perfis" "SKIP" "DryRun — $($perfis.Count) seriam removidos"
        } else {
            Registrar "Perfis" "SKIP" "Cancelado pelo operador"
        }
    } catch {
        Registrar "Perfis" "ERRO" $_.Exception.Message
    }
}

# ============================================================
#  11. LIMPEZA DE DISCO
# ============================================================

function Invoke-LimpezaDisco {
    TUI-Update "Disco" "EXEC"
    try {
        if ($SkipCleaning) { Registrar "Disco" "SKIP" "SkipCleaning"; return }
        if ($DryRun)       { Registrar "Disco" "SKIP" "DryRun"; return }

        # Garante que o perfil de limpeza 1 existe no registro
        $sagePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        $categorias = @(
            "Temporary Files", "Recycle Bin", "Downloaded Program Files",
            "Internet Cache Files", "Old ChkDsk Files", "System error memory dump files",
            "Temporary Setup Files", "Windows Error Reporting Files"
        )
        foreach ($cat in $categorias) {
            $key = "$sagePath\$cat"
            if (Test-Path $key) {
                Set-ItemProperty -Path $key -Name StateFlags0001 -Value 2 -Type DWord -ErrorAction SilentlyContinue
            }
        }

        Start-Process cleanmgr -ArgumentList "/sagerun:1" -Wait -WindowStyle Hidden
        Start-Process Dism.exe -ArgumentList "/online /Cleanup-Image /StartComponentCleanup /Quiet" -Wait -WindowStyle Hidden

        Remove-Item "C:\Windows\Temp\*"  -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:TEMP\*"        -Recurse -Force -ErrorAction SilentlyContinue

        Registrar "Disco" "OK" "Limpeza concluída"
    } catch {
        Registrar "Disco" "ERRO" $_.Exception.Message
    }
}

# ============================================================
#  12. INVENTÁRIO DE SOFTWARES INSTALADOS
# ============================================================

function Get-SoftwaresInstalados {
    TUI-Update "Softwares" "EXEC"
    try {
        $paths = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        $softs = foreach ($p in $paths) {
            if (Test-Path $p) {
                Get-ItemProperty $p -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName } |
                    Select-Object DisplayName, DisplayVersion, Publisher,
                        @{ N="InstallDate"; E={ $_.InstallDate } }
            }
        }

        $softs = $softs | Sort-Object DisplayName -Unique

        # Salva CSV junto ao log
        $csvPath = "$($Script:BaseLog)\softwares_$($Script:Hostname)_$($Script:Data).csv"
        $softs | Export-Csv $csvPath -NoTypeInformation -Encoding UTF8

        Write-Log "Softwares inventariados: $($softs.Count) | CSV: $csvPath" "OK"
        Registrar "Softwares" "OK" "$($softs.Count) softwares — CSV salvo"

        return $softs
    } catch {
        Registrar "Softwares" "ERRO" $_.Exception.Message
        return $null
    }
}

# ============================================================
#  13. STATUS DA BATERIA
# ============================================================

function Get-BateriaStatus {
    TUI-Update "Bateria" "EXEC"
    try {
        $bat = Get-WmiObject Win32_Battery -ErrorAction SilentlyContinue

        if (!$bat) {
            Registrar "Bateria" "SKIP" "Desktop / sem bateria"
            return
        }

        $saude   = $bat.EstimatedChargeRemaining
        $status  = switch ($bat.BatteryStatus) {
            1 { "Descarregando" }
            2 { "CA conectada" }
            3 { "Carregando" }
            default { "Status $($bat.BatteryStatus)" }
        }

        # Capacidade de design vs atual (quando disponível)
        $designCap  = $bat.DesignCapacity
        $fullCap    = $bat.FullChargeCapacity
        $saudePerc  = if ($designCap -and $fullCap -and $designCap -gt 0) {
            [math]::Round($fullCap / $designCap * 100)
        } else { $null }

        $detalhe = "$status | Carga: ${saude}%"
        if ($saudePerc) { $detalhe += " | Saúde: ${saudePerc}%" }

        if ($saudePerc -and $saudePerc -lt 60) {
            Registrar "Bateria" "ALERTA" "$detalhe — SUBSTITUIÇÃO RECOMENDADA"
        } elseif ($saude -lt 20) {
            Registrar "Bateria" "ALERTA" $detalhe
        } else {
            Registrar "Bateria" "OK" $detalhe
        }
    } catch {
        Registrar "Bateria" "ERRO" $_.Exception.Message
    }
}

# ============================================================
#  14. VERIFICAÇÃO DE REBOOT PENDENTE
# ============================================================

function Test-RebootPendente {
    TUI-Update "Reboot" "EXEC"
    try {
        $pendente = $false
        $motivos  = @()

        # Windows Update
        $wuKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        if (Test-Path $wuKey) { $pendente = $true; $motivos += "Windows Update" }

        # File rename operations
        $fro = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -ErrorAction SilentlyContinue).PendingFileRenameOperations
        if ($fro) { $pendente = $true; $motivos += "PendingFileRename" }

        # Component Based Servicing
        $cbsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
        if (Test-Path $cbsKey) { $pendente = $true; $motivos += "CBS" }

        if ($pendente) {
            Registrar "Reboot" "ALERTA" "Reboot necessário: $($motivos -join ', ')"
        } else {
            Registrar "Reboot" "OK" "Nenhum reboot pendente"
        }
    } catch {
        Registrar "Reboot" "ERRO" $_.Exception.Message
    }
}

# ============================================================
#  15. AUDITORIA DE USUÁRIOS LOCAIS
# ============================================================

function Get-AuditoriaUsuarios {
    TUI-Update "Usuarios" "EXEC"
    try {
        $users = Get-LocalUser | Select-Object Name, Enabled, LastLogon,
            PasswordExpires, PasswordLastSet,
            @{ N="SenhaExpirada"; E={ $_.PasswordExpires -and $_.PasswordExpires -lt (Get-Date) } }

        $habilitados = ($users | Where-Object { $_.Enabled }).Count
        $suspeitos   = ($users | Where-Object { $_.Enabled -and $_.Name -notin @("Administrador","Administrator",$env:USERNAME) }).Count

        Write-Log "Usuários locais: $($users.Count) total, $habilitados habilitados, $suspeitos não-padrão habilitados" "INFO"

        if ($suspeitos -gt 0) {
            Registrar "Usuarios" "ALERTA" "$habilitados habilitados, $suspeitos não-padrão"
        } else {
            Registrar "Usuarios" "OK" "$habilitados habilitados"
        }

        return $users
    } catch {
        Registrar "Usuarios" "ERRO" $_.Exception.Message
        return $null
    }
}

# ============================================================
#  RELATÓRIO FINAL NO CONSOLE
# ============================================================

function Show-ChecklistFinal {
    $duracao = [math]::Round(((Get-Date) - $Script:StartTime).TotalMinutes, 1)

    $linhaFinal = $Script:TUI_StartLine + $Script:Etapas.Count + 5
    [Console]::SetCursorPosition(0, $linhaFinal)

    $erros   = ($Script:Resultados | Where-Object { $_.Status -eq "ERRO" }).Count
    $alertas = ($Script:Resultados | Where-Object { $_.Status -eq "ALERTA" }).Count

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                  PREVENTIVA CONCLUÍDA                ║" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "  ║  Duração : ${duracao} min$(if($DryRun){' [DRY RUN]'})".PadRight(55) + "║" -ForegroundColor Cyan
    Write-Host "  ║  Erros   : $erros".PadRight(55) + "║" -ForegroundColor $(if($erros -gt 0){"Red"}else{"Cyan"})
    Write-Host "  ║  Alertas : $alertas".PadRight(55) + "║" -ForegroundColor $(if($alertas -gt 0){"Yellow"}else{"Cyan"})
    Write-Host "  ║  Log     : $($Script:LogFile)".PadRight(55).Substring(0,54) + "║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    Write-Log "===== FIM DA PREVENTIVA | Duração: ${duracao}min | Erros: $erros | Alertas: $alertas =====" "INFO"
}

# ============================================================
#  ENVIO DO LOG PARA SHARE DE REDE
# ============================================================

function Send-LogParaShare {
    if (!$Script:ShareLogs) { return }
    try {
        $destino = "$($Script:ShareLogs)\$($Script:Hostname)"
        if (!(Test-Path $destino)) {
            New-Item -ItemType Directory -Path $destino -Force | Out-Null
        }
        Copy-Item $Script:LogFile -Destination $destino -Force
        $csv = "$($Script:BaseLog)\softwares_$($Script:Hostname)_$($Script:Data).csv"
        if (Test-Path $csv) { Copy-Item $csv -Destination $destino -Force }
        Write-Log "Logs enviados para $destino" "OK"
    } catch {
        Write-Log "Falha ao enviar log para share: $_" "ALERTA"
    }
}

# ============================================================
#  MAIN — ORQUESTRAÇÃO
# ============================================================

# Coleta de informações iniciais (cliente e técnico, se não passados)
if (!$Silent) {
    if (!$Cliente) { $Cliente = Read-Host "  Nome do cliente" }
    if (!$Tecnico) { $Tecnico = Read-Host "  Seu nome (técnico)" }
}

TUI-Init

$hw      = Get-HardwareInfo
$internet= Test-Internet

Write-Log "HARDWARE: $($hw.Fabricante) $($hw.Modelo) | CPU: $($hw.CPU) | RAM: $($hw.RAM_Total_GB)GB | Disco: $($hw.Discos) | S/N: $($hw.NumSerie) | Build: $($hw.Build) | IP: $($hw.IPs) | Uptime: $($hw.Uptime_Dias)d" "INFO"

# Etapas sequenciais rápidas
Set-AdminLocal
Get-WindowsStatus
Get-OfficeStatus
Get-DefenderStatus

# Etapas paralelas (updates — as mais demoradas)
Start-UpdatesParalelo

# Etapas sequenciais pós-update
Update-Drivers
Invoke-GLPIAgent
Remove-PerfisAntigos
Invoke-LimpezaDisco

# Inventário e diagnósticos
$softwares = Get-SoftwaresInstalados
Get-BateriaStatus
Test-RebootPendente
$usuarios  = Get-AuditoriaUsuarios

# Finalização
Show-ChecklistFinal
Send-LogParaShare

Write-Host "  Pressione qualquer tecla para fechar..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")