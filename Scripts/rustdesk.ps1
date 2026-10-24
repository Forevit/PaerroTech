<#
.SYNOPSIS
    Instala/atualiza o RustDesk e configura o servidor PaerroTech.
.DESCRIPTION
    Compatível com Windows PowerShell 5.1 e execução por irm | iex.
    Exige sessão elevada; nunca tenta elevar novamente o conteúdo recebido por pipeline.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$rustdeskDefaultExePath = Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'
$rustdeskExePath = $rustdeskDefaultExePath
# O parser de --config foi conferido no código oficial da tag 1.5.0; versões posteriores falham fechadas.
$configSyntaxValidatedThrough = [version]'1.5.0'
$rustdeskServer = 'monitor.paerrotecnologia.com.br'
$rendezvousPort = 21116
$relayPort = 21117
$rustdeskKey = '4XzfD7gwCxuMeW7vjyCRhlwJrU9ovvUAMAkD2x1KFgg='
$logRoot = Join-Path $env:PUBLIC 'Documents\Logs\Outros'
$logFile = Join-Path $logRoot 'rustdesk_script.log'
$script:logReady = $false
$status = [ordered]@{
    '1. Permissões' = 'Não iniciada'
    '2. Ambiente' = 'Não iniciada'
    '3. Release e integridade' = 'Não iniciada'
    '4. Instalação' = 'Não iniciada'
    '5. Servidor' = 'Não iniciada'
    '6. Senha' = 'Não iniciada'
    '7. Validação local' = 'Não iniciada'
    '8. Conexão remota manual' = 'Não confirmada'
    'AnyDesk' = 'Não avaliado'
}
$installerPath = $null
$fatalErrors = New-Object System.Collections.Generic.List[string]

function Write-Log {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Write-ConsoleMessage {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','OK','AVISO','ERRO')][string]$Level = 'INFO'
    )
    $color = switch ($Level) {
        'OK' { 'Green' }
        'AVISO' { 'Yellow' }
        'ERRO' { 'Red' }
        default { 'Cyan' }
    }
    Write-Host ('[{0}] {1}' -f $Level, $Message) -ForegroundColor $color
    if ($script:logReady) {
        $logLevel = switch ($Level) { 'AVISO' { 'WARN' } 'ERRO' { 'ERROR' } default { 'INFO' } }
        Write-Log $Message $logLevel
    }
}

