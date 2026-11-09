. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Emprestimo e devolucao: contrato, empresa, status e concorrencia'

$c = NovoCenario -ComObra -ComEmpresaB
$obraId = $c.obra.id
$responsavelId = $c.pedreiroUsuario.id
$autorId = $c.engenheiroUsuario.id
$equipamento = Chamar POST '/equipamentos' $c.engenheiro @{
    equipamento = @{ nome = "Betoneira $($c.marca)"; patrimonio = "BET-$($c.marca)"; status = 'disponivel' }
} 201 'cria equipamento disponivel'
$equipamentoId = $equipamento.id
$obraB = Chamar POST '/obras' $c.masterB @{
    obra = @{ nome = "Obra B $($c.marca)"; endereco = 'Rua B'; status = 'ativa' }
} 201 'cria obra da empresa B'
$usuarioB = Chamar POST '/usuarios' $c.masterB @{
    usuario = @{ nome = "Responsavel B $($c.marca)"; email = "responsavelb.$($c.marca)@teste.com"; senha = $global:SenhaPadrao; tipo = 'pedreiro' }
} 201 'cria responsavel da empresa B'
$equipamentoB = Chamar POST '/equipamentos' $c.masterB @{
    equipamento = @{ nome = "Betoneira B $($c.marca)"; patrimonio = "BET-$($c.marca)"; status = 'disponivel' }
} 201 'cria equipamento da empresa B'
$dados = @{ equipamento_id = $equipamentoId; usuario_id = $responsavelId; obra_id = $obraId; dias = 2 }
$contagem = "SELECT COUNT(*)::text FROM emprestimo WHERE equipamento_id = $equipamentoId"
$saldo = "SELECT status FROM equipamento WHERE id = $equipamentoId"
$logs = "SELECT COUNT(*)::text FROM log_sistema WHERE acao LIKE 'EMPRESTIMO_EQUIPAMENTO %equipamento=$equipamentoId %'"
$devolucoes = "SELECT COUNT(*)::text FROM log_sistema WHERE acao LIKE 'DEVOLUCAO_EQUIPAMENTO %equipamento=$equipamentoId %'"

Chamar GET '/emprestimos' $null $null 401 'GET sem token' | Out-Null
Chamar GET '/emprestimos' $c.pedreiro $null 403 'pedreiro nao consulta emprestimos' | Out-Null
Chamar POST '/emprestimos' $c.pedreiro @{ emprestimo = $dados } 403 'pedreiro nao empresta' | Out-Null
foreach ($dias in @($null, '2', 0, -1, 1.5, 2147483648, 2147483647)) {
    Chamar POST '/emprestimos' $c.engenheiro @{ emprestimo = @{
        equipamento_id = $equipamentoId; usuario_id = $responsavelId; obra_id = $obraId; dias = $dias
    } } 400 'prazo invalido ou fora da capacidade de datas' | Out-Null
}
foreach ($campo in @('equipamento_id', 'usuario_id', 'obra_id')) {
    $alheio = $dados.Clone()
    $alheio[$campo] = switch ($campo) {
        'equipamento_id' { $equipamentoB.id }
        'usuario_id' { $usuarioB.id }
        'obra_id' { $obraB.id }
    }
    Chamar POST '/emprestimos' $c.engenheiro @{ emprestimo = $alheio } 404 'referencia de outra empresa nao empresta' | Out-Null
}
VerificarBanco $contagem '0' 'recusas nao gravaram emprestimo'
VerificarBanco $saldo 'disponivel' 'recusas mantiveram equipamento disponivel'
VerificarBanco $logs '0' 'recusas nao deixaram log de emprestimo'

