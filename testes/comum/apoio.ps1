$ErrorActionPreference = 'Stop'

if (-not $global:BaseUrl) {
    $global:BaseUrl = if ($env:CONSTROI_API_URL) { $env:CONSTROI_API_URL } else { 'http://localhost:8080' }
}
if (-not $global:DatabaseUrl) { $global:DatabaseUrl = $env:DATABASE_URL }
if (-not $global:RaizApi) {
    $global:RaizApi = (Resolve-Path (Join-Path $PSScriptRoot '..\..\constroi_api')).Path
}

$global:SenhaPadrao = 'Senha#Forte123'

function IniciarCaso {
    param([string]$Nome)

    $global:CasoAtual = $Nome
    $global:Falhas = @()
    $global:Total = 0
    $global:Cenarios = @()
    Write-Host ''
    Write-Host "  $Nome" -ForegroundColor Cyan
}

function Falhar {
    param([string]$Motivo)

    $global:Falhas += $Motivo
    Write-Host ("    FALHA {0}" -f $Motivo) -ForegroundColor Red
}

function Conferir {
    param([bool]$Condicao, [string]$Rotulo)

    $global:Total++
    if ($Condicao) {
        Write-Host ("    ok    {0}" -f $Rotulo) -ForegroundColor DarkGray
        return
    }
    Falhar $Rotulo
}

