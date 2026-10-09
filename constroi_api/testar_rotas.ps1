param(
    [string]$BaseUrl = $(if ($env:CONSTROI_API_URL) { $env:CONSTROI_API_URL } else { 'http://localhost:8080' }),
    [string]$DatabaseUrl = $env:DATABASE_URL,
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

function ExecutarBanco {
    param([string[]]$Argumentos)

    $urlAnterior = $env:DATABASE_URL
    $encodingAnterior = [Console]::OutputEncoding
    Push-Location $PSScriptRoot
    try {
        if (-not [string]::IsNullOrWhiteSpace($DatabaseUrl)) { $env:DATABASE_URL = $DatabaseUrl }
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $saida = & dart run bin/testar_banco.dart @Argumentos
        if ($LASTEXITCODE -ne 0) { throw "Falha no apoio Dart ao banco ($($Argumentos[0])). A suite nao pode ignorar este teste." }
        return ($saida | Out-String | ConvertFrom-Json)
    }
    finally {
        $env:DATABASE_URL = $urlAnterior
        [Console]::OutputEncoding = $encodingAnterior
        Pop-Location
    }
}

function VerificarBanco {
    param([string]$Consulta, [string]$Esperado, [string]$Rotulo)

    $consultaBanco = ExecutarBanco -Argumentos @('consultar', $Consulta)
    $resultado = $consultaBanco.resultado
    if ($resultado -ne $Esperado) {
        $script:falhas += "$Rotulo (esperado '$Esperado', veio '$resultado')"
        Write-Host "  FALHA $Rotulo" -ForegroundColor Red
        return
    }
    Write-Host "  ok   $Rotulo" -ForegroundColor DarkGray
}

# Falha antes de criar fixtures se o banco nao estiver configurado/acessivel.
ExecutarBanco -Argumentos @('validar') | Out-Null

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

Secao 'EQUIPE DA OBRA'
$rotaEquipe = "/obras/$($obra.id)/equipe"
Chamar GET $rotaEquipe $tokenPedreiro $null 404 'GET equipe pedreiro sem vinculo' | Out-Null
$equipeInicial = Chamar GET $rotaEquipe $engenheiro $null 200 'GET equipe engenheiro sem vinculo'
if ($null -eq $equipeInicial.equipe) { $script:falhas += 'GET equipe sem propriedade equipe' }
Chamar GET $rotaEquipe $master $null 200 'GET equipe master sem vinculo' | Out-Null

$vinculo = Chamar POST $rotaEquipe $engenheiro @{ equipe = @{ usuario_id = $pedreiro.id } } 201 'POST equipe vinculo valido'
if ($null -eq $vinculo -or $vinculo.usuario_id -ne $pedreiro.id -or $vinculo.obra_id -ne $obra.id) {
    $script:falhas += 'POST equipe retornou vinculo inesperado'
}
Chamar POST $rotaEquipe $engenheiro @{ equipe = @{ usuario_id = $pedreiro.id } } 409 'POST equipe duplicado' | Out-Null

$equipeAtiva = Chamar GET $rotaEquipe $tokenPedreiro $null 200 'GET equipe com pedreiro vinculado'
if (-not ($equipeAtiva.equipe | Where-Object { $_.usuario_id -eq $pedreiro.id })) {
    $script:falhas += 'Pedreiro nao encontrou o proprio vinculo ativo'
}
Chamar POST $rotaEquipe $tokenPedreiro @{ equipe = @{ usuario_id = $pedreiro.id } } 403 'POST equipe negado ao pedreiro' | Out-Null
Chamar DELETE "$rotaEquipe/$($pedreiro.id)" $tokenPedreiro $null 403 'DELETE equipe negado ao pedreiro' | Out-Null

$vinculoEncerrado = Chamar DELETE "$rotaEquipe/$($pedreiro.id)" $engenheiro $null 200 'DELETE equipe encerra vinculo'
if ($null -eq $vinculoEncerrado.data_fim) { $script:falhas += 'Encerramento nao retornou data_fim' }
if ($null -ne $vinculo.id) {
    VerificarBanco "SELECT COUNT(*) FROM usuario_obra WHERE id = $($vinculo.id) AND data_fim IS NOT NULL;" '1' `
        'Vinculo encerrado permanece no banco'
}

Chamar GET $rotaEquipe $tokenPedreiro $null 404 'GET equipe pedreiro vinculo encerrado' | Out-Null
$equipeFinal = Chamar GET $rotaEquipe $engenheiro $null 200 'GET equipe sem encerrados'
if ($equipeFinal.equipe | Where-Object { $_.usuario_id -eq $pedreiro.id }) {
    $script:falhas += 'Vinculo encerrado ainda consta na equipe ativa'
}

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
$empresaB = Chamar POST '/empresas' $null @{
    empresa = @{ nome = "Construtora B $marca"; cnpj = "22.222.222/$marca" }
    usuario = @{ nome = "Master B $marca"; email = "masterb.$marca@teste.com"; senha = $senhaPadrao }
} 201 'POST /empresas segunda empresa'
$masterB = Entrar "masterb.$marca@teste.com"
Chamar GET "/obras/$($obra.id)" $masterB $null 404 'obra da empresa A com token da B' | Out-Null
Chamar GET $rotaEquipe $masterB $null 404 'equipe da empresa A com token da B' | Out-Null
Chamar GET "/produtos/$($produto.id)" $masterB $null 404 'produto da empresa A com token da B' | Out-Null
Chamar GET "/usuarios/$($pedreiro.id)" $masterB $null 404 'usuario da empresa A com token da B' | Out-Null
$euB = Chamar GET '/eu' $masterB $null 200 'GET /eu empresa B'
$vinculoOutraEmpresa = Chamar POST $rotaEquipe $engenheiro `
    @{ equipe = @{ usuario_id = $euB.id } } 400 'POST equipe usuario de outra empresa'
if ($null -eq $vinculoOutraEmpresa -and $null -ne $euB.id) {
    VerificarBanco "SELECT COUNT(*) FROM usuario_obra WHERE obra_id = $($obra.id) AND usuario_id = $($euB.id);" '0' `
        'Nenhum vinculo criado entre empresas'
}


Secao 'PEDIDOS - CRIACAO'
$rotaPedidos = '/pedidos'
Chamar POST $rotaPedidos $tokenPedreiro @{
    pedido = @{ obra_id = $obra.id; itens = @(@{ produto_id = $produto.id; quantidade = 1 }) }
} 403 'POST pedido pedreiro sem vinculo' | Out-Null

Chamar POST $rotaEquipe $engenheiro @{ equipe = @{ usuario_id = $pedreiro.id } } 201 'revincula pedreiro a obra' | Out-Null

$pedido = Chamar POST $rotaPedidos $tokenPedreiro @{
    pedido = @{
        obra_id = $obra.id
        justificativa = "Reposicao $marca"
        itens = @(@{ produto_id = $produto.id; quantidade = 2.5 })
    }
} 201 'POST pedido valido'

if ($null -eq $pedido) {
    $falhas += 'POST pedido valido nao retornou corpo'
}
else {
    if ($pedido.protocolo -notmatch '^PED-[0-9A-F]{32}$') {
        $falhas += "Protocolo fora do formato esperado ($($pedido.protocolo))"
    }
    if ($pedido.status -ne 'pendente') { $falhas += "Status inicial deveria ser pendente, veio $($pedido.status)" }
    if ($pedido.usuario_id -ne $pedreiro.id) { $falhas += 'Pedido gravado com usuario_id errado' }
    if ($pedido.obra_id -ne $obra.id) { $falhas += 'Pedido gravado com obra_id errado' }
    if ($pedido.itens.Count -ne 1) { $falhas += "Pedido deveria ter 1 item, veio $($pedido.itens.Count)" }
    elseif ("$($pedido.itens[0].quantidade)" -ne '2.50') {
        $falhas += "Quantidade deveria vir 2.50, veio $($pedido.itens[0].quantidade)"
    }
}

Chamar POST $rotaPedidos $null @{
    pedido = @{ obra_id = $obra.id; itens = @(@{ produto_id = $produto.id; quantidade = 1 }) }
} 401 'POST pedido sem token' | Out-Null
Chamar POST $rotaPedidos $tokenPedreiro @{
    obra_id = $obra.id; itens = @(@{ produto_id = $produto.id; quantidade = 1 })
} 400 'POST pedido sem envelope' | Out-Null
Chamar POST $rotaPedidos $tokenPedreiro @{ pedido = @{ obra_id = $obra.id; itens = @() } } 400 'POST pedido sem itens' | Out-Null
Chamar POST $rotaPedidos $tokenPedreiro @{
    pedido = @{ obra_id = $obra.id; itens = @(
        @{ produto_id = $produto.id; quantidade = 1 },
        @{ produto_id = $produto.id; quantidade = 2 }
    ) }
} 400 'POST pedido com produto repetido' | Out-Null
Chamar POST $rotaPedidos $tokenPedreiro @{
    pedido = @{ obra_id = $obra.id; itens = @(@{ produto_id = $produto.id; quantidade = 0 }) }
} 400 'POST pedido com quantidade zero' | Out-Null
Chamar POST $rotaPedidos $tokenPedreiro @{
    pedido = @{ obra_id = $obra.id; itens = @(@{ produto_id = $produto.id; quantidade = 1.555 }) }
} 400 'POST pedido com 3 casas decimais' | Out-Null
Chamar POST $rotaPedidos $tokenPedreiro @{
    pedido = @{ obra_id = 999999999; itens = @(@{ produto_id = $produto.id; quantidade = 1 }) }
} 404 'POST pedido em obra inexistente' | Out-Null
Chamar POST $rotaPedidos $tokenPedreiro @{
    pedido = @{ obra_id = $obra.id; itens = @(@{ produto_id = 999999999; quantidade = 1 }) }
} 400 'POST pedido com produto inexistente' | Out-Null

$itensDemais = 1..201 | ForEach-Object { @{ produto_id = $_; quantidade = 1 } }
Chamar POST $rotaPedidos $tokenPedreiro @{ pedido = @{ obra_id = $obra.id; itens = $itensDemais } } 400 'POST pedido com 201 itens' | Out-Null

Chamar PUT $rotaPedidos $tokenPedreiro $null 405 'PUT /pedidos nao permitido' | Out-Null

Secao 'PEDIDOS - PROTOCOLO SOB CONCORRENCIA'
$simultaneos = 12
try { Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue } catch { }
$cliente = [System.Net.Http.HttpClient]::new()
$cliente.Timeout = [TimeSpan]::FromSeconds(60)
$cliente.DefaultRequestHeaders.Authorization =
    [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $tokenPedreiro)

$corpoJson = @{
    pedido = @{ obra_id = $obra.id; itens = @(@{ produto_id = $produto.id; quantidade = 1 }) }
} | ConvertTo-Json -Depth 6

$codigos = @()
$protocolos = @()
try {
    $tarefas = @(1..$simultaneos | ForEach-Object {
        $conteudo = [System.Net.Http.StringContent]::new($corpoJson, [System.Text.Encoding]::UTF8, 'application/json')
        $cliente.PostAsync("$BaseUrl$rotaPedidos", $conteudo)
    })
    [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tarefas)

    foreach ($tarefa in $tarefas) {
        $resposta = $tarefa.Result
        $codigos += [int]$resposta.StatusCode
        if ($resposta.IsSuccessStatusCode) {
            $texto = $resposta.Content.ReadAsStringAsync().Result
            try { $protocolos += ($texto | ConvertFrom-Json).protocolo } catch { }
        }
    }
}
finally {
    $cliente.Dispose()
}

$script:total += $simultaneos
$criados = ($codigos | Where-Object { $_ -eq 201 }).Count
$distintos = ($protocolos | Select-Object -Unique).Count
$erros5xx = ($codigos | Where-Object { $_ -ge 500 }).Count

if ($criados -lt 2 -or $distintos -ne $criados) {
    $detalhe = "criados $criados, distintos $distintos"
    $falhas += "Protocolo repetido sob concorrencia ($detalhe)"
    Write-Host ("  FALHA {0,-46} {1}" -f 'protocolo unico sob concorrencia', $detalhe) -ForegroundColor Red
}
else {
    Write-Host ("  ok   {0,-46} {1}" -f 'protocolo unico sob concorrencia', "$distintos/$criados distintos") -ForegroundColor DarkGray
}

if ($erros5xx -gt 0) {
    $falhas += "API devolveu $erros5xx erro(s) 5xx com $simultaneos pedidos simultaneos"
    Write-Host ("  FALHA {0,-46} {1}" -f 'suporta carga simultanea', "$erros5xx de $simultaneos deram 5xx") -ForegroundColor Red
}
else {
    Write-Host ("  ok   {0,-46} {1}" -f 'suporta carga simultanea', "$criados/$simultaneos sem 5xx") -ForegroundColor DarkGray
}

Secao 'PEDIDOS - LEITURA E ISOLAMENTO'
$pedreiroDois = Chamar POST '/usuarios' $master @{
    usuario = @{ nome = "Ped2 $marca"; email = "ped2.$marca@teste.com"; senha = $senhaPadrao; tipo = 'pedreiro' }
} 201 'POST /usuarios segundo pedreiro'
$tokenPedreiroDois = Entrar "ped2.$marca@teste.com"
Chamar POST $rotaEquipe $engenheiro @{ equipe = @{ usuario_id = $pedreiroDois.id } } 201 'vincula segundo pedreiro' | Out-Null

$pedidoDoOutro = Chamar POST $rotaPedidos $tokenPedreiroDois @{
    pedido = @{ obra_id = $obra.id; itens = @(@{ produto_id = $produto.id; quantidade = 1 }) }
} 201 'POST pedido do segundo pedreiro'

if ($null -ne $pedido -and $null -ne $pedidoDoOutro) {
    Chamar GET "$rotaPedidos/$($pedidoDoOutro.id)" $tokenPedreiro $null 404 'pedreiro nao le pedido de outro' | Out-Null
    Chamar GET "$rotaPedidos/$($pedido.id)" $tokenPedreiroDois $null 404 'segundo pedreiro nao le o primeiro' | Out-Null
    Chamar GET "$rotaPedidos/$($pedido.id)" $tokenPedreiro $null 200 'pedreiro le o proprio pedido' | Out-Null
    Chamar GET "$rotaPedidos/$($pedido.id)" $engenheiro $null 200 'engenheiro le pedido de qualquer um' | Out-Null
    Chamar GET "$rotaPedidos/$($pedido.id)" $masterB $null 404 'pedido da empresa A com token da B' | Out-Null

    $listaPedreiro = Chamar GET $rotaPedidos $tokenPedreiro $null 200 'GET /pedidos como pedreiro'
    if ($listaPedreiro.pedidos | Where-Object { $_.usuario_id -ne $pedreiro.id }) {
        $falhas += 'Lista do pedreiro trouxe pedido de outro usuario'
    }
    $listaEngenheiro = Chamar GET $rotaPedidos $engenheiro $null 200 'GET /pedidos como engenheiro'
    if (-not ($listaEngenheiro.pedidos | Where-Object { $_.usuario_id -eq $pedreiroDois.id })) {
        $falhas += 'Engenheiro nao enxergou pedido do segundo pedreiro'
    }

    $porProtocolo = Chamar GET "$rotaPedidos`?protocolo=$($pedido.protocolo)" $engenheiro $null 200 'GET /pedidos filtra por protocolo'
    if ($porProtocolo.pedidos.Count -ne 1) { $falhas += 'Filtro por protocolo deveria trazer exatamente 1' }
}

Chamar GET "$rotaPedidos`?limit=1" $engenheiro $null 200 'GET /pedidos com limit=1' | Out-Null
Chamar GET "$rotaPedidos`?limit=0" $engenheiro $null 400 'GET /pedidos com limit=0' | Out-Null
Chamar GET "$rotaPedidos`?limit=201" $engenheiro $null 400 'GET /pedidos com limit=201' | Out-Null
Chamar GET "$rotaPedidos`?offset=-1" $engenheiro $null 400 'GET /pedidos com offset negativo' | Out-Null
Chamar GET "$rotaPedidos`?obra_id=abc" $engenheiro $null 400 'GET /pedidos com obra_id invalido' | Out-Null
Chamar GET "$rotaPedidos/0" $engenheiro $null 400 'GET /pedidos/0 invalido' | Out-Null
Chamar GET $rotaPedidos $null $null 401 'GET /pedidos sem token' | Out-Null

Secao 'CONSULTA DE ESTOQUE'
# Usuario exclusivo: a secao de pedidos pode revincular os seus proprios usuarios.
$pedreiroEstoque = Chamar POST '/usuarios' $master @{
    usuario = @{ nome = "Ped estoque $marca"; email = "ped.estoque.$marca@teste.com"; senha = $senhaPadrao; tipo = 'pedreiro' }
} 201 'POST /usuarios pedreiro do estoque'
if ($null -eq $pedreiroEstoque.id) { throw 'Falha ao criar usuario do cenario de estoque.' }
$tokenPedreiroEstoque = Entrar "ped.estoque.$marca@teste.com"
$rotaEstoque = "/estoque?obra_id=$($obra.id)"
Chamar GET $rotaEstoque $tokenPedreiroEstoque $null 404 'GET estoque sem vinculo' | Out-Null
$semVinculo = Chamar GET '/estoque' $tokenPedreiroEstoque $null 200 'GET estoque geral sem vinculo'
if (@($semVinculo.estoque).Count -ne 0) { $falhas += 'Usuario sem vinculo recebeu saldos de estoque' }
Chamar POST $rotaEquipe $engenheiro @{ equipe = @{ usuario_id = $pedreiroEstoque.id } } 201 'vincula pedreiro do estoque' | Out-Null
Chamar GET $rotaEstoque $engenheiro $null 200 'GET estoque engenheiro' | Out-Null
Chamar GET $rotaEstoque $tokenPedreiroEstoque $null 200 'GET estoque pedreiro vinculado' | Out-Null
Chamar GET $rotaEstoque $masterB $null 404 'GET estoque empresa B' | Out-Null
Chamar GET $rotaEstoque $null $null 401 'GET estoque sem token' | Out-Null
Chamar GET '/estoque' $master $null 200 'GET estoque sem obra_id' | Out-Null
Chamar GET '/estoque' $tokenPedreiroEstoque $null 200 'GET estoque geral pedreiro' | Out-Null
Chamar GET '/estoque?categoria_id=abc' $master $null 400 'GET estoque categoria invalida' | Out-Null
Chamar GET '/estoque?categoria_id=2147483647' $master $null 200 'GET estoque categoria inexistente' | Out-Null
Chamar GET "$rotaEstoque&baixo=1" $master $null 400 'GET estoque filtro invalido' | Out-Null
Chamar POST $rotaEstoque $tokenPedreiroEstoque @{} 405 'POST estoque nao permitido' | Out-Null

$configurado = Chamar PATCH "/produtos/$($produto.id)" $engenheiro @{
    produto = @{ sku = "CIM-$marca"; estoque_minimo = '5.00' }
} 200 'PATCH SKU e minimo do produto'
if ($configurado.sku -ne "CIM-$marca" -or [decimal]$configurado.estoque_minimo -ne 5) {
    $falhas += 'SKU ou minimo nao foram persistidos'
}
Chamar POST '/produtos' $engenheiro @{
    produto = @{ nome = "Outro $marca"; unidade = 'un'; sku = "cim-$marca" }
} 409 'POST SKU duplicado na empresa' | Out-Null
Chamar PATCH "/produtos/$($produto.id)" $engenheiro @{
    produto = @{ estoque_minimo = -1 }
} 400 'PATCH minimo negativo' | Out-Null

$preparo = ExecutarBanco -Argumentos @('estoque', "$($obra.id)", "$($produto.id)", '5')
$categoriaEstoque = $preparo.categoria_custo_id
if ($null -eq $categoriaEstoque -or [decimal]$preparo.quantidade -ne 5) { throw 'Preparo de estoque nao retornou o saldo e a categoria esperados.' }
$saldo = Chamar GET "$rotaEstoque&busca=cim-$marca&baixo=true" $tokenPedreiroEstoque $null 200 'GET estoque por SKU e minimo'
if (@($saldo.estoque).Count -ne 1 -or $saldo.estoque[0].produto_id -ne $produto.id -or
    [decimal]$saldo.estoque[0].quantidade -ne 5 -or -not $saldo.estoque[0].baixo -or
    $saldo.estoque[0].produto_nome -ne $produto.nome -or
    $saldo.estoque[0].unidade -ne $configurado.unidade -or
    $saldo.estoque[0].sku -ne "CIM-$marca" -or
    [decimal]$saldo.estoque[0].estoque_minimo -ne 5 -or
    $saldo.estoque[0].categoria_custo_id -ne $categoriaEstoque -or
    $saldo.estoque[0].categoria_nome -ne $preparo.categoria_nome) {
    $falhas += 'Busca por SKU ou estoque baixo retornou saldo inesperado'
}
$porNome = Chamar GET "$rotaEstoque&busca=Cimento" $engenheiro $null 200 'GET estoque busca por nome'
if (-not ($porNome.estoque | Where-Object { $_.produto_id -eq $produto.id })) {
    $falhas += 'Busca por nome nao retornou o produto'
}
$categoria = Chamar GET "/estoque?categoria_id=$categoriaEstoque&busca=cim-$marca" $tokenPedreiroEstoque $null 200 'GET estoque categoria sem obra_id'
if (@($categoria.estoque).Count -ne 1 -or
    $categoria.estoque[0].obra_id -ne $obra.id -or
    $categoria.estoque[0].categoria_custo_id -ne [int]$categoriaEstoque -or
    $categoria.estoque[0].categoria_nome -ne $preparo.categoria_nome) {
    $falhas += 'Categoria ou escopo geral do estoque divergiram do contrato'
}
$semCategoria = Chamar GET "$rotaEstoque&categoria_id=2147483647" $engenheiro $null 200 'GET estoque sem saldo na categoria'
if (@($semCategoria.estoque).Count -ne 0) { $falhas += 'Filtro de categoria foi ignorado' }
ExecutarBanco -Argumentos @('estoque', "$($obra.id)", "$($produto.id)", '6') | Out-Null
$acima = Chamar GET "$rotaEstoque&baixo=true" $engenheiro $null 200 'GET estoque acima do minimo'
if ($acima.estoque | Where-Object { $_.produto_id -eq $produto.id }) {
    $falhas += 'Saldo acima do minimo apareceu como baixo'
}

$encerradoEstoque = Chamar DELETE "$rotaEquipe/$($pedreiroEstoque.id)" $engenheiro $null 200 'encerra vinculo do cenario de estoque'
if ($null -eq $encerradoEstoque.data_fim) { $falhas += 'Vinculo do estoque nao foi encerrado' }
Chamar GET $rotaEstoque $tokenPedreiroEstoque $null 404 'GET estoque vinculo encerrado' | Out-Null
$aposEncerramento = Chamar GET '/estoque' $tokenPedreiroEstoque $null 200 'GET estoque geral apos encerramento'
if (@($aposEncerramento.estoque).Count -ne 0) { $falhas += 'Vinculo encerrado ainda permite consultar saldos' }

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
Write-Host "  DELETE FROM estoque WHERE obra_id IN (SELECT id FROM obra WHERE nome LIKE '%$marca');" -ForegroundColor DarkGray
Write-Host "  DELETE FROM item_pedido WHERE pedido_id IN (SELECT p.id FROM pedido p JOIN obra o ON o.id = p.obra_id WHERE o.nome LIKE '%$marca');" -ForegroundColor DarkGray
Write-Host "  DELETE FROM pedido WHERE obra_id IN (SELECT id FROM obra WHERE nome LIKE '%$marca');" -ForegroundColor DarkGray
Write-Host "  DELETE FROM obra WHERE nome LIKE '%$marca';" -ForegroundColor DarkGray
Write-Host "  DELETE FROM produto WHERE nome LIKE '%$marca';" -ForegroundColor DarkGray
Write-Host "  DELETE FROM equipamento WHERE nome LIKE '%$marca';" -ForegroundColor DarkGray
Write-Host "  DELETE FROM usuario WHERE email LIKE '%$marca@teste.com';" -ForegroundColor DarkGray
Write-Host "  DELETE FROM empresa WHERE nome LIKE '%$marca';" -ForegroundColor DarkGray

if ($falhas.Count -gt 0) { exit 1 }