$primeiro = Chamar POST '/emprestimos' $c.engenheiro @{ emprestimo = $dados } 201 'registra emprestimo'
$emprestimoId = $primeiro.id
Conferir ($primeiro.equipamento_id -eq $equipamentoId) 'contrato traz equipamento_id'
Conferir ($primeiro.equipamento_nome -eq $equipamento.nome) 'contrato traz equipamento_nome'
Conferir ($primeiro.usuario_id -eq $responsavelId -and $primeiro.responsavel_nome -eq $c.pedreiroUsuario.nome) 'contrato traz responsavel'
Conferir ($primeiro.obra_id -eq $obraId -and $primeiro.obra_nome -eq $c.obra.nome) 'contrato traz obra'
Conferir ($primeiro.status -eq 'aberto' -and -not $primeiro.atrasado -and $null -eq $primeiro.data_devolucao) 'aberto ainda nao esta atrasado nem devolvido'
VerificarBanco $saldo 'em_uso' 'emprestimo atualiza equipamento na mesma operacao'
VerificarBanco "SELECT EXTRACT(EPOCH FROM (data_prevista-data_emprestimo))::bigint::text FROM emprestimo WHERE id = $emprestimoId" '172800' 'prazo usa exatamente os dois dias informados'
VerificarBanco "SELECT COUNT(*)::text FROM log_sistema WHERE usuario_id = $autorId AND empresa_id = (SELECT empresa_id FROM obra WHERE id = $obraId) AND acao = 'EMPRESTIMO_EQUIPAMENTO emprestimo=$emprestimoId equipamento=$equipamentoId usuario=$responsavelId obra=$obraId dias=2'" '1' 'log usa autor e empresa corretos'
Chamar POST '/emprestimos' $c.engenheiro @{ emprestimo = $dados } 409 'nao empresta equipamento em uso' | Out-Null
Chamar PATCH "/equipamentos/$equipamentoId" $c.engenheiro @{ equipamento = @{ status = 'disponivel' } } 409 'cadastro nao contorna emprestimo aberto' | Out-Null
Chamar PATCH "/emprestimos/$emprestimoId" $c.masterB @{ emprestimo = @{ status = 'devolvido' } } 404 'outra empresa nao devolve' | Out-Null
$outros = Chamar GET "/emprestimos?equipamento_id=$equipamentoId" $c.masterB $null 200 'consulta da outra empresa'
Conferir (@($outros.emprestimos).Count -eq 0) 'consulta nao expoe emprestimos alheios'

ExecutarBanco -Argumentos @('consultar', "WITH t AS (UPDATE emprestimo SET data_emprestimo=CURRENT_TIMESTAMP-INTERVAL '3 days', data_prevista=CURRENT_TIMESTAMP-INTERVAL '1 day' WHERE id=$emprestimoId RETURNING 1) SELECT COUNT(*)::text FROM t") | Out-Null
$abertos = Chamar GET "/emprestimos?equipamento_id=$equipamentoId&status=aberto" $c.engenheiro $null 200 'lista abertos do equipamento'
Conferir (@($abertos.emprestimos).Count -eq 1 -and $abertos.emprestimos[0].atrasado) 'prazo vencido aparece como atrasado'
$devolvido = Chamar PATCH "/emprestimos/$emprestimoId" $c.engenheiro @{ emprestimo = @{ status = 'devolvido' } } 200 'registra devolucao'
Conferir ($devolvido.status -eq 'devolvido' -and $null -ne $devolvido.data_devolucao -and -not $devolvido.atrasado) 'devolucao traz data e deixa de contar atraso'
VerificarBanco $saldo 'disponivel' 'devolucao libera equipamento'
VerificarBanco $devolucoes '1' 'devolucao deixa um log'
Chamar PATCH "/emprestimos/$emprestimoId" $c.engenheiro @{ emprestimo = @{ status = 'devolvido' } } 409 'devolucao nao pode ser repetida' | Out-Null

