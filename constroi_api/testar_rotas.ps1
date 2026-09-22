$ErrorActionPreference = 'Continue'
$base = 'http://localhost:8080'
$senhaPadrao = 'Senha#Forte123'
$marca = Get-Random -Minimum 1000 -Maximum 9999

function Chamar {
    param(
        [string]$Metodo,
        [string]$Rota,
        [string]$Token,
        $Corpo,
        [string]$Rotulo
    )
    $parametros = @{
        Uri             = "$base$Rota"
        Method          = $Metodo
        UseBasicParsing = $true
    }
    if ($Token) { $parametros.Headers = @{ Authorization = "Bearer $Token" } }
    if ($Corpo) {
        $parametros.Body = ($Corpo | ConvertTo-Json -Depth 5)
        $parametros.ContentType = 'application/json'
    }
    try {
        $resposta = Invoke-WebRequest @parametros
        Write-Host ("{0,-42} {1}" -f $Rotulo, $resposta.StatusCode) -ForegroundColor Green
        return ($resposta.Content | ConvertFrom-Json)
    }
    catch {
        $codigo = $_.Exception.Response.StatusCode.value__
        Write-Host ("{0,-42} {1}  {2}" -f $Rotulo, $codigo, $_.ErrorDetails.Message) -ForegroundColor Yellow
        return $null
    }
}

function Entrar {
    param([string]$Email)
    $r = Chamar POST '/login' $null @{ email = $Email; senha = $senhaPadrao } "login $Email"
    return $r.token
}

Write-Host "`n=== SAUDE ===" -ForegroundColor Cyan
Chamar GET '/health' $null $null 'GET /health' | Out-Null

Write-Host "`n=== EMPRESA + MASTER ===" -ForegroundColor Cyan
$novaEmpresa = Chamar POST '/empresas' $null @{
    empresa = @{ nome = "Construtora Teste $marca"; cnpj = "12.345.678/000$marca" }
    usuario = @{ nome = "Master $marca"; email = "master$marca@teste.com"; senha = $senhaPadrao }
} 'POST /empresas'

Write-Host "`n=== LOGIN ===" -ForegroundColor Cyan
$master = Entrar "master$marca@teste.com"
if (-not $master) { Write-Host 'Sem token de master, parando.' -ForegroundColor Red; return }

Chamar GET '/eu' $master $null 'GET /eu' | Out-Null

Write-Host "`n=== USUARIOS  (exige master) ===" -ForegroundColor Cyan
Chamar GET '/usuarios' $master $null 'GET /usuarios' | Out-Null

$engenheiro = Chamar POST '/usuarios' $master @{
    usuario = @{ nome = "Engenheiro $marca"; email = "eng$marca@teste.com"; senha = $senhaPadrao; tipo = 'engenheiro' }
} 'POST /usuarios (engenheiro)'

$pedreiro = Chamar POST '/usuarios' $master @{
    usuario = @{ nome = "Pedreiro $marca"; email = "ped$marca@teste.com"; senha = $senhaPadrao; tipo = 'pedreiro' }
} 'POST /usuarios (pedreiro)'

if ($engenheiro) {
    Chamar GET "/usuarios/$($engenheiro.id)" $master $null "GET /usuarios/$($engenheiro.id)" | Out-Null
    Chamar PATCH "/usuarios/$($engenheiro.id)" $master @{
        usuario = @{ nome = "Engenheiro $marca renomeado" }
    } "PATCH /usuarios/$($engenheiro.id)" | Out-Null
}

Write-Host "`n=== PRODUTOS  (exige engenheiro) ===" -ForegroundColor Cyan
$tokenEng = Entrar "eng$marca@teste.com"

Chamar GET '/produtos' $tokenEng $null 'GET /produtos' | Out-Null

$produto = Chamar POST '/produtos' $tokenEng @{
    produto = @{ nome = "Cimento CP-II $marca"; unidade = 'saco' }
} 'POST /produtos'

if ($produto) {
    Chamar GET "/produtos/$($produto.id)" $tokenEng $null "GET /produtos/$($produto.id)" | Out-Null
    Chamar PATCH "/produtos/$($produto.id)" $tokenEng @{
        produto = @{ unidade = 'un' }
    } "PATCH /produtos/$($produto.id)" | Out-Null
}

Write-Host "`n=== EQUIPAMENTOS  (exige engenheiro) ===" -ForegroundColor Cyan
Chamar GET '/equipamentos' $tokenEng $null 'GET /equipamentos' | Out-Null

$equipamento = Chamar POST '/equipamentos' $tokenEng @{
    equipamento = @{ nome = "Betoneira $marca"; patrimonio = "BT-$marca"; status = 'disponivel' }
} 'POST /equipamentos'

if ($equipamento) {
    Chamar GET "/equipamentos/$($equipamento.id)" $tokenEng $null "GET /equipamentos/$($equipamento.id)" | Out-Null
    Chamar PATCH "/equipamentos/$($equipamento.id)" $tokenEng @{
        equipamento = @{ status = 'manutencao' }
    } "PATCH /equipamentos/$($equipamento.id)" | Out-Null
}

Write-Host "`n=== PERMISSAO  (tudo abaixo deve dar 401 ou 403) ===" -ForegroundColor Cyan
$tokenPed = Entrar "ped$marca@teste.com"

Chamar GET '/eu' $null $null 'GET /eu sem token           -> 401' | Out-Null
Chamar GET '/eu' 'token-invalido' $null 'GET /eu token invalido      -> 401' | Out-Null
Chamar GET '/produtos' $tokenPed $null 'GET /produtos como pedreiro -> 403' | Out-Null
Chamar POST '/produtos' $tokenPed @{ produto = @{ nome = "Furtivo $marca"; unidade = 'un' } } 'POST /produtos como pedreiro-> 403' | Out-Null
Chamar GET '/usuarios' $tokenEng $null 'GET /usuarios como engenheiro-> 403' | Out-Null

Write-Host "`n=== CORPO INVALIDO  (tudo abaixo deve dar 400) ===" -ForegroundColor Cyan
Chamar POST '/produtos' $tokenEng @{ nome = 'Sem envelope'; unidade = 'un' } 'POST /produtos sem envelope -> 400' | Out-Null
Chamar POST '/produtos' $tokenEng @{ produto = @{ nome = 'Unidade errada'; unidade = 'caixinha' } } 'POST /produtos unidade errada-> 400' | Out-Null
Chamar POST '/usuarios' $master @{ usuario = @{ nome = 'X'; email = 'x@x.com'; senha = '123'; tipo = 'pedreiro' } } 'POST /usuarios senha curta  -> 400' | Out-Null
Chamar POST '/usuarios' $master @{ usuario = @{ nome = 'X'; email = 'x@x.com'; senha = $senhaPadrao; tipo = 'chefao' } } 'POST /usuarios tipo invalido-> 400' | Out-Null

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
Write-Host "Dados criados com a marca $marca. Para limpar:" -ForegroundColor DarkGray
Write-Host "  DELETE FROM produto WHERE nome LIKE '%$marca';" -ForegroundColor DarkGray
Write-Host "  DELETE FROM equipamento WHERE nome LIKE '%$marca';" -ForegroundColor DarkGray
Write-Host "  DELETE FROM usuario WHERE email LIKE '%$marca@teste.com';" -ForegroundColor DarkGray
Write-Host "  DELETE FROM empresa WHERE nome LIKE '%$marca';" -ForegroundColor DarkGray
