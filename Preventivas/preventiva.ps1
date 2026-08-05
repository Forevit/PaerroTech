# ============================================================
#  PREVENTIVA CORPORATIVA - PADRONIZACAO DE MAQUINA v2.0
#  By Eduardo Ferreira | Paerro Tecnologia
# ============================================================

$ProfileAgeMonths             = 3
$WindowsUpdateTimeoutSeconds  = 1800
$GLPITimeoutSeconds           = 300

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

        [int]$TimeoutSeconds = 500,

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
            Write-Log "Nao foi possivel encerrar ${StepName}: $($_.Exception.Message)" "ERRO"
        }
        return [PSCustomObject]@{ Sucesso = $false; TimedOut = $true; ExitCode = $null }
    }

    if ($Process.ExitCode -eq 0) {
        Write-Log "$StepName finalizado com sucesso" "OK"
        return [PSCustomObject]@{ Sucesso = $true; TimedOut = $false; ExitCode = 0 }
    }

    Write-Log "$StepName finalizado com codigo $($Process.ExitCode)" "ALERTA"
    return [PSCustomObject]@{ Sucesso = $false; TimedOut = $false; ExitCode = $Process.ExitCode }
}

# ── Formata o tamanho de uma atualizacao do Windows Update para exibicao ──
function Format-UpdateSize {
    param($Size)

    if ($null -eq $Size -or $Size -eq "") { return "Desconhecido" }
    if ($Size -is [string]) { return $Size }

    try {
        $MB = [math]::Round([double]$Size / 1MB, 1)
        return "$MB MB"
    }
    catch {
        return "$Size"
    }
}

# ── Menu generico de selecao usado por Windows Update e Limpeza de Perfis ──
# Centraliza a logica repetida de "listar opcoes + ler indices + TODOS/CANCELAR"
function Read-MenuSelection {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Itens,

        [Parameter(Mandatory = $true)]
        [scriptblock]$FormatoLinha,

        [string]$Titulo = "OPCOES DISPONIVEIS",
        [string]$Prompt = "Sua escolha"
    )

    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host $Titulo -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow

    for ($i = 0; $i -lt $Itens.Count; $i++) {
        $Linha = & $FormatoLinha $Itens[$i] ($i + 1)
        Write-Host $Linha -ForegroundColor Cyan
    }

    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "Opcoes de Entrada:" -ForegroundColor Gray
    Write-Host " - Digite os indices separados por virgula (Ex: 1,3)" -ForegroundColor Gray
    Write-Host " - Digite TODOS para selecionar a lista completa" -ForegroundColor Gray
    Write-Host " - Digite CANCELAR para nao selecionar nada" -ForegroundColor Gray
    Write-Host ""

    $Escolha = Read-Host $Prompt

    if ($Escolha -eq "TODOS") {
        return $Itens
    }

    if ($Escolha -eq "CANCELAR" -or [string]::IsNullOrWhiteSpace($Escolha)) {
        return @()
    }

    $Selecionados = @()
    $Indices = $Escolha -split ',' | ForEach-Object { $_.Trim() }

    foreach ($IdxStr in $Indices) {
        $Idx = 0
        if ([int]::TryParse($IdxStr, [ref]$Idx) -and $Idx -ge 1 -and $Idx -le $Itens.Count) {
            $Selecionados += $Itens[$Idx - 1]
        }
    }

    return $Selecionados
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

# ── Aciona o Windows Update via UsoClient quando o PSWindowsUpdate falha ──
function Invoke-WindowsUpdateFallbackUsoClient {
    Write-Log "Tentando fallback via UsoClient..." "ALERTA"
    try {
        if (Test-CommandExists "UsoClient.exe") {
            Start-Process UsoClient.exe -ArgumentList "StartScan" -NoNewWindow
            Start-Process UsoClient.exe -ArgumentList "StartDownload" -NoNewWindow
            Start-Process UsoClient.exe -ArgumentList "StartInstall" -NoNewWindow
            Write-Log "UsoClient acionado para Windows Update (sem confirmacao de execucao real, pois UsoClient nao retorna status)" "ALERTA"
            $script:Status_WindowsUpdate = "FALLBACK USOCLIENT"
        }
        else {
            Write-Log "UsoClient.exe nao encontrado. Windows Update nao pode ser acionado" "ERRO"
            $script:Status_WindowsUpdate = "ERRO"
        }
    }
    catch {
        Write-Log "Erro no fallback Windows Update: $($_.Exception.Message)" "ERRO"
        $script:Status_WindowsUpdate = "ERRO"
    }
}

