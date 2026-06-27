# ============================================================
#  PREVENTIVA CORPORATIVA - PADRONIZACAO DE MAQUINA v2.1
#  By Eduardo Ferreira | Paerro Tecnologia
# ============================================================

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipAdmin,
    [switch]$SkipWindowsUpdate,
    [switch]$SkipOfficeUpdate,
    [switch]$SkipWinget,
    [switch]$SkipDrivers,
    [switch]$SkipGLPI,
    [switch]$SkipProfiles,
    [switch]$SkipCleanup,
    [switch]$NoReboot,
    [int]$ProfileAgeMonths = 6,
    [int]$GLPITimeoutSeconds = 300,
    [int]$WindowsUpdateTimeoutSeconds = 1800
)

# ── Auto-elevacao ────────────────────────────────────────────
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")

if (-not $IsAdmin) {

    if ($PSCommandPath) {
        $ScriptPath = $PSCommandPath
    }
    else {
        $ScriptUrl  = "https://raw.githubusercontent.com/Forevit/PaerroTech/main/Preventivas/preventiva.ps1"
        $ScriptPath = Join-Path $env:TEMP "Preventiva-Corporativa_$(Get-Random).ps1"
        Invoke-WebRequest -Uri $ScriptUrl -OutFile $ScriptPath -UseBasicParsing
    }

    $Argumentos = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$ScriptPath`""
    )

    foreach ($Parametro in $PSBoundParameters.Keys) {
        $Valor = $PSBoundParameters[$Parametro]

        if ($Valor -is [switch] -or $Valor -eq $true) {
            $Argumentos += "-$Parametro"
        }
        else {
            $Argumentos += "-$Parametro"
            $Argumentos += "$Valor"
        }
    }

    Start-Process PowerShell -Verb RunAs -ArgumentList $Argumentos
    exit
}

# ── Forca UTF-8 para evitar mojibake na saida de comandos externos ──
chcp 65001 | Out-Null
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================
# LOG ESTRUTURADO
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

    switch ($Nivel) {
        "OK"     { Write-Host $Mensagem -ForegroundColor Green }
        "ERRO"   { Write-Host $Mensagem -ForegroundColor Red }
        "ALERTA" { Write-Host $Mensagem -ForegroundColor Yellow }
        default  { Write-Host $Mensagem }
    }
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

function Test-Internet {
    try {
        $Teste = Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
        return [bool]$Teste
    }
    catch {
        return $false
    }
}

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

        [int]$TimeoutSeconds = 300,

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
        return $false
    }

    if ($Process.ExitCode -eq 0) {
        Write-Log "$StepName finalizado com sucesso" "OK"
        return $true
    }

    Write-Log "$StepName finalizado com codigo $($Process.ExitCode)" "ALERTA"
    return $false
}

# ── MODIFICACAO: Timeout generico para cmdlets/modulos (nao apenas processos externos) ──
# Usado pelo Windows Update, ja que o PSWindowsUpdate roda dentro da propria sessao
# e nao gera um processo externo que o Invoke-ProcessWithTimeout possa monitorar.
function Invoke-ScriptBlockWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList = @(),

        [int]$TimeoutSeconds = 300,

        [string]$StepName = "Tarefa"
    )

    $Job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList

    if (Wait-Job -Job $Job -Timeout $TimeoutSeconds) {
        $JobErro   = $Job.ChildJobs[0].Error
        $Resultado = Receive-Job -Job $Job -ErrorAction SilentlyContinue
        Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue

        if ($JobErro -and $JobErro.Count -gt 0) {
            Write-Log "$StepName retornou erro: $($JobErro[0])" "ERRO"
            return [PSCustomObject]@{ Sucesso = $false; TimedOut = $false; Resultado = $Resultado }
        }

        Write-Log "$StepName finalizado dentro do tempo limite ($TimeoutSeconds s)" "OK"
        return [PSCustomObject]@{ Sucesso = $true; TimedOut = $false; Resultado = $Resultado }
    }
    else {
        Write-Log "$StepName excedeu o timeout de $TimeoutSeconds segundos. Encerrando job..." "ALERTA"
        Stop-Job -Job $Job -ErrorAction SilentlyContinue
        Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ Sucesso = $false; TimedOut = $true; Resultado = $null }
    }
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

# ── MODIFICAÇÃO 1: Confirmação de senha dupla (Set-LocalAdministrator) ────────
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

        # Conversao temporaria e segura para comparacao de strings limpas
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
# OBS: o UsoClient nao retorna status de execucao real, entao essa via fica
# marcada como "FALLBACK USOCLIENT" no checklist final, e nao "OK".
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

# ── MODIFICACAO: valida que o servico esta realmente rodando, lista as
# atualizacoes disponiveis com tamanho, deixa o tecnico escolher o que instalar,
# instala com timeout real (job) e confirma no historico do Windows Update
# que a instalacao de fato ocorreu (em vez de confiar apenas no retorno do comando) ──
function Invoke-WindowsUpdateStep {
    if ($SkipWindowsUpdate) {
        Write-Log "Windows Update ignorado por parametro" "ALERTA"
        $script:Status_WindowsUpdate = "IGNORADO"
        return
    }

    if (-not $script:InternetOK) {
        Write-Log "Windows Update ignorado: sem internet" "ALERTA"
        $script:Status_WindowsUpdate = "SEM INTERNET"
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

    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "ATUALIZACOES DO WINDOWS DISPONIVEIS" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow

    for ($i = 0; $i -lt $UpdatesDisponiveis.Count; $i++) {
        $U = $UpdatesDisponiveis[$i]
        $TamanhoFormatado = Format-UpdateSize -Size $U.Size
        Write-Host (" [{0}] {1} | KB: {2} | Tamanho: {3}" -f ($i + 1), $U.Title, $U.KB, $TamanhoFormatado) -ForegroundColor Cyan
    }

    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "Opcoes de Entrada:" -ForegroundColor Gray
    Write-Host " - Digite os indices separados por virgula (Ex: 1,3)" -ForegroundColor Gray
    Write-Host " - Digite TODOS para instalar a lista completa" -ForegroundColor Gray
    Write-Host " - Digite CANCELAR para nao instalar nada agora" -ForegroundColor Gray
    Write-Host ""

    $Escolha = Read-Host "Quais atualizacoes deseja instalar?"

    $UpdatesAlvo = @()

    if ($Escolha -eq "TODOS") {
        $UpdatesAlvo = $UpdatesDisponiveis
    }
    elseif ($Escolha -eq "CANCELAR" -or [string]::IsNullOrWhiteSpace($Escolha)) {
        Write-Log "Instalacao de Windows Update cancelada pelo tecnico" "ALERTA"
        $script:Status_WindowsUpdate = "CANCELADO"
        return
    }
    else {
        $Indices = $Escolha -split ',' | ForEach-Object { $_.Trim() }
        foreach ($IdxStr in $Indices) {
            $Idx = 0
            if ([int]::TryParse($IdxStr, [ref]$Idx) -and $Idx -ge 1 -and $Idx -le $UpdatesDisponiveis.Count) {
                $UpdatesAlvo += $UpdatesDisponiveis[$Idx - 1]
            }
        }
    }

    if ($UpdatesAlvo.Count -eq 0) {
        Write-Log "Nenhuma selecao valida de Windows Update realizada pelo tecnico" "ALERTA"
        $script:Status_WindowsUpdate = "NENHUMA SELECAO"
        return
    }

    $KBsAlvo = @($UpdatesAlvo | ForEach-Object { $_.KB } | Where-Object { $_ })
    Write-Log "Instalando $($UpdatesAlvo.Count) atualizacao(oes) selecionada(s) pelo tecnico: $($KBsAlvo -join ', ')" "INFO"

    # ── Instalacao com timeout real, em job separado (nao bloqueia indefinidamente) ──
    $Resultado = Invoke-ScriptBlockWithTimeout -StepName "Instalacao do Windows Update" -TimeoutSeconds $WindowsUpdateTimeoutSeconds -ArgumentList (, $KBsAlvo) -ScriptBlock {
        param($KBs)
        Import-Module PSWindowsUpdate -Force
        if ($KBs -and $KBs.Count -gt 0) {
            Get-WindowsUpdate -MicrosoftUpdate -KBArticleID $KBs -Install -AcceptAll -IgnoreReboot -Confirm:$false -ErrorAction Stop
        }
        else {
            Get-WindowsUpdate -MicrosoftUpdate -Install -AcceptAll -IgnoreReboot -Confirm:$false -ErrorAction Stop
        }
    }

    if ($Resultado.TimedOut) {
        Write-Log "Instalacao do Windows Update excedeu o timeout configurado ($WindowsUpdateTimeoutSeconds s). O Windows Update pode continuar instalando em segundo plano mesmo com o job interrompido; valide manualmente depois" "ALERTA"
        $script:Status_WindowsUpdate = "TIMEOUT"
        return
    }

    # ── Validacao 2: confirma no HISTORICO real do Windows Update que a instalacao ocorreu ──
    # (em vez de confiar apenas no codigo de retorno do comando)
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

function Invoke-OfficeUpdateStep {
    if ($SkipOfficeUpdate) {
        Write-Log "Office Update ignorado por parametro" "ALERTA"
        return
    }

    $OfficeC2RPaths = @(
        "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe",
        "C:\Program Files (x86)\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
    )

    $OfficeC2R = $OfficeC2RPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($OfficeC2R) {
        Write-Log "Atualizando Office Click-to-Run..." "INFO"
        Write-Log "Valide a Ativação do OFFICE"
        Invoke-NativeCommand -FilePath $OfficeC2R -Arguments @("/update", "user", "displaylevel=false", "forceappshutdown=true") -SuccessMessage "Office Update acionado" -ErrorMessage "Office Update retornou erro"
    }
    else {
        Write-Log "OfficeC2RClient.exe nao encontrado" "ALERTA"
    }
}

# ── MODIFICACAO: validacao explicita de que o winget esta de fato instalado
# (executavel encontrado E respondendo --version), com status no checklist final ──
function Invoke-WingetStep {
    if ($SkipWinget) {
        Write-Log "Winget ignorado por parametro" "ALERTA"
        $script:Status_Winget = "IGNORADO"
        return
    }

    if (-not $script:InternetOK) {
        Write-Log "Winget ignorado: sem internet" "ALERTA"
        $script:Status_Winget = "SEM INTERNET"
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

    Write-Log "Atualizando fontes do Winget..." "INFO"
    try {
        winget source update | Out-Null
    }
    catch {
        Write-Log "Nao foi possivel atualizar fontes do Winget" "ALERTA"
    }

    Write-Log "Verificando aplicacoes pendentes de atualizacao..." "INFO"

    # Executa a listagem nativa de upgrades para avaliacao visual
    $ListaUpgrades = winget upgrade | Out-String

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

# ── MODIFICACAO: auditoria do ultimo login de TODOS os perfis locais (nao
# apenas dos candidatos a remocao), exibida e logada antes da etapa de remocao ──
function Remove-OldProfilesStep {
    if ($SkipProfiles) {
        Write-Log "Limpeza de perfis ignorada por parametro" "ALERTA"
        return
    }

    $UsuarioAtual = $env:USERNAME

    # ── Auditoria: ultimo login de todos os perfis locais (visivel mesmo para quem nao sera removido) ──
    $TodosPerfis = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.Special -eq $false -and
        $_.LocalPath -like "C:\Users\*" -and
        $_.LocalPath -notmatch "\\Default" -and
        $_.LocalPath -notmatch "\\Public"
    }

    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "AUDITORIA - ULTIMO LOGIN DE TODOS OS PERFIS LOCAIS" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    foreach ($P in $TodosPerfis) {
        $NomeUsuario   = Split-Path $P.LocalPath -Leaf
        $UltimoLoginAud = Convert-WmiDateSafe -WmiDate $P.LastUseTime
        $StatusCarregado = if ($P.Loaded) { "LOGADO AGORA" } else { "" }
        $DataTexto = if ($UltimoLoginAud) { $UltimoLoginAud.ToString('dd/MM/yyyy HH:mm') } else { "Sem registro / nunca logou" }

        Write-Host (" - {0,-20} Ultimo login: {1,-20} {2}" -f $NomeUsuario, $DataTexto, $StatusCarregado) -ForegroundColor Gray
        Write-Log "Auditoria de perfil: $NomeUsuario | Ultimo login: $DataTexto" "INFO"
    }
    Write-Host "============================================================`n" -ForegroundColor Cyan

    $Limite = (Get-Date).AddMonths(-$ProfileAgeMonths)
    $PerfisCandidatos = @()

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

    foreach ($Perfil in $Perfis) {
        $UltimoUso = Convert-WmiDateSafe -WmiDate $Perfil.LastUseTime

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
        Write-Log "Nenhum perfil sem login ha mais de $ProfileAgeMonths meses encontrado." "OK"
        return
    }

    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "PERFIS DETECTADOS (Sem login ha mais de $ProfileAgeMonths meses)" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    
    for ($i = 0; $i -lt $PerfisCandidatos.Count; $i++) {
        $P = $PerfisCandidatos[$i]
        Write-Host " [$($i + 1)] Perfil: $($P.Usuario) | Ultimo Login: $($P.UltimoUso.ToString('dd/MM/yyyy'))" -ForegroundColor Cyan
    }
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "Opcoes de Entrada:" -ForegroundColor Gray
    Write-Host " - Digite os indices separados por virgula (Ex: 1,3)" -ForegroundColor Gray
    Write-Host " - Digite TODOS para selecionar a lista completa" -ForegroundColor Gray
    Write-Host " - Digite CANCELAR para abortar a exclusao"`n -ForegroundColor Gray

    $Escolha = Read-Host "Sua escolha"
    $PerfisAlvo = @()

    if ($Escolha -eq "TODOS") {
        $PerfisAlvo = $PerfisCandidatos
    } 
    elseif ($Escolha -eq "CANCELAR" -or [string]::IsNullOrWhiteSpace($Escolha)) {
        Write-Log "Remocao de perfis cancelada." "ALERTA"
        return
    } 
    else {
        $Indices = $Escolha -split ',' | ForEach-Object { $_.Trim() }
        foreach ($IdxStr in $Indices) {
            if ([int]::TryParse($IdxStr, [ref]$Idx) -and $Idx -ge 1 -and $Idx -le $PerfisCandidatos.Count) {
                $PerfisAlvo += $PerfisCandidatos[$Idx - 1]
            }
        }
    }

    if ($PerfisAlvo.Count -eq 0) {
        Write-Log "Nenhuma selecao valida realizada pelo tecnico." "ALERTA"
        return
    }

    Write-Host "`nVOCE SELECIONOU OS SEGUINTES PERFIS PARA EXCLUSAO:" -ForegroundColor Red
    foreach ($Alvo in $PerfisAlvo) {
        Write-Host " ✔ $($Alvo.Usuario) [$($Alvo.Caminho)]" -ForegroundColor Yellow
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

function Test-PendingReboot {
    $RebootKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    )

    if (Test-Path $RebootKeys[0]) { return $true }
    if (Test-Path $RebootKeys[1]) { return $true }

    try {
        $PendingFileRename = Get-ItemProperty -Path $RebootKeys[2] -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($PendingFileRename) { return $true }
    }
    catch { }

    return $false
}

# ============================================================
# INICIO DO FLUXO PRINCIPAL
# ============================================================

Write-Log "===== INICIO DA PREVENTIVA =====" "INFO"

$Hostname = $env:COMPUTERNAME
$script:Status_Admin = "NAO EXECUTADO"
$script:Status_Windows = "NAO VERIFICADO"
$script:Status_WindowsUpdate = "NAO VERIFICADO"
$script:Status_Winget = "NAO VERIFICADO"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PREVENTIVA CORPORATIVA" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "HOSTNAME: $Hostname" -ForegroundColor Yellow
Write-Host "Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor Gray
Write-Host "Log: $LogFile" -ForegroundColor Gray
Write-Host "Remocao de perfis: usuarios sem login ha mais de $ProfileAgeMonths meses" -ForegroundColor Gray
Write-Host "Timeout Windows Update: $WindowsUpdateTimeoutSeconds segundos" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$script:InternetOK = Test-Internet
if ($script:InternetOK) {
    Write-Log "Conectividade com a internet OK" "OK"
}
else {
    Write-Log "Sem acesso a internet. Etapas online podem ser ignoradas ou falhar" "ALERTA"
}

Invoke-Step -Nome "Administrador local" -Acao { Set-LocalAdministrator }
Invoke-Step -Nome "Status de ativacao do Windows" -Acao { Get-WindowsActivationStatus }
Invoke-Step -Nome "Status de ativacao do Office" -Acao { Get-OfficeActivationStatus }
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
Write-Host "Office: $script:Office_Ativado"
Write-Host "Admin: $script:Status_Admin"
Write-Host "Windows Update: $script:Status_WindowsUpdate"
Write-Host "Winget: $script:Status_Winget"
Write-Host "Log: $LogFile"

if ($script:Status_Windows -ne "OK") {
    Write-Host ""
    Write-Host "AVISO: LICENCIAMENTO PENDENTE OU NAO CONFIRMADO (Windows/Office)" -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "LICENCIAMENTO OK" -ForegroundColor Green
}

if (Test-PendingReboot) {
    Write-Log "Reinicializacao pendente detectada" "ALERTA"
    Write-Host ""
    Write-Host "REINICIALIZACAO PENDENTE" -ForegroundColor Yellow

    if (-not $NoReboot) {
        if ((Read-Host "Deseja reiniciar agora? (S/N)") -match "^[sS]$") {
            Write-Log "Reinicio autorizado pelo tecnico" "INFO"
            Restart-Computer -Force
        }
        else {
            Write-Log "Reinicio pendente nao executado pelo tecnico" "ALERTA"
        }
    }
    else {
        Write-Log "Reinicio automatico ignorado por parametro -NoReboot" "ALERTA"
    }
}
else {
    Write-Log "Nenhuma reinicializacao pendente detectada" "OK"
}

Write-Log "===== FIM DA PREVENTIVA =====" "INFO"