function Write-Stage {
    param([Parameter(Mandatory)][ValidateRange(1,8)][int]$Number, [Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ('-' * 68) -ForegroundColor DarkGray
    Write-ConsoleMessage ('[{0}/8] {1}' -f $Number, $Title) 'INFO'
}

function Show-ExecutionSummary {
    param([Parameter(Mandatory)][bool]$EssentialSuccess, [bool]$RemoteConnectionConfirmed = $false)
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkGray
    Write-Host 'Resumo da execução' -ForegroundColor White
    foreach ($key in $status.Keys) {
        Write-Host ('- {0}: {1}' -f $key, $status[$key])
    }
    if ($script:logReady) {
        Write-Host ('Log: {0}' -f $logFile) -ForegroundColor Gray
    } else {
        Write-Host 'Log: não criado; o script parou antes de preparar o arquivo.' -ForegroundColor Gray
    }
    if (-not $EssentialSuccess) {
        Write-ConsoleMessage 'Configuração essencial do RustDesk não concluída; o AnyDesk foi preservado.' 'ERRO'
    } elseif ($RemoteConnectionConfirmed) {
        Write-ConsoleMessage 'Configuração local concluída e conexão real confirmada pelo técnico. Persistência após reinício ainda não testada.' 'OK'
    } else {
        Write-ConsoleMessage 'Configuração local concluída, mas conexão real não confirmada; AnyDesk preservado por segurança.' 'AVISO'
    }
}

Write-Host ''
Write-Host '====================================================================' -ForegroundColor DarkCyan
Write-Host ' Configuração do RustDesk — Paerro Tecnologia' -ForegroundColor White
Write-Host ' Autor: Eduardo Ferreira' -ForegroundColor Gray
Write-Host ' Objetivo: instalar e configurar RustDesk para acesso remoto técnico.' -ForegroundColor Gray
Write-Host ' O processo verifica a versão, instala/atualiza se necessário, configura' -ForegroundColor Gray
Write-Host ' o servidor personalizado e solicita uma senha permanente.' -ForegroundColor Gray
Write-Host ' O AnyDesk só será considerado após as etapas essenciais serem validadas.' -ForegroundColor Yellow
Write-Host ' Não feche esta janela do PowerShell durante a execução.' -ForegroundColor Yellow
Write-Host '====================================================================' -ForegroundColor DarkCyan

Write-Stage 1 'Verificando permissões administrativas'
# Validar a elevação antes de criar pastas, baixar arquivos ou alterar o computador.
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {
    $status['1. Permissões'] = 'FALHOU: não foi possível verificar a elevação.'
    Write-ConsoleMessage 'Não foi possível verificar os privilégios. Abra o Windows PowerShell como Administrador e execute novamente.' 'ERRO'
    Write-ConsoleMessage 'Nenhuma alteração foi iniciada; o log não foi criado porque a elevação não foi confirmada.' 'AVISO'
    $status['8. Conexão remota manual'] = 'IGNORADA: nenhuma etapa foi executada.'
    $status['AnyDesk'] = 'PRESERVADO: permissões não confirmadas.'
    $global:LASTEXITCODE = 1
    Show-ExecutionSummary $false
    throw 'Execução interrompida: não foi possível confirmar os privilégios administrativos.'
}
if (-not $isAdmin) {
    $status['1. Permissões'] = 'FALHOU: PowerShell sem elevação.'
    Write-ConsoleMessage 'Este script exige privilégios administrativos. Abra o PowerShell como Administrador e execute novamente:' 'ERRO'
    Write-Host 'irm https://raw.githubusercontent.com/Forevit/PaerroTech/main/Scripts/rustdesk.ps1 | iex' -ForegroundColor Gray
    Write-ConsoleMessage 'Nenhuma alteração foi iniciada; o log não foi criado porque a elevação não foi confirmada.' 'AVISO'
    $status['8. Conexão remota manual'] = 'IGNORADA: nenhuma etapa foi executada.'
    $status['AnyDesk'] = 'PRESERVADO: PowerShell sem elevação.'
    $global:LASTEXITCODE = 1
    Show-ExecutionSummary $false
    throw 'Execução interrompida: abra PowerShell como Administrador e execute novamente.'
}
$status['1. Permissões'] = 'Concluída: sessão administrativa confirmada.'
try {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $script:logReady = $true
    Write-Log '==== Início do script RustDesk PaerroTech ===='
    Write-ConsoleMessage 'Privilégios administrativos confirmados.' 'OK'
} catch {
    $status['1. Permissões'] = "FALHOU: não foi possível preparar o log em '$logRoot'."
    Write-ConsoleMessage ("Não foi possível preparar o log. Motivo: {0}" -f $_.Exception.Message) 'ERRO'
    Write-ConsoleMessage 'Procedimento interrompido antes de baixar ou alterar o RustDesk.' 'AVISO'
    $status['8. Conexão remota manual'] = 'IGNORADA: log indisponível.'
    $status['AnyDesk'] = 'PRESERVADO: nenhuma alteração foi feita.'
    $global:LASTEXITCODE = 1
    Show-ExecutionSummary $false
    throw 'Execução interrompida: não foi possível preparar o log.'
}

function Get-InstalledVersion {
    param([string]$Path = $rustdeskExePath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $raw = (Get-Item -LiteralPath $Path).VersionInfo.ProductVersion
    if ($raw -match '(\d+\.\d+\.\d+)') { return [pscustomobject]@{ Raw = $raw; Version = [version]$Matches[1] } }
    throw "Não foi possível interpretar a versão instalada: '$raw'."
}

function Get-ExistingRustDeskInstallation {
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $registrations = @(foreach ($root in $uninstallRoots) {
        Get-ItemProperty -Path $root -ErrorAction Stop | Where-Object { $_.DisplayName -match '(?i)^RustDesk(?:\s|$)' }
    })

    if (-not $registrations) {
        $knownPaths = @(
            (Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'RustDesk\rustdesk.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\RustDesk\rustdesk.exe'),
            (Join-Path $env:LOCALAPPDATA 'RustDesk\rustdesk.exe')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
        if ($knownPaths.Count -gt 0) {
            throw 'Foi encontrado rustdesk.exe em um caminho conhecido, mas sem registro de desinstalação que permita validar sua origem. Instalação ambígua; nenhuma alteração foi feita.'
        }
        return $null
    }

    $candidates = @{}
    foreach ($registration in $registrations) {
        if ([string]$registration.Publisher -notmatch '(?i)RustDesk|Purslane') {
            throw "O registro '$($registration.DisplayName)' não identifica um publicador RustDesk validável. Instalação ambígua; nenhuma alteração foi feita."
        }

        $paths = New-Object System.Collections.Generic.List[string]
        if (-not [string]::IsNullOrWhiteSpace([string]$registration.InstallLocation)) {
            $paths.Add((Join-Path ([string]$registration.InstallLocation) 'rustdesk.exe'))
        }
        $icon = [string]$registration.DisplayIcon
        $iconMatch = [regex]::Match($icon, '^\s*"(?<path>[^"\r\n]+\.exe)"(?:,\d+)?\s*$')
        if (-not $iconMatch.Success) { $iconMatch = [regex]::Match($icon, '^\s*(?<path>[^,\r\n]+?\.exe)(?:,\d+)?\s*$') }
        if ($iconMatch.Success -and [IO.Path]::GetFileName($iconMatch.Groups['path'].Value) -ieq 'rustdesk.exe') {
            $paths.Add($iconMatch.Groups['path'].Value)
        }

        foreach ($candidate in $paths) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidate).Path)
                if (-not $candidates.ContainsKey($resolved)) { $candidates.Add($resolved, $registration) }
            }
        }
    }

    if ($candidates.Count -eq 0) {
        throw 'Há registro de RustDesk, mas não foi possível validar um executável rustdesk.exe pelo registro. Instalação ambígua; nenhuma alteração foi feita.'
    }
    if ($candidates.Count -gt 1) {
        throw 'Foram encontradas múltiplas instalações RustDesk em caminhos diferentes. Nenhuma foi alterada; resolva a ambiguidade manualmente.'
    }

    $path = @($candidates.Keys)[0]
    $registration = $candidates[$path]
    $version = Get-InstalledVersion -Path $path
    if (-not $version) { throw 'O executável registrado não tem uma versão legível.' }
    foreach ($registered in $registrations) {
        $displayVersion = [string]$registered.DisplayVersion
        if (-not [string]::IsNullOrWhiteSpace($displayVersion)) {
            if ($displayVersion -notmatch '(\d+\.\d+\.\d+)') {
                throw 'A versão no registro de desinstalação não pôde ser interpretada; instalação ambígua.'
            }
            if ([version]$Matches[1] -ne $version.Version) {
                throw 'A versão no registro de desinstalação diverge da versão do executável; instalação ambígua.'
            }
        }
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -eq [Management.Automation.SignatureStatus]::Valid) {
        if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)RustDesk|Purslane') {
            throw 'O executável tem assinatura válida, mas o signatário não corresponde ao RustDesk; nenhuma alteração foi feita.'
        }
        $origin = 'Registro do Windows e Authenticode válido para RustDesk.'
    } elseif ($signature.Status -eq [Management.Automation.SignatureStatus]::NotSigned) {
        $origin = 'Registro do Windows indica publicador RustDesk; executável sem Authenticode. Origem limitada ao registro.'
        Write-ConsoleMessage $origin 'AVISO'
    } else {
        throw "Authenticode do executável RustDesk não é confiável (status: $($signature.Status)); nenhuma alteração foi feita."
    }

    return [pscustomobject]@{ Path = $path; Version = $version; Origin = $origin }
}

