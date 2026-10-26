. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Custos: totais, periodo e isolamento contra o banco'

$c = NovoCenario -ComObra -ComProduto -ComEmpresaB
$obraId = $c.obra.id
$produtoId = $c.produto.id
$engenheiroId = $c.engenheiroUsuario.id

$beta = Chamar POST '/obras' $c.engenheiro @{
    obra = @{ nome = "Obra Beta $($c.marca)"; endereco = 'Rua de teste, 456'; status = 'ativa' }
} 201 'cria segunda obra sem orcamento'
$betaId = $beta.id

$fuso = "AT TIME ZONE 'America/Sao_Paulo'"
$partes = @(
    "WITH marcos AS (SELECT date_trunc('week', CURRENT_TIMESTAMP $fuso) $fuso AS inicio_semana, date_trunc('month', CURRENT_TIMESTAMP $fuso) $fuso AS inicio_mes)",
    "cat AS (SELECT (SELECT id FROM categoria_custo WHERE nome = 'Cimento e agregados') AS cimento, (SELECT id FROM categoria_custo WHERE nome LIKE 'Loca%de equipamentos') AS locacao, (SELECT id FROM categoria_custo WHERE nome LIKE 'EPI e consum%') AS epi)",
    "orcamento AS (UPDATE obra SET orcamento_total = 10000.00 WHERE id = $obraId RETURNING id)",
    "entrada AS (INSERT INTO entrada_estoque (usuario_id, obra_id, data) SELECT $engenheiroId, $obraId, inicio_semana - interval '1 second' FROM marcos RETURNING id)",
    "itens AS (INSERT INTO item_entrada (entrada_id, produto_id, quantidade, valor_unitario, categoria_custo_id) SELECT entrada.id, $produtoId, v.quantidade, v.preco, CASE WHEN v.preco IS NULL THEN NULL ELSE cat.cimento END FROM entrada, cat, (VALUES (12.50::numeric, 44.80::numeric), (3.33::numeric, 10.07::numeric), (5.00::numeric, NULL::numeric)) AS v(quantidade, preco) RETURNING 1)",
    "gasto_locacao AS (INSERT INTO despesa_obra (empresa_id, obra_id, registrado_por_usuario_id, categoria_custo_id, descricao, valor, data_lancamento) SELECT o.empresa_id, o.id, $engenheiroId, cat.locacao, 'Locacao de betoneira', 1500.00, CURRENT_TIMESTAMP FROM obra o, cat WHERE o.id = $obraId RETURNING 1)",
    "gasto_epi AS (INSERT INTO despesa_obra (empresa_id, obra_id, registrado_por_usuario_id, categoria_custo_id, descricao, valor, data_lancamento) SELECT o.empresa_id, o.id, $engenheiroId, cat.epi, 'EPI da equipe', 275.25, marcos.inicio_mes - interval '1 second' FROM obra o, cat, marcos WHERE o.id = $obraId RETURNING 1)"
)
$semear = ($partes -join ', ') + " SELECT ((inicio_semana - interval '1 second') >= inicio_mes)::int::text || ((inicio_mes - interval '1 second') >= inicio_semana)::int::text FROM marcos"

$calendario = (ExecutarBanco -Argumentos @('consultar', $semear)).resultado
$materialNoMes = $calendario.Substring(0, 1) -eq '1'
$epiNaSemana = $calendario.Substring(1, 1) -eq '1'
Write-Host ("    material dentro do mes: {0} | EPI dentro da semana: {1}" -f $materialNoMes, $epiNaSemana) -ForegroundColor DarkGray

$custoMaterial = [decimal]'593.53'
$custoLocacao = [decimal]'1500.00'
$custoEpi = [decimal]'275.25'
$custoTotal = [decimal]'2368.78'
$custoMes = $custoLocacao + $(if ($materialNoMes) { $custoMaterial } else { [decimal]0 })
$lancamentosMes = 1 + $(if ($materialNoMes) { 2 } else { 0 })
$custoSemana = $custoLocacao + $(if ($epiNaSemana) { $custoEpi } else { [decimal]0 })
$lancamentosSemana = 1 + $(if ($epiNaSemana) { 1 } else { 0 })

$total = Chamar GET '/custos' $c.engenheiro $null 200 'custos da empresa sem filtro'
$resumo = $total.resumo
Conferir ([decimal]$resumo.custo_acumulado -eq $custoTotal) "acumulado soma material e despesa (veio $($resumo.custo_acumulado))"
Conferir ([decimal]$resumo.custo_periodo -eq $custoTotal) "periodo total nao corta nada (veio $($resumo.custo_periodo))"
Conferir ([int]$resumo.lancamentos_periodo -eq 4) "quatro lancamentos no total (veio $($resumo.lancamentos_periodo))"
Conferir ([int]$resumo.itens_sem_preco -eq 1) "conta o item de entrada sem preco (veio $($resumo.itens_sem_preco))"
Conferir ($null -eq $resumo.orcamento_total) 'uma obra sem orcamento zera o total global'
Conferir ($null -eq $resumo.saldo_orcamento) 'sem orcamento global nao ha saldo'
Conferir ($null -eq $resumo.percentual_consumido) 'sem orcamento global nao ha percentual'
Conferir (@($total.obras).Count -eq 2) "a empresa enxerga as duas obras (veio $(@($total.obras).Count))"
Conferir (@($total.totais_por_obra).Count -eq 2) 'totais_por_obra traz as duas obras'

