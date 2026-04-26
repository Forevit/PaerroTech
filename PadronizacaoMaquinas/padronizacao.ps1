# ============================================================
#  SCRIPT DE PADRONIZAÇÃO DE MÁQUINA CORPORATIVA
#  by Eduardo Ferreira
# ============================================================

# ── Auto-elevação ────────────────────────────────────────────
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process PowerShell -Verb RunAs "-NoProfile -ExecutionPolicy Bypass -Command `"cd '$pwd'; & '$PSCommandPath';`""
    Exit
}

# ── Sistema de Logs ──────────────────────────────────────────
# Estrutura: C:\Users\Public\Documents\Logs\
#   ├── Padronizacao\     ← logs deste script
#   ├── Preventiva\       ← logs de scripts de manutenção preventiva
#   └── (outros scripts futuros...)
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
    $linha     = "[$timestamp] [$Tipo] $Mensagem"

    $linha | Out-File -FilePath $logFile -Append -Encoding UTF8

    switch ($Tipo) {
        "ETAPA" { Write-Host "`n$linha" -ForegroundColor Cyan   }
        "OK"    { Write-Host $linha     -ForegroundColor Green  }
        "ERRO"  { Write-Host $linha     -ForegroundColor Red    }
        "AVISO" { Write-Host $linha     -ForegroundColor Yellow }
        default { Write-Host $linha     -ForegroundColor White  }
    }
}

function Write-LogErro {
    param([string]$Mensagem, [System.Management.Automation.ErrorRecord]$Excecao)
    Write-Log $Mensagem "ERRO"
    if ($Excecao) {
        Write-Log "  Detalhe: $($Excecao.Exception.Message)" "ERRO"
        Write-Log "  Linha  : $($Excecao.InvocationInfo.ScriptLineNumber)" "ERRO"
    }
}

# ── Barra de progresso ───────────────────────────────────────
# ⚠️  Atualize este número sempre que adicionar/remover uma etapa numerada
$totalEtapas = 6