function Invoke-RustDesk {
    param([Parameter(Mandatory)][string[]]$ArgumentList)
    $p = Start-Process -FilePath $rustdeskExePath -ArgumentList $ArgumentList -Wait -PassThru -ErrorAction Stop
    if ($p.ExitCode -ne 0) { throw "RustDesk retornou código $($p.ExitCode) ao executar a operação." }
    return $p.ExitCode
}

function Get-RustDeskOption {
    param([Parameter(Mandatory)][string]$Name)
    $output = & $rustdeskExePath --option $Name 2>$null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "Não foi possível consultar a opção '$Name' (código $exitCode)." }
    return (@($output) -join "`n").Trim()
}

function ConvertTo-WindowsCommandLineArgument {
    param([Parameter(Mandatory)][string]$Value)
    # Escaping compatível com as regras de parsing de argumentos do Windows.
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
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

function Install-RustDesk {
    param([Parameter(Mandatory)]$Release, $InstalledVersion)
    $asset = $Release.Asset
    $targetVersion = $Release.Version
    $installed = $InstalledVersion
    if ($installed) {
        Write-Log "Versão instalada detectada: $($installed.Raw). Release estável atual: $targetVersion."
        if ($installed.Version -ge $targetVersion) {
            Write-Log 'A versão instalada é igual ou mais recente; instalação ignorada.'
            return "Mantida versão $($installed.Raw) (sem downgrade/reinstalação)."
        }
    }

    $downloadRoot = Join-Path $env:ProgramData 'PaerroTech\RustDesk'
    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    $script:installerPath = Join-Path $downloadRoot ('rustdesk-{0}.exe' -f [guid]::NewGuid().ToString('N'))
    Write-ConsoleMessage "Baixando RustDesk $targetVersion do release oficial." 'INFO'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $script:installerPath -UseBasicParsing
    if (-not (Test-Path -LiteralPath $script:installerPath -PathType Leaf) -or (Get-Item -LiteralPath $script:installerPath).Length -ne [long]$asset.size) {
        throw 'O instalador baixado está ausente ou seu tamanho diverge do asset publicado.'
    }
    $actual = (Get-FileHash -LiteralPath $script:installerPath -Algorithm SHA256).Hash
    $expected = $asset.digest.Substring(7)
    if ($actual -ine $expected) { throw 'SHA-256 do instalador diverge do digest publicado pelo GitHub; instalação cancelada.' }
    Write-ConsoleMessage 'Tamanho e SHA-256 do arquivo conferem com os metadados do release.' 'OK'
    $signature = Get-AuthenticodeSignature -LiteralPath $script:installerPath
    if ($signature.Status -eq [Management.Automation.SignatureStatus]::Valid) {
        if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)RustDesk|Purslane') {
            throw 'O instalador tem assinatura Authenticode válida, mas o signatário não corresponde ao RustDesk.'
        }
        Write-ConsoleMessage 'Authenticode válido e signatário RustDesk confirmado.' 'OK'
    } elseif ($signature.Status -eq [Management.Automation.SignatureStatus]::NotSigned) {
        Write-ConsoleMessage 'O instalador não tem assinatura Authenticode; a origem será aceita somente pela URL oficial e pelo SHA-256 publicado, já conferido.' 'AVISO'
    } else {
        throw "A verificação Authenticode do instalador retornou '$($signature.Status)'; instalação cancelada."
    }

    $process = Start-Process -FilePath $script:installerPath -ArgumentList '--silent-install' -Wait -PassThru -ErrorAction Stop
    if ($process.ExitCode -ne 0) { throw "Instalador terminou com código $($process.ExitCode)." }
    if (-not (Test-Path -LiteralPath $rustdeskExePath -PathType Leaf)) { throw 'Instalador terminou sem criar rustdesk.exe no caminho esperado.' }
    $after = Get-InstalledVersion
    if (-not $after -or $after.Version -lt $targetVersion) { throw 'A versão instalada após o setup não corresponde ao release selecionado.' }
    return "Instalado/atualizado para $($after.Raw)."
}