$categorias = @($total.categorias)
Conferir ($categorias.Count -eq 3) "tres categorias com lancamento (veio $($categorias.Count))"
Conferir ([decimal]$categorias[0].valor -eq $custoLocacao) "maior categoria e a locacao (veio $($categorias[0].valor))"
Conferir ([decimal]$categorias[1].valor -eq $custoMaterial) "material agrupa 560.00 + 33.53 (veio $($categorias[1].valor))"
Conferir ($categorias[1].nome -eq 'Cimento e agregados') "categoria do material veio do item de entrada (veio $($categorias[1].nome))"
Conferir ([decimal]$categorias[2].valor -eq $custoEpi) "menor categoria e o EPI (veio $($categorias[2].valor))"

$lancamentos = @($total.lancamentos)
Conferir ($lancamentos.Count -eq 4) "lista traz os quatro lancamentos (veio $($lancamentos.Count))"
Conferir ($lancamentos[0].descricao -eq 'Locacao de betoneira') "o mais recente vem primeiro (veio $($lancamentos[0].descricao))"
Conferir ($total.paginacao.tem_mais -eq $false) 'quatro lancamentos cabem no limite padrao'

$pagina = Chamar GET '/custos?limit=2' $c.engenheiro $null 200 'custos com limite de 2'
Conferir (@($pagina.lancamentos).Count -eq 2) "o limite corta a lista (veio $(@($pagina.lancamentos).Count))"
Conferir ($pagina.paginacao.tem_mais -eq $true) 'limite menor que o total acusa mais paginas'

$alpha = (Chamar GET "/custos?obra_id=$obraId" $c.engenheiro $null 200 'custos da obra com orcamento').resumo
Conferir ([decimal]$alpha.custo_acumulado -eq $custoTotal) "a obra concentra todo o custo (veio $($alpha.custo_acumulado))"
Conferir ([decimal]$alpha.orcamento_total -eq [decimal]'10000.00') "orcamento da obra (veio $($alpha.orcamento_total))"
Conferir ([decimal]$alpha.saldo_orcamento -eq [decimal]'7631.22') "saldo 10000.00 - 2368.78 (veio $($alpha.saldo_orcamento))"
Conferir ([decimal]$alpha.percentual_consumido -eq [decimal]'23.7') "percentual arredondado em uma casa (veio $($alpha.percentual_consumido))"

$semCusto = (Chamar GET "/custos?obra_id=$betaId" $c.engenheiro $null 200 'custos da obra sem orcamento').resumo
Conferir ([decimal]$semCusto.custo_acumulado -eq [decimal]0) "obra sem lancamento soma zero (veio $($semCusto.custo_acumulado))"
Conferir ($null -eq $semCusto.orcamento_total) 'obra sem orcamento devolve nulo'
Conferir ([int]$semCusto.itens_sem_preco -eq 0) "item sem preco e da outra obra (veio $($semCusto.itens_sem_preco))"

$mes = (Chamar GET '/custos?periodo=mes' $c.engenheiro $null 200 'custos do mes corrente').resumo
Conferir ([decimal]$mes.custo_periodo -eq $custoMes) "periodo do mes (esperado $custoMes, veio $($mes.custo_periodo))"
Conferir ([int]$mes.lancamentos_periodo -eq $lancamentosMes) "lancamentos do mes (esperado $lancamentosMes, veio $($mes.lancamentos_periodo))"
Conferir ([decimal]$mes.custo_acumulado -eq $custoTotal) "o acumulado ignora o filtro de periodo (veio $($mes.custo_acumulado))"

$semana = (Chamar GET '/custos?periodo=semana' $c.engenheiro $null 200 'custos da semana corrente').resumo
Conferir ([decimal]$semana.custo_periodo -eq $custoSemana) "periodo da semana (esperado $custoSemana, veio $($semana.custo_periodo))"
Conferir ([int]$semana.lancamentos_periodo -eq $lancamentosSemana) "lancamentos da semana (esperado $lancamentosSemana, veio $($semana.lancamentos_periodo))"

$outra = Chamar GET '/custos' $c.masterB $null 200 'empresa B consulta os proprios custos'
Conferir (@($outra.obras).Count -eq 0) "empresa B nao tem obra (veio $(@($outra.obras).Count))"
Conferir ([decimal]$outra.resumo.custo_acumulado -eq [decimal]0) "empresa B soma zero (veio $($outra.resumo.custo_acumulado))"
Conferir (@($outra.totais_por_obra).Count -eq 0) 'empresa B nao recebe totais de obra alheia'
Conferir (@($outra.lancamentos).Count -eq 0) 'empresa B nao recebe lancamento alheio'
Chamar GET "/custos?obra_id=$obraId" $c.masterB $null 404 'empresa B pedindo obra alheia com orcamento' | Out-Null
Chamar GET "/custos?obra_id=$betaId" $c.masterB $null 404 'empresa B pedindo obra alheia sem orcamento' | Out-Null

FinalizarCaso
