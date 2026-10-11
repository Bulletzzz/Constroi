. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Equipe da obra: vinculo, duplicata e encerramento'

$c = NovoCenario -ComObra
$rota = $c.rotaEquipe
$pedreiroId = $c.pedreiroUsuario.id

Chamar GET $rota $c.pedreiro $null 404 'GET equipe pedreiro sem vinculo' | Out-Null
$inicial = Chamar GET $rota $c.engenheiro $null 200 'GET equipe engenheiro'
Conferir ($null -ne $inicial.equipe) 'resposta traz a propriedade equipe'
Chamar GET $rota $c.master $null 200 'GET equipe master' | Out-Null

$vinculo = Chamar POST $rota $c.engenheiro @{ equipe = @{ usuario_id = $pedreiroId } } 201 'POST equipe vinculo valido'
Conferir ($vinculo.usuario_id -eq $pedreiroId -and $vinculo.obra_id -eq $c.obra.id) 'vinculo retornou usuario e obra certos'

Chamar POST $rota $c.engenheiro @{ equipe = @{ usuario_id = $pedreiroId } } 409 'POST equipe duplicado' | Out-Null
Chamar POST $rota $c.engenheiro @{ equipe = @{ usuario_id = 999999999 } } 404 'POST equipe usuario inexistente' | Out-Null
Chamar POST $rota $c.engenheiro @{ usuario_id = $pedreiroId } 400 'POST equipe sem envelope' | Out-Null

$ativa = Chamar GET $rota $c.pedreiro $null 200 'GET equipe com pedreiro vinculado'
Conferir ([bool]($ativa.equipe | Where-Object { $_.usuario_id -eq $pedreiroId })) 'pedreiro encontra o proprio vinculo'

Chamar POST $rota $c.pedreiro @{ equipe = @{ usuario_id = $pedreiroId } } 403 'POST equipe negado ao pedreiro' | Out-Null
Chamar DELETE "$rota/$pedreiroId" $c.pedreiro $null 403 'DELETE equipe negado ao pedreiro' | Out-Null

$encerrado = Chamar DELETE "$rota/$pedreiroId" $c.engenheiro $null 200 'DELETE equipe encerra vinculo'
Conferir ($null -ne $encerrado.data_fim) 'encerramento retornou data_fim'

VerificarBanco "SELECT COUNT(*)::text FROM usuario_obra WHERE id = $($vinculo.id) AND data_fim IS NOT NULL" '1' `
    'vinculo encerrado permanece no banco como historico'

Chamar GET $rota $c.pedreiro $null 404 'GET equipe pedreiro com vinculo encerrado' | Out-Null
$final = Chamar GET $rota $c.engenheiro $null 200 'GET equipe sem encerrados'
Conferir (-not ($final.equipe | Where-Object { $_.usuario_id -eq $pedreiroId })) 'vinculo encerrado sai da equipe ativa'

Chamar POST $rota $c.engenheiro @{ equipe = @{ usuario_id = $pedreiroId } } 201 'revincular depois de encerrar' | Out-Null

FinalizarCaso
