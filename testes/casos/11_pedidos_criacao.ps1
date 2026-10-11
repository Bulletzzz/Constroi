. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Pedidos: criacao e validacao de itens'

$c = NovoCenario -ComObra -ComProduto
$marca = $c.marca
$obraId = $c.obra.id
$produtoId = $c.produto.id

Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = $obraId; itens = @(@{ produto_id = $produtoId; quantidade = 1 }) }
} 403 'pedreiro sem vinculo nao cria pedido' | Out-Null

Chamar POST $c.rotaEquipe $c.engenheiro @{ equipe = @{ usuario_id = $c.pedreiroUsuario.id } } 201 'vincula pedreiro' | Out-Null

$pedido = Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{
        obra_id = $obraId
        justificativa = "Reposicao $marca"
        itens = @(@{ produto_id = $produtoId; quantidade = 2.5 })
    }
} 201 'POST pedido valido'

Conferir ($pedido.protocolo -match '^PED-[0-9A-F]{32}$') "protocolo no formato esperado ($($pedido.protocolo))"
Conferir ($pedido.status -eq 'pendente') "status inicial pendente (veio $($pedido.status))"
Conferir ($pedido.usuario_id -eq $c.pedreiroUsuario.id) 'pedido gravado com o solicitante certo'
Conferir ($pedido.obra_id -eq $obraId) 'pedido gravado na obra certa'
Conferir (@($pedido.itens).Count -eq 1) 'pedido tem exatamente 1 item'
Conferir ("$($pedido.itens[0].quantidade)" -eq '2.50') "quantidade preserva 2 casas (veio $($pedido.itens[0].quantidade))"

Chamar POST '/pedidos' $null @{
    pedido = @{ obra_id = $obraId; itens = @(@{ produto_id = $produtoId; quantidade = 1 }) }
} 401 'POST pedido sem token' | Out-Null

Chamar POST '/pedidos' $c.pedreiro @{
    obra_id = $obraId; itens = @(@{ produto_id = $produtoId; quantidade = 1 })
} 400 'POST pedido sem envelope' | Out-Null

Chamar POST '/pedidos' $c.pedreiro @{ pedido = @{ obra_id = $obraId; itens = @() } } 400 'POST pedido sem itens' | Out-Null

Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = $obraId; itens = @(
        @{ produto_id = $produtoId; quantidade = 1 },
        @{ produto_id = $produtoId; quantidade = 2 }
    ) }
} 400 'POST pedido com produto repetido' | Out-Null

Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = $obraId; itens = @(@{ produto_id = $produtoId; quantidade = 0 }) }
} 400 'POST pedido com quantidade zero' | Out-Null

Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = $obraId; itens = @(@{ produto_id = $produtoId; quantidade = -1 }) }
} 400 'POST pedido com quantidade negativa' | Out-Null

Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = $obraId; itens = @(@{ produto_id = $produtoId; quantidade = 1.555 }) }
} 400 'POST pedido com 3 casas decimais' | Out-Null

Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = 999999999; itens = @(@{ produto_id = $produtoId; quantidade = 1 }) }
} 404 'POST pedido em obra inexistente' | Out-Null

Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = $obraId; itens = @(@{ produto_id = 999999999; quantidade = 1 }) }
} 400 'POST pedido com produto inexistente' | Out-Null

$itensDemais = 1..201 | ForEach-Object { @{ produto_id = $_; quantidade = 1 } }
Chamar POST '/pedidos' $c.pedreiro @{ pedido = @{ obra_id = $obraId; itens = $itensDemais } } 400 'POST pedido com 201 itens' | Out-Null

Chamar PUT '/pedidos' $c.pedreiro $null 405 'PUT /pedidos nao permitido' | Out-Null

VerificarBanco "SELECT COUNT(*)::text FROM pedido WHERE obra_id = $obraId" '1' `
    'apenas o pedido valido foi gravado'

FinalizarCaso
