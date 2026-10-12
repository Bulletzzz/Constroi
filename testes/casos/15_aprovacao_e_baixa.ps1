. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Aprovacao de pedido com baixa de estoque'

$c = NovoCenario -ComObra -ComProduto -ComEquipe -ComEmpresaB
$obraId = $c.obra.id
$produtoId = $c.produto.id

ExecutarBanco -Argumentos @('estoque', "$obraId", "$produtoId", '2.50') | Out-Null

$pedido = Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = $obraId; itens = @(@{ produto_id = $produtoId; quantidade = 1.25 }) }
} 201 'cria pedido para baixa'
$rota = "/pedidos/$($pedido.id)"
$aprovar = @{ pedido = @{ status = 'aprovado' } }

Chamar PATCH $rota $null $aprovar 401 'aprovar sem token' | Out-Null
Chamar PATCH $rota $c.pedreiro $aprovar 403 'pedreiro nao aprova' | Out-Null
Chamar PATCH $rota $c.masterB $aprovar 404 'empresa B nao aprova pedido da A' | Out-Null
Chamar PATCH $rota $c.engenheiro @{} 400 'aprovacao com corpo invalido' | Out-Null

$aprovado = Chamar PATCH $rota $c.engenheiro $aprovar 200 'engenheiro aprova e baixa'
Conferir ($aprovado.status -eq 'aprovado') 'pedido ficou aprovado'
Conferir (@($aprovado.baixas).Count -eq 1) 'resposta traz 1 baixa'
Conferir ([decimal]$aprovado.baixas[0].quantidade -eq 1.25) 'baixa com a quantidade decimal pedida'
Conferir ([decimal]$aprovado.baixas[0].saldo -eq 1.25) 'saldo restante calculado em NUMERIC'

$detalhe = Chamar GET $rota $c.pedreiro $null 200 'pedreiro acompanha a aprovacao'
Conferir ($detalhe.status -eq 'aprovado') 'detalhe mostra aprovado'

Chamar PATCH $rota $c.engenheiro $aprovar 409 'reaprovacao nao duplica baixa' | Out-Null
VerificarBanco "SELECT COUNT(*)::text FROM log_sistema WHERE acao LIKE 'BAIXA_ESTOQUE pedido=$($pedido.id) %'" '1' `
    'baixa registrou exatamente um log'

$semSaldo = Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = $obraId; itens = @(@{ produto_id = $produtoId; quantidade = 2 }) }
} 201 'cria pedido acima do saldo'
Chamar PATCH "/pedidos/$($semSaldo.id)" $c.engenheiro $aprovar 409 'saldo insuficiente nao aprova' | Out-Null

$pendente = Chamar GET "/pedidos/$($semSaldo.id)" $c.pedreiro $null 200 'pedido sem saldo continua pendente'
Conferir ($pendente.status -eq 'pendente') 'falta de saldo nao muda o status'

VerificarBanco "SELECT quantidade::text FROM estoque WHERE obra_id = $obraId AND produto_id = $produtoId" '1.25' `
    'reaprovacao e falta de saldo nao alteraram o estoque'

Chamar PATCH $rota $c.engenheiro @{ pedido = @{ status = 'invalido' } } 400 'status desconhecido' | Out-Null
Chamar PATCH '/pedidos/999999999' $c.engenheiro $aprovar 404 'aprovar pedido inexistente' | Out-Null

$orfao = Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = $obraId; itens = @(@{ produto_id = $produtoId; quantidade = 1 }) }
} 201 'cria pedido que perdera os itens'
ExecutarBanco -Argumentos @('consultar',
    "WITH d AS (DELETE FROM item_pedido WHERE pedido_id = $($orfao.id) RETURNING 1) SELECT COUNT(*)::text FROM d") | Out-Null
Chamar PATCH "/pedidos/$($orfao.id)" $c.engenheiro $aprovar 400 'pedido sem itens validos da 400' | Out-Null
VerificarBanco "SELECT status FROM pedido WHERE id = $($orfao.id)" 'pendente' `
    'pedido recusado por itens invalidos nao muda de status'

FinalizarCaso