$dados.dias = 4000
$segundo = Chamar POST '/emprestimos' $c.master @{ emprestimo = $dados } 201 'master empresta sem limite comercial de 365 dias'
VerificarBanco "SELECT EXTRACT(EPOCH FROM (data_prevista-data_emprestimo))::bigint::text FROM emprestimo WHERE id=$($segundo.id)" '345600000' 'prazo de 4000 dias foi preservado'
Chamar PATCH "/emprestimos/$emprestimoId" $c.engenheiro @{ emprestimo = @{ status = 'devolvido' } } 409 'repetir devolucao antiga nao libera emprestimo novo' | Out-Null
VerificarBanco $saldo 'em_uso' 'emprestimo novo continua em uso'
Chamar PATCH "/emprestimos/$($segundo.id)" $c.master @{ emprestimo = @{ status = 'devolvido' } } 200 'master devolve' | Out-Null

$dados.dias = 2
$json = @{ emprestimo = $dados } | ConvertTo-Json -Depth 5
Add-Type -AssemblyName System.Net.Http
$cliente = [System.Net.Http.HttpClient]::new()
$cliente.Timeout = [TimeSpan]::FromSeconds(60)
$cliente.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $c.engenheiro)
$conteudos = @()
$respostas = @()
try {
    $tarefas = @()
    for ($i = 0; $i -lt 8; $i++) {
        $conteudo = [System.Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, 'application/json')
        $conteudos += $conteudo
        $tarefas += $cliente.PostAsync("$global:BaseUrl/emprestimos", $conteudo)
    }
    [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tarefas)
    $respostas = @($tarefas | ForEach-Object { $_.Result })
    $codigos = @($respostas | ForEach-Object { [int]$_.StatusCode })
    Conferir (@($codigos | Where-Object { $_ -eq 201 }).Count -eq 1) 'oito POSTs concorrentes confirmam exatamente um emprestimo'
    Conferir (@($codigos | Where-Object { $_ -eq 409 }).Count -eq 7) 'outros sete recebem conflito, sem 500'
    $vencedor = $respostas | Where-Object { [int]$_.StatusCode -eq 201 } | Select-Object -First 1
    $terceiro = $vencedor.Content.ReadAsStringAsync().Result | ConvertFrom-Json
    foreach ($resposta in $respostas) { $resposta.Dispose() }
    $respostas = @()
    $tarefas = @()
    $jsonDevolucao = @{ emprestimo = @{ status = 'devolvido' } } | ConvertTo-Json
    for ($i = 0; $i -lt 2; $i++) {
        $conteudo = [System.Net.Http.StringContent]::new($jsonDevolucao, [Text.Encoding]::UTF8, 'application/json')
        $conteudos += $conteudo
        $requisicao = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new('PATCH'), "$global:BaseUrl/emprestimos/$($terceiro.id)")
        $requisicao.Content = $conteudo
        $tarefas += $cliente.SendAsync($requisicao)
    }
    [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tarefas)
    $respostas = @($tarefas | ForEach-Object { $_.Result })
    $codigos = @($respostas | ForEach-Object { [int]$_.StatusCode })
    Conferir (@($codigos | Where-Object { $_ -eq 200 }).Count -eq 1) 'duas devolucoes concorrentes confirmam uma vez'
    Conferir (@($codigos | Where-Object { $_ -eq 409 }).Count -eq 1) 'segunda devolucao concorrente recebe conflito'
}
finally {
    foreach ($resposta in $respostas) { $resposta.Dispose() }
    foreach ($conteudo in $conteudos) { $conteudo.Dispose() }
    $cliente.Dispose()
}
VerificarBanco $contagem '3' 'somente tres emprestimos foram persistidos'
VerificarBanco $logs '3' 'cada emprestimo tem exatamente um log'
VerificarBanco $devolucoes '3' 'cada devolucao tem exatamente um log'
VerificarBanco $saldo 'disponivel' 'equipamento termina disponivel'
VerificarBanco "SELECT COUNT(*)::text FROM emprestimo WHERE equipamento_id=$equipamentoId AND status='aberto'" '0' 'nenhum emprestimo aberto ficou para tras'

FinalizarCaso