# ── Garante que o servico "Microsoft Update" esta registrado no WUA.
# Sem isso, buscas com -MicrosoftUpdate podem silenciosamente nao
# retornar nada mesmo com atualizacoes pendentes ──
function Confirm-MicrosoftUpdateServiceRegistered {
    try {
        $MSUpdateServiceID = "7971f918-a847-4430-9279-4a52d1efe18d"
        $Registrado = Get-WUServiceManager -ErrorAction SilentlyContinue | Where-Object { $_.ServiceID -eq $MSUpdateServiceID }

        if (-not $Registrado) {
            Write-Log "Servico Microsoft Update nao registrado no WUA. Registrando..." "ALERTA"
            Add-WUServiceManager -MicrosoftUpdate -Confirm:$false -ErrorAction Stop | Out-Null
            Write-Log "Servico Microsoft Update registrado com sucesso" "OK"
        }
        else {
            Write-Log "Servico Microsoft Update ja registrado no WUA" "INFO"
        }
        return $true
    }
    catch {
        Write-Log "Nao foi possivel registrar o servico Microsoft Update: $($_.Exception.Message)" "ALERTA"
        return $false
    }
}

# ── Instala os KBs selecionados em um PROCESSO elevado separado, e nao
# em um Start-Job. O WUA (COM) e sensivel ao contexto de execucao e
# historicamente falha/trava quando chamado de dentro de jobs em
# background; um processo powershell.exe normal, elevado e monitorado
# via Invoke-ProcessWithTimeout, e mais confiavel ──
function Install-SelectedWindowsUpdates {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$KBsAlvo,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $PastaTemp = Join-Path $env:TEMP "PreventivaWU"
    if (!(Test-Path $PastaTemp)) { New-Item -ItemType Directory -Path $PastaTemp -Force | Out-Null }

    $ScriptInstalacao = Join-Path $PastaTemp "instalar_updates.ps1"
    $LogInstalacao    = Join-Path $PastaTemp "instalar_updates.log"

    if (Test-Path $LogInstalacao) { Remove-Item $LogInstalacao -Force -ErrorAction SilentlyContinue }

    $KBsFormatados = ($KBsAlvo | ForEach-Object { "'$_'" }) -join ","

    $ConteudoScript = @"
try {
    Import-Module PSWindowsUpdate -Force
    `$KBs = @($KBsFormatados)
    if (`$KBs.Count -gt 0) {
        Get-WindowsUpdate -MicrosoftUpdate -KBArticleID `$KBs -Install -AcceptAll -IgnoreReboot -Confirm:`$false -Verbose *> '$LogInstalacao'
    }
    else {
        Get-WindowsUpdate -MicrosoftUpdate -Install -AcceptAll -IgnoreReboot -Confirm:`$false -Verbose *> '$LogInstalacao'
    }
    exit 0
}
catch {
    `$_.Exception.Message | Out-File -FilePath '$LogInstalacao' -Append
    exit 1
}
"@

    Set-Content -Path $ScriptInstalacao -Value $ConteudoScript -Encoding UTF8

    Write-Log "Instalando atualizacoes em processo separado (timeout: $TimeoutSeconds s)..." "INFO"

    $Resultado = Invoke-ProcessWithTimeout `
        -FilePath "powershell.exe" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptInstalacao`"") `
        -TimeoutSeconds $TimeoutSeconds `
        -StepName "Instalacao do Windows Update"

    if (Test-Path $LogInstalacao) {
        Get-Content $LogInstalacao | ForEach-Object { Write-Log "WU: $_" "INFO" }
    }

    return $Resultado
}