function Get-RustDeskRelease {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $releaseUri = 'https://api.github.com/repos/rustdesk/rustdesk/releases/latest'
    $release = Invoke-RestMethod -Uri $releaseUri -Method Get -UseBasicParsing -Headers @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'PaerroTech-RustDesk-Installer' }
    if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^\d+\.\d+\.\d+$') {
        throw 'A API não retornou um release estável válido; instalação cancelada.'
    }
    $targetVersion = [version]$release.tag_name
    if ($targetVersion -gt $configSyntaxValidatedThrough) {
        throw "Release $targetVersion posterior à versão $configSyntaxValidatedThrough analisada para --config. Atualização/configuração cancelada até revisão do código dessa versão."
    }
    $assetName = 'rustdesk-{0}-x86_64.exe' -f $release.tag_name
    $asset = @($release.assets | Where-Object { $_.name -eq $assetName }) | Select-Object -First 1
    if (-not $asset -or $asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw 'O release não publica um digest SHA-256 confiável para o instalador Windows x64; instalação cancelada.'
    }
    if ($asset.browser_download_url -notmatch '^https://github\.com/rustdesk/rustdesk/releases/download/') {
        throw 'A origem do instalador não corresponde ao repositório oficial RustDesk; instalação cancelada.'
    }
    return [pscustomobject]@{ Asset = $asset; Version = $targetVersion }
}

function Configure-RustDesk {
    param([Parameter(Mandatory)][version]$Version)
    if ($Version -gt $configSyntaxValidatedThrough) {
        throw "A versão instalada $Version é posterior à versão $configSyntaxValidatedThrough analisada para --config."
    }
    $service = Get-Service -Name 'rustdesk' -ErrorAction SilentlyContinue
    if (-not $service) {
        Invoke-RustDesk -ArgumentList @('--install-service') | Out-Null
        $service = Get-Service -Name 'rustdesk' -ErrorAction Stop
    }
    if ($service.Status -ne 'Running') {
        Start-Service -Name 'rustdesk' -ErrorAction Stop
    }
    (Get-Service -Name 'rustdesk' -ErrorAction Stop).WaitForStatus('Running', [TimeSpan]::FromSeconds(45))
    $config = 'host={0}:{1},key={2},relay={0}:{3}' -f $rustdeskServer, $rendezvousPort, $rustdeskKey, $relayPort
    Invoke-RustDesk -ArgumentList @('--config', $config) | Out-Null

    # O código 1.5.0 ignora silenciosamente strings não reconhecidas e ainda retorna;
    # consulte o estado atual por --option para não confiar apenas no exit code.
    $actualHost = Get-RustDeskOption -Name 'custom-rendezvous-server'
    $actualKey = Get-RustDeskOption -Name 'key'
    $actualRelay = Get-RustDeskOption -Name 'relay-server'
    $expectedHost = '{0}:{1}' -f $rustdeskServer, $rendezvousPort
    $expectedRelay = '{0}:{1}' -f $rustdeskServer, $relayPort
    if ($actualHost -ne $expectedHost -or $actualKey -ne $rustdeskKey -or $actualRelay -ne $expectedRelay) {
        throw 'A leitura posterior das opções não corresponde ao host, à chave pública e ao relay PaerroTech.'
    }
    $service = Get-Service -Name 'rustdesk' -ErrorAction Stop
    $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(45))
    return 'Serviço estava Running antes da configuração; --config aplicado e host, chave e relay conferidos por --option. Reinicialização ainda não testada.'
}

