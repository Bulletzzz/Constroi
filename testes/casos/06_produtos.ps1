. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Produtos: catalogo, SKU e estoque minimo'

$c = NovoCenario -ComUsuarios
$marca = $c.marca

$produto = Chamar POST '/produtos' $c.engenheiro @{
    produto = @{ nome = "Cimento $marca"; unidade = 'saco' }
} 201 'POST /produtos'
Conferir ($null -ne $produto.id) 'produto criado recebeu id'
Conferir ([decimal]$produto.estoque_minimo -eq 0) 'produto novo nasce com minimo zero'

Chamar GET '/produtos' $c.engenheiro $null 200 'GET /produtos' | Out-Null
Chamar GET "/produtos/$($produto.id)" $c.engenheiro $null 200 'GET /produtos/{id}' | Out-Null
Chamar PATCH "/produtos/$($produto.id)" $c.engenheiro @{ produto = @{ unidade = 'un' } } 200 'PATCH unidade' | Out-Null

Chamar POST '/produtos' $c.engenheiro @{ produto = @{ nome = "Cimento $marca"; unidade = 'saco' } } 409 'POST nome repetido' | Out-Null
Chamar POST '/produtos' $c.engenheiro @{ produto = @{ nome = 'Y'; unidade = 'caixinha' } } 400 'POST unidade invalida' | Out-Null
Chamar POST '/produtos' $c.engenheiro @{ nome = 'Y'; unidade = 'un' } 400 'POST sem envelope' | Out-Null

$configurado = Chamar PATCH "/produtos/$($produto.id)" $c.engenheiro @{
    produto = @{ sku = "CIM-$marca"; estoque_minimo = '5.00' }
} 200 'PATCH SKU e minimo'
Conferir ($configurado.sku -eq "CIM-$marca" -and [decimal]$configurado.estoque_minimo -eq 5) 'SKU e minimo persistiram'

Chamar POST '/produtos' $c.engenheiro @{
    produto = @{ nome = "Outro $marca"; unidade = 'un'; sku = "cim-$marca" }
} 409 'POST SKU duplicado ignorando caixa' | Out-Null

Chamar PATCH "/produtos/$($produto.id)" $c.engenheiro @{ produto = @{ estoque_minimo = -1 } } 400 'PATCH minimo negativo' | Out-Null
Chamar PATCH "/produtos/$($produto.id)" $c.engenheiro @{ produto = @{ estoque_minimo = $null } } 400 'PATCH minimo nulo' | Out-Null
Chamar PATCH "/produtos/$($produto.id)" $c.engenheiro @{ produto = @{ estoque_minimo = '7,50' } } 200 'PATCH minimo com virgula' | Out-Null

$limpo = Chamar PATCH "/produtos/$($produto.id)" $c.engenheiro @{ produto = @{ sku = $null } } 200 'PATCH remove o SKU'
Conferir ($null -eq $limpo.sku) 'SKU ficou nulo'

Chamar GET '/produtos' $c.pedreiro $null 403 'GET /produtos como pedreiro' | Out-Null
Chamar POST '/produtos' $c.pedreiro @{ produto = @{ nome = "Furtivo $marca"; unidade = 'un' } } 403 'POST /produtos como pedreiro' | Out-Null

VerificarBanco "SELECT estoque_minimo::text FROM produto WHERE id = $($produto.id)" '7.50' `
    'minimo com virgula virou decimal no banco'

FinalizarCaso
