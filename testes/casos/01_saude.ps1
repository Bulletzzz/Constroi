. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Saude da API'

$saude = Chamar GET '/health' $null $null 200 'GET /health'
Conferir ($saude.status -eq 'ok') 'health responde status ok'
Conferir ($null -eq $saude.detalhe) 'health nao devolve detalhe do erro'
Conferir (-not ("$($saude | ConvertTo-Json -Depth 4)" -match 'postgres')) `
    'health nao devolve string de conexao'

$raiz = Chamar GET '/' $null $null 200 'GET /'
Conferir (-not ("$($raiz | ConvertTo-Json -Depth 4)" -match 'Frog')) `
    'raiz nao revela o framework'

Chamar GET '/rota-que-nao-existe' $null $null 404 'rota inexistente' | Out-Null

Chamar GET '/estoque' $null $null 401 'estoque sem token' | Out-Null
Chamar GET '/painel' $null $null 401 'painel sem token' | Out-Null
Chamar GET '/logs' $null $null 401 'logs sem token' | Out-Null
Chamar GET '/usuarios' $null $null 401 'usuarios sem token' | Out-Null
Chamar GET '/eu' $null $null 401 'eu sem token' | Out-Null
Chamar GET '/obras' $null $null 401 'obras sem token' | Out-Null
Chamar GET '/custos' $null $null 401 'custos sem token' | Out-Null
Chamar GET '/pedidos' $null $null 401 'pedidos sem token' | Out-Null
Chamar GET '/equipamentos' $null $null 401 'equipamentos sem token' | Out-Null
Chamar GET '/emprestimos' $null $null 401 'emprestimos sem token' | Out-Null
Chamar GET '/categorias' $null $null 401 'categorias sem token' | Out-Null

FinalizarCaso
