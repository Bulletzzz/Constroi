. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Consulta de estoque: filtros, contrato e vinculo'

$c = NovoCenario -ComObra -ComProduto
$marca = $c.marca
$obraId = $c.obra.id
$produtoId = $c.produto.id
$rotaEstoque = "/estoque?obra_id=$obraId"

Chamar GET $rotaEstoque $c.pedreiro $null 404 'GET estoque sem vinculo' | Out-Null
$semVinculo = Chamar GET '/estoque' $c.pedreiro $null 200 'GET estoque geral sem vinculo'
Conferir (@($semVinculo.estoque).Count -eq 0) 'usuario sem vinculo nao recebe saldos'

Chamar POST $c.rotaEquipe $c.engenheiro @{ equipe = @{ usuario_id = $c.pedreiroUsuario.id } } 201 'vincula pedreiro' | Out-Null

Chamar GET $rotaEstoque $c.engenheiro $null 200 'GET estoque engenheiro' | Out-Null
Chamar GET $rotaEstoque $c.pedreiro $null 200 'GET estoque pedreiro vinculado' | Out-Null
Chamar GET $rotaEstoque $null $null 401 'GET estoque sem token' | Out-Null
Chamar GET '/estoque' $c.master $null 200 'GET estoque sem obra_id' | Out-Null
Chamar GET '/estoque?categoria_id=abc' $c.master $null 400 'categoria invalida' | Out-Null
Chamar GET '/estoque?categoria_id=2147483647' $c.master $null 200 'categoria inexistente' | Out-Null
Chamar GET "$rotaEstoque&baixo=1" $c.master $null 400 'filtro baixo invalido' | Out-Null
Chamar GET "$rotaEstoque&limit=0" $c.master $null 400 'limit=0' | Out-Null
Chamar GET "$rotaEstoque&limit=201" $c.master $null 400 'limit=201' | Out-Null
Chamar GET '/estoque?obra_id=999999999' $c.master $null 404 'obra inexistente' | Out-Null
Chamar POST $rotaEstoque $c.pedreiro @{} 405 'POST /estoque nao permitido' | Out-Null

Chamar PATCH "/produtos/$produtoId" $c.engenheiro @{
    produto = @{ sku = "CIM-$marca"; estoque_minimo = '5.00' }
} 200 'configura SKU e minimo' | Out-Null

$preparo = ExecutarBanco -Argumentos @('estoque', "$obraId", "$produtoId", '5')
$categoriaId = $preparo.categoria_custo_id
Conferir ($null -ne $categoriaId -and [decimal]$preparo.quantidade -eq 5) 'preparo deixou saldo 5 e categoria'

$saldo = Chamar GET "$rotaEstoque&busca=cim-$marca&baixo=true" $c.pedreiro $null 200 'busca por SKU com baixo=true'
$linha = $saldo.estoque[0]
Conferir (@($saldo.estoque).Count -eq 1) 'busca por SKU retorna 1 linha'
Conferir ($linha.produto_id -eq $produtoId) 'linha traz o produto certo'
Conferir ([decimal]$linha.quantidade -eq 5) "quantidade 5 (veio $($linha.quantidade))"
Conferir ([bool]$linha.baixo) 'saldo igual ao minimo conta como baixo'
Conferir ($linha.produto_nome -eq $c.produto.nome) 'contrato usa produto_nome'
Conferir ($linha.sku -eq "CIM-$marca") 'linha traz o SKU'
Conferir ([decimal]$linha.estoque_minimo -eq 5) 'linha traz o minimo'
Conferir ($linha.categoria_custo_id -eq [int]$categoriaId) 'linha traz categoria_custo_id'
Conferir ($linha.categoria_nome -eq $preparo.categoria_nome) 'linha traz categoria_nome com acento'

$porNome = Chamar GET "$rotaEstoque&busca=Cimento" $c.engenheiro $null 200 'busca por nome'
Conferir ([bool]($porNome.estoque | Where-Object { $_.produto_id -eq $produtoId })) 'busca por nome encontra o produto'

$porCategoria = Chamar GET "/estoque?categoria_id=$categoriaId&busca=cim-$marca" $c.pedreiro $null 200 'categoria sem obra_id'
Conferir (@($porCategoria.estoque).Count -eq 1 -and $porCategoria.estoque[0].obra_id -eq $obraId) `
    'escopo geral respeita a categoria e a obra vinculada'

$semCategoria = Chamar GET "$rotaEstoque&categoria_id=2147483647" $c.engenheiro $null 200 'categoria sem saldos'
Conferir (@($semCategoria.estoque).Count -eq 0) 'filtro de categoria nao e ignorado'

ExecutarBanco -Argumentos @('estoque', "$obraId", "$produtoId", '6') | Out-Null
$acima = Chamar GET "$rotaEstoque&baixo=true" $c.engenheiro $null 200 'saldo acima do minimo'
Conferir (-not ($acima.estoque | Where-Object { $_.produto_id -eq $produtoId })) 'saldo acima do minimo sai do filtro baixo'

Chamar DELETE "$($c.rotaEquipe)/$($c.pedreiroUsuario.id)" $c.engenheiro $null 200 'encerra vinculo' | Out-Null
Chamar GET $rotaEstoque $c.pedreiro $null 404 'GET estoque com vinculo encerrado' | Out-Null
$aposEncerrar = Chamar GET '/estoque' $c.pedreiro $null 200 'GET estoque geral apos encerrar'
Conferir (@($aposEncerrar.estoque).Count -eq 0) 'vinculo encerrado nao enxerga mais saldos'

FinalizarCaso
