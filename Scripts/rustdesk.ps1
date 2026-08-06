<#
.SYNOPSIS
    Instalação/atualização do RustDesk (instalador visível, não-silencioso) + aplicação de configuração TOML.
.NOTES
    Correções aplicadas em relação à versão original:
      - $rustdeskKey e $rustdeskServer agora são de fato interpolados no TOML.
      - Resolução do usuário interativo logado (necessário porque, mesmo elevando via UAC,
        o processo pode acabar rodando sob outra conta admin) em vez de confiar em $env:USERNAME.
      - $ErrorActionPreference global 'SilentlyContinue' removido; passos críticos usam try/catch.
      - Checagem de exit code do instalador e validação do download (tamanho + SHA256 opcional).
      - Escrita dos arquivos TOML sem BOM (evita problemas de parsing já vistos em outros scripts).
      - Auto-elevação via UAC (mesmo padrão da Preventiva) em vez de simplesmente abortar se não-admin.
      - --silent-install removido: instalador roda visível e o script espera ele fechar.
      - Limpeza da variável de senha em memória após uso.
#>

# ==== Configuração ====
$logFile            = "C:\Temp\rustdesk_script.log"
$requiredVersion    = "1.4.2"
$rustdeskDownload   = "https://github.com/rustdesk/rustdesk/releases/download/1.4.2/rustdesk-1.4.2-x86_64.exe"
$installTempPath    = "C:\Temp\rustdesk.exe"
$rustdeskExePath    = "C:\Program Files\RustDesk\rustdesk.exe"
$rustdeskLogDir     = "$env:APPDATA\RustDesk\log"
$serviceConfigPath  = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml"

# URL raw onde este script fica hospedado, usada para o relançamento elevado
# (mesmo padrão da Preventiva e do Scripts/rustdesk.ps1 do repo). Ajuste se o
# caminho final no PaerroTech for diferente.
$scriptSelfUrl      = "https://raw.githubusercontent.com/Forevit/PaerroTech/main/Scripts/rustdesk.ps1"

# ---- Preencher antes de rodar em produção ----
$rustdeskServer         = 'monitor.paerrotecnologia.com.br'
$rustdeskKey            = '4XzfD7gwCxuMeW7vjyCRhlwJrU9ovvUAMAkD2x1KFgg='
$rustdeskPasswordPlain  = 'qaz.123'
$rustdeskSha256         = ''   # opcional: hash SHA256 do instalador, se quiser validar integridade

# NOTA DE SEGURANÇA: o RustDesk só aceita definir a senha permanente via CLI
# (--password), então ela fica visível em texto puro no command line do processo
# enquanto ele roda (visível via Task Manager/WMI). Isso não tem como ser
# totalmente evitado com a abordagem atual do RustDesk; a variável é limpa da
# memória do script logo após o uso, mas a janela de exposição do processo filho
# permanece. Se isso for um problema de compliance, vale investigar se sua versão
# do RustDesk aceita 'password_hash' direto no TOML.

# ==== Funções ====

