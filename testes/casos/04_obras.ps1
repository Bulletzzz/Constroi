. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Obras: criacao, edicao e validacao'

$c = NovoCenario -ComUsuarios
$marca = $c.marca

$obra = Chamar POST '/obras' $c.engenheiro @{
    obra = @{ nome = "Obra Alpha $marca"; endereco = 'Rua de teste, 123'; status = 'planejamento'; orcamento_total = 250000.5 }
} 201 'POST /obras com orcamento'
Conferir ($null -ne $obra.id) 'obra criada recebeu id'

Chamar GET '/obras' $c.engenheiro $null 200 'GET /obras engenheiro' | Out-Null
Chamar GET "/obras/$($obra.id)" $c.engenheiro $null 200 'GET /obras/{id}' | Out-Null
Chamar PATCH "/obras/$($obra.id)" $c.engenheiro @{ obra = @{ status = 'ativa' } } 200 'PATCH status' | Out-Null
Chamar PATCH "/obras/$($obra.id)" $c.engenheiro @{ obra = @{ orcamento_total = '310000,75' } } 200 'PATCH orcamento com virgula' | Out-Null
Chamar PATCH "/obras/$($obra.id)" $c.engenheiro @{ obra = @{ orcamento_total = $null } } 200 'PATCH orcamento nulo limpa' | Out-Null
Chamar PATCH "/obras/$($obra.id)" $c.engenheiro @{ obra = @{ orcamento_total = -5 } } 400 'PATCH orcamento negativo' | Out-Null

Chamar POST '/obras' $c.engenheiro @{ obra = @{ nome = 'X'; endereco = 'Y'; status = 'andando' } } 400 'POST status invalido' | Out-Null
Chamar POST '/obras' $c.engenheiro @{ nome = 'X'; endereco = 'Y'; status = 'ativa' } 400 'POST /obras sem envelope' | Out-Null
Chamar GET '/obras/999999' $c.engenheiro $null 404 'GET obra inexistente' | Out-Null
Chamar GET '/obras/abc' $c.engenheiro $null 400 'GET obra com id invalido' | Out-Null
Chamar DELETE "/obras/$($obra.id)" $c.engenheiro $null 405 'DELETE /obras/{id}' | Out-Null

Chamar GET '/obras' $c.pedreiro $null 200 'GET /obras pedreiro sem vinculo' | Out-Null
Chamar GET "/obras/$($obra.id)" $c.pedreiro $null 404 'GET obra nao vinculada' | Out-Null
Chamar POST '/obras' $c.pedreiro @{ obra = @{ nome = 'Furtiva'; endereco = 'Y'; status = 'ativa' } } 403 'POST /obras pedreiro' | Out-Null
Chamar PATCH "/obras/$($obra.id)" $c.pedreiro @{ obra = @{ status = 'concluida' } } 403 'PATCH /obras pedreiro' | Out-Null

VerificarBanco "SELECT orcamento_total IS NULL FROM obra WHERE id = $($obra.id)" 'true' `
    'orcamento continua nulo apos o PATCH negativo'

FinalizarCaso