function Test-SecureStringEqual {
    param([Parameter(Mandatory)][Security.SecureString]$First, [Parameter(Mandatory)][Security.SecureString]$Second)
    $firstBstr = [IntPtr]::Zero
    $secondBstr = [IntPtr]::Zero
    $firstPlain = $null
    $secondPlain = $null
    try {
        $firstBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($First)
        $secondBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Second)
        $firstPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($firstBstr)
        $secondPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secondBstr)
        return [string]::Equals($firstPlain, $secondPlain, [StringComparison]::Ordinal)
    } finally {
        if ($firstBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($firstBstr) }
        if ($secondBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secondBstr) }
        $firstPlain = $null
        $secondPlain = $null
    }
}

function Set-RustDeskPassword {
    $secure = $null
    $confirmation = $null
    $bstr = [IntPtr]::Zero
    $plain = $null
    try {
        $secure = Read-Host 'Digite a senha permanente do RustDesk (mínimo 8 caracteres)' -AsSecureString
        if ($secure.Length -lt 8) { throw 'Senha inválida: use pelo menos 8 caracteres.' }
        $confirmation = Read-Host 'Digite novamente a senha para confirmar' -AsSecureString
        if (-not (Test-SecureStringEqual -First $secure -Second $confirmation)) {
            throw 'A confirmação não corresponde à senha digitada; o comando não foi executado.'
        }
        Write-ConsoleMessage 'Confirmação conferida. O argumento --password ficará temporariamente na linha de comando do processo RustDesk.' 'AVISO'
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $rustdeskExePath
        $psi.Arguments = '--password ' + (ConvertTo-WindowsCommandLineArgument $plain)
        $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { throw "A CLI do RustDesk retornou código $($p.ExitCode) ao aplicar a senha." }
        return 'Comando retornou código 0; o RustDesk não oferece consulta confiável para confirmar que a senha foi persistida. Validação manual necessária.'
    } finally {
        if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $plain = $null
        if ($secure) { $secure.Dispose() }
        if ($confirmation) { $confirmation.Dispose() }
    }
}

function Confirm-RemoteConnection {
    if (-not [Environment]::UserInteractive) {
        throw 'Não há sessão interativa. A confirmação manual não pode ser obtida; AnyDesk será preservado.'
    }
    try {
        if ([Console]::IsInputRedirected) {
            throw 'A entrada do terminal está redirecionada. Não é possível obter confirmação manual segura.'
        }
    } catch [System.NotSupportedException] {
        # Alguns hosts interativos não expõem redirecionamento de Console; Read-Host ainda será validado.
    }
    Write-ConsoleMessage 'Confirme somente depois de fazer uma conexão real a partir de outro dispositivo usando o ID deste RustDesk e a senha recém-configurada.' 'AVISO'
    Write-ConsoleMessage 'A presença do serviço e as opções locais não provam conectividade. Digite SIM para confirmar que a sessão remota funcionou; Enter ou qualquer outra resposta preserva o AnyDesk.' 'INFO'
    $response = Read-Host 'A conexão real foi estabelecida com sucesso? Digite SIM para confirmar'
    return ([string]$response).Trim() -ieq 'SIM'
}

