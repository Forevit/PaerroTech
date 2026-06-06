# ============================================================
#  SCRIPT DE PADRONIZAÇÃO DE MÁQUINA CORPORATIVA
#  by Eduardo Ferreira | Paerro Tecnologia
# ============================================================

# ============================================================
# AUTO-ELEVAÇÃO
# ============================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process PowerShell -Verb RunAs "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Exit
}

# ============================================================
# SISTEMA DE LOGS
# ============================================================
$logRaiz = "C:\Users\Public\Documents\Logs"
$logDir  = "$logRaiz\Padronizacao"
$logFile = "$logDir\padronizacao_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

New-Item -ItemType Directory -Path $logRaiz -Force | Out-Null
New-Item -ItemType Directory -Path $logDir  -Force | Out-Null

function Write-Log {
    param(
        [string]$Mensagem,
        [ValidateSet("INFO","OK","ERRO","AVISO","ETAPA")]
        [string]$Tipo = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $linha = "[$timestamp] [$Tipo] $Mensagem"

    $linha | Out-File -FilePath $logFile -Append -Encoding UTF8

    switch ($Tipo) {
        "ETAPA" { Write-Host "`n$linha" -ForegroundColor Cyan }
        "OK"    { Write-Host $linha -ForegroundColor Green }
        "ERRO"  { Write-Host $linha -ForegroundColor Red }
        "AVISO" { Write-Host $linha -ForegroundColor Yellow }
        default { Write-Host $linha -ForegroundColor White }
    }
}

function Write-LogErro {
    param([string]$Mensagem, [System.Management.Automation.ErrorRecord]$Excecao)
    Write-Log $Mensagem "ERRO"
    if ($Excecao) {
        Write-Log "Detalhe: $($Excecao.Exception.Message)" "ERRO"
        Write-Log "Linha  : $($Excecao.InvocationInfo.ScriptLineNumber)" "ERRO"
    }
}

# ============================================================
# CONTROLE DE ETAPAS / RETOMADA APÓS REBOOT
# ============================================================
$totalEtapas = 9
$regPath = "HKLM:\SOFTWARE\Padronizacao"

$scriptPath = if ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
} else {
    [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}

function Get-Etapa {
    if (Test-Path $regPath) {
        return (Get-ItemProperty -Path $regPath -Name "Etapa" -ErrorAction SilentlyContinue).Etapa
    }
    return 0
}

function Set-Etapa {
    param([int]$Numero)
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name "Etapa" -Value $Numero
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
    Set-ItemProperty -Path $regPath -Name $Chave -Value $Valor
}

function Set-RunOnce {
    Set-DadoSalvo "ScriptPath" $scriptPath

    $cmd = "PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
                     -Name "Padronizacao" `
                     -Value $cmd

    Write-Log "RunOnce configurado para retomada após reboot." "INFO"
}

function Remove-Estado {
    Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
                        -Name "Padronizacao" `
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
    try {
        $officeUrl = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=O365ProPlusRetail&platform=x64&language=pt-br&version=O16GA"
        $officeInstaller = "$env:TEMP\OfficeSetup.exe"

        Write-Log "Baixando instalador Microsoft 365 Apps..." "INFO"
        Invoke-WebRequest -Uri $officeUrl -OutFile $officeInstaller -UseBasicParsing -ErrorAction Stop

        Write-Log "Iniciando instalação do Microsoft 365 Apps..." "INFO"
        $proc = Start-Process $officeInstaller -Wait -PassThru

        if ($proc.ExitCode -eq 0) {
            Write-Log "Microsoft 365 Apps instalado com sucesso." "OK"
        } else {
            Write-Log "Instalador do Office retornou código $($proc.ExitCode). Verifique manualmente." "AVISO"
        }

        Remove-Item $officeInstaller -Force -ErrorAction SilentlyContinue
    } catch {
        Write-LogErro "Falha ao instalar Microsoft 365 Apps." $_
    }
}

function Instalar-DriversFabricante {
    try {
        $fabricante = (Get-CimInstance Win32_ComputerSystem).Manufacturer
        Write-Log "Fabricante detectado: $fabricante" "INFO"

        switch -Wildcard ($fabricante.ToLower()) {
            "*dell*" {
                Write-Log "Instalando Dell Command Update..." "INFO"
                winget install --id Dell.CommandUpdate --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-File -FilePath $logFile -Append -Encoding UTF8

                $dcu = "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe"
                if (Test-Path $dcu) {
                    Write-Log "Executando Dell Command Update..." "INFO"
                    Start-Process $dcu -ArgumentList "/applyUpdates -silent" -Wait
                    Write-Log "Dell Command Update concluído." "OK"
                } else {
                    Write-Log "dcu-cli.exe não encontrado. Execute manualmente se necessário." "AVISO"
                }
            }

            "*lenovo*" {
                Write-Log "Instalando Lenovo System Update..." "INFO"
                winget install --id Lenovo.SystemUpdate --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-File -FilePath $logFile -Append -Encoding UTF8
                Write-Log "Lenovo System Update instalado. Execute a aplicação manualmente para aplicar drivers pendentes." "AVISO"
            }

            default {
                Write-Log "Fabricante '$fabricante' não mapeado. Nenhum driver instalado automaticamente." "AVISO"
            }
        }
    } catch {
        Write-LogErro "Falha na instalação de drivers do fabricante." $_
    }
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
        $admin = Get-LocalUser -Name "Administrador" -ErrorAction SilentlyContinue

        if (-not $admin) {
            Write-Log "Conta local 'Administrador' não encontrada. Verifique idioma/edição do Windows." "AVISO"
        } else {
            if (-not $admin.Enabled) {
                Enable-LocalUser -Name "Administrador" -ErrorAction Stop
                Write-Log "Conta 'Administrador' habilitada." "OK"
            } else {
                Write-Log "Conta 'Administrador' já está habilitada." "OK"
            }

            $alterarSenha = Read-Host "Deseja definir/alterar a senha do Administrador local? (S/N)"
            if ($alterarSenha -match '^[sS]') {
                do {
                    $adminPass        = Read-Host "Defina a senha para a conta Administrador" -AsSecureString
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

                Set-LocalUser -Name "Administrador" -Password $adminPass -PasswordNeverExpires $true -ErrorAction Stop
                Write-Log "Senha do Administrador local definida." "OK"

                $pass1 = $null
                $pass2 = $null
                $adminPass = $null
                $adminPassConfirm = $null
                [System.GC]::Collect()
            }
        }
    } catch {
        Write-LogErro "Falha ao verificar/configurar Administrador local." $_
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
        Exit
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

        Invoke-RestMethod https://get.activated.win | Invoke-Expression

        Write-Log "Upgrade Home -> Pro pendente de execução/configuração." "AVISO"
        pause
        Exit
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
                $domAdmin = Read-Host "Usuário do domínio com permissão para adicionar máquinas"
                $domPass = Read-Host "Senha do usuário do domínio" -AsSecureString
                $credencial = New-Object System.Management.Automation.PSCredential($domAdmin, $domPass)

                Set-DadoSalvo "Hostname" $novoHostname
                Set-DadoSalvo "Dominio" $dominio

                Add-Computer -DomainName $dominio -Credential $credencial -NewName $novoHostname -Force -ErrorAction Stop
                Write-Log "Máquina '$novoHostname' adicionada ao domínio '$dominio'." "OK"

                $credencial = $null
                $domPass = $null
                [System.GC]::Collect()

                Set-Etapa 3
                Set-RunOnce
                Write-Log "Reiniciando para aplicar hostname/domínio..." "INFO"
                Start-Sleep -Seconds 5
                Restart-Computer -Force
                Exit
            }

            "2" {
                do {
                    $novoHostname = Read-Host "Digite o novo hostname"
                    $hostnameValido = Assert-HostnameValido $novoHostname
                } while (-not $hostnameValido)

                Set-DadoSalvo "Hostname" $novoHostname
                Set-DadoSalvo "Dominio" "Não ingressado"

                Rename-Computer -NewName $novoHostname -Force -ErrorAction Stop
                Write-Log "Hostname alterado para '$novoHostname'." "OK"

                Set-Etapa 3
                Set-RunOnce
                Write-Log "Reiniciando para aplicar hostname..." "INFO"
                Start-Sleep -Seconds 5
                Restart-Computer -Force
                Exit
            }

            default {
                Set-DadoSalvo "Hostname" $env:COMPUTERNAME
                Set-DadoSalvo "Dominio" "Etapa pulada"
                Write-Log "Etapa de hostname/domínio pulada pelo técnico." "AVISO"
            }
        }
    } catch {
        Write-LogErro "Falha na etapa de hostname/domínio." $_
        Write-Log "Verifique conectividade, DNS, credenciais e permissões no domínio." "AVISO"
        pause
        Exit
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

            $wuJob = Start-Job -ScriptBlock {
                Import-Module PSWindowsUpdate -Force
                Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -Verbose 2>&1
            }

            Write-Log "Windows Update iniciado em background. Job ID: $($wuJob.Id)." "OK"
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
        Exit
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
            $resultado | Out-File -FilePath $logFile -Append -Encoding UTF8

            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
                Write-Log "$($app.Nome) instalado ou já existente." "OK"
            } else {
                Write-Log "$($app.Nome) retornou código $LASTEXITCODE. Verifique manualmente." "AVISO"
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

            if ($proc.ExitCode -eq 0) {
                Write-Log "GLPI Agent instalado. Servidor: $glpiServer" "OK"
            } else {
                Write-Log "msiexec retornou código $($proc.ExitCode)." "AVISO"
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
        Instalar-OfficeMicrosoft365
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
        Instalar-DriversFabricante
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

    try {
       Invoke-RestMethod https://get.activated.win | Invoke-Expression


        Write-Log "Bloco de ativação/licenciamento executado ou mantido para validação manual." "AVISO"
    } catch {
        Write-LogErro "Falha durante ativação/licenciamento." $_
    }

    Set-Etapa 9
}

# ============================================================
# AGUARDAR WINDOWS UPDATE, SE AINDA ESTIVER RODANDO
# ============================================================
Write-Log "Verificando status do Windows Update em background..." "INFO"
$wuJobs = Get-Job -State Running -ErrorAction SilentlyContinue | Where-Object { $_.Command -like "*WindowsUpdate*" }

if ($wuJobs) {
    Write-Log "Windows Update ainda está em execução. Aguardando até 30 minutos..." "AVISO"
    $concluido = $wuJobs | Wait-Job -Timeout 1800

    if ($concluido) {
        $wuJobs | Receive-Job | Out-File -FilePath $logFile -Append -Encoding UTF8
        Write-Log "Windows Update concluído." "OK"
    } else {
        Write-Log "Windows Update não concluiu no tempo limite. Verifique manualmente." "AVISO"
        $wuJobs | Stop-Job -ErrorAction SilentlyContinue
    }

    $wuJobs | Remove-Job -ErrorAction SilentlyContinue
} else {
    Write-Log "Windows Update finalizado, pulado ou não iniciado nesta sessão." "INFO"
}

# ============================================================
# RESUMO FINAL
# ============================================================
$novoHostname = Get-DadoSalvo "Hostname"
$dominio = Get-DadoSalvo "Dominio"
$officeStatus = if (Test-OfficeInstalado) { "Instalado" } else { "Não detectado" }
$windowsEdicao = Get-WindowsEdicao

Write-Progress -Activity "Padronização Corporativa" -Completed

Write-Log "============================================" "INFO"
Write-Log "PADRONIZAÇÃO CONCLUÍDA" "OK"
Write-Log "Hostname : $novoHostname" "INFO"
Write-Log "Domínio  : $dominio" "INFO"
Write-Log "Windows  : $windowsEdicao" "INFO"
Write-Log "Office   : $officeStatus" "INFO"
Write-Log "Log salvo em: $logFile" "INFO"
Write-Log "============================================" "INFO"

Remove-Estado

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "   PADRONIZAÇÃO CONCLUÍDA!" -ForegroundColor Cyan
Write-Host "   Hostname : $novoHostname" -ForegroundColor White
Write-Host "   Domínio  : $dominio" -ForegroundColor White
Write-Host "   Windows  : $windowsEdicao" -ForegroundColor White
Write-Host "   Office   : $officeStatus" -ForegroundColor White
Write-Host "   Log      : $logFile" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

pause