function Invoke-WindowsUpdateStep {
    if ($SkipWindowsUpdate) {
        Write-Log "Windows Update ignorado por parametro" "ALERTA"
        $script:Status_WindowsUpdate = "IGNORADO"
        return
    }


    $script:Status_WindowsUpdate = "ERRO"

    # ── Validacao 1: o servico Windows Update (wuauserv) esta de fato rodando ──
    try {
        $ServicoWU = Get-Service -Name "wuauserv" -ErrorAction Stop

        if ($ServicoWU.StartType -eq "Disabled") {
            Write-Log "Servico Windows Update (wuauserv) esta DESABILITADO. Habilitando..." "ALERTA"
            Set-Service -Name "wuauserv" -StartupType Manual
        }

        if ($ServicoWU.Status -ne "Running") {
            Write-Log "Servico wuauserv parado. Iniciando..." "ALERTA"
            Start-Service -Name "wuauserv"
            Start-Sleep -Seconds 2
        }

        if ((Get-Service -Name "wuauserv").Status -eq "Running") {
            Write-Log "Servico Windows Update (wuauserv) confirmado em execucao" "OK"
        }
        else {
            Write-Log "Servico Windows Update (wuauserv) nao iniciou. Abortando etapa" "ERRO"
            $script:Status_WindowsUpdate = "SERVICO PARADO"
            return
        }
    }
    catch {
        Write-Log "Nao foi possivel verificar o servico wuauserv: $($_.Exception.Message)" "ERRO"
        return
    }

    # ── Garante modulo PSWindowsUpdate disponivel ──
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
    }
    catch {
        Write-Log "Falha ao preparar modulo PSWindowsUpdate: $($_.Exception.Message)" "ERRO"
        Invoke-WindowsUpdateFallbackUsoClient
        return
    }

    # ── Garante que o servico Microsoft Update esta registrado no WUA ──
    Confirm-MicrosoftUpdateServiceRegistered | Out-Null

    # ── Busca (sem instalar ainda) para listar o que esta disponivel, com tamanho ──
    Write-Log "Buscando atualizacoes disponiveis (somente busca, nada sera instalado ainda)..." "INFO"

    try {
        $UpdatesDisponiveis = @(Get-WindowsUpdate -MicrosoftUpdate -IgnoreReboot -ErrorAction Stop)
    }
    catch {
        Write-Log "Falha ao buscar atualizacoes via PSWindowsUpdate: $($_.Exception.Message)" "ALERTA"
        Invoke-WindowsUpdateFallbackUsoClient
        return
    }

    if ($UpdatesDisponiveis.Count -eq 0) {
        Write-Log "Nenhuma atualizacao do Windows pendente. Sistema atualizado" "OK"
        $script:Status_WindowsUpdate = "OK"
        return
    }

    $UpdatesAlvo = Read-MenuSelection `
        -Itens $UpdatesDisponiveis `
        -Titulo "ATUALIZACOES DO WINDOWS DISPONIVEIS" `
        -Prompt "Quais atualizacoes deseja instalar?" `
        -FormatoLinha {
            param($U, $Numero)
            $TamanhoFormatado = Format-UpdateSize -Size $U.Size
            " [{0}] {1} | KB: {2} | Tamanho: {3}" -f $Numero, $U.Title, $U.KB, $TamanhoFormatado
        }

    if ($UpdatesAlvo.Count -eq 0) {
        Write-Log "Nenhuma selecao valida de Windows Update realizada pelo tecnico (ou cancelado)" "ALERTA"
        $script:Status_WindowsUpdate = "CANCELADO"
        return
    }

    $KBsAlvo = @($UpdatesAlvo | ForEach-Object { $_.KB } | Where-Object { $_ })
    Write-Log "Instalando $($UpdatesAlvo.Count) atualizacao(oes) selecionada(s) pelo tecnico: $($KBsAlvo -join ', ')" "INFO"

    $Resultado = Install-SelectedWindowsUpdates -KBsAlvo $KBsAlvo -TimeoutSeconds $WindowsUpdateTimeoutSeconds

    if ($Resultado.TimedOut) {
        Write-Log "Instalacao do Windows Update excedeu o timeout configurado ($WindowsUpdateTimeoutSeconds s). O Windows Update pode continuar instalando em segundo plano; valide manualmente depois" "ALERTA"
        $script:Status_WindowsUpdate = "TIMEOUT"
        return
    }

    # ── Validacao 2: confirma no HISTORICO real do Windows Update que a instalacao ocorreu ──
    Start-Sleep -Seconds 5

    try {
        $Historico  = Get-WUHistory -Last 25 -ErrorAction SilentlyContinue
        $Instalados = @()
        $ComFalha   = @()

        foreach ($KB in $KBsAlvo) {
            $Entrada = $Historico | Where-Object { $_.KB -eq $KB } | Sort-Object Date -Descending | Select-Object -First 1

            if ($Entrada -and $Entrada.Result -match "Succeeded|Sucesso") {
                $Instalados += $KB
            }
            else {
                $ComFalha += $KB
            }
        }

        if ($ComFalha.Count -eq 0) {
            Write-Log "Validado no historico: todas as atualizacoes selecionadas foram instaladas com sucesso" "OK"
            $script:Status_WindowsUpdate = "OK"
        }
        elseif ($Instalados.Count -gt 0) {
            Write-Log "Instalacao parcial. Confirmadas: $($Instalados -join ', ') | Pendentes/Falha: $($ComFalha -join ', ')" "ALERTA"
            $script:Status_WindowsUpdate = "PARCIAL"
        }
        else {
            Write-Log "Nenhuma das atualizacoes selecionadas foi confirmada no historico do Windows Update. Verifique manualmente" "ERRO"
            $script:Status_WindowsUpdate = "NAO CONFIRMADO"
        }
    }
    catch {
        Write-Log "Nao foi possivel validar via Get-WUHistory: $($_.Exception.Message)" "ALERTA"
        $script:Status_WindowsUpdate = "NAO VALIDADO"
    }
}

