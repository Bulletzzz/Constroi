. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Usuarios: leitura, edicao e inativacao'

$c = NovoCenario -ComUsuarios
$marca = $c.marca
$pedreiroId = $c.pedreiroUsuario.id

Chamar GET '/usuarios' $c.master $null 200 'GET /usuarios master' | Out-Null
Chamar GET "/usuarios/$pedreiroId" $c.master $null 200 'GET /usuarios/{id}' | Out-Null
Chamar PATCH "/usuarios/$pedreiroId" $c.master @{ usuario = @{ nome = "Ped $marca renomeado" } } 200 'PATCH nome' | Out-Null
Chamar GET '/usuarios/999999' $c.master $null 404 'GET usuario inexistente' | Out-Null
Chamar GET '/usuarios/abc' $c.master $null 400 'GET usuario com id invalido' | Out-Null

Chamar GET '/usuarios' $c.engenheiro $null 403 'GET /usuarios engenheiro' | Out-Null
Chamar GET '/usuarios' $c.pedreiro $null 403 'GET /usuarios pedreiro' | Out-Null
Chamar PATCH "/usuarios/$pedreiroId" $c.engenheiro @{ usuario = @{ nome = 'Furtivo' } } 403 'PATCH usuario por engenheiro' | Out-Null

Chamar PATCH "/usuarios/$pedreiroId/inativar" $c.master $null 200 'PATCH inativar' | Out-Null
VerificarBanco "SELECT ativo::text FROM usuario WHERE id = $pedreiroId" 'false' 'usuario ficou inativo no banco'

$codigoLogin = CodigoDoLogin "ped.$marca@teste.com"
Conferir ($codigoLogin -eq 403) "usuario inativo nao consegue logar (veio $codigoLogin)"

$comSenhaErrada = CodigoDoLogin "ped.$marca@teste.com" 'OutraSenha#9'
$inexistente = CodigoDoLogin "naoexiste.$marca@teste.com" 'OutraSenha#9'
$ativoSenhaErrada = CodigoDoLogin "master.$marca@teste.com" 'OutraSenha#9'

Conferir ($comSenhaErrada -eq 401) "inativo com senha errada responde 401 generico (veio $comSenhaErrada)"
Conferir ($inexistente -eq 401) "email inexistente responde 401 (veio $inexistente)"
Conferir ($ativoSenhaErrada -eq 401) "ativo com senha errada responde 401 (veio $ativoSenhaErrada)"
Conferir ($comSenhaErrada -eq $inexistente -and $ativoSenhaErrada -eq $inexistente) `
    "sem senha valida, contas ativa, inativa e inexistente respondem igual"

$engenheiroId = $c.engenheiroUsuario.id
$emailBloqueado = "eng.$marca@teste.com"
for ($tentativa = 1; $tentativa -le 5; $tentativa++) {
    $codigo = CodigoDoLogin $emailBloqueado 'OutraSenha#9'
    Conferir ($codigo -eq 401) "senha errada na tentativa $tentativa responde 401 (veio $codigo)"
}
VerificarBanco "SELECT (bloqueado_ate > CURRENT_TIMESTAMP)::text FROM usuario WHERE id = $engenheiroId" 'true' `
    'cinco falhas mantem a protecao de bloqueio'

$bloqueadoAte = (ExecutarBanco -Argumentos @('consultar', "SELECT bloqueado_ate::text FROM usuario WHERE id = $engenheiroId")).resultado
$sessoesAntes = (ExecutarBanco -Argumentos @('consultar', "SELECT COUNT(*)::text FROM sessao_usuario WHERE usuario_id = $engenheiroId")).resultado
$bloqueadoSenhaErrada = CodigoDoLogin $emailBloqueado 'OutraSenha#9'
$bloqueadoSenhaCerta = CodigoDoLogin $emailBloqueado
Conferir ($bloqueadoSenhaErrada -eq 401 -and $bloqueadoSenhaErrada -eq $inexistente) `
    "conta bloqueada com senha errada nao revela cadastro (veio $bloqueadoSenhaErrada)"
Conferir ($bloqueadoSenhaCerta -eq 429) "conta bloqueada com senha certa continua impedida (veio $bloqueadoSenhaCerta)"
VerificarBanco "SELECT bloqueado_ate::text FROM usuario WHERE id = $engenheiroId" $bloqueadoAte `
    'tentativas durante o bloqueio nao limpam nem prolongam o prazo'
VerificarBanco "SELECT COUNT(*)::text FROM sessao_usuario WHERE usuario_id = $engenheiroId" $sessoesAntes `
    'tentativas bloqueadas nao criam sessoes'

ExecutarBanco -Argumentos @('consultar', "UPDATE usuario SET bloqueado_ate = CURRENT_TIMESTAMP - INTERVAL '1 minute', tentativas_login = 4 WHERE id = $engenheiroId RETURNING id::text") | Out-Null
$depoisDoPrazo = CodigoDoLogin $emailBloqueado 'OutraSenha#9'
Conferir ($depoisDoPrazo -eq 401) "senha errada apos expirar bloqueio responde 401 (veio $depoisDoPrazo)"
VerificarBanco "SELECT (tentativas_login = 1 AND bloqueado_ate IS NULL)::text FROM usuario WHERE id = $engenheiroId" 'true' `
    'bloqueio expirado reinicia a contagem na primeira falha'
$loginValido = CodigoDoLogin $emailBloqueado
Conferir ($loginValido -eq 200) "login valido apos expirar bloqueio funciona (veio $loginValido)"
VerificarBanco "SELECT (tentativas_login = 0 AND bloqueado_ate IS NULL)::text FROM usuario WHERE id = $engenheiroId" 'true' `
    'login valido limpa contagem de falhas'

VerificarBanco "SELECT nome FROM usuario WHERE id = $pedreiroId" "Ped $marca renomeado" 'nome renomeado persistiu'

FinalizarCaso
