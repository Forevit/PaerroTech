<#
.SYNOPSIS
    Instala/atualiza o RustDesk e configura o servidor PaerroTech.
.DESCRIPTION
    Para execução interativa, solicita a senha permanente sem eco. Em automações,
    aceita a variável de ambiente RUSTDESK_PASSWORD (por exemplo, injetada por um
    GitHub Actions self-hosted runner). O script não consegue consultar GitHub
    Secrets diretamente.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ==== Configuração ====
$requiredVersion   = '1.4.9'
$rustdeskDownload  = "https://github.com/rustdesk/rustdesk/releases/download/$requiredVersion/rustdesk-$requiredVersion-x86_64.exe"
$rustdeskSha256    = 'eaedeb0088e687bf46f7c46a9c6ea5493ce51f3134dfd6acbedb47b5b9136274'
$rustdeskExePath   = Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'
$rustdeskServer    = 'monitor.paerrotecnologia.com.br'
$rendezvousPort    = 21116
$relayPort         = 21117
$rustdeskKey       = '4XzfD7gwCxuMeW7vjyCRhlwJrU9ovvUAMAkD2x1KFgg='
$serviceConfigPath = 'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml'
$logRoot           = Join-Path $env:PUBLIC 'Documents\Logs\Outros'
$logFile           = Join-Path $logRoot 'rustdesk_script.log'