function Chamar {
    param(
        [string]$Metodo,
        [string]$Rota,
        [string]$Token,
        $Corpo,
        [int]$Esperado,
        [string]$Rotulo
    )

    $global:Total++
    $parametros = @{
        Uri             = "$global:BaseUrl$Rota"
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
        Write-Host ("    ok    {0,-50} {1}" -f $Rotulo, $codigo) -ForegroundColor DarkGray
    }
    else {
        $global:Falhas += "$Rotulo (esperado $Esperado, veio $codigo)"
        Write-Host ("    FALHA {0,-50} esperado {1}, veio {2}" -f $Rotulo, $Esperado, $codigo) -ForegroundColor Red
    }
    if ($global:Detalhado -and $conteudo) {
        Write-Host ("          {0}" -f ($conteudo -replace '\s+', ' ')) -ForegroundColor DarkGray
    }

    if ($conteudo -and $codigo -lt 400) {
        try { return $conteudo | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

function Entrar {
    param([string]$Email)

    $resposta = Invoke-RestMethod -Uri "$global:BaseUrl/login" -Method Post `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ email = $Email; senha = $global:SenhaPadrao } | ConvertTo-Json)
    return $resposta.token
}

function CodigoDoLogin {
    param([string]$Email, [string]$Senha = $global:SenhaPadrao)

    try {
        Invoke-WebRequest -Uri "$global:BaseUrl/login" -Method Post -UseBasicParsing `
            -ContentType 'application/json; charset=utf-8' `
            -Body (@{ email = $Email; senha = $Senha } | ConvertTo-Json) -ErrorAction Stop | Out-Null
        return 200
    }
    catch { return [int]$_.Exception.Response.StatusCode.value__ }
}

function ExecutarBanco {
    param([string[]]$Argumentos)

    $urlAnterior = $env:DATABASE_URL
    $encodingAnterior = [Console]::OutputEncoding
    Push-Location $global:RaizApi
    try {
        if (-not [string]::IsNullOrWhiteSpace($global:DatabaseUrl)) { $env:DATABASE_URL = $global:DatabaseUrl }
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $saida = & dart run bin/testar_banco.dart @Argumentos
        if ($LASTEXITCODE -ne 0) {
            throw "Falha no apoio Dart ao banco ($($Argumentos[0])). O caso nao pode ser ignorado."
        }
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

    $resultado = (ExecutarBanco -Argumentos @('consultar', $Consulta)).resultado
    Conferir ($resultado -eq $Esperado) "$Rotulo (esperado '$Esperado', veio '$resultado')"
}

function ValidarBanco {
    ExecutarBanco -Argumentos @('validar') | Out-Null
}

function NovaMarca {
    return [Guid]::NewGuid().ToString('N').Substring(0, 6)
}

function NovoCenario {
    param(
        [switch]$ComUsuarios,
        [switch]$ComObra,
        [switch]$ComProduto,
        [switch]$ComEquipe,
        [switch]$ComEmpresaB
    )

    $marca = NovaMarca
    $global:Cenarios += $marca

    $cenario = [ordered]@{ marca = $marca }

    Chamar POST '/empresas' $null @{
        empresa = @{ nome = "Construtora A $marca"; cnpj = "11.111.111/$marca" }
        usuario = @{ nome = "Master $marca"; email = "master.$marca@teste.com"; senha = $global:SenhaPadrao }
    } 201 'cenario: cria empresa A' | Out-Null
    $cenario.master = Entrar "master.$marca@teste.com"

    if ($ComUsuarios -or $ComObra -or $ComProduto -or $ComEquipe) {
        $cenario.engenheiroUsuario = Chamar POST '/usuarios' $cenario.master @{
            usuario = @{ nome = "Eng $marca"; email = "eng.$marca@teste.com"; senha = $global:SenhaPadrao; tipo = 'engenheiro' }
        } 201 'cenario: cria engenheiro'
        $cenario.pedreiroUsuario = Chamar POST '/usuarios' $cenario.master @{
            usuario = @{ nome = "Ped $marca"; email = "ped.$marca@teste.com"; senha = $global:SenhaPadrao; tipo = 'pedreiro' }
        } 201 'cenario: cria pedreiro'
        $cenario.engenheiro = Entrar "eng.$marca@teste.com"
        $cenario.pedreiro = Entrar "ped.$marca@teste.com"
    }

    if ($ComObra -or $ComEquipe) {
        $cenario.obra = Chamar POST '/obras' $cenario.engenheiro @{
            obra = @{ nome = "Obra Alpha $marca"; endereco = 'Rua de teste, 123'; status = 'ativa' }
        } 201 'cenario: cria obra'
        $cenario.rotaEquipe = "/obras/$($cenario.obra.id)/equipe"
    }

    if ($ComProduto) {
        $cenario.produto = Chamar POST '/produtos' $cenario.engenheiro @{
            produto = @{ nome = "Cimento $marca"; unidade = 'saco' }
        } 201 'cenario: cria produto'
    }

    if ($ComEquipe) {
        Chamar POST $cenario.rotaEquipe $cenario.engenheiro @{
            equipe = @{ usuario_id = $cenario.pedreiroUsuario.id }
        } 201 'cenario: vincula pedreiro a obra' | Out-Null
    }

    if ($ComEmpresaB) {
        Chamar POST '/empresas' $null @{
            empresa = @{ nome = "Construtora B $marca"; cnpj = "22.222.222/$marca" }
            usuario = @{ nome = "Master B $marca"; email = "masterb.$marca@teste.com"; senha = $global:SenhaPadrao }
        } 201 'cenario: cria empresa B' | Out-Null
        $cenario.masterB = Entrar "masterb.$marca@teste.com"
    }

    return [pscustomobject]$cenario
}

function LimparMarca {
    param([string]$Marca)

    $partes = @(
        "WITH alvo AS (SELECT id FROM empresa WHERE nome LIKE '%$Marca')",
        "u AS (SELECT id FROM usuario WHERE empresa_id IN (SELECT id FROM alvo))",
        "o AS (SELECT id FROM obra WHERE empresa_id IN (SELECT id FROM alvo))",
        "d1 AS (DELETE FROM item_pedido WHERE pedido_id IN (SELECT id FROM pedido WHERE obra_id IN (SELECT id FROM o)) RETURNING 1)",
        "d2 AS (DELETE FROM pedido WHERE obra_id IN (SELECT id FROM o) RETURNING 1)",
        "d3 AS (DELETE FROM estoque WHERE obra_id IN (SELECT id FROM o) RETURNING 1)",
        "d4 AS (DELETE FROM usuario_obra WHERE obra_id IN (SELECT id FROM o) RETURNING 1)",
        "d5 AS (DELETE FROM log_sistema WHERE usuario_id IN (SELECT id FROM u) RETURNING 1)",
        "d6 AS (DELETE FROM equipamento WHERE empresa_id IN (SELECT id FROM alvo) RETURNING 1)",
        "d7 AS (DELETE FROM produto WHERE empresa_id IN (SELECT id FROM alvo) RETURNING 1)",
        "d8 AS (DELETE FROM obra WHERE id IN (SELECT id FROM o) RETURNING 1)",
        "d9 AS (DELETE FROM usuario WHERE id IN (SELECT id FROM u) RETURNING 1)",
        "d10 AS (DELETE FROM empresa WHERE id IN (SELECT id FROM alvo) RETURNING 1)"
    )
    $sql = ($partes -join ', ') + ' SELECT COUNT(*)::text FROM d10'
    ExecutarBanco -Argumentos @('consultar', $sql) | Out-Null
}

function FinalizarCaso {
    if (-not $global:SemLimpeza) {
        foreach ($marca in $global:Cenarios) {
            try { LimparMarca $marca }
            catch { Falhar "Limpeza da marca $marca falhou: $($_.Exception.Message)" }
        }
    }

    $global:UltimoResultado = [pscustomobject]@{
        nome    = $global:CasoAtual
        total   = $global:Total
        falhas  = $global:Falhas
        marcas  = $global:Cenarios
        passou  = ($global:Falhas.Count -eq 0)
    }
}