function Update-Progresso {
    param([int]$Numero, [string]$Status)
    $percentual = [math]::Round(($Numero / $totalEtapas) * 100)
    Write-Progress `
        -Activity        "Padronização Corporativa — by Eduardo Ferreira" `
        -Status          "Etapa $Numero/$totalEtapas — $Status" `
        -PercentComplete $percentual
}

# ── Constantes de estado ─────────────────────────────────────
$regPath  = "HKLM:\SOFTWARE\Padronizacao"
$credFile = "$env:ProgramData\paerro_cred.xml"

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

function Set-Etapa($numero) {
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name "Etapa" -Value $numero
}

function Set-RunOnce {
    $caminhoSalvo = Get-DadoSalvo "ScriptPath"
    if ($caminhoSalvo -like "*.exe") {
        $cmd = "`"$caminhoSalvo`""
    } else {
        $cmd = "PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File `"$caminhoSalvo`""
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
                     -Name "Padronizacao" -Value $cmd
}

function Remove-Estado {
    Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
                        -Name "Padronizacao" -ErrorAction SilentlyContinue
    Remove-Item -Path $credFile -Force -ErrorAction SilentlyContinue
}

function Get-DadoSalvo($chave) {
    if (Test-Path $regPath) {
        return (Get-ItemProperty -Path $regPath -Name $chave -ErrorAction SilentlyContinue).$chave
    }
    return $null
}

function Set-DadoSalvo($chave, $valor) {
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name $chave -Value $valor
}

# ── Detecção de fabricante + drivers ─────────────────────────
function Install-Drivers {
    $fabricante = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    Write-Log "Fabricante detectado: $fabricante" "INFO"

    switch -Wildcard ($fabricante.ToLower()) {
        "*dell*" {
            Write-Log "Instalando Dell Command Update..." "INFO"
            winget install --id Dell.CommandUpdate --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Start-Sleep -Seconds 10
            $dcu = "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe"
            if (Test-Path $dcu) {
                Write-Log "Executando Dell Command Update para instalar drivers..." "INFO"
                Start-Process $dcu -ArgumentList "/applyUpdates -silent" -Wait
                Write-Log "Dell Command Update concluído." "OK"
            } else {
                Write-Log "dcu-cli.exe não encontrado após instalação. Verifique manualmente." "AVISO"
            }
        }
        "*lenovo*" {
            Write-Log "Instalando Lenovo System Update..." "INFO"
            winget install --id Lenovo.SystemUpdate --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Write-Log "Lenovo System Update instalado. Execute-o manualmente para aplicar drivers pendentes." "AVISO"
        }
        "*hp*" {
            Write-Log "Instalando HP Support Assistant..." "INFO"
            winget install --id HP.HPSupportAssistant --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Write-Log "HP Support Assistant instalado." "OK"
        }
        default {
            Write-Log "Fabricante '$fabricante' não mapeado. Nenhum driver instalado automaticamente." "AVISO"
        }
    }
}

# ── Config de clientes (para consulta LDAP de hostname) ──────
$clientes = @{
    1 = @{ Nome = "GrupoApoioCob";         Base = "GAPC"; Dominio = "DC=apoio,DC=local"     }
    2 = @{ Nome = "GrupoLocusEmpresarial"; Base = "GLHE"; Dominio = "DC=locus,DC=local"     }
    3 = @{ Nome = "GrupoTopClean";         Base = "GTPC"; Dominio = "DC=topclean,DC=local"  }
    4 = @{ Nome = "GrupoEsquadra";         Base = "GESQ"; Dominio = "DC=gesquadra,DC=local" }
}

$sufixosTipo = @{
    "1" = @{ Label = "Notebook"; Sufixo = "NTB" }
    "2" = @{ Label = "Desktop";  Sufixo = "DSK" }
}

# ── Consulta LDAP e retorna próximo hostname sugerido ────────
function Get-ProximoHostnameLDAP {
    param([string]$Base, [string]$Dominio, [string]$Sufixo)

    try {
        $searcher = New-Object System.DirectoryServices.DirectorySearcher
        $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$Dominio")
        $searcher.Filter = "(name=$Base$Sufixo*)"
        $searcher.PropertiesToLoad.Add("name") | Out-Null
        $resultados = $searcher.FindAll()

        if ($resultados.Count -eq 0) {
            return @{ Sugestao = "${Base}${Sufixo}0001"; Existentes = @() }
        }

        $nomes = $resultados | ForEach-Object { $_.Properties["name"][0] }

        $numeros = $nomes | ForEach-Object {
            if ($_ -match "(\d+)$") { [int]$Matches[1] }
        } | Where-Object { $_ -ne $null } | Sort-Object

        $proximo  = ($numeros | Measure-Object -Maximum).Maximum + 1
        $sugestao = "$Base$Sufixo{0:D4}" -f $proximo

        return @{ Sugestao = $sugestao; Existentes = ($nomes | Sort-Object) }

    } catch {
        Write-Log "Falha na consulta LDAP: $($_.Exception.Message)" "AVISO"
        return $null
    }
}

# ── Validação de hostname ────────────────────────────────────
function Assert-HostnameValido {
    param([string]$Hostname)
    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        Write-Log "Hostname não pode ser vazio." "ERRO"; return $false
    }
    if ($Hostname.Length -gt 15) {
        Write-Log "Hostname '$Hostname' excede 15 caracteres (limite NetBIOS)." "ERRO"; return $false
    }
    if ($Hostname -notmatch '^[a-zA-Z0-9\-]+$') {
        Write-Log "Hostname '$Hostname' contém caracteres inválidos. Use apenas letras, números e hífen." "ERRO"; return $false
    }
    if ($Hostname -match '^-|-$') {
        Write-Log "Hostname '$Hostname' não pode começar ou terminar com hífen." "ERRO"; return $false
    }
    return $true
}

# ── Lê etapa atual ───────────────────────────────────────────
$etapaAtual = Get-Etapa

Clear-Host
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   PADRONIZAÇÃO DE MÁQUINA CORPORATIVA" -ForegroundColor Cyan
Write-Host "          by Eduardo Ferreira" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Log "Script iniciado. Etapa atual: $etapaAtual" "INFO"
Write-Log "Log salvo em: $logFile" "INFO"

if ($etapaAtual -gt 0) {
    Write-Log "Retomando a partir da etapa $etapaAtual após reboot." "AVISO"
}

# ============================================================
# PRÉ-VERIFICAÇÃO — EDIÇÃO DO WINDOWS
# Roda apenas uma vez, antes de qualquer etapa numerada.
# Se o Windows for Home, pausa para o técnico fazer o upgrade,
# configura RunOnce e sai — o script retoma automaticamente
# após o reboot causado pelo upgrade.
# ============================================================
$upgradeVerificado = Get-DadoSalvo "UpgradeVerificado"

if ($etapaAtual -lt 1 -and $upgradeVerificado -ne "1") {

    $edicao = (Get-CimInstance Win32_OperatingSystem).Caption
    Write-Log "Edição detectada: $edicao" "INFO"

    if ($edicao -like "*Home*") {
        Write-Log "Windows Home detectado. Upgrade para Pro necessário antes de continuar." "AVISO"

        Write-Host "`n============================================" -ForegroundColor Yellow
        Write-Host "   ATENÇÃO — WINDOWS HOME DETECTADO" -ForegroundColor Yellow
        Write-Host "============================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Esta máquina está com Windows Home." -ForegroundColor White
        Write-Host "  É necessário fazer o upgrade para Pro" -ForegroundColor White
        Write-Host "  antes de continuar a padronização." -ForegroundColor White
        Write-Host ""
        Write-Host "  Após concluir o upgrade, a máquina vai" -ForegroundColor Gray
        Write-Host "  reiniciar e o script continuará sozinho." -ForegroundColor Gray
        Write-Host "============================================`n" -ForegroundColor Yellow

        # Salva flag e configura RunOnce ANTES de abrir a ferramenta,
        # garantindo retomada mesmo que o reboot seja imediato.
        Set-DadoSalvo "UpgradeVerificado" "1"
        Set-DadoSalvo "ScriptPath"        $scriptPath
        Set-RunOnce
        Write-Log "RunOnce configurado. Script retomará após reboot do upgrade." "INFO"

        Write-Host "  Pressione qualquer tecla para abrir a ferramenta de upgrade..." -ForegroundColor Cyan
        pause

        # ====================================================
        # INSIRA AQUI o comando de upgrade Home → Pro
        # ====================================================

        # Mantém o script aberto enquanto o técnico age.
        # Se o upgrade reiniciar a máquina, o RunOnce já está configurado.
        Write-Host "`n  Aguardando conclusão do upgrade..." -ForegroundColor Yellow
        Write-Host "  (se a máquina reiniciar, o script continuará automaticamente)" -ForegroundColor Gray
        pause
        Exit

    } else {
        Write-Log "Edição OK: $edicao. Prosseguindo." "OK"
        Set-DadoSalvo "UpgradeVerificado" "1"
    }
}

# ============================================================
# WINDOWS UPDATE EM BACKGROUND
# ============================================================
if ($etapaAtual -lt 1) {
    Write-Log "Iniciando Windows Update em segundo plano..." "ETAPA"

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

        Write-Log "Windows Update rodando em background (Job ID: $($wuJob.Id))." "OK"

    } catch {
        Write-LogErro "Falha ao iniciar Windows Update em background." $_
        Write-Log "Continuando sem Windows Update." "AVISO"
    }
}

# ============================================================
# ETAPA 1 — HOSTNAME + DOMÍNIO (com consulta LDAP integrada)
# ============================================================
if ($etapaAtual -lt 1) {
    Update-Progresso 1 "Hostname e Ingresso no Domínio"
    Write-Log "ETAPA 1 — Hostname e Ingresso no Domínio" "ETAPA"

    try {
        # ── Seleção de cliente ───────────────────────────────
        Write-Host "`nSelecione o cliente:`n" -ForegroundColor Yellow
        $clientes.GetEnumerator() | Sort-Object Key | ForEach-Object {
            Write-Host "  [$($_.Key)] $($_.Value.Nome)" -ForegroundColor White
        }
        Write-Host "  [0] Pular consulta e digitar hostname manualmente`n" -ForegroundColor Gray

        $opcaoCliente = Read-Host "Digite o número"
        $hostnameSugerido = $null

        if ($opcaoCliente -ne "0" -and $clientes.ContainsKey([int]$opcaoCliente)) {
            $clienteSelecionado = $clientes[[int]$opcaoCliente]

            Write-Host "`nTipo de máquina:`n" -ForegroundColor Yellow
            Write-Host "  [1] Notebook  ($($clienteSelecionado.Base)NTB****)" -ForegroundColor White
            Write-Host "  [2] Desktop   ($($clienteSelecionado.Base)DSK****)`n" -ForegroundColor White

            $opcaoTipo = Read-Host "Escolha"

            if ($sufixosTipo.ContainsKey($opcaoTipo)) {
                $tipoSelecionado = $sufixosTipo[$opcaoTipo]

                Write-Host "`nConsultando AD de $($clienteSelecionado.Nome)..." -ForegroundColor Cyan
                Write-Log "Consultando LDAP para $($clienteSelecionado.Nome) - $($tipoSelecionado.Label)" "INFO"

                $resultado = Get-ProximoHostnameLDAP `
                    -Base    $clienteSelecionado.Base `
                    -Dominio $clienteSelecionado.Dominio `
                    -Sufixo  $tipoSelecionado.Sufixo

                if ($resultado) {
                    if ($resultado.Existentes.Count -gt 0) {
                        Write-Host "`n  Máquinas já cadastradas:" -ForegroundColor Gray
                        $resultado.Existentes | ForEach-Object {
                            Write-Host "    · $_" -ForegroundColor DarkGray
                        }
                    } else {
                        Write-Host "`n  Nenhuma máquina cadastrada ainda para este padrão." -ForegroundColor Gray
                    }

                    $hostnameSugerido = $resultado.Sugestao
                    Write-Host "`n  ➜ Próximo hostname sugerido: " -NoNewline -ForegroundColor Green
                    Write-Host $hostnameSugerido -ForegroundColor Yellow
                    Write-Log "Hostname sugerido pelo LDAP: $hostnameSugerido" "OK"
                } else {
                    Write-Host "  Não foi possível consultar o AD. Digite o hostname manualmente." -ForegroundColor Yellow
                }
            }
        }

        # ── Confirmação ou digitação manual do hostname ──────
        Write-Host ""
        do {
            if ($hostnameSugerido) {
                $confirmacao  = Read-Host "Usar '$hostnameSugerido'? (Enter para confirmar ou digite outro)"
                $novoHostname = if ([string]::IsNullOrWhiteSpace($confirmacao)) { $hostnameSugerido } else { $confirmacao }
            } else {
                $novoHostname = Read-Host "Digite o hostname da máquina"
            }
            $hostnameValido = Assert-HostnameValido $novoHostname
            if (-not $hostnameValido) {
                Write-Host "  Tente novamente." -ForegroundColor Yellow
                $hostnameSugerido = $null
            }
        } while (-not $hostnameValido)

        # ── Dados do domínio ─────────────────────────────────
        $dominio  = Read-Host "Digite o nome do domínio (ex: empresa.local)"
        $domAdmin = Read-Host "Usuário do domínio com permissão para adicionar máquinas"
        $domPass  = Read-Host "Senha do usuário do domínio" -AsSecureString

        $credencial = New-Object System.Management.Automation.PSCredential($domAdmin, $domPass)

        Set-DadoSalvo "Hostname"   $novoHostname
        Set-DadoSalvo "Dominio"    $dominio
        Set-DadoSalvo "ScriptPath" $scriptPath

        Add-Computer -DomainName $dominio -Credential $credencial -NewName $novoHostname -Force -ErrorAction Stop
        Write-Log "Máquina '$novoHostname' adicionada ao domínio '$dominio'." "OK"

        $credencial = $null
        $domPass    = $null
        [System.GC]::Collect()

    } catch {
        Write-LogErro "Falha ao ingressar no domínio ou definir hostname." $_
        Write-Log "Verifique as credenciais e a conectividade com o domínio." "AVISO"
        pause; Exit
    }

    Set-Etapa 1
    Set-RunOnce
    Write-Log "Reiniciando para aplicar hostname e domínio..." "INFO"
    Start-Sleep -Seconds 5
    Restart-Computer -Force
    Exit
}

# ── Recupera dados salvos ────────────────────────────────────
$novoHostname = Get-DadoSalvo "Hostname"
$dominio      = Get-DadoSalvo "Dominio"

if (Test-Path $credFile) {
    Write-Log "Arquivo de credencial legado encontrado e removido." "AVISO"
    Remove-Item $credFile -Force -ErrorAction SilentlyContinue
}

# ============================================================
# ETAPA 2 — USUÁRIO ADMINISTRADOR LOCAL
# ============================================================
if ($etapaAtual -lt 2) {
    Update-Progresso 2 "Habilitando Conta Administrador Local"
    Write-Log "ETAPA 2 — Habilitando Conta Administrador Local" "ETAPA"

    try {
        do {
            $adminPass        = Read-Host "Defina a senha para a conta Administrador" -AsSecureString
            $adminPassConfirm = Read-Host "Confirme a senha"                          -AsSecureString

            $pass1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                         [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPass))
            $pass2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                         [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPassConfirm))

            if ($pass1 -ne $pass2) {
                Write-Log "As senhas não coincidem. Tente novamente." "AVISO"
            }
        } while ($pass1 -ne $pass2)

        $pass1 = $null
        $pass2 = $null
        [System.GC]::Collect()

        Enable-LocalUser -Name "Administrador" -ErrorAction Stop
        Set-LocalUser    -Name "Administrador" -Password $adminPass -PasswordNeverExpires $true -ErrorAction Stop
        Write-Log "Conta 'Administrador' habilitada e senha definida." "OK"

    } catch {
        Write-LogErro "Falha ao configurar a conta Administrador." $_
    }

    Set-Etapa 2
}

# ============================================================
# ETAPA 3 — INSTALAÇÃO DE APLICATIVOS VIA WINGET
# ============================================================
if ($etapaAtual -lt 3) {
    Update-Progresso 3 "Instalando aplicativos via Winget"
    Write-Log "ETAPA 3 — Instalando aplicativos via Winget" "ETAPA"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Winget não encontrado. Instale o 'App Installer' pela Microsoft Store e execute novamente." "ERRO"
        pause; Exit
    }

    $apps = @(
        @{ Id = "Google.Chrome";                 Nome = "Google Chrome"        },
        @{ Id = "Mozilla.Firefox";               Nome = "Mozilla Firefox"      },
        @{ Id = "Oracle.JavaRuntimeEnvironment"; Nome = "Java 8 (JRE)"         },
        @{ Id = "AnyDesk.AnyDesk";               Nome = "AnyDesk"              },
        @{ Id = "Adobe.Acrobat.Reader.64-bit";   Nome = "Adobe Acrobat Reader" },
        @{ Id = "RARLab.WinRAR";                 Nome = "WinRAR"               }
    )

    foreach ($app in $apps) {
        try {
            Write-Log "Instalando $($app.Nome)..." "INFO"
            $resultado = winget install --id $app.Id --silent --accept-package-agreements --accept-source-agreements 2>&1
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
                Write-Log "$($app.Nome) instalado com sucesso." "OK"
            } else {
                Write-Log "$($app.Nome) retornou código $LASTEXITCODE. Pode ter falhado." "AVISO"
                $resultado | Out-File -FilePath $logFile -Append -Encoding UTF8
            }
        } catch {
            Write-LogErro "Erro ao instalar $($app.Nome)." $_
        }
    }

    Set-Etapa 3
}

# ============================================================
# ETAPA 4 — GLPI AGENT
# ============================================================
if ($etapaAtual -lt 4) {
    Update-Progresso 4 "Instalando GLPI Agent"
    Write-Log "ETAPA 4 — Instalando GLPI Agent" "ETAPA"

    try {
        $glpiUrl    = "https://github.com/glpi-project/glpi-agent/releases/download/1.9/GLPI-Agent-1.9-x64.msi"
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
        Write-LogErro "Falha ao instalar o GLPI Agent." $_
    }

    Set-Etapa 4
}

# ============================================================
# ETAPA 5 — MICROSOFT OFFICE (via ODT) + DRIVERS DO FABRICANTE
# ============================================================
if ($etapaAtual -lt 5) {
    Update-Progresso 5 "Instalando Microsoft Office 2021 e Drivers"
    Write-Log "ETAPA 5 — Instalando Microsoft Office 2021" "ETAPA"

    try {
        $odtDir = "$env:TEMP\ODT"
        New-Item -ItemType Directory -Path $odtDir -Force | Out-Null

        Write-Log "Buscando URL mais recente do Office Deployment Tool..." "INFO"
        try {
            $odtPage     = Invoke-WebRequest -Uri "https://www.microsoft.com/en-us/download/details.aspx?id=49117" `
                               -UseBasicParsing -ErrorAction Stop
            $odtUrlMatch = [regex]::Match($odtPage.Links.href -join "`n",
                               'https://download\.microsoft\.com/download/[^\s"]+officedeploymenttool[^\s"]+\.exe')

            if ($odtUrlMatch.Success) {
                $odtUrl = $odtUrlMatch.Value
                Write-Log "URL do ODT encontrada: $odtUrl" "INFO"
            } else {
                throw "Não foi possível extrair a URL do ODT da página da Microsoft."
            }
        } catch {
            $odtUrl = "https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_18129-20030.exe"
            Write-Log "Falha ao buscar URL dinâmica. Usando URL de fallback." "AVISO"
        }

        $odtExe = "$odtDir\odt.exe"
        Write-Log "Baixando Office Deployment Tool..." "INFO"
        Invoke-WebRequest -Uri $odtUrl -OutFile $odtExe -UseBasicParsing -ErrorAction Stop
        Start-Process $odtExe -ArgumentList "/quiet /extract:`"$odtDir`"" -Wait

        @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="PerpetualVL2021">
    <Product ID="ProPlus2021Volume">
      <Language ID="pt-br" />
      <ExcludeApp ID="Access" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="OneDrive" />
      <ExcludeApp ID="Publisher" />
    </Product>
  </Add>
  <Display Level="Full" AcceptEULA="TRUE" />
  <Property Name="AUTOACTIVATE" Value="0" />
</Configuration>
"@ | Out-File -FilePath "$odtDir\config.xml" -Encoding UTF8

        Write-Log "Instalando Office 2021... (pode demorar vários minutos)" "INFO"
        $proc = Start-Process "$odtDir\setup.exe" -ArgumentList "/configure `"$odtDir\config.xml`"" -Wait -PassThru
        if ($proc.ExitCode -eq 0) {
            Write-Log "Microsoft Office 2021 instalado com sucesso." "OK"
        } else {
            Write-Log "setup.exe do Office retornou código $($proc.ExitCode)." "AVISO"
        }

    } catch {
        Write-LogErro "Falha ao instalar o Microsoft Office." $_
    }

    Write-Log "Detectando fabricante para instalação de drivers..." "INFO"
    try {
        Install-Drivers
    } catch {
        Write-LogErro "Falha ao instalar drivers do fabricante." $_
    }

    Set-Etapa 5
}

# ============================================================
# ETAPA 6 — ATIVAÇÃO
# ============================================================
if ($etapaAtual -lt 6) {
    Update-Progresso 6 "Ativação"
    Write-Log "ETAPA 6 — Ativação" "ETAPA"

    # =========================================================
    # INSIRA AQUI o comando de ativação
    # =========================================================

    Write-Log "Etapa de ativação pendente de configuração." "AVISO"

    Set-Etapa 6
}

# ============================================================
# AGUARDA O JOB DO WINDOWS UPDATE (timeout: 30 minutos)
# ============================================================
Write-Log "Verificando status do Windows Update em background..." "INFO"
$wuJobs = Get-Job -State Running -ErrorAction SilentlyContinue | Where-Object { $_.Command -like "*WindowsUpdate*" }
if ($wuJobs) {
    Write-Log "Windows Update ainda em execução. Aguardando (timeout: 30 min)..." "AVISO"
    $concluido = $wuJobs | Wait-Job -Timeout 1800
    if ($concluido) {
        $wuJobs | Receive-Job | Out-File -FilePath $logFile -Append -Encoding UTF8
        Write-Log "Windows Update concluído." "OK"
    } else {
        Write-Log "Windows Update não concluiu no tempo limite. Verifique o Job manualmente (Get-Job)." "AVISO"
        $wuJobs | Stop-Job
        $wuJobs | Remove-Job
    }
} else {
    Write-Log "Windows Update já finalizado ou não iniciado nesta sessão." "INFO"
}

# ============================================================
# LIMPEZA FINAL
# ============================================================
Write-Progress -Activity "Padronização Corporativa" -Completed
Write-Log "Limpando estado temporário do registro..." "INFO"
Remove-Estado

Write-Log "============================================" "INFO"
Write-Log "PADRONIZAÇÃO CONCLUÍDA COM SUCESSO" "OK"
Write-Log "Hostname : $novoHostname" "INFO"
Write-Log "Domínio  : $dominio" "INFO"
Write-Log "Log salvo em: $logFile" "INFO"
Write-Log "============================================" "INFO"

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "   PADRONIZAÇÃO CONCLUÍDA COM SUCESSO!" -ForegroundColor Cyan
Write-Host "   Hostname : $novoHostname"             -ForegroundColor White
Write-Host "   Domínio  : $dominio"                  -ForegroundColor White
Write-Host "   Log      : $logFile"                  -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

pause