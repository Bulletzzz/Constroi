param(
    [string]$BaseUrl = $(if ($env:CONSTROI_API_URL) { $env:CONSTROI_API_URL } else { 'http://localhost:8080' }),
    [string]$DatabaseUrl = $env:DATABASE_URL,
    [string]$Caso = '*',
    [switch]$Detalhado,
    [switch]$Listar,
    [switch]$SemLimpeza
)

$ErrorActionPreference = 'Stop'

$global:BaseUrl = $BaseUrl
$global:DatabaseUrl = $DatabaseUrl
$global:Detalhado = [bool]$Detalhado
$global:SemLimpeza = [bool]$SemLimpeza
$global:RaizApi = (Resolve-Path (Join-Path $PSScriptRoot '..\constroi_api')).Path

. (Join-Path $PSScriptRoot 'comum\apoio.ps1')

$pasta = Join-Path $PSScriptRoot 'casos'
$arquivos = Get-ChildItem -Path $pasta -Filter '*.ps1' | Sort-Object Name

if ($Caso -ne '*') {
    $arquivos = $arquivos | Where-Object { $_.BaseName -like "*$Caso*" }
}

if ($Listar) {
    Write-Host ''
    Write-Host 'Casos disponiveis:' -ForegroundColor Cyan
    $arquivos | ForEach-Object { Write-Host "  $($_.BaseName)" }
    Write-Host ''
    return
}

if (-not $arquivos) {
    Write-Host "Nenhum caso casou com '$Caso'. Use -Listar para ver os nomes." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host "API: $BaseUrl" -ForegroundColor DarkGray
Write-Host "Casos: $($arquivos.Count)" -ForegroundColor DarkGray

try {
    ValidarBanco
}
catch {
    Write-Host ''
    Write-Host "Banco indisponivel, a suite nao roda: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$resultados = @()
$cronometro = [Diagnostics.Stopwatch]::StartNew()

foreach ($arquivo in $arquivos) {
    $global:UltimoResultado = $null
    $inicio = $cronometro.Elapsed

    try {
        & $arquivo.FullName
        if ($null -eq $global:UltimoResultado) {
            throw "O caso terminou sem chamar FinalizarCaso."
        }
        $resultado = $global:UltimoResultado
    }
    catch {
        $resultado = [pscustomobject]@{
            nome   = $arquivo.BaseName
            total  = if ($global:Total) { $global:Total } else { 0 }
            falhas = @("ERRO: $($_.Exception.Message)")
            marcas = $global:Cenarios
            passou = $false
        }
        Write-Host ("    ERRO  {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    $resultados += [pscustomobject]@{
        arquivo  = $arquivo.BaseName
        nome     = $resultado.nome
        total    = $resultado.total
        falhas   = $resultado.falhas
        marcas   = $resultado.marcas
        passou   = $resultado.passou
        duracao  = [math]::Round(($cronometro.Elapsed - $inicio).TotalSeconds, 1)
    }
}

$cronometro.Stop()

$chamadas = ($resultados | Measure-Object -Property total -Sum).Sum
$quebrados = @($resultados | Where-Object { -not $_.passou })

Write-Host ''
Write-Host ('=' * 68) -ForegroundColor DarkGray
foreach ($r in $resultados) {
    $marca = if ($r.passou) { 'ok   ' } else { 'FALHA' }
    $cor = if ($r.passou) { 'Green' } else { 'Red' }
    $resumo = if ($r.passou) { "$($r.total) chamadas" } else { "$($r.falhas.Count) de $($r.total)" }
    Write-Host ("{0}  {1,-42} {2,-16} {3}s" -f $marca, $r.arquivo, $resumo, $r.duracao) -ForegroundColor $cor
}
Write-Host ('=' * 68) -ForegroundColor DarkGray

if ($quebrados.Count -eq 0) {
    Write-Host ''
    Write-Host "$($resultados.Count) casos, $chamadas chamadas, tudo como esperado em $([math]::Round($cronometro.Elapsed.TotalSeconds, 1))s." -ForegroundColor Green
    Write-Host ''
    exit 0
}

Write-Host ''
Write-Host "$($quebrados.Count) de $($resultados.Count) casos falharam:" -ForegroundColor Red
foreach ($r in $quebrados) {
    Write-Host ''
    Write-Host "  $($r.arquivo)" -ForegroundColor Red
    $r.falhas | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    Write-Host "    repetir: .\testes\executar.ps1 -Caso $($r.arquivo)" -ForegroundColor DarkGray
}

if ($SemLimpeza) {
    $marcas = $resultados | ForEach-Object { $_.marcas } | Where-Object { $_ }
    Write-Host ''
    Write-Host "Marcas mantidas no banco: $($marcas -join ', ')" -ForegroundColor DarkGray
}

Write-Host ''
exit 1
