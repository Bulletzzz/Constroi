. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Saude da API'

Chamar GET '/health' $null $null 200 'GET /health' | Out-Null
Chamar GET '/rota-que-nao-existe' $null $null 404 'rota inexistente' | Out-Null

FinalizarCaso
