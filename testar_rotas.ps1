param(
    [string]$BaseUrl = $(if ($env:CONSTROI_API_URL) { $env:CONSTROI_API_URL } else { 'http://localhost:8080' }),
    [string]$Token = $env:CONSTROI_TOKEN,
    [string]$TokenPedreiro = $env:CONSTROI_PEDREIRO_TOKEN,
    [string]$DatabaseUrl = $env:DATABASE_URL
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Token)) {
    throw 'Defina CONSTROI_TOKEN ou informe -Token com um JWT de engenheiro ou master.'
}
if ([string]::IsNullOrWhiteSpace($TokenPedreiro)) {
    throw 'Defina CONSTROI_PEDREIRO_TOKEN ou informe -TokenPedreiro com um JWT de pedreiro.'
}
if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
    throw 'Defina DATABASE_URL ou informe -DatabaseUrl para verificar o historico no banco.'
}
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    throw 'O comando psql e necessario para verificar a persistencia do historico.'
}

$headers = @{ Authorization = "Bearer $Token" }
$headersPedreiro = @{ Authorization = "Bearer $TokenPedreiro" }
$sufixo = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$marca = Get-Random -Minimum 1000 -Maximum 9999
$nome = "Obra smoke $sufixo"

function Chamar-Esperando {
    param(
        [string]$Metodo,
        [string]$Rota,
        [int]$StatusEsperado,
        [hashtable]$Cabecalhos,
        $Corpo,
        [string]$Rotulo
    )

    $parametros = @{
        Uri             = "$BaseUrl$Rota"
        Method          = $Metodo
        UseBasicParsing = $true
    }
    if ($Cabecalhos) { $parametros.Headers = $Cabecalhos }
    if ($null -ne $Corpo) {
        $parametros.Body = ($Corpo | ConvertTo-Json -Depth 5)
        $parametros.ContentType = 'application/json; charset=utf-8'
    }

    try {
        $resposta = Invoke-WebRequest @parametros
        $status = [int]$resposta.StatusCode
        $conteudo = $resposta.Content
    }
    catch {
        if (-not $_.Exception.Response) { throw }
        $status = [int]$_.Exception.Response.StatusCode
        $leitor = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $conteudo = $leitor.ReadToEnd()
        $leitor.Dispose()
    }

    if ($status -ne $StatusEsperado) {
        throw "${Rotulo}: esperado HTTP $StatusEsperado, recebido HTTP $status. $conteudo"
    }
    Write-Host ("{0,-48} {1}" -f $Rotulo, $status) -ForegroundColor Green
    if ([string]::IsNullOrWhiteSpace($conteudo)) { return $null }
    return $conteudo | ConvertFrom-Json
}

function Verificar-Banco {
    param([string]$Consulta, [string]$Esperado, [string]$Rotulo)

    $resultado = (& psql $DatabaseUrl -At -c $Consulta | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $resultado -ne $Esperado) {
        throw "${Rotulo}: esperado '$Esperado', recebido '$resultado'."
    }
    Write-Host ("{0,-48} OK" -f $Rotulo) -ForegroundColor Green
}

$listaInicial = Chamar-Esperando GET '/obras' 200 $headers $null 'GET /obras'
if ($null -eq $listaInicial.obras) { throw 'GET /obras nao retornou a propriedade obras.' }

$corpoObra = @{
    obra = @{ nome = $nome; endereco = 'Rua de teste, 123'; status = 'planejamento' }
}
$criada = Chamar-Esperando POST '/obras' 201 $headers $corpoObra 'POST /obras'
if ($criada.nome -ne $nome -or $criada.status -ne 'planejamento') {
    throw 'POST /obras retornou dados inesperados.'
}

$obraId = $criada.id
$eu = Chamar-Esperando GET '/eu' 200 $headers $null 'GET /eu'
$usuarioId = $eu.id
$buscada = Chamar-Esperando GET "/obras/$obraId" 200 $headers $null 'GET /obras/{id}'
if ($buscada.id -ne $obraId) { throw 'GET /obras/{id} retornou uma obra diferente.' }

