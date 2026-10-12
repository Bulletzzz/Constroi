. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Equipamentos: cadastro e status'

$c = NovoCenario -ComUsuarios
$marca = $c.marca

$equipamento = Chamar POST '/equipamentos' $c.engenheiro @{
    equipamento = @{ nome = "Betoneira $marca"; patrimonio = "BT-$marca"; status = 'disponivel' }
} 201 'POST /equipamentos'
Conferir ($null -ne $equipamento.id) 'equipamento criado recebeu id'

Chamar GET '/equipamentos' $c.engenheiro $null 200 'GET /equipamentos' | Out-Null
Chamar GET "/equipamentos/$($equipamento.id)" $c.engenheiro $null 200 'GET /equipamentos/{id}' | Out-Null
Chamar PATCH "/equipamentos/$($equipamento.id)" $c.engenheiro @{ equipamento = @{ status = 'manutencao' } } 200 'PATCH status' | Out-Null

Chamar POST '/equipamentos' $c.engenheiro @{
    equipamento = @{ nome = 'Y'; patrimonio = 'Z'; status = 'quebradoo' }
} 400 'POST status invalido' | Out-Null
Chamar POST '/equipamentos' $c.engenheiro @{
    equipamento = @{ nome = "Clone $marca"; patrimonio = "BT-$marca"; status = 'disponivel' }
} 409 'POST patrimonio repetido' | Out-Null
Chamar POST '/equipamentos' $c.engenheiro @{ nome = 'Y'; patrimonio = 'Z'; status = 'disponivel' } 400 'POST sem envelope' | Out-Null
Chamar GET '/equipamentos/999999' $c.engenheiro $null 404 'GET equipamento inexistente' | Out-Null

Chamar GET '/equipamentos' $c.pedreiro $null 403 'GET /equipamentos como pedreiro' | Out-Null

VerificarBanco "SELECT status FROM equipamento WHERE id = $($equipamento.id)" 'manutencao' `
    'status persistido apos o PATCH'

FinalizarCaso
