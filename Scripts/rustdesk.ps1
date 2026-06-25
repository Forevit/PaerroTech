# ==========================================================
# Projeto: Implantação RustDesk 
# By Eduardo Ferreira | Paerro Tecnologia
# ==========================================================

# -------------------------
# CONFIGURAÇÕES
# -------------------------
$RustDeskUrl = "https://github.com/rustdesk/rustdesk/releases/download/1.4.7/rustdesk-1.4.7-x86_64.exe"
$TomlUrl = "https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPOSITORIO/main/RustDesk2.toml"

# -------------------------
# VALIDAÇÃO ADMIN
# -------------------------
$Admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $Admin) {
    Write-Host ""
    Write-Host "Execute o PowerShell como Administrador." -ForegroundColor Red
    return
}

# -------------------------
# VALIDAÇÃO DE CONFIGURAÇÃO
# -------------------------
if ($TomlUrl -match "SEU_USUARIO|SEU_REPOSITORIO") {
    Write-Host ""
    Write-Host "Atualize a variavel `$TomlUrl com o link real do RustDesk2.toml antes de executar." -ForegroundColor Red
    return
}

# -------------------------
# LOG
# -------------------------
$LogFolder = "C:\Users\Public\Documents\Logs\Outros"

if (!(Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}

$LogFile = Join-Path $LogFolder ("RustDesk_Deploy_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

function Write-Log {
    param([string]$Message)

    $Linha = "[{0}] {1}" -f (Get-Date -Format "dd/MM/yyyy HH:mm:ss"), $Message

    Add-Content -Path $LogFile -Value $Linha

    Write-Host $Linha
}

Write-Log "=================================================="
Write-Log "Projeto: Implantação RustDesk"
Write-Log "By Eduardo Ferreira"
Write-Log "=================================================="

Write-Log "Computador: $env:COMPUTERNAME"
Write-Log "Usuario: $env:USERNAME"

try {
    $SO = (Get-CimInstance Win32_OperatingSystem).Caption
    Write-Log "Sistema Operacional: $SO"
}
catch {
    Write-Log "Nao foi possivel identificar o sistema operacional."
}

# -------------------------
# REMOVER ANYDESK
# -------------------------
function Remove-AnyDesk {

    Write-Log "Iniciando remocao do AnyDesk"

    Get-Process AnyDesk -ErrorAction SilentlyContinue | Stop-Process -Force

    Stop-Service AnyDesk -Force -ErrorAction SilentlyContinue

    sc.exe delete AnyDesk | Out-Null

    $Paths = @(
        "$env:ProgramFiles\AnyDesk",
        "${env:ProgramFiles(x86)}\AnyDesk",
        "$env:ProgramData\AnyDesk",
        "$env:APPDATA\AnyDesk",
        "$env:LOCALAPPDATA\AnyDesk"
    )

    foreach ($Path in $Paths) {

        if (Test-Path $Path) {

            try {
                Remove-Item $Path -Recurse -Force -ErrorAction Stop
                Write-Log "Removido: $Path"
            }
            catch {
                Write-Log "Falha ao remover: $Path"
            }
        }
    }

    Write-Log "Remocao do AnyDesk concluida"
}

# -------------------------
# INSTALAR RUSTDESK
# -------------------------
function Install-RustDesk {

    if (Get-Service RustDesk -ErrorAction SilentlyContinue) {

        Write-Log "RustDesk ja esta instalado."

        return
    }

    $Installer = "$env:TEMP\RustDesk.exe"

    Write-Log "Baixando RustDesk"

    Invoke-WebRequest -Uri $RustDeskUrl -OutFile $Installer

    Write-Log "Instalando RustDesk"

    Start-Process -FilePath $Installer -ArgumentList "--silent-install" -Wait

    # Espera ativa pelo servico em vez de Start-Sleep fixo -
    # garante que a instalacao de fato concluiu antes de seguir
    $Timeout = 30
    $Elapsed = 0
    while (-not (Get-Service RustDesk -ErrorAction SilentlyContinue) -and $Elapsed -lt $Timeout) {
        Start-Sleep -Seconds 2
        $Elapsed += 2
    }

    if (-not (Get-Service RustDesk -ErrorAction SilentlyContinue)) {
        throw "Servico RustDesk nao foi criado apos $Timeout segundos - instalacao pode ter falhado"
    }

    Write-Log "RustDesk instalado com sucesso"
}

# -------------------------
# CONFIGURAR RUSTDESK
# -------------------------
function Set-RustDeskConfig {

    Write-Log "Aplicando configuracao"

    # IMPORTANTE: o servico RustDesk roda como conta LocalService, nao como
    # o usuario logado. Para acesso unattended funcionar mesmo sem ninguem
    # logado (ex: apos reboot), o toml precisa estar nos DOIS perfis abaixo.
    $ConfigFolder = "$env:APPDATA\RustDesk\config"
    $ServiceConfigFolder = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config"

    foreach ($Folder in @($ConfigFolder, $ServiceConfigFolder)) {
        if (!(Test-Path $Folder)) {
            New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        }
    }

    $TempToml = "$env:TEMP\RustDesk2.toml"

    Invoke-WebRequest -Uri $TomlUrl -OutFile $TempToml

    Copy-Item $TempToml "$ConfigFolder\RustDesk2.toml" -Force
    Copy-Item $TempToml "$ServiceConfigFolder\RustDesk2.toml" -Force

    # Hash de referencia para a verificacao pos-restart (ver Test-RustDeskConfigIntegrity)
    $script:TomlHashEsperado = (Get-FileHash $TempToml -Algorithm SHA256).Hash

    $ServidorConfigurado = Get-Content $TempToml | Where-Object { $_ -match "rendezvous_server|custom-rendezvous-server" } | Select-Object -First 1
    if (-not $ServidorConfigurado) { $ServidorConfigurado = "(nao identificado no toml baixado)" }

    Write-Log "Servidor configurado: $ServidorConfigurado"
    Write-Log "Arquivo RustDesk2.toml aplicado em perfil de usuario e em LocalService"
}

# -------------------------
# VERIFICAÇÃO DE INTEGRIDADE DO CONFIG
# -------------------------
function Test-RustDeskConfigIntegrity {

    # Algumas versoes do RustDesk sobrescrevem o RustDesk2.toml com o
    # default ao subir pela primeira vez. Esta funcao confere se o
    # arquivo aplicado sobreviveu e reaplica se necessario.

    Write-Log "Verificando integridade do RustDesk2.toml apos start do servico"

    Start-Sleep -Seconds 5

    $Caminhos = @(
        "$env:APPDATA\RustDesk\config\RustDesk2.toml",
        "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml"
    )

    foreach ($Path in $Caminhos) {

        if (-not (Test-Path $Path)) {
            Write-Log "AVISO: $Path nao existe apos start do servico"
            continue
        }

        $HashAtual = (Get-FileHash $Path -Algorithm SHA256).Hash

        if ($HashAtual -ne $script:TomlHashEsperado) {
            Write-Log "AVISO: $Path foi sobrescrito pelo RustDesk (bug conhecido de overwrite no primeiro launch). Reaplicando..."
            Copy-Item "$env:TEMP\RustDesk2.toml" $Path -Force
        }
        else {
            Write-Log "OK: $Path integro"
        }
    }
}

# -------------------------
# SERVIÇO
# -------------------------
function Start-RustDeskService {

    Write-Log "Configurando servico RustDesk"

    Set-Service -Name RustDesk -StartupType Automatic

    Restart-Service -Name RustDesk -Force

    # Espera ativa pelo status Running em vez de assumir sucesso
    $Timeout = 30
    $Elapsed = 0
    while ((Get-Service RustDesk).Status -ne 'Running' -and $Elapsed -lt $Timeout) {
        Start-Sleep -Seconds 2
        $Elapsed += 2
    }

    if ((Get-Service RustDesk).Status -ne 'Running') {
        Write-Log "AVISO: servico RustDesk nao chegou a Running apos $Timeout segundos"
    }
    else {
        Write-Log "Servico iniciado com sucesso"
    }

    Test-RustDeskConfigIntegrity
}

# -------------------------
# CONFIRMAÇÃO SENHA
# -------------------------
function Confirm-UnattendedPassword {

    # A senha padrao da Paerro NAO fica neste script. O tecnico define
    # manualmente via CLI usando o comando abaixo, com o servico ja
    # rodando, e so confirma aqui que foi feito.

    $RustDeskExe = "$env:ProgramFiles\RustDesk\rustdesk.exe"

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "ATENCAO" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Defina a senha padrao de acesso nao supervisionado executando, em outra janela:"
    Write-Host ""
    Write-Host "    & `"$RustDeskExe`" --password `"SUA_SENHA_PADRAO_AQUI`"" -ForegroundColor White
    Write-Host ""
    Write-Host "Substitua SUA_SENHA_PADRAO_AQUI pela senha padronizada da Paerro."
    Write-Host "A senha deve ser definida antes de finalizar este procedimento."
    Write-Host ""

    do {

        $Confirmacao = Read-Host "Digite SIM apos definir a senha para confirmar"

    } until ($Confirmacao.ToUpper() -eq "SIM")

    Write-Host ""
    Write-Host "Confirmacao registrada." -ForegroundColor Green

    Write-Log "Tecnico confirmou definicao da senha padrao via CLI (rustdesk.exe --password)."
}

# -------------------------
# EXECUÇÃO
# -------------------------
try {

    Remove-AnyDesk

    Install-RustDesk

    Set-RustDeskConfig

    Start-RustDeskService

    Confirm-UnattendedPassword

    Write-Log "Implantacao finalizada com sucesso"
}
catch {

    Write-Log "ERRO: $($_.Exception.Message)"

    throw
}