$atualizada = Chamar-Esperando PATCH "/obras/$obraId" 200 $headers `
    @{ obra = @{ status = 'ativa' } } 'PATCH /obras/{id}'
if ($atualizada.status -ne 'ativa') { throw 'PATCH /obras/{id} nao atualizou o status.' }

$rotaEquipe = "/obras/$obraId/equipe"
$equipeInicial = Chamar-Esperando GET $rotaEquipe 200 $headersPedreiro $null 'GET equipe como pedreiro'
if ($null -eq $equipeInicial.equipe) { throw 'GET equipe nao retornou a propriedade equipe.' }

$vinculo = Chamar-Esperando POST $rotaEquipe 201 $headers `
    @{ equipe = @{ usuario_id = $usuarioId } } 'POST equipe (vinculo valido)'
$vinculoId = $vinculo.id
if ($vinculo.usuario_id -ne $usuarioId -or $vinculo.obra_id -ne $obraId) {
    throw 'POST equipe retornou um vinculo inesperado.'
}

$duplicado = Chamar-Esperando POST $rotaEquipe 409 $headers `
    @{ equipe = @{ usuario_id = $usuarioId } } 'POST equipe (duplicado -> 409)'
if ($null -eq $duplicado.erro) { throw 'Vinculo duplicado nao retornou erro.' }

$empresaAlheia = Chamar-Esperando POST '/empresas' 201 $null @{
    empresa = @{ nome = "Empresa smoke $sufixo"; cnpj = "12.345.678/000$marca" }
    usuario = @{ nome = "Master smoke $sufixo"; email = "master$sufixo@teste.com"; senha = 'Senha#Forte123' }
} 'POST /empresas (usuario de outra empresa)'
$usuarioAlheioId = $empresaAlheia.usuario.id
$crossEmpresa = Chamar-Esperando POST $rotaEquipe 400 $headers `
    @{ equipe = @{ usuario_id = $usuarioAlheioId } } 'POST equipe (outra empresa -> 400)'
if ($null -eq $crossEmpresa.erro) { throw 'Usuario de outra empresa nao foi recusado.' }
Verificar-Banco "SELECT COUNT(*) FROM usuario_obra WHERE obra_id = $obraId AND usuario_id = $usuarioAlheioId;" '0' `
    'Sem vinculo criado para outra empresa'

$equipePedreiro = Chamar-Esperando GET $rotaEquipe 200 $headersPedreiro $null 'GET equipe permitido ao pedreiro'
if (-not ($equipePedreiro.equipe | Where-Object { $_.usuario_id -eq $usuarioId })) {
    throw 'Pedreiro nao encontrou o vinculo ativo na equipe.'
}
Chamar-Esperando POST $rotaEquipe 403 $headersPedreiro `
    @{ equipe = @{ usuario_id = $usuarioId } } 'POST equipe negado ao pedreiro' | Out-Null
Chamar-Esperando DELETE "$rotaEquipe/$usuarioId" 403 $headersPedreiro $null `
    'DELETE equipe negado ao pedreiro' | Out-Null

$encerrado = Chamar-Esperando DELETE "$rotaEquipe/$usuarioId" 200 $headers $null `
    'DELETE equipe (encerrar vinculo)'
if ($null -eq $encerrado.data_fim) { throw 'Encerramento nao retornou data_fim.' }
Verificar-Banco "SELECT COUNT(*) FROM usuario_obra WHERE id = $vinculoId AND data_fim IS NOT NULL;" '1' `
    'Vinculo encerrado preservado no banco'

$equipeFinal = Chamar-Esperando GET $rotaEquipe 200 $headersPedreiro $null 'GET equipe sem vinculo encerrado'
if ($equipeFinal.equipe | Where-Object { $_.usuario_id -eq $usuarioId }) {
    throw 'Vinculo encerrado ainda aparece na equipe ativa.'
}

Write-Host "Testes de obras/equipe OK (obra id=$obraId, vinculo id=$vinculoId)."