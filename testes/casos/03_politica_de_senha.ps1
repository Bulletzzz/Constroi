. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Politica de senha e perfis aceitos'

$c = NovoCenario
$marca = $c.marca

Chamar POST '/usuarios' $c.master @{
    usuario = @{ nome = 'X'; email = "curta.$marca@teste.com"; senha = 'Ab#3xyz'; tipo = 'pedreiro' }
} 400 'senha com 7 caracteres' | Out-Null

Chamar POST '/usuarios' $c.master @{
    usuario = @{ nome = 'X'; email = "comum.$marca@teste.com"; senha = '12345678'; tipo = 'pedreiro' }
} 400 'senha comum 12345678' | Out-Null

Chamar POST '/usuarios' $c.master @{
    usuario = @{ nome = 'X'; email = "maiuscula.$marca@teste.com"; senha = 'SeNhA123'; tipo = 'pedreiro' }
} 400 'senha comum com outra caixa' | Out-Null

Chamar POST '/usuarios' $c.master @{
    usuario = @{ nome = 'X'; email = "oito.$marca@teste.com"; senha = 'Abcdefgh'; tipo = 'pedreiro' }
} 201 'oito caracteres fora da lista e aceita' | Out-Null

Chamar POST '/usuarios' $c.master @{
    usuario = @{ nome = 'X'; email = "tipo.$marca@teste.com"; senha = $global:SenhaPadrao; tipo = 'chefao' }
} 400 'tipo de usuario invalido' | Out-Null

Chamar POST '/usuarios' $c.master @{
    usuario = @{ nome = 'X'; email = "semarroba.$marca"; senha = $global:SenhaPadrao; tipo = 'pedreiro' }
} 400 'email sem formato valido' | Out-Null

Chamar POST '/usuarios' $c.master @{
    nome = 'X'; email = "semenvelope.$marca@teste.com"; senha = $global:SenhaPadrao; tipo = 'pedreiro'
} 400 'POST /usuarios sem envelope' | Out-Null

VerificarBanco "SELECT COUNT(*)::text FROM usuario WHERE email LIKE '%.$marca@teste.com' AND email NOT LIKE 'master.%' AND email NOT LIKE 'oito.%'" '0' `
    'nenhuma senha recusada gerou usuario'

FinalizarCaso