# ── Le a versao do Office instalado a partir do registro do Click-to-Run ──
function Get-OfficeC2RVersion {
    $CaminhosRegistro = @(
        "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration"
    )

    foreach ($Caminho in $CaminhosRegistro) {
        if (Test-Path $Caminho) {
            $Valor = Get-ItemProperty -Path $Caminho -Name "VersionToReport" -ErrorAction SilentlyContinue
            if ($Valor) { return $Valor.VersionToReport }
        }
    }

    return $null
}

# ── MODIFICACAO: agora valida de fato se o Office atualizou, comparando
# a versao antes/depois e aguardando o processo real do updater
# (OfficeClickToRun.exe), em vez de confiar no ExitCode do launcher
# (que retorna 0 quase sempre, mesmo sem atualizar nada) ──
function Invoke-OfficeUpdateStep {
    if ($SkipOfficeUpdate) {
        Write-Log "Office Update ignorado por parametro" "ALERTA"
        $script:Status_Office = "IGNORADO"
        return
    }

    $script:Status_Office = "NAO INSTALADO"

    $OfficeC2RPaths = @(
        "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe",
        "C:\Program Files (x86)\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
    )

    $OfficeC2R = $OfficeC2RPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $OfficeC2R) {
        Write-Log "OfficeC2RClient.exe nao encontrado (Office nao instalado via Click-to-Run)" "ALERTA"
        return
    }

    $VersaoAntes = Get-OfficeC2RVersion
    Write-Log "Versao do Office antes da atualizacao: $VersaoAntes" "INFO"

    Write-Log "Disparando atualizacao do Office..." "INFO"
    Start-Process -FilePath $OfficeC2R -ArgumentList @("/update", "user", "displaylevel=false", "forceappshutdown=true") -NoNewWindow

    # ── Aguarda o processo real do updater aparecer e depois terminar ──
    $UpdaterEncontrado = $false
    $TentativasEspera = 0

    while ($TentativasEspera -lt 30) {
        if (Get-Process -Name "OfficeClickToRun" -ErrorAction SilentlyContinue) {
            $UpdaterEncontrado = $true
            break
        }
        Start-Sleep -Seconds 2
        $TentativasEspera++
    }

    if ($UpdaterEncontrado) {
        Write-Log "Processo de atualizacao do Office (OfficeClickToRun) detectado. Aguardando finalizar..." "INFO"
        $LimiteEspera = (Get-Date).AddMinutes(15)
        while ((Get-Process -Name "OfficeClickToRun" -ErrorAction SilentlyContinue) -and (Get-Date) -lt $LimiteEspera) {
            Start-Sleep -Seconds 5
        }
    }
    else {
        Write-Log "Processo de atualizacao do Office nao foi detectado em 60s. Pode ja estar atualizado ou o update nao iniciou" "ALERTA"
    }

    Start-Sleep -Seconds 3
    $VersaoDepois = Get-OfficeC2RVersion
    Write-Log "Versao do Office apos a atualizacao: $VersaoDepois" "INFO"

    if ($VersaoAntes -and $VersaoDepois -and $VersaoAntes -ne $VersaoDepois) {
        Write-Log "Office atualizado com sucesso: $VersaoAntes -> $VersaoDepois" "OK"
        $script:Status_Office = "ATUALIZADO ($VersaoDepois)"
    }
    elseif ($VersaoDepois) {
        Write-Log "Office ja estava na versao mais recente: $VersaoDepois" "OK"
        $script:Status_Office = "JA ATUALIZADO ($VersaoDepois)"
    }
    else {
        Write-Log "Nao foi possivel confirmar a versao do Office apos a atualizacao" "ALERTA"
        $script:Status_Office = "NAO CONFIRMADO"
    }
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

