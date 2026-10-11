. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'RNF20: concorrencia na baixa do ultimo saldo'

$simultaneos = 8
$c = NovoCenario -ComObra -ComProduto -ComEquipe
$obraId = $c.obra.id
$produtoId = $c.produto.id

$preparo = ExecutarBanco -Argumentos @('estoque', "$obraId", "$produtoId", '1')
Conferir ([decimal]$preparo.quantidade -eq 1) 'cenario comeca com saldo de 1 unidade'

$pedidos = @()
for ($i = 0; $i -lt $simultaneos; $i++) {
    $pedidos += Chamar POST '/pedidos' $c.pedreiro @{
        pedido = @{ obra_id = $obraId; itens = @(@{ produto_id = $produtoId; quantidade = 1 }) }
    } 201 "cria pedido $($i + 1) de $simultaneos"
}

$json = @{ pedido = @{ status = 'aprovado' } } | ConvertTo-Json -Depth 4

try { Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue } catch { }
$cliente = [System.Net.Http.HttpClient]::new()
$cliente.Timeout = [TimeSpan]::FromSeconds(60)
$cliente.DefaultRequestHeaders.Authorization =
    [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $c.engenheiro)

$codigos = @()
try {
    $tarefas = @($pedidos | ForEach-Object {
        $conteudo = [System.Net.Http.StringContent]::new($json, [System.Text.Encoding]::UTF8, 'application/json')
        $cliente.PatchAsync("$global:BaseUrl/pedidos/$($_.id)", $conteudo)
    })
    [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tarefas)
    foreach ($tarefa in $tarefas) { $codigos += [int]$tarefa.Result.StatusCode }
}
finally { $cliente.Dispose() }

$aprovados = ($codigos | Where-Object { $_ -eq 200 }).Count
$conflitos = ($codigos | Where-Object { $_ -eq 409 }).Count
$erros5xx = ($codigos | Where-Object { $_ -ge 500 }).Count

Write-Host "    codigos: $($codigos -join ', ')" -ForegroundColor DarkGray

Conferir ($aprovados -eq 1) "apenas 1 aprovacao consome o ultimo saldo (aprovados $aprovados)"
Conferir ($conflitos -eq ($simultaneos - 1)) "as outras $($simultaneos - 1) recebem 409 (veio $conflitos)"
Conferir ($erros5xx -eq 0) "nenhum 5xx sob concorrencia (veio $erros5xx)"

$saldo = (ExecutarBanco -Argumentos @('consultar',
    "SELECT quantidade::text FROM estoque WHERE obra_id = $obraId AND produto_id = $produtoId")).resultado
Write-Host "    saldo final: $saldo" -ForegroundColor DarkGray
Conferir ([decimal]$saldo -ge 0) "estoque nunca fica negativo (veio $saldo)"
Conferir ([decimal]$saldo -eq 0) "ultimo saldo foi consumido exatamente uma vez (veio $saldo)"

VerificarBanco "SELECT COUNT(*)::text FROM log_sistema WHERE acao LIKE 'BAIXA_ESTOQUE pedido=%obra=$obraId %'" '1' `
    'transacoes revertidas nao deixaram log'

FinalizarCaso
