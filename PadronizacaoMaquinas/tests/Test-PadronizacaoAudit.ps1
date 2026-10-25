[CmdletBinding()]
param([string]$ScriptPath = (Join-Path $PSScriptRoot '..\padronizacao.ps1'))
$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $ScriptPath).Path
$source = Get-Content -LiteralPath $resolved -Raw
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($resolved, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "PowerShell parse errors: $($parseErrors -join '; ')" }
function Assert-That([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" }; Write-Host "PASS: $Message" }


# Test pure hostname and DNS discovery logic with local command mocks.
function Write-Log { param($Message,$Type) }
$fn = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-HostnameValido' }, $true); . ([scriptblock]::Create($fn.Extent.Text))
Assert-That (Assert-HostnameValido 'PC-123') 'valid NetBIOS hostname accepted'
Assert-That (-not (Assert-HostnameValido '-PC')) 'hostname beginning with hyphen rejected'
Assert-That (-not (Assert-HostnameValido 'PC_NAME')) 'hostname with underscore rejected'
Assert-That (-not (Assert-HostnameValido '1234567890123456')) 'hostname longer than 15 characters rejected'

$script:MockDnsFails = $false; $script:MockPortsOpen = $true
function Resolve-DnsName { param($Name,$Type,[switch]$DnsOnly,$ErrorAction); if ($script:MockDnsFails) { throw 'mock SRV lookup failed' }; [pscustomobject]@{ NameTarget='localhost.'; Priority=0; Weight=100 } }
function Test-NetConnection { param($ComputerName,$Port,$InformationLevel,$WarningAction); return $script:MockPortsOpen }
$fn = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-DomainController' }, $true); . ([scriptblock]::Create($fn.Extent.Text))
Assert-That ((Get-DomainController -Domain 'example.test') -eq 'localhost') 'SRV record, host resolution and required ports select a controller'
$script:MockPortsOpen = $false
$portFailure = $false; try { Get-DomainController -Domain 'example.test' } catch { $portFailure = $_.Exception.Message -match 'TCP/389' }
Assert-That $portFailure 'controller with required ports closed is rejected'
$script:MockDnsFails = $true
$dnsFailure = $false; try { Get-DomainController -Domain 'example.test' } catch { $dnsFailure = $_.Exception.Message -match 'DNS SRV' }
Assert-That $dnsFailure 'missing SRV discovery is reported as DNS discovery failure'

# Exercise the post-reboot state gate with in-memory mocks; no registry or machine state is changed.
$script:MockState = @{ PendingAction='JoinDomain'; Hostname='PC-123'; Dominio='example.test' }
$script:MockSystem = [pscustomobject]@{ Name='PC-123'; PartOfDomain=$true; Domain='example.test' }
$script:MockStage = 2
$script:regPath = 'MOCK:'
function Get-DadoSalvo { param([string]$Chave) return $script:MockState[$Chave] }
function Get-CimInstance { param($ClassName,$ErrorAction) return $script:MockSystem }
function Set-Etapa { param([int]$Numero) $script:MockStage = $Numero }
function Remove-ItemProperty { param($Path,$Name,$ErrorAction) if ($Name -eq 'PendingAction') { $script:MockState.Remove('PendingAction') } }
$fn = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Complete-PendingAction' }, $true); . ([scriptblock]::Create($fn.Extent.Text))
Complete-PendingAction
Assert-That ($script:MockStage -eq 3) 'valid post-reboot hostname and domain advance stage 3'
$script:MockState.PendingAction = 'JoinDomain'; $script:MockStage = 2; $script:MockSystem = [pscustomobject]@{ Name='PC-123'; PartOfDomain=$false; Domain='WORKGROUP' }
Complete-PendingAction
Assert-That ($script:MockStage -eq 2 -and -not $script:MockState.PendingAction) 'unjoined host reopens stage 3 and clears the stale retry marker'

Assert-That ($source -notmatch 'Start-Job') 'Windows Update does not rely on process-local jobs'
Assert-That ($source -notmatch 'MainModule\.FileName') 'script path never falls back to powershell.exe'
Assert-That ($source -match "PendingAction") 'critical operation records a pending state for post-reboot validation'
Write-Host 'All audit unit checks passed.' -ForegroundColor Green
