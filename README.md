# PaerroTech

Repositório de automações de suporte, manutenção e infraestrutura da Paerro Tecnologia.

## Estrutura

- `PadronizacaoMaquinas/`: script interativo de preparação de estações Windows, documentação da auditoria e fluxograma.
- `Preventivas/`: rotinas de manutenção preventiva.
- `Scripts/`: utilitários diversos.
- `ScriptsMikrotik/`: scripts RouterOS para rotas, failover e balanceamento.

## Padronização de máquinas

Consulte [`PadronizacaoMaquinas/README.md`](PadronizacaoMaquinas/README.md) para requisitos, execução local/remota, etapas e retomada após reinício. A documentação da auditoria está em [`PadronizacaoMaquinas/AUDITORIA.md`](PadronizacaoMaquinas/AUDITORIA.md).

O script usa Windows PowerShell 5.1 em Windows 10/11, exige privilégios administrativos para operações de máquina e precisa de uma sessão interativa. Não execute o conteúdo principal por `irm | iex`; use o procedimento documentado que salva o `.ps1` em arquivo antes de executá-lo.

## Padrão de logs

A padronização grava logs em `C:\Users\Public\Documents\Logs\Padronizacao\`. Outros scripts podem usar subdiretórios próprios dentro de `C:\Users\Public\Documents\Logs\`.

## Segurança e contribuição

Execute somente código revisado, use licenças e credenciais autorizadas e valide mudanças primeiro em ambiente de teste. Desenvolva em branch separada e submeta as alterações para revisão antes de implantá-las.
