. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Pedidos: leitura, filtros e isolamento'

$c = NovoCenario -ComObra -ComProduto -ComEquipe -ComEmpresaB
$marca = $c.marca

$pedido = Chamar POST '/pedidos' $c.pedreiro @{
    pedido = @{ obra_id = $c.obra.id; itens = @(@{ produto_id = $c.produto.id; quantidade = 1 }) }
} 201 'pedido do primeiro pedreiro'

$segundo = Chamar POST '/usuarios' $c.master @{
    usuario = @{ nome = "Ped2 $marca"; email = "ped2.$marca@teste.com"; senha = $global:SenhaPadrao; tipo = 'pedreiro' }
} 201 'cria segundo pedreiro'
$tokenSegundo = Entrar "ped2.$marca@teste.com"
Chamar POST $c.rotaEquipe $c.engenheiro @{ equipe = @{ usuario_id = $segundo.id } } 201 'vincula segundo pedreiro' | Out-Null

$pedidoDoOutro = Chamar POST '/pedidos' $tokenSegundo @{
    pedido = @{ obra_id = $c.obra.id; itens = @(@{ produto_id = $c.produto.id; quantidade = 1 }) }
} 201 'pedido do segundo pedreiro'

Chamar GET "/pedidos/$($pedidoDoOutro.id)" $c.pedreiro $null 404 'pedreiro nao le pedido de outro' | Out-Null
Chamar GET "/pedidos/$($pedido.id)" $tokenSegundo $null 404 'segundo pedreiro nao le o primeiro' | Out-Null
Chamar GET "/pedidos/$($pedido.id)" $c.pedreiro $null 200 'pedreiro le o proprio pedido' | Out-Null
Chamar GET "/pedidos/$($pedido.id)" $c.engenheiro $null 200 'engenheiro le pedido de qualquer um' | Out-Null
Chamar GET "/pedidos/$($pedido.id)" $c.masterB $null 404 'pedido da empresa A com token da B' | Out-Null

$listaPedreiro = Chamar GET '/pedidos' $c.pedreiro $null 200 'GET /pedidos como pedreiro'
Conferir (-not ($listaPedreiro.pedidos | Where-Object { $_.usuario_id -ne $c.pedreiroUsuario.id })) `
    'lista do pedreiro so traz os proprios pedidos'

$listaEngenheiro = Chamar GET '/pedidos' $c.engenheiro $null 200 'GET /pedidos como engenheiro'
Conferir ([bool]($listaEngenheiro.pedidos | Where-Object { $_.usuario_id -eq $segundo.id })) `
    'engenheiro enxerga pedido do segundo pedreiro'

$porProtocolo = Chamar GET "/pedidos?protocolo=$($pedido.protocolo)" $c.engenheiro $null 200 'filtra por protocolo'
Conferir (@($porProtocolo.pedidos).Count -eq 1) "filtro por protocolo traz 1 (veio $(@($porProtocolo.pedidos).Count))"

$porObra = Chamar GET "/pedidos?obra_id=$($c.obra.id)" $c.engenheiro $null 200 'filtra por obra'
Conferir (@($porObra.pedidos).Count -eq 2) "filtro por obra traz 2 (veio $(@($porObra.pedidos).Count))"

Chamar GET '/pedidos?limit=1' $c.engenheiro $null 200 'limit=1' | Out-Null
Chamar GET '/pedidos?limit=0' $c.engenheiro $null 400 'limit=0' | Out-Null
Chamar GET '/pedidos?limit=201' $c.engenheiro $null 400 'limit=201' | Out-Null
Chamar GET '/pedidos?offset=-1' $c.engenheiro $null 400 'offset negativo' | Out-Null
Chamar GET '/pedidos?obra_id=abc' $c.engenheiro $null 400 'obra_id invalido' | Out-Null
Chamar GET '/pedidos/0' $c.engenheiro $null 400 'GET /pedidos/0' | Out-Null
Chamar GET '/pedidos' $null $null 401 'GET /pedidos sem token' | Out-Null

FinalizarCaso
