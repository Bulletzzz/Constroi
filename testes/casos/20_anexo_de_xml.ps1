. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Anexo de XML: nao soma estoque e nao aceita duas vezes'

$c = NovoCenario -ComObra -ComProduto
$obraId = $c.obra.id
$produtoId = $c.produto.id
$engenheiroId = $c.engenheiroUsuario.id

ExecutarBanco -Argumentos @('estoque', "$obraId", "$produtoId", '10') | Out-Null
$saldo = "SELECT quantidade::text FROM estoque WHERE obra_id = $obraId AND produto_id = $produtoId"
VerificarBanco $saldo '10.00' 'cenario comeca com saldo conhecido'

$entradaId = (ExecutarBanco -Argumentos @('consultar',
    "INSERT INTO entrada_estoque (usuario_id, obra_id, justificativa) VALUES ($engenheiroId, $obraId, 'manual') RETURNING id")).resultado
Conferir ($entradaId -match '^\d+$') "entrada sem XML criada para o anexo (veio $entradaId)"

$nota = MontarNfe -Chave ('4' * 44) -Nome $c.produto.nome -Quantidade '7.0000'
$rota = "/entradas/$entradaId/xml"
$registros = "SELECT COUNT(*)::text FROM log_sistema WHERE usuario_id = $engenheiroId AND acao LIKE 'ANEXO_NFE %'"

$anexo = EnviarArquivo PATCH $rota $c.engenheiro $nota $null 200 'anexa o XML na entrada'
Conferir ($anexo.xml_anexado -eq $true) 'resposta confirma o anexo'
VerificarBanco $saldo '10.00' 'anexar XML nao soma quantidade nenhuma'
VerificarBanco $registros '1' 'anexo deixa exatamente um registro no log'

$outraNota = MontarNfe -Chave ('5' * 44) -Nome $c.produto.nome
$ocupada = EnviarArquivo PATCH $rota $c.engenheiro $outraNota $null 409 'entrada que ja tem XML nao aceita outro'
Conferir ($ocupada.erro -match 'ja possui XML') "a recusa diz que a entrada ja tem XML (veio '$($ocupada.erro)')"
VerificarBanco $saldo '10.00' 'segunda tentativa nao soma duas vezes'

$segunda = (ExecutarBanco -Argumentos @('consultar',
    "INSERT INTO entrada_estoque (usuario_id, obra_id, justificativa) VALUES ($engenheiroId, $obraId, 'manual') RETURNING id")).resultado
$repetida = EnviarArquivo PATCH "/entradas/$segunda/xml" $c.engenheiro $nota $null 409 'mesma chave em outra entrada da mesma empresa recusa'
Conferir ($repetida.erro -match 'ja foi registrada') "a recusa diz que a chave ja foi usada (veio '$($repetida.erro)')"

EnviarArquivo PATCH "/entradas/$segunda/xml" $c.pedreiro $outraNota $null 403 'pedreiro nao anexa' | Out-Null
EnviarArquivo PATCH '/entradas/999999/xml' $c.engenheiro $outraNota $null 404 'entrada inexistente' | Out-Null
EnviarArquivo PATCH '/entradas/abc/xml' $c.engenheiro $outraNota $null 400 'id invalido' | Out-Null
VerificarBanco $saldo '10.00' 'nenhuma recusa mexeu no saldo'
VerificarBanco $registros '1' 'recusas nao deixaram registro no log'

FinalizarCaso
