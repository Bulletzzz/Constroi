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

Chamar POST $c.rotaEquipe $c.engenheiro @{ equipe = @{ usuario_id = $euB.id } } 400 'vincular usuario de outra empresa' | Out-Null
VerificarBanco "SELECT COUNT(*)::text FROM usuario_obra WHERE obra_id = $($c.obra.id) AND usuario_id = $($euB.id)" '0' `
    'nenhum vinculo cruzado foi criado'

$obrasB = Chamar GET '/obras' $c.masterB $null 200 'GET /obras empresa B'
Conferir (-not ($obrasB.obras | Where-Object { $_.id -eq $c.obra.id })) 'listagem da B nao traz obra da A'

$produtosB = Chamar GET '/produtos' $c.masterB $null 200 'GET /produtos empresa B'
Conferir (-not ($produtosB.produtos | Where-Object { $_.id -eq $c.produto.id })) 'listagem da B nao traz produto da A'

FinalizarCaso