function Write-Log {
    param([string]$message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $message" | Out-File -Append -FilePath $logFile
}

function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-ContentNoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-LoggedOnUserProfilePath {
    # Resolve o perfil do usuário logado interativamente, independente do
    # contexto em que o script está rodando (ex.: SYSTEM via RMM).
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $fullUser = $cs.UserName   # formato DOMINIO\usuario ou MAQUINA\usuario
        if (-not $fullUser) {
            Write-Log "Nenhum usuário logado interativamente detectado."
            return $null
        }
        $userOnly    = $fullUser.Split('\')[-1]
        $profilePath = Join-Path "C:\Users" $userOnly
        if (Test-Path $profilePath) {
            Write-Log "Usuário logado detectado: $fullUser (perfil: $profilePath)"
            return $profilePath
        } else {
            Write-Log "Perfil não encontrado em '$profilePath' para o usuário '$fullUser'."
            return $null
        }
    } catch {
        Write-Log "Falha ao resolver usuário logado: $($_.Exception.Message)"
        return $null
    }
}

# ==== Auto-elevação (mesma lógica da Preventiva) ====
# Se não estiver rodando como admin, relança elevado via UAC repuxando o
# próprio script pela URL raw (necessário porque, em execução via irm | iex,
# $PSCommandPath é nulo — não dá pra simplesmente re-invocar "-File $PSCommandPath").
if (-not (Test-IsAdmin)) {

    Start-Process powershell `
        -Verb RunAs `
        -ArgumentList "-ExecutionPolicy Bypass -Command `"irm $scriptSelfUrl | iex`""

    return
}

Write-Log "==== Script Start ===="

# ==== 0) Checar versão instalada ====
$skipInstall = $false
if (Test-Path $rustdeskExePath) {
    try {
        $versionInfo     = (Get-Command $rustdeskExePath).FileVersionInfo
        $installedVersion = $versionInfo.ProductVersion
        Write-Log "RustDesk detectado. Versão instalada: $installedVersion"
        if ([version]$installedVersion -ge [version]$requiredVersion) {
            Write-Log "RustDesk já está na versão exigida ($requiredVersion) ou superior. Pulando instalação."
            $skipInstall = $true
        } else {
            Write-Log "Versão instalada ($installedVersion) é menor que a exigida ($requiredVersion). Atualizando."
        }
    } catch {
        Write-Log "Falha ao obter versão instalada: $($_.Exception.Message). Prosseguindo com a instalação."
    }
} else {
    Write-Log "RustDesk não está instalado. Prosseguindo com a instalação."
}

# ==== 1) Criar diretório temporário ====
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
    Write-Log "Diretório temporário criado."
}

if (-not $skipInstall) {

    # ==== 2) Download com validação ====
    try {
        Write-Log "Baixando RustDesk $requiredVersion..."
        Invoke-WebRequest -Uri $rustdeskDownload -OutFile $installTempPath -ErrorAction Stop

        if (-not (Test-Path $installTempPath) -or (Get-Item $installTempPath).Length -eq 0) {
            throw "Arquivo baixado está vazio ou não existe."
        }
        Write-Log "Download concluído ($((Get-Item $installTempPath).Length) bytes)."

        if ($rustdeskSha256) {
            $actualHash = (Get-FileHash -Path $installTempPath -Algorithm SHA256).Hash
            if ($actualHash -ne $rustdeskSha256) {
                throw "Hash SHA256 não confere. Esperado: $rustdeskSha256 / Obtido: $actualHash"
            }
            Write-Log "Integridade do instalador verificada via SHA256."
        }
    } catch {
        Write-Log "ERRO no download: $($_.Exception.Message)"
        Write-Output "Falha ao baixar o instalador do RustDesk. Veja $logFile."
        exit 1
    }

    # ==== 3) Instalação (não-silenciosa — abre o instalador normalmente) ====
    try {
        Write-Log "Instalando RustDesk (instalador visível, aguardando conclusão)..."
        $proc = Start-Process -FilePath $installTempPath -Wait -PassThru -ErrorAction Stop
        if ($proc.ExitCode -ne 0) {
            throw "Instalador retornou código de saída $($proc.ExitCode)."
        }
        Write-Log "Instalação concluída."
        Start-Sleep -Seconds 5
    } catch {
        Write-Log "ERRO na instalação: $($_.Exception.Message)"
        Write-Output "Falha ao instalar o RustDesk. Veja $logFile."
        exit 1
    }

    # ==== 3.1) Parar serviço e processos (não fatal se falhar) ====
    try {
        Write-Log "Parando serviço RustDesk..."
        net stop rustdesk 2>&1 | Out-Null
        Get-Process rustdesk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } catch {
        Write-Log "Aviso: falha ao parar serviço/processo RustDesk: $($_.Exception.Message)"
    }
}

# ==== 4) Gerar e aplicar configuração TOML ====
$toml = @"
rendezvous_server = '$rustdeskServer:21116'
nat_type = 1
serial = 0

[options]
av1-test = 'Y'
allow-remote-config-modification = 'Y'
relay-server = '$rustdeskServer'
allow-auto-update = 'Y'
key = '$rustdeskKey'
custom-rendezvous-server = '$rustdeskServer'
verification-method = 'use-permanent-password'

"@

$defaultToml = @"
[options]
view_style = 'adaptive'
"@

$loggedUserProfile = Get-LoggedOnUserProfilePath
$configPaths = @()
if ($loggedUserProfile) {
    $configPaths += Join-Path $loggedUserProfile "AppData\Roaming\RustDesk\config\RustDesk2.toml"
} else {
    Write-Log "Aviso: config do usuário interativo não será aplicada (usuário não detectado)."
}
$configPaths += $serviceConfigPath

foreach ($path in $configPaths) {
    try {
        $dir = Split-Path $path
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Log "Diretório $dir criado."
        }

        Set-ContentNoBom -Path $path -Content $toml
        Write-Log "Configuração TOML escrita em $path."

        $defaultPath = Join-Path -Path $dir -ChildPath "RustDesk_default.toml"
        Set-ContentNoBom -Path $defaultPath -Content $defaultToml
        Write-Log "Configuração TOML padrão escrita em $defaultPath."
    } catch {
        Write-Log "ERRO ao escrever configuração em '$path': $($_.Exception.Message)"
    }
}

# ==== 5) Iniciar serviço RustDesk ====
try {
    Write-Log "Iniciando serviço RustDesk..."
    net start rustdesk 2>&1 | Out-Null
    Start-Sleep -Seconds 5
} catch {
    Write-Log "Aviso: falha ao iniciar serviço RustDesk: $($_.Exception.Message)"
}

# ==== 6) Definir senha de acesso ====
try {
    Write-Log "Definindo senha de acesso do RustDesk..."
    Start-Process -FilePath $rustdeskExePath -ArgumentList "--password", $rustdeskPasswordPlain -Wait -ErrorAction Stop
    Start-Sleep -Seconds 5
} catch {
    Write-Log "ERRO ao definir senha: $($_.Exception.Message)"
} finally {
    # Limpa a senha da memória do script assim que possível.
    $rustdeskPasswordPlain = $null
    [System.GC]::Collect()
}

# ==== 7) Validar configuração nos logs ====
Write-Log "Validando configuração de senha nos logs..."
if (Test-Path $rustdeskLogDir) {
    $logs = Get-ChildItem -Path $rustdeskLogDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 3
    $found = $false
    foreach ($log in $logs) {
        if (Select-String -Path $log.FullName -Pattern "password" -Quiet) {
            Write-Log "Entrada relacionada a senha encontrada em $($log.Name)."
            Write-Output "Senha definida (verificação encontrada em $($log.Name)). Confira o log se quiser confirmar que não é uma mensagem de erro."
            $found = $true
            break
        }
    }
    if (-not $found) {
        Write-Log "Nenhuma entrada relacionada a senha encontrada nos logs recentes."
        Write-Output "Aviso: nenhuma confirmação de senha detectada nos logs."
    }
} else {
    Write-Log "Diretório de log do RustDesk não encontrado: $rustdeskLogDir"
    Write-Output "Diretório de log do RustDesk não encontrado."
}

Write-Log "==== Script End ===="
Write-Output "Script completo. Verifique $logFile para mais detalhes."
