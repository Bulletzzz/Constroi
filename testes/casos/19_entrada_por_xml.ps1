. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Entrada por XML: soma certa, material desconhecido e XML invalido'

$c = NovoCenario -ComObra -ComProduto
$obraId = $c.obra.id
$produtoId = $c.produto.id
$nomeProduto = $c.produto.nome
$campos = @{ obra_id = "$obraId" }
$contagem = "SELECT COUNT(*)::text FROM entrada_estoque WHERE obra_id = $obraId"
$saldo = "SELECT COALESCE(MAX(quantidade), 0)::text FROM estoque WHERE obra_id = $obraId AND produto_id = $produtoId"
$registros = "SELECT COUNT(*)::text FROM log_sistema WHERE acao LIKE 'ENTRADA_NFE %obra=$obraId %'"

VerificarBanco $contagem '0' 'cenario comeca sem entradas'

$nota = MontarNfe -Chave ('1' * 44) -Nome $nomeProduto -Quantidade '1.2500'
EnviarArquivo POST '/entradas/xml' $c.engenheiro $nota $campos 201 'importa NF-e com material do catalogo' | Out-Null
VerificarBanco $saldo '1.25' 'entrada soma exatamente a quantidade da nota'
VerificarBanco $contagem '1' 'uma entrada gravada'
VerificarBanco $registros '1' 'importacao deixa exatamente um registro no log'

EnviarArquivo POST '/entradas/xml' $c.engenheiro $nota $campos 409 'mesma chave nao importa duas vezes' | Out-Null
VerificarBanco $saldo '1.25' 'reenvio da mesma nota nao soma de novo'
VerificarBanco $contagem '1' 'reenvio nao cria segunda entrada'

$desconhecido = MontarNfe -Chave ('2' * 44) -Nome 'Material Que Nao Existe' -Codigo 'XXX-99'
$pendencia = EnviarArquivo POST '/entradas/xml' $c.engenheiro $desconhecido $campos 422 'material fora do catalogo recusa a nota'
Conferir ($pendencia.materiais_pendentes.Count -eq 1) "a resposta aponta o material pendente (veio $($pendencia.materiais_pendentes.Count))"
Conferir ($pendencia.materiais_pendentes[0].motivo -eq 'nao_encontrado') "motivo e nao_encontrado (veio $($pendencia.materiais_pendentes[0].motivo))"
VerificarBanco $contagem '1' 'nota recusada nao grava entrada'
VerificarBanco $saldo '1.25' 'nota recusada nao mexe no saldo'

$unidadeErrada = MontarNfe -Chave ('3' * 44) -Nome $nomeProduto -Unidade 'tonelada'
$divergente = EnviarArquivo POST '/entradas/xml' $c.engenheiro $unidadeErrada $campos 422 'unidade diferente do cadastro recusa a nota'
Conferir ($divergente.materiais_pendentes[0].motivo -eq 'unidade_diferente') "motivo e unidade_diferente (veio $($divergente.materiais_pendentes[0].motivo))"
VerificarBanco $contagem '1' 'unidade divergente nao grava entrada'

EnviarArquivo POST '/entradas/xml' $c.engenheiro '<nfeProc><NFe>' $campos 400 'XML malformado devolve erro claro' | Out-Null
EnviarArquivo POST '/entradas/xml' $c.engenheiro '<?xml version="1.0"?><outro/>' $campos 400 'XML fora do namespace da NF-e recusa' | Out-Null
EnviarArquivo POST '/entradas/xml' $c.engenheiro $nota @{ obra_id = 'abc' } 400 'obra_id invalido recusa' | Out-Null
EnviarArquivo POST '/entradas/xml' $c.pedreiro $nota $campos 403 'pedreiro nao importa nota' | Out-Null
EnviarArquivo POST '/entradas/xml' $null $nota $campos 401 'sem token nao importa nota' | Out-Null
VerificarBanco $contagem '1' 'nenhuma recusa deixou entrada no banco'
VerificarBanco $registros '1' 'nenhuma recusa deixou registro no log'

FinalizarCaso
