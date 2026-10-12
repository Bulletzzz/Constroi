. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Pedidos: protocolo unico sob concorrencia'

$simultaneos = 12
$c = NovoCenario -ComObra -ComProduto -ComEquipe

$corpoJson = @{
    pedido = @{ obra_id = $c.obra.id; itens = @(@{ produto_id = $c.produto.id; quantidade = 1 }) }
} | ConvertTo-Json -Depth 6

try { Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue } catch { }
$cliente = [System.Net.Http.HttpClient]::new()
$cliente.Timeout = [TimeSpan]::FromSeconds(60)
$cliente.DefaultRequestHeaders.Authorization =
    [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $c.pedreiro)

$codigos = @()
$protocolos = @()
try {
    $tarefas = @(1..$simultaneos | ForEach-Object {
        $conteudo = [System.Net.Http.StringContent]::new($corpoJson, [System.Text.Encoding]::UTF8, 'application/json')
        $cliente.PostAsync("$global:BaseUrl/pedidos", $conteudo)
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
finally { $cliente.Dispose() }

$criados = ($codigos | Where-Object { $_ -eq 201 }).Count
$distintos = ($protocolos | Select-Object -Unique).Count
$erros5xx = ($codigos | Where-Object { $_ -ge 500 }).Count

Write-Host "    codigos: $($codigos -join ', ')" -ForegroundColor DarkGray

Conferir ($criados -ge 2) "pelo menos 2 pedidos criados (criados $criados)"
Conferir ($distintos -eq $criados) "protocolo unico sob concorrencia ($distintos distintos de $criados criados)"
Conferir ($erros5xx -eq 0) "nenhum 5xx com $simultaneos pedidos simultaneos (veio $erros5xx)"

VerificarBanco "SELECT COUNT(DISTINCT protocolo)::text FROM pedido WHERE obra_id = $($c.obra.id)" "$criados" `
    'banco guardou um protocolo distinto por pedido'

FinalizarCaso
