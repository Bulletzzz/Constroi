. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Cadastro de empresa, login e perfis'

$marca = NovaMarca
$global:Cenarios += $marca

$criada = Chamar POST '/empresas' $null @{
    empresa = @{ nome = "Construtora A $marca"; cnpj = "11.111.111/$marca" }
    usuario = @{ nome = "Master $marca"; email = "master.$marca@teste.com"; senha = $global:SenhaPadrao }
} 201 'POST /empresas'
Conferir ($null -ne $criada) 'POST /empresas retornou corpo'

Chamar POST '/empresas' $null @{
    empresa = @{ nome = "Construtora A $marca" }
} 400 'POST /empresas sem usuario' | Out-Null

$master = Entrar "master.$marca@teste.com"
$eu = Chamar GET '/eu' $master $null 200 'GET /eu com token de master'
Conferir ($eu.tipo -eq 'master') "primeiro usuario nasce master (veio '$($eu.tipo)')"

$engenheiro = Chamar POST '/usuarios' $master @{
    usuario = @{ nome = "Eng $marca"; email = "eng.$marca@teste.com"; senha = $global:SenhaPadrao; tipo = 'engenheiro' }
} 201 'POST /usuarios engenheiro'
$pedreiro = Chamar POST '/usuarios' $master @{
    usuario = @{ nome = "Ped $marca"; email = "ped.$marca@teste.com"; senha = $global:SenhaPadrao; tipo = 'pedreiro' }
} 201 'POST /usuarios pedreiro'

$tokenEngenheiro = Entrar "eng.$marca@teste.com"
$tokenPedreiro = Entrar "ped.$marca@teste.com"

$euEngenheiro = Chamar GET '/eu' $tokenEngenheiro $null 200 'GET /eu com token de engenheiro'
$euPedreiro = Chamar GET '/eu' $tokenPedreiro $null 200 'GET /eu com token de pedreiro'
Conferir ($euEngenheiro.tipo -eq 'engenheiro') 'perfil do engenheiro veio correto'
Conferir ($euPedreiro.tipo -eq 'pedreiro') 'perfil do pedreiro veio correto'
Conferir ($euEngenheiro.empresa_id -eq $eu.empresa_id) 'usuarios criados ficam na mesma empresa'

Chamar POST '/usuarios' $master @{
    usuario = @{ nome = "Repetido $marca"; email = "eng.$marca@teste.com"; senha = $global:SenhaPadrao; tipo = 'pedreiro' }
} 409 'POST /usuarios email repetido' | Out-Null

Conferir ($null -ne $engenheiro.id -and $null -ne $pedreiro.id) 'usuarios criados receberam id'

FinalizarCaso