function Write-Log {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InteractiveProfilePath {
    $fullUser = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName
    if (-not $fullUser) { return $null }

    try {
        $account = [System.Security.Principal.NTAccount]::new($fullUser)
        $sid = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
        $profile = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
            Where-Object { $_.SID -eq $sid -and -not $_.Special } |
            Select-Object -First 1
        if ($profile -and (Test-Path -LiteralPath $profile.LocalPath)) { return $profile.LocalPath }
    } catch {
        Write-Log "Não foi possível resolver o perfil de '$fullUser': $($_.Exception.Message)" 'WARN'
    }
    return $null
}

function ConvertTo-TomlString {
    param([Parameter(Mandatory)][string]$Value)
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n') + '"'
}

function Get-RustDeskPassword {
    if (-not [string]::IsNullOrWhiteSpace($env:RUSTDESK_PASSWORD)) {
        if ($env:RUSTDESK_PASSWORD.Length -lt 12) { throw 'RUSTDESK_PASSWORD deve ter pelo menos 12 caracteres.' }
        return $env:RUSTDESK_PASSWORD
    }
    if (-not [Environment]::UserInteractive) {
        throw 'Defina RUSTDESK_PASSWORD no ambiente de execução. Em GitHub Actions, mapeie o secret para essa variável no job.'
    }
    $secure = Read-Host 'Senha permanente do RustDesk' -AsSecureString
    if ($secure.Length -lt 12) { $secure.Dispose(); throw 'A senha deve ter pelo menos 12 caracteres.' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $secure.Dispose()
    }
}

function ConvertTo-WindowsCommandLineArgument {
    param([Parameter(Mandatory)][string]$Value)
    # Escaping segundo as regras de quoting do CommandLineToArgvW.
    $builder = [System.Text.StringBuilder]::new('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (2 * $slashes + 1))).Append('"')
        } else {
            [void]$builder.Append(('\' * $slashes)).Append($character)
        }
        $slashes = 0
    }
    [void]$builder.Append(('\' * (2 * $slashes))).Append('"')
    return $builder.ToString()
}

# Preparar log antes de qualquer operação registrada.
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

if (-not (Test-IsAdmin)) {
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
        return
    }
    Write-Error 'Execute este comando em um PowerShell aberto como Administrador. Para irm | iex, inicie primeiro um PowerShell elevado.'
    return
}

Write-Log '==== Início da instalação/configuração do RustDesk ===='
$password = $null
$installerPath = $null
try {
    $skipInstall = $false
    if (Test-Path -LiteralPath $rustdeskExePath) {
        $installedText = (Get-Item -LiteralPath $rustdeskExePath).VersionInfo.ProductVersion
        $installedVersion = [version](($installedText -split '[+-]')[0] -replace '[^0-9.].*$', '')
        Write-Log "Versão detectada: $installedText"
        if ($installedVersion -ge [version]$requiredVersion) { $skipInstall = $true }
    }

    if (-not $skipInstall) {
        # Pasta dedicada em ProgramData evita executar um arquivo temporário
        # deixado em um diretório compartilhado como C:\Temp.
        $downloadRoot = Join-Path $env:ProgramData 'PaerroTech\RustDesk'
        New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
        $installerPath = Join-Path $downloadRoot ("rustdesk-{0}.exe" -f [guid]::NewGuid().ToString('N'))

        Write-Log "Baixando RustDesk $requiredVersion..."
        Invoke-WebRequest -Uri $rustdeskDownload -OutFile $installerPath -UseBasicParsing
        if (-not (Test-Path -LiteralPath $installerPath) -or (Get-Item -LiteralPath $installerPath).Length -lt 1MB) {
            throw 'O arquivo baixado está ausente ou tem tamanho inesperado.'
        }
        $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $rustdeskSha256) {
            throw "SHA-256 do instalador não confere (esperado $rustdeskSha256, recebido $actualHash)."
        }
        Write-Log 'SHA-256 do instalador oficial verificado.'

        $process = Start-Process -FilePath $installerPath -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "Instalador terminou com código $($process.ExitCode)." }
        if (-not (Test-Path -LiteralPath $rustdeskExePath)) { throw 'Instalador terminou, mas rustdesk.exe não foi encontrado no caminho esperado.' }
    }

    # Pare o serviço antes de editar os TOMLs: o processo pode persistir o estado
    # atual ao encerrar e sobrescrever as alterações feitas enquanto estava ativo.
    $service = Get-Service -Name 'rustdesk' -ErrorAction Stop
    if ($service.Status -eq 'Running') {
        Stop-Service -Name 'rustdesk' -Force -ErrorAction Stop
        (Get-Service -Name 'rustdesk' -ErrorAction Stop).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    }
    Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    $userProfile = Get-InteractiveProfilePath
    $configPaths = @($serviceConfigPath)
    if ($userProfile) {
        $configPaths += Join-Path $userProfile 'AppData\Roaming\RustDesk\config\RustDesk2.toml'
    } else {
        Write-Log 'Nenhum usuário interativo detectado; será configurado apenas o perfil LocalService.' 'WARN'
    }

    $toml = @"
rendezvous_server = "$(ConvertTo-TomlString "$rustdeskServer`:$rendezvousPort")"
nat_type = 1
serial = 0

[options]
av1-test = 'Y'
allow-remote-config-modification = 'Y'
relay-server = "$(ConvertTo-TomlString "$rustdeskServer`:$relayPort")"
allow-auto-update = 'Y'
key = "$(ConvertTo-TomlString $rustdeskKey)"
custom-rendezvous-server = "$(ConvertTo-TomlString "$rustdeskServer`:$rendezvousPort")"
verification-method = 'use-permanent-password'
"@
    $defaultToml = "[options]`nview_style = 'adaptive'`n"

    foreach ($path in $configPaths) {
        $directory = Split-Path -Parent $path
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($path, $toml, $utf8NoBom)
        [System.IO.File]::WriteAllText((Join-Path $directory 'RustDesk_default.toml'), $defaultToml, $utf8NoBom)
    }

    Start-Service -Name 'rustdesk' -ErrorAction Stop
    (Get-Service -Name 'rustdesk' -ErrorAction Stop).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))

    # Valida os valores gravados nos dois arquivos, sem depender de logs vagos.
    foreach ($path in $configPaths) {
        $written = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($written -notmatch [regex]::Escape("$rustdeskServer`:$rendezvousPort") -or
            $written -notmatch [regex]::Escape($rustdeskKey)) {
            throw "A validação da configuração falhou em '$path'."
        }
    }

    $password = Get-RustDeskPassword
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $rustdeskExePath
    $psi.Arguments = '--password ' + (ConvertTo-WindowsCommandLineArgument $password)
    $psi.UseShellExecute = $false
    $passwordProcess = [System.Diagnostics.Process]::Start($psi)
    $passwordProcess.WaitForExit()
    if ($passwordProcess.ExitCode -ne 0) { throw "RustDesk recusou a definição da senha (código $($passwordProcess.ExitCode))." }
    Write-Log 'Senha definida via CLI; o comando retornou sucesso.'
    Write-Output 'RustDesk instalado/configurado. A senha foi aplicada com sucesso.'
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    Write-Error "Falha na instalação/configuração do RustDesk: $($_.Exception.Message)"
    exit 1
} finally {
    $password = $null
    if ($installerPath -and (Test-Path -LiteralPath $installerPath)) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }
    [System.GC]::Collect()
    Write-Log '==== Fim do script ===='
}