function Remove-AnyDesk {
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $entries = @(foreach ($root in $uninstallRoots) {
        Get-ItemProperty -Path $root -ErrorAction Stop | Where-Object { $_.DisplayName -match '(?i)^AnyDesk' }
    })
    if (-not $entries) {
        $portable = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { $_.Name -match '(?i)^AnyDesk.*\.exe$' })
        $service = @(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object { $_.Name -match '(?i)AnyDesk' -or $_.DisplayName -match '(?i)AnyDesk' -or $_.PathName -match '(?i)AnyDesk' })
        if ($portable -or $service) { throw 'Foi detectado processo ou serviço AnyDesk sem desinstalador registrado. Não foi removido automaticamente; revise e remova manualmente.' }
        return 'Nenhuma entrada encontrada em HKLM 64/32-bit ou HKCU desta sessão, nem processo/serviço identificado. Perfis de outros usuários e cópias portáteis inativas não foram pesquisados.'
    }
    foreach ($entry in $entries) {
        $command = [string]$entry.QuietUninstallString
        if ([string]::IsNullOrWhiteSpace($command)) {
            if ([string]::IsNullOrWhiteSpace([string]$entry.UninstallString)) {
                throw "AnyDesk '$($entry.DisplayName)' não publicou QuietUninstallString nem UninstallString; remova manualmente pelas Configurações do Windows."
            }
            throw "AnyDesk '$($entry.DisplayName)' só publicou UninstallString normal. Como não é garantidamente silencioso, não foi executado; remova manualmente pelas Configurações do Windows."
        }

        # Aceita apenas comando direto e inequívoco para um executável AnyDesk assinado.
        # Comandos MSI, scripts e desinstaladores intermediários ficam para remoção manual.
        $match = [regex]::Match($command, '^\s*"(?<exe>[^"\r\n]+\.exe)"(?<args>\s+[^\r\n]*)?\s*$')
        if (-not $match.Success) {
            $match = [regex]::Match($command, '^\s*(?<exe>[^\s"\r\n]+\.exe)(?<args>\s+[^\r\n]*)?\s*$')
        }
        if (-not $match.Success) {
            throw "QuietUninstallString de '$($entry.DisplayName)' não é um comando direto validável; pode usar um intermediário. Não foi executado; remova manualmente."
        }
        $exe = $match.Groups['exe'].Value
        $args = $match.Groups['args'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($args)) {
            throw "QuietUninstallString de '$($entry.DisplayName)' não informa argumentos próprios de desinstalação; não foi executado. Remova manualmente."
        }
        if ([IO.Path]::GetFileName($exe) -notmatch '(?i)^AnyDesk.*\.exe$' -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
            throw "QuietUninstallString de '$($entry.DisplayName)' não aponta diretamente para um executável AnyDesk existente; não foi executado. Remova manualmente."
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $exe
        if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
            -not $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch '(?i)(AnyDesk|philandro)') {
            throw "A assinatura do executável em QuietUninstallString de '$($entry.DisplayName)' não pôde ser validada como AnyDesk; não foi executado. Remova manualmente."
        }
        $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -ErrorAction Stop
        if ($p.ExitCode -ne 0) { throw "Desinstalador AnyDesk retornou código $($p.ExitCode)." }
    }
    Start-Sleep -Seconds 2
    $stillRegistered = @(foreach ($root in $uninstallRoots) {
        Get-ItemProperty -Path $root -ErrorAction Stop | Where-Object { $_.DisplayName -match '(?i)^AnyDesk' }
    })
    $stillRunning = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { $_.Name -match '(?i)^AnyDesk.*\.exe$' })
    $stillService = @(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object { $_.Name -match '(?i)AnyDesk' -or $_.DisplayName -match '(?i)AnyDesk' -or $_.PathName -match '(?i)AnyDesk' })
    if ($stillRegistered -or $stillRunning -or $stillService) { throw 'A verificação encontrou instalação, serviço ou processo AnyDesk após o desinstalador.' }
    return 'Desinstalador registrado executado; após a execução não havia entrada em HKLM 64/32-bit ou HKCU desta sessão, processo nem serviço AnyDesk identificado. Perfis de outros usuários e cópias portáteis inativas não foram pesquisados; dados não foram apagados.'
}

$installedVersion = $null
$existingInstallation = $null
$releaseInfo = $null
$rustDeskReadyForAnyDeskRemoval = $false
$remoteConnectionConfirmed = $false

Write-Stage 2 'Verificando o ambiente'
try {
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'Este instalador oficial selecionado requer Windows x64; nenhuma instalação foi iniciada.'
    }
    Write-ConsoleMessage 'Arquitetura do Windows: x64.' 'INFO'
    $existingInstallation = Get-ExistingRustDeskInstallation
    if ($existingInstallation) {
        $rustdeskExePath = $existingInstallation.Path
        $installedVersion = $existingInstallation.Version
        if ($installedVersion.Version -gt $configSyntaxValidatedThrough) {
            throw "Foi encontrada a versão $($installedVersion.Raw), posterior à última versão analisada ($configSyntaxValidatedThrough). Nenhuma alteração será feita até revisão da CLI."
        }
        Write-ConsoleMessage ("RustDesk detectado em {0}: versão {1}. Origem: {2}" -f $rustdeskExePath, $installedVersion.Raw, $existingInstallation.Origin) 'INFO'
        Write-ConsoleMessage 'Será mantida se for igual ou mais recente que o release selecionado; downgrade não será feito.' 'INFO'
    } else {
        Write-ConsoleMessage 'Nenhuma instalação RustDesk registrada ou nos caminhos conhecidos foi encontrada; será feita uma instalação nova.' 'INFO'
    }
    $status['2. Ambiente'] = 'Concluída: Windows x64 verificado e estado instalado consultado.'
    Write-ConsoleMessage $status['2. Ambiente'] 'OK'
} catch {
    $status['2. Ambiente'] = "FALHOU: $($_.Exception.Message)"
    $fatalErrors.Add($status['2. Ambiente'])
    Write-ConsoleMessage $status['2. Ambiente'] 'ERRO'
}

