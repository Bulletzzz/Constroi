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

Conferir ($comSenhaErrada -eq 403) "inativo responde 403 mesmo com senha errada (veio $comSenhaErrada)"
Conferir ($inexistente -eq 401) "email inexistente responde 401 (veio $inexistente)"
Conferir ($ativoSenhaErrada -eq 401) "ativo com senha errada responde 401 (veio $ativoSenhaErrada)"
Conferir ($comSenhaErrada -ne $inexistente) `
    "conta inativa e distinguivel de inexistente sem senha valida ($comSenhaErrada vs $inexistente)"

VerificarBanco "SELECT nome FROM usuario WHERE id = $pedreiroId" "Ped $marca renomeado" 'nome renomeado persistiu'

FinalizarCaso
