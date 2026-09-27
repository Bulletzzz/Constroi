param(
    [string]$BaseUrl = $(if ($env:CONSTROI_API_URL) { $env:CONSTROI_API_URL } else { 'http://localhost:8080' }),
    [switch]$Detalhado
)

$ErrorActionPreference = 'Stop'

$senhaPadrao = 'Senha#Forte123'
$marca = [Guid]::NewGuid().ToString('N').Substring(0, 6)
$falhas = @()
$total = 0

function Chamar {
    param(
        [string]$Metodo,
        [string]$Rota,
        [string]$Token,
        $Corpo,
        [int]$Esperado,
        [string]$Rotulo
    )

    $script:total++
    $parametros = @{
        Uri             = "$BaseUrl$Rota"
        Method          = $Metodo
        UseBasicParsing = $true
    }
    if ($Token) { $parametros.Headers = @{ Authorization = "Bearer $Token" } }
    if ($null -ne $Corpo) {
        $parametros.Body = ($Corpo | ConvertTo-Json -Depth 6)
        $parametros.ContentType = 'application/json; charset=utf-8'
    }

    $codigo = 0
    $conteudo = ''
    try {
        $resposta = Invoke-WebRequest @parametros -ErrorAction Stop
        $codigo = $resposta.StatusCode
        $conteudo = $resposta.Content
    }
    catch {
        $codigo = $_.Exception.Response.StatusCode.value__
        $conteudo = $_.ErrorDetails.Message
    }

    if ($codigo -eq $Esperado) {
        Write-Host ("  ok   {0,-46} {1}" -f $Rotulo, $codigo) -ForegroundColor DarkGray
    }
    else {
        Write-Host ("  FALHA {0,-46} esperado {1}, veio {2}" -f $Rotulo, $Esperado, $codigo) -ForegroundColor Red
        $script:falhas += "$Rotulo (esperado $Esperado, veio $codigo)"
    }
    if ($Detalhado -and $conteudo) {
        Write-Host ("       {0}" -f ($conteudo -replace '\s+', ' ')) -ForegroundColor DarkGray
    }

    if ($conteudo -and $codigo -lt 400) {
        try { return $conteudo | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

function Entrar {
    param([string]$Email)
    $r = Invoke-RestMethod -Uri "$BaseUrl/login" -Method Post `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ email = $Email; senha = $senhaPadrao } | ConvertTo-Json)
    return $r.token
}

function Secao {
    param([string]$Titulo)
    Write-Host ''
    Write-Host $Titulo -ForegroundColor Cyan
}

Secao 'SAUDE'
Chamar GET '/health' $null $null 200 'GET /health' | Out-Null

Secao 'EMPRESA, LOGIN E PERFIS'
Chamar POST '/empresas' $null @{
    empresa = @{ nome = "Construtora A $marca"; cnpj = "11.111.111/$marca" }
    usuario = @{ nome = "Master $marca"; email = "master.$marca@teste.com"; senha = $senhaPadrao }
} 201 'POST /empresas' | Out-Null

$master = Entrar "master.$marca@teste.com"
Chamar GET '/eu' $master $null 200 'GET /eu' | Out-Null

Chamar POST '/usuarios' $master @{
    usuario = @{ nome = "Eng $marca"; email = "eng.$marca@teste.com"; senha = $senhaPadrao; tipo = 'engenheiro' }
} 201 'POST /usuarios engenheiro' | Out-Null

$pedreiro = Chamar POST '/usuarios' $master @{
    usuario = @{ nome = "Ped $marca"; email = "ped.$marca@teste.com"; senha = $senhaPadrao; tipo = 'pedreiro' }
} 201 'POST /usuarios pedreiro'

$engenheiro = Entrar "eng.$marca@teste.com"
$tokenPedreiro = Entrar "ped.$marca@teste.com"

Secao 'POLITICA DE SENHA'
Chamar POST '/usuarios' $master @{
    usuario = @{ nome = 'X'; email = "curta.$marca@teste.com"; senha = 'Ab#3xyz'; tipo = 'pedreiro' }
} 400 'senha com 7 caracteres' | Out-Null
Chamar POST '/usuarios' $master @{
    usuario = @{ nome = 'X'; email = "comum.$marca@teste.com"; senha = '12345678'; tipo = 'pedreiro' }
} 400 'senha comum 12345678' | Out-Null
Chamar POST '/usuarios' $master @{
    usuario = @{ nome = 'X'; email = "tipo.$marca@teste.com"; senha = $senhaPadrao; tipo = 'chefao' }
} 400 'tipo de usuario invalido' | Out-Null

Secao 'OBRAS'
$obra = Chamar POST '/obras' $engenheiro @{
    obra = @{ nome = "Obra Alpha $marca"; endereco = 'Rua de teste, 123'; status = 'planejamento'; orcamento_total = 250000.5 }
} 201 'POST /obras com orcamento'

Chamar GET '/obras' $engenheiro $null 200 'GET /obras engenheiro' | Out-Null
Chamar GET "/obras/$($obra.id)" $engenheiro $null 200 'GET /obras/{id}' | Out-Null
Chamar PATCH "/obras/$($obra.id)" $engenheiro @{ obra = @{ status = 'ativa' } } 200 'PATCH status' | Out-Null
Chamar PATCH "/obras/$($obra.id)" $engenheiro @{ obra = @{ orcamento_total = '310000,75' } } 200 'PATCH orcamento com virgula' | Out-Null
Chamar PATCH "/obras/$($obra.id)" $engenheiro @{ obra = @{ orcamento_total = $null } } 200 'PATCH orcamento nulo limpa' | Out-Null
Chamar PATCH "/obras/$($obra.id)" $engenheiro @{ obra = @{ orcamento_total = -5 } } 400 'PATCH orcamento negativo' | Out-Null
Chamar POST '/obras' $engenheiro @{ obra = @{ nome = 'X'; endereco = 'Y'; status = 'andando' } } 400 'POST status invalido' | Out-Null
Chamar POST '/obras' $engenheiro @{ nome = 'X'; endereco = 'Y'; status = 'ativa' } 400 'POST /obras sem envelope' | Out-Null
Chamar GET '/obras/999999' $engenheiro $null 404 'GET obra inexistente' | Out-Null
Chamar GET '/obras/abc' $engenheiro $null 400 'GET obra com id invalido' | Out-Null
Chamar DELETE "/obras/$($obra.id)" $engenheiro $null 405 'DELETE /obras/{id}' | Out-Null

Secao 'OBRAS VISTAS PELO PEDREIRO'
Chamar GET '/obras' $tokenPedreiro $null 200 'GET /obras pedreiro sem vinculo' | Out-Null
Chamar GET "/obras/$($obra.id)" $tokenPedreiro $null 404 'GET obra nao vinculada' | Out-Null
Chamar POST '/obras' $tokenPedreiro @{ obra = @{ nome = 'Furtiva'; endereco = 'Y'; status = 'ativa' } } 403 'POST /obras pedreiro' | Out-Null
Chamar PATCH "/obras/$($obra.id)" $tokenPedreiro @{ obra = @{ status = 'concluida' } } 403 'PATCH /obras pedreiro' | Out-Null

Secao 'PRODUTOS'
$produto = Chamar POST '/produtos' $engenheiro @{ produto = @{ nome = "Cimento $marca"; unidade = 'saco' } } 201 'POST /produtos'
Chamar GET '/produtos' $engenheiro $null 200 'GET /produtos' | Out-Null
Chamar GET "/produtos/$($produto.id)" $engenheiro $null 200 'GET /produtos/{id}' | Out-Null
Chamar PATCH "/produtos/$($produto.id)" $engenheiro @{ produto = @{ unidade = 'un' } } 200 'PATCH /produtos/{id}' | Out-Null
Chamar POST '/produtos' $engenheiro @{ produto = @{ nome = "Cimento $marca"; unidade = 'saco' } } 409 'POST /produtos nome repetido' | Out-Null
Chamar POST '/produtos' $engenheiro @{ produto = @{ nome = 'Y'; unidade = 'caixinha' } } 400 'POST /produtos unidade invalida' | Out-Null
Chamar POST '/produtos' $engenheiro @{ nome = 'Y'; unidade = 'un' } 400 'POST /produtos sem envelope' | Out-Null

Secao 'EQUIPAMENTOS'
$equipamento = Chamar POST '/equipamentos' $engenheiro @{
    equipamento = @{ nome = "Betoneira $marca"; patrimonio = "BT-$marca"; status = 'disponivel' }
} 201 'POST /equipamentos'
Chamar GET '/equipamentos' $engenheiro $null 200 'GET /equipamentos' | Out-Null
Chamar GET "/equipamentos/$($equipamento.id)" $engenheiro $null 200 'GET /equipamentos/{id}' | Out-Null
Chamar PATCH "/equipamentos/$($equipamento.id)" $engenheiro @{ equipamento = @{ status = 'manutencao' } } 200 'PATCH /equipamentos/{id}' | Out-Null
Chamar POST '/equipamentos' $engenheiro @{ equipamento = @{ nome = 'Y'; patrimonio = 'Z'; status = 'quebradoo' } } 400 'POST status invalido' | Out-Null

Secao 'USUARIOS'
Chamar GET '/usuarios' $master $null 200 'GET /usuarios master' | Out-Null
Chamar GET "/usuarios/$($pedreiro.id)" $master $null 200 'GET /usuarios/{id}' | Out-Null
Chamar PATCH "/usuarios/$($pedreiro.id)" $master @{ usuario = @{ nome = "Ped $marca renomeado" } } 200 'PATCH /usuarios/{id}' | Out-Null
Chamar PATCH "/usuarios/$($pedreiro.id)/inativar" $master $null 200 'PATCH inativar' | Out-Null
Chamar GET '/usuarios' $engenheiro $null 403 'GET /usuarios engenheiro' | Out-Null

Secao 'AUTENTICACAO E PERMISSAO'
Chamar GET '/eu' $null $null 401 'sem token' | Out-Null
Chamar GET '/eu' 'token-adulterado' $null 401 'token invalido' | Out-Null
Chamar POST '/login' $null @{ email = "master.$marca@teste.com"; senha = 'errada' } 401 'senha errada' | Out-Null
Chamar POST '/login' $null @{ email = "ninguem.$marca@teste.com"; senha = $senhaPadrao } 401 'email inexistente' | Out-Null
Chamar POST '/login' $null @{ email = "master.$marca@teste.com" } 400 'corpo incompleto' | Out-Null
Chamar GET '/produtos' $tokenPedreiro $null 403 'produtos como pedreiro' | Out-Null

Secao 'ISOLAMENTO ENTRE EMPRESAS'
Chamar POST '/empresas' $null @{
    empresa = @{ nome = "Construtora B $marca"; cnpj = "22.222.222/$marca" }
    usuario = @{ nome = "Master B $marca"; email = "masterb.$marca@teste.com"; senha = $senhaPadrao }
} 201 'POST /empresas segunda empresa' | Out-Null
$masterB = Entrar "masterb.$marca@teste.com"
Chamar GET "/obras/$($obra.id)" $masterB $null 404 'obra da empresa A com token da B' | Out-Null
Chamar GET "/produtos/$($produto.id)" $masterB $null 404 'produto da empresa A com token da B' | Out-Null
Chamar GET "/usuarios/$($pedreiro.id)" $masterB $null 404 'usuario da empresa A com token da B' | Out-Null

Write-Host ''
if ($falhas.Count -eq 0) {
    Write-Host "$total chamadas, todas com o codigo esperado." -ForegroundColor Green
}
else {
    Write-Host "$total chamadas, $($falhas.Count) fora do esperado:" -ForegroundColor Red
    $falhas | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

Write-Host ''
Write-Host "Dados criados com a marca $marca. Para limpar:" -ForegroundColor DarkGray
Write-Host "  DELETE FROM usuario_obra WHERE empresa_id IN (SELECT id FROM empresa WHERE nome LIKE '%$marca');" -ForegroundColor DarkGray
Write-Host "  DELETE FROM obra WHERE nome LIKE '%$marca';" -ForegroundColor DarkGray
Write-Host "  DELETE FROM produto WHERE nome LIKE '%$marca';" -ForegroundColor DarkGray
Write-Host "  DELETE FROM equipamento WHERE nome LIKE '%$marca';" -ForegroundColor DarkGray
Write-Host "  DELETE FROM usuario WHERE email LIKE '%$marca@teste.com';" -ForegroundColor DarkGray
Write-Host "  DELETE FROM empresa WHERE nome LIKE '%$marca';" -ForegroundColor DarkGray

if ($falhas.Count -gt 0) { exit 1 }