# ── Retorna a data de uso mais confiavel de um perfil, cruzando o
# LastUseTime do Win32_UserProfile (pouco confiavel para contas de AD,
# onde o registro de ProfileList nem sempre e atualizado no logoff)
# com o LastWriteTime do arquivo NTUSER.DAT do proprio perfil, que
# reflete a ultima vez que o hive do usuario foi de fato gravado ──
function Get-ProfileLastUsedDate {
    param(
        [Parameter(Mandatory = $true)]
        $Perfil
    )

    $DataWmi = Convert-WmiDateSafe -WmiDate $Perfil.LastUseTime

    $DataNtUser = $null
    $CaminhoNtUser = Join-Path $Perfil.LocalPath "NTUSER.DAT"
    if (Test-Path $CaminhoNtUser) {
        try {
            $DataNtUser = (Get-Item $CaminhoNtUser -Force -ErrorAction Stop).LastWriteTime
        }
        catch {
            $DataNtUser = $null
        }
    }

    if ($DataWmi -and $DataNtUser) {
        if ($DataWmi -gt $DataNtUser) { return $DataWmi } else { return $DataNtUser }
    }
    elseif ($DataNtUser) {
        return $DataNtUser
    }
    else {
        return $DataWmi
    }
}

function Remove-OldProfilesStep {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($SkipProfiles) {
        Write-Log "Limpeza de perfis ignorada por parametro" "ALERTA"
        return
    }

    $UsuarioAtual = $env:USERNAME

    # ── Auditoria: ultimo login (WMI + NTUSER.DAT) de todos os perfis locais ──
    $TodosPerfis = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.Special -eq $false -and
        $_.LocalPath -like "C:\Users\*" -and
        $_.LocalPath -notmatch "\\Default" -and
        $_.LocalPath -notmatch "\\Public"
    }

    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "AUDITORIA - ULTIMO USO DE TODOS OS PERFIS LOCAIS (WMI + NTUSER.DAT)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    foreach ($P in $TodosPerfis) {
        $NomeUsuario     = Split-Path $P.LocalPath -Leaf
        $UltimoUsoAud    = Get-ProfileLastUsedDate -Perfil $P
        $StatusCarregado = if ($P.Loaded) { "LOGADO AGORA" } else { "" }
        $DataTexto       = if ($UltimoUsoAud) { $UltimoUsoAud.ToString('dd/MM/yyyy HH:mm') } else { "Sem registro / nunca logou" }

        Write-Host (" - {0,-20} Ultimo uso: {1,-20} {2}" -f $NomeUsuario, $DataTexto, $StatusCarregado) -ForegroundColor Gray
        Write-Log "Auditoria de perfil: $NomeUsuario | Ultimo uso: $DataTexto" "INFO"
    }
    Write-Host "============================================================`n" -ForegroundColor Cyan

    $Limite = (Get-Date).AddMonths(-$ProfileAgeMonths)

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

    $PerfisCandidatos = @()

    foreach ($Perfil in $Perfis) {
        $UltimoUso = Get-ProfileLastUsedDate -Perfil $Perfil

        if (-not $UltimoUso) {
            continue
        }

        if ($UltimoUso -lt $Limite) {
            $PerfisCandidatos += [PSCustomObject]@{
                PerfilObj = $Perfil
                Usuario   = Split-Path $Perfil.LocalPath -Leaf
                Caminho   = $Perfil.LocalPath
                UltimoUso = $UltimoUso
            }
        }
    }

    if (-not $PerfisCandidatos -or $PerfisCandidatos.Count -eq 0) {
        Write-Log "Nenhum perfil sem uso ha mais de $ProfileAgeMonths meses encontrado." "OK"
        return
    }

    $PerfisAlvo = Read-MenuSelection `
        -Itens $PerfisCandidatos `
        -Titulo "PERFIS DETECTADOS (Sem uso ha mais de $ProfileAgeMonths meses)" `
        -Prompt "Quais perfis deseja remover?" `
        -FormatoLinha {
            param($P, $Numero)
            " [{0}] Perfil: {1} | Ultimo uso: {2}" -f $Numero, $P.Usuario, $P.UltimoUso.ToString('dd/MM/yyyy')
        }

    if ($PerfisAlvo.Count -eq 0) {
        Write-Log "Nenhuma selecao valida de perfis realizada pelo tecnico (ou cancelado)." "ALERTA"
        return
    }

    Write-Host "`nVOCE SELECIONOU OS SEGUINTES PERFIS PARA EXCLUSAO:" -ForegroundColor Red
    foreach ($Alvo in $PerfisAlvo) {
        Write-Host " - $($Alvo.Usuario) [$($Alvo.Caminho)]" -ForegroundColor Yellow
    }

    $ConfirmacaoFinal = Read-Host "`nConfirma a exclusao definitiva destes $($PerfisAlvo.Count) perfis? Digite APAGAR para prosseguir"

    if ($ConfirmacaoFinal -ne "APAGAR") {
        Write-Log "Acao abortada de ultima hora pelo tecnico." "ALERTA"
        return
    }

    foreach ($Item in $PerfisAlvo) {
        $Perfil = $Item.PerfilObj
        try {
            if ($PSCmdlet.ShouldProcess($Item.Caminho, "Remover perfil inativo")) {
                Remove-CimInstance $Perfil -ErrorAction Stop
                Write-Log "Perfil removido com sucesso: $($Item.Usuario)" "OK"
            }
        }
        catch {
            Write-Log "Erro ao remover perfil $($Item.Usuario): $($_.Exception.Message)" "ERRO"
        }
    }
}

function Invoke-CleanupStep {
    if ($SkipCleanup) {
        Write-Log "Limpeza de disco ignorada por parametro" "ALERTA"
        return
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
Write-Host "Remocao de perfis: usuarios sem uso ha mais de $ProfileAgeMonths meses" -ForegroundColor Gray
Write-Host "Timeout Windows Update: $WindowsUpdateTimeoutSeconds segundos" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Invoke-Step -Nome "Administrador local" -Acao { Set-LocalAdministrator }
Invoke-Step -Nome "Status de ativacao do Windows" -Acao { Get-WindowsActivationStatus }
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