Write-Stage 3 'Obtendo a versão estável e validando os metadados'
if ($fatalErrors.Count -eq 0) {
    try {
        Write-ConsoleMessage 'Consultando o release estável mais recente e o digest SHA-256 publicado.' 'INFO'
        $releaseInfo = Get-RustDeskRelease
        $status['3. Release e integridade'] = "Concluída: release estável $($releaseInfo.Version) selecionado; digest SHA-256 disponível para validação do arquivo."
        Write-ConsoleMessage ("Versão selecionada: {0}. O instalador será validado antes de executar." -f $releaseInfo.Version) 'OK'
    } catch {
        $status['3. Release e integridade'] = "FALHOU: $($_.Exception.Message)"
        $fatalErrors.Add($status['3. Release e integridade'])
        Write-ConsoleMessage $status['3. Release e integridade'] 'ERRO'
    }
} else {
    $status['3. Release e integridade'] = 'IGNORADA porque a verificação do ambiente falhou.'
    Write-ConsoleMessage $status['3. Release e integridade'] 'AVISO'
}

Write-Stage 4 'Instalando ou verificando o RustDesk'
if ($fatalErrors.Count -eq 0) {
    try {
        if ($installedVersion -and $installedVersion.Version -lt $releaseInfo.Version -and
            -not [string]::Equals([IO.Path]::GetFullPath($rustdeskExePath), [IO.Path]::GetFullPath($rustdeskDefaultExePath), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'A instalação antiga está fora do caminho padrão. Não conheço um parâmetro de atualização validado para esse caminho; atualize manualmente para evitar uma segunda instalação.'
        }
        $installResult = Install-RustDesk -Release $releaseInfo -InstalledVersion $installedVersion
        if (-not (Test-Path -LiteralPath $rustdeskExePath -PathType Leaf)) {
            throw 'O executável RustDesk não existe no caminho esperado após a operação.'
        }
        $verifiedVersion = Get-InstalledVersion
        if (-not $verifiedVersion -or $verifiedVersion.Version -lt $releaseInfo.Version) {
            throw 'A versão encontrada após a operação é inferior ao release estável selecionado.'
        }
        $status['4. Instalação'] = "Concluída: $installResult Executável presente; versão efetiva $($verifiedVersion.Raw)."
        Write-ConsoleMessage $status['4. Instalação'] 'OK'
    } catch {
        $status['4. Instalação'] = "FALHOU: $($_.Exception.Message)"
        $fatalErrors.Add($status['4. Instalação'])
        Write-ConsoleMessage $status['4. Instalação'] 'ERRO'
    }
} else {
    $status['4. Instalação'] = 'IGNORADA porque uma etapa anterior falhou.'
    Write-ConsoleMessage $status['4. Instalação'] 'AVISO'
}

Write-Stage 5 'Configurando e conferindo o servidor PaerroTech'
if ($fatalErrors.Count -eq 0) {
    try {
        Write-ConsoleMessage ("Servidor: {0}; rendezvous: {1}; relay: {2}." -f $rustdeskServer, $rendezvousPort, $relayPort) 'INFO'
        $status['5. Servidor'] = Configure-RustDesk -Version $verifiedVersion.Version
        Write-ConsoleMessage $status['5. Servidor'] 'OK'
    } catch {
        $status['5. Servidor'] = "FALHOU: $($_.Exception.Message)"
        $fatalErrors.Add($status['5. Servidor'])
        Write-ConsoleMessage $status['5. Servidor'] 'ERRO'
    }
} else {
    $status['5. Servidor'] = 'IGNORADA porque uma etapa anterior falhou.'
    Write-ConsoleMessage $status['5. Servidor'] 'AVISO'
}

Write-Stage 6 'Configurando a senha permanente'
if ($fatalErrors.Count -eq 0) {
    try {
        Write-ConsoleMessage 'A entrada será oculta e solicitada duas vezes. O RustDesk não oferece consulta confiável para confirmar a senha gravada.' 'INFO'
        $status['6. Senha'] = Set-RustDeskPassword
        Write-ConsoleMessage 'A CLI terminou com código zero; isso não comprova persistência da senha.' 'OK'
    } catch {
        $status['6. Senha'] = 'FALHOU: senha inválida, confirmação divergente ou CLI não concluiu com código zero. Detalhes sensíveis omitidos.'
        $fatalErrors.Add($status['6. Senha'])
        Write-ConsoleMessage $status['6. Senha'] 'ERRO'
    }
} else {
    $status['6. Senha'] = 'IGNORADA porque uma etapa essencial anterior falhou.'
    Write-ConsoleMessage $status['6. Senha'] 'AVISO'
}

Write-Stage 7 'Validando o resultado local'
if ($fatalErrors.Count -eq 0) {
    try {
        $actualHost = Get-RustDeskOption -Name 'custom-rendezvous-server'
        $actualKey = Get-RustDeskOption -Name 'key'
        $actualRelay = Get-RustDeskOption -Name 'relay-server'
        $expectedHost = '{0}:{1}' -f $rustdeskServer, $rendezvousPort
        $expectedRelay = '{0}:{1}' -f $rustdeskServer, $relayPort
        if ($actualHost -ne $expectedHost -or $actualKey -ne $rustdeskKey -or $actualRelay -ne $expectedRelay) {
            throw 'A leitura local de host, chave pública ou relay não corresponde aos valores PaerroTech.'
        }
        $service = Get-Service -Name 'rustdesk' -ErrorAction Stop
        $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(45))
        if (-not (Test-Path -LiteralPath $rustdeskExePath -PathType Leaf)) { throw 'O executável RustDesk não está presente.' }
        $status['7. Validação local'] = 'Concluída: executável e versão verificados; serviço Running; host, chave pública e relay conferidos por --option. Isso não valida conexão remota nem persistência após reinício.'
        Write-ConsoleMessage $status['7. Validação local'] 'OK'
        Write-ConsoleMessage 'A conexão remota ainda não foi confirmada.' 'AVISO'
        $rustDeskReadyForAnyDeskRemoval = $true
    } catch {
        $status['7. Validação local'] = "FALHOU: $($_.Exception.Message)"
        $fatalErrors.Add($status['7. Validação local'])
        Write-ConsoleMessage $status['7. Validação local'] 'ERRO'
    }
} else {
    $status['7. Validação local'] = 'IGNORADA porque uma etapa essencial falhou.'
    Write-ConsoleMessage $status['7. Validação local'] 'AVISO'
}

