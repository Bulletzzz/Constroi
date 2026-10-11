. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Autenticacao e hierarquia de permissao'

$c = NovoCenario -ComUsuarios
$marca = $c.marca

Chamar GET '/eu' $null $null 401 'sem token' | Out-Null
Chamar GET '/eu' 'token-adulterado' $null 401 'token invalido' | Out-Null
Chamar GET '/eu' 'Bearer' $null 401 'token vazio' | Out-Null

Chamar POST '/login' $null @{ email = "master.$marca@teste.com"; senha = 'errada' } 401 'senha errada' | Out-Null
Chamar POST '/login' $null @{ email = "ninguem.$marca@teste.com"; senha = $global:SenhaPadrao } 401 'email inexistente' | Out-Null
Chamar POST '/login' $null @{ email = "master.$marca@teste.com" } 400 'corpo incompleto' | Out-Null
Chamar POST '/login' $null @{} 400 'corpo vazio' | Out-Null

Chamar GET '/produtos' $c.pedreiro $null 403 'pedreiro nao le produtos' | Out-Null
Chamar GET '/usuarios' $c.engenheiro $null 403 'engenheiro nao le usuarios' | Out-Null
Chamar GET '/produtos' $c.engenheiro $null 200 'engenheiro le produtos' | Out-Null
Chamar GET '/usuarios' $c.master $null 200 'master le usuarios' | Out-Null
Chamar GET '/produtos' $c.master $null 200 'master alcanca nivel de engenheiro' | Out-Null

$eu = Chamar GET '/eu' $c.master $null 200 'GET /eu nao vaza senha'
Conferir ($null -eq $eu.senha -and $null -eq $eu.senha_hash) 'resposta de /eu nao traz hash de senha'

FinalizarCaso
