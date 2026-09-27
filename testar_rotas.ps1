param(
    [string]$BaseUrl = $(if ($env:CONSTROI_API_URL) { $env:CONSTROI_API_URL } else { 'http://localhost:8080' }),
    [string]$Token = $env:CONSTROI_TOKEN
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Token)) {
    throw 'Defina CONSTROI_TOKEN ou informe -Token com um JWT de engenheiro ou master.'
}

$headers = @{ Authorization = "Bearer $Token" }
$sufixo = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$nome = "Obra smoke $sufixo"
$payload = @{
    obra = @{
        nome = $nome
        endereco = 'Rua de teste, 123'
        status = 'planejamento'
    }
} | ConvertTo-Json -Depth 4

$listaInicial = Invoke-RestMethod -Method Get -Uri "$BaseUrl/obras" -Headers $headers
if ($null -eq $listaInicial.obras) { throw 'GET /obras nao retornou a propriedade obras.' }

$criada = Invoke-RestMethod -Method Post -Uri "$BaseUrl/obras" -Headers $headers `
    -ContentType 'application/json; charset=utf-8' -Body $payload
if ($criada.nome -ne $nome -or $criada.status -ne 'planejamento') {
    throw 'POST /obras retornou dados inesperados.'
}

$obraId = $criada.id
$buscada = Invoke-RestMethod -Method Get -Uri "$BaseUrl/obras/$obraId" -Headers $headers
if ($buscada.id -ne $obraId) { throw 'GET /obras/{id} retornou uma obra diferente.' }

$patch = @{ obra = @{ status = 'ativa' } } | ConvertTo-Json -Depth 4
$atualizada = Invoke-RestMethod -Method Patch -Uri "$BaseUrl/obras/$obraId" -Headers $headers `
    -ContentType 'application/json; charset=utf-8' -Body $patch
if ($atualizada.status -ne 'ativa') { throw 'PATCH /obras/{id} nao atualizou o status.' }

Write-Host "CRUD de obras OK (obra id=$obraId, status=$($atualizada.status))."