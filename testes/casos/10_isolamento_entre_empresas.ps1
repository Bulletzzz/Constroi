. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Isolamento entre empresas'

$c = NovoCenario -ComObra -ComProduto -ComEmpresaB

Chamar GET "/obras/$($c.obra.id)" $c.masterB $null 404 'obra da empresa A com token da B' | Out-Null
Chamar GET $c.rotaEquipe $c.masterB $null 404 'equipe da empresa A com token da B' | Out-Null
Chamar GET "/produtos/$($c.produto.id)" $c.masterB $null 404 'produto da empresa A com token da B' | Out-Null
Chamar GET "/usuarios/$($c.pedreiroUsuario.id)" $c.masterB $null 404 'usuario da empresa A com token da B' | Out-Null
Chamar PATCH "/obras/$($c.obra.id)" $c.masterB @{ obra = @{ status = 'concluida' } } 404 'PATCH obra da empresa A pela B' | Out-Null

$euB = Chamar GET '/eu' $c.masterB $null 200 'GET /eu empresa B'
Conferir ($euB.empresa_id -ne $c.pedreiroUsuario.empresa_id) 'empresas tem ids diferentes'

Chamar POST $c.rotaEquipe $c.engenheiro @{ equipe = @{ usuario_id = $euB.id } } 404 'vincular usuario de outra empresa' | Out-Null
VerificarBanco "SELECT COUNT(*)::text FROM usuario_obra WHERE obra_id = $($c.obra.id) AND usuario_id = $($euB.id)" '0' `
    'nenhum vinculo cruzado foi criado'

$obrasB = Chamar GET '/obras' $c.masterB $null 200 'GET /obras empresa B'
Conferir (-not ($obrasB.obras | Where-Object { $_.id -eq $c.obra.id })) 'listagem da B nao traz obra da A'

$produtosB = Chamar GET '/produtos' $c.masterB $null 200 'GET /produtos empresa B'
Conferir (-not ($produtosB.produtos | Where-Object { $_.id -eq $c.produto.id })) 'listagem da B nao traz produto da A'

# Varredura de leitura: nenhuma rota pode devolver dado da empresa A ao token da B.
$estoqueB = Chamar GET '/estoque' $c.masterB $null 200 'GET /estoque empresa B'
Conferir (-not ($estoqueB.estoque | Where-Object { $_.produto_id -eq $c.produto.id })) `
    'estoque da B nao traz produto da A'
Conferir (-not ($estoqueB.estoque | Where-Object { $_.obra_id -eq $c.obra.id })) `
    'estoque da B nao traz obra da A'

Chamar GET "/estoque?obra_id=$($c.obra.id)" $c.masterB $null 404 'estoque da obra da A com token da B' | Out-Null

$painelB = Chamar GET '/painel' $c.masterB $null 200 'GET /painel empresa B'
Conferir (-not ($painelB.obras | Where-Object { $_.id -eq $c.obra.id })) `
    'painel da B nao lista obra da A'
Conferir ([int]$painelB.indicadores.total_itens -eq 0) `
    "painel da B comeca sem itens (veio $($painelB.indicadores.total_itens))"

Chamar GET "/painel?obra_id=$($c.obra.id)" $c.masterB $null 404 'painel da obra da A com token da B' | Out-Null

$custosB = Chamar GET '/custos' $c.masterB $null 200 'GET /custos empresa B'
Conferir (-not ($custosB.obras | Where-Object { $_.id -eq $c.obra.id })) `
    'custos da B nao lista obra da A'
Conferir ([decimal]$custosB.resumo.custo_acumulado -eq 0) `
    "custos da B comecam zerados (veio $($custosB.resumo.custo_acumulado))"

Chamar GET "/custos?obra_id=$($c.obra.id)" $c.masterB $null 404 'custos da obra da A com token da B' | Out-Null

$logsB = Chamar GET '/logs' $c.masterB $null 200 'GET /logs empresa B'
$idsDaA = @($c.engenheiroUsuario.id, $c.pedreiroUsuario.id)
Conferir (-not ($logsB.logs | Where-Object { $idsDaA -contains $_.usuario_id })) `
    'logs da B nao trazem evento de usuario da A'

$pedidosB = Chamar GET '/pedidos' $c.masterB $null 200 'GET /pedidos empresa B'
Conferir ($pedidosB.pedidos.Count -eq 0) `
    "pedidos da B comecam vazios (veio $($pedidosB.pedidos.Count))"

$pedidosDaObraA = Chamar GET "/pedidos?obra_id=$($c.obra.id)" $c.masterB $null 200 'pedidos da obra da A com token da B'
Conferir ($pedidosDaObraA.pedidos.Count -eq 0) 'filtro por obra alheia devolve lista vazia'

$equipamentosB = Chamar GET '/equipamentos' $c.masterB $null 200 'GET /equipamentos empresa B'
Conferir ($equipamentosB.equipamentos.Count -eq 0) 'equipamentos da B comecam vazios'

$emprestimosB = Chamar GET '/emprestimos' $c.masterB $null 200 'GET /emprestimos empresa B'
Conferir ($emprestimosB.emprestimos.Count -eq 0) 'emprestimos da B comecam vazios'

$usuariosB = Chamar GET '/usuarios' $c.masterB $null 200 'GET /usuarios empresa B'
Conferir (-not ($usuariosB.usuarios | Where-Object { $idsDaA -contains $_.id })) `
    'usuarios da B nao trazem pessoa da A'

# Escrita: a B nao pode lancar nem decidir nada dentro da A.
Chamar POST '/custos/despesas' $c.masterB @{
    despesa = @{ obra_id = $c.obra.id; categoria_custo_id = 1; descricao = 'Invasao'; valor = '10.00' }
} 404 'despesa na obra da A com token da B' | Out-Null
VerificarBanco "SELECT COUNT(*)::text FROM despesa_obra WHERE obra_id = $($c.obra.id)" '0' `
    'nenhuma despesa cruzada foi gravada'

Chamar POST '/pedidos' $c.masterB @{
    pedido = @{ obra_id = $c.obra.id; itens = @(@{ produto_id = $c.produto.id; quantidade = 1 }) }
} 404 'pedido na obra da A com token da B' | Out-Null

Chamar POST '/produtos' $c.masterB @{
    produto = @{ nome = "Cimento $($c.marca)"; unidade = 'kg' }
} 201 'B cria produto com nome igual ao da A' | Out-Null

FinalizarCaso