Write-Stage 8 'Confirmando manualmente a conexão remota'
if ($rustDeskReadyForAnyDeskRemoval -and $fatalErrors.Count -eq 0) {
    try {
        $remoteConnectionConfirmed = Confirm-RemoteConnection
        if ($remoteConnectionConfirmed) {
            $status['8. Conexão remota manual'] = 'CONFIRMADA pelo técnico após conexão real.'
            Write-ConsoleMessage $status['8. Conexão remota manual'] 'OK'
        } else {
            $status['8. Conexão remota manual'] = 'NÃO CONFIRMADA; resposta diferente de SIM ou Enter. AnyDesk será preservado.'
            Write-ConsoleMessage $status['8. Conexão remota manual'] 'AVISO'
        }
    } catch {
        $remoteConnectionConfirmed = $false
        $status['8. Conexão remota manual'] = "NÃO CONFIRMADA: $($_.Exception.Message)"
        Write-ConsoleMessage $status['8. Conexão remota manual'] 'AVISO'
    }
} else {
    $status['8. Conexão remota manual'] = 'IGNORADA porque uma etapa essencial falhou; AnyDesk será preservado.'
    Write-ConsoleMessage $status['8. Conexão remota manual'] 'AVISO'
}

Write-ConsoleMessage 'Subetapa: remoção conservadora do AnyDesk.' 'INFO'
if ($rustDeskReadyForAnyDeskRemoval -and $remoteConnectionConfirmed -and $fatalErrors.Count -eq 0) {
    try {
        $status['AnyDesk'] = Remove-AnyDesk
        if ($status['AnyDesk'] -match 'Nenhuma entrada encontrada') {
            Write-ConsoleMessage $status['AnyDesk'] 'AVISO'
        } else {
            Write-ConsoleMessage $status['AnyDesk'] 'OK'
        }
    } catch {
        $status['AnyDesk'] = "AVISO: $($_.Exception.Message)"
        Write-ConsoleMessage $status['AnyDesk'] 'AVISO'
    }
} else {
    $status['AnyDesk'] = 'PRESERVADO: conexão real não confirmada ou uma etapa essencial falhou; desinstalação ignorada por segurança.'
    Write-ConsoleMessage $status['AnyDesk'] 'AVISO'
}

if ($installerPath -and (Test-Path -LiteralPath $installerPath)) {
    Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
}
Show-ExecutionSummary ($fatalErrors.Count -eq 0) $remoteConnectionConfirmed
Write-Log '==== Fim do script ===='
if ($fatalErrors.Count -gt 0) {
    $global:LASTEXITCODE = 1
    throw 'Uma ou mais etapas essenciais falharam. Consulte o resumo e o log; o AnyDesk foi preservado.'
}
$global:LASTEXITCODE = 0
