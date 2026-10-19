. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Recusa de pedido com justificativa e log'

$c = NovoCenario -ComObra -ComProduto -ComEquipe -ComEmpresaB
$obraId = $c.obra.id
$produtoId = $c.produto.id

ExecutarBanco -Argumentos @('estoque', "$obraId", "$produtoId", '2.50') | Out-Null

$pedido = Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{
        obra_id = $obraId
        justificativa = 'Material para concretagem'
        itens = @(@{ produto_id = $produtoId; quantidade = 10 })
    }
} 201 'cria pedido com justificativa original'
$rota = "/pedidos/$($pedido.id)"
$recusar = @{ pedido = @{ status = 'recusado'; justificativa = '  Material desnecessario  ' } }

Chamar PATCH $rota $null $recusar 401 'recusar sem token' | Out-Null
Chamar PATCH $rota $c.pedreiro $recusar 403 'pedreiro nao recusa' | Out-Null
Chamar PATCH $rota $c.masterB $recusar 404 'empresa B nao recusa pedido da A' | Out-Null
Chamar PATCH $rota $c.engenheiro @{ pedido = @{ status = 'recusado' } } 400 'recusa sem justificativa' | Out-Null

foreach ($justificativa in @($null, '', '   ', 123, ('a' * 256))) {
    Chamar PATCH $rota $c.engenheiro @{
        pedido = @{ status = 'recusado'; justificativa = $justificativa }
    } 400 'recusa com justificativa invalida' | Out-Null
}

$recusado = Chamar PATCH $rota $c.engenheiro $recusar 200 'engenheiro recusa mesmo sem saldo suficiente'
Conferir ($recusado.status -eq 'recusado') 'pedido ficou recusado'
Conferir ($recusado.justificativa -eq 'Material para concretagem') 'motivo original foi preservado'
Conferir ($recusado.justificativa_recusa -eq 'Material desnecessario') 'motivo da recusa foi aparado'

$detalhe = Chamar GET $rota $c.pedreiro $null 200 'pedreiro acompanha a recusa'
Conferir ($detalhe.justificativa_recusa -eq 'Material desnecessario') 'detalhe mostra motivo da recusa'
$lista = Chamar GET "/pedidos?protocolo=$($pedido.protocolo)" $c.pedreiro $null 200 'consulta pedido por protocolo'
Conferir ($lista.pedidos[0].justificativa_recusa -eq 'Material desnecessario') 'listagem mostra motivo da recusa'

Chamar PATCH $rota $c.engenheiro $recusar 409 'pedido recusado nao pode ser recusado de novo' | Out-Null
Chamar PATCH $rota $c.engenheiro @{ pedido = @{ status = 'aprovado' } } 409 'pedido recusado nao pode ser aprovado' | Out-Null
Chamar PATCH '/pedidos/999999999' $c.engenheiro $recusar 404 'recusar pedido inexistente' | Out-Null

VerificarBanco "SELECT COUNT(*)::text FROM log_sistema WHERE usuario_id = $($c.engenheiroUsuario.id) AND acao LIKE 'RECUSA_PEDIDO pedido=$($pedido.id) %'" '1' `
    'recusa registrou exatamente um log com o ator autenticado'
VerificarBanco "SELECT COUNT(*)::text FROM log_sistema WHERE acao LIKE 'BAIXA_ESTOQUE pedido=$($pedido.id) %'" '0' `
    'recusa nao registrou baixa'
VerificarBanco "SELECT quantidade::text FROM estoque WHERE obra_id = $obraId AND produto_id = $produtoId" '2.50' `
    'recusa nao alterou o estoque'

$outro = Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = $obraId; itens = @(@{ produto_id = $produtoId; quantidade = 1 }) }
} 201 'cria pedido para recusa pelo master'
$limite = 'a' * 255
$peloMaster = Chamar PATCH "/pedidos/$($outro.id)" $c.master @{
    pedido = @{ status = 'recusado'; justificativa = "  $limite  " }
} 200 'master recusa com 255 caracteres apos aparar'
Conferir ($peloMaster.justificativa_recusa -eq $limite) 'justificativa no limite foi gravada inteira'

FinalizarCaso
