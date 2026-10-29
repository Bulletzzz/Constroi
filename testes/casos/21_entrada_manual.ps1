. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Entrada manual: saldo, auditoria, isolamento, rollback e concorrencia'

$c = NovoCenario -ComObra -ComProduto -ComEmpresaB
$obraId = $c.obra.id
$produtoId = $c.produto.id
$engenheiroId = $c.engenheiroUsuario.id
$segundo = Chamar POST '/produtos' $c.engenheiro @{
    produto = @{ nome = "Areia $($c.marca)"; unidade = 'kg' }
} 201 'cria segundo produto'
$segundoId = $segundo.id
$obraB = Chamar POST '/obras' $c.masterB @{
    obra = @{ nome = "Obra B $($c.marca)"; endereco = 'Rua B'; status = 'ativa' }
} 201 'cria obra de outra empresa'
$produtoB = Chamar POST '/produtos' $c.masterB @{
    produto = @{ nome = "Produto B $($c.marca)"; unidade = 'un' }
} 201 'cria produto de outra empresa'

$entrada = @{
    obra_id = $obraId
    usuario_id = 2147483647
    justificativa = ' Material recebido sem nota fiscal '
    itens = @(@{ produto_id = $produtoId; quantidade = 1.25 })
}
$contagem = "SELECT COUNT(*)::text FROM entrada_estoque WHERE obra_id = $obraId"
$saldo = "SELECT quantidade::text FROM estoque WHERE obra_id = $obraId AND produto_id = $produtoId"
$registros = "SELECT COUNT(*)::text FROM log_sistema WHERE acao LIKE 'ENTRADA_MANUAL %obra=$obraId %'"
$estado = @"
SELECT json_build_array(
    (SELECT COUNT(*) FROM entrada_estoque WHERE obra_id IN ($obraId, $($obraB.id))),
    (SELECT COUNT(*) FROM item_entrada WHERE entrada_id IN
        (SELECT id FROM entrada_estoque WHERE obra_id IN ($obraId, $($obraB.id)))),
    (SELECT COUNT(*) FROM log_sistema WHERE usuario_id IN
        (SELECT id FROM usuario WHERE empresa_id IN
            (SELECT empresa_id FROM obra WHERE id IN ($obraId, $($obraB.id))))),
    (SELECT json_agg(s ORDER BY obra_id, produto_id) FROM
        (SELECT obra_id, produto_id, quantidade::text FROM estoque
         WHERE obra_id IN ($obraId, $($obraB.id))) s)
)::text
"@

$primeira = Chamar POST '/entradas' $c.engenheiro @{ entrada = $entrada } 201 'engenheiro cria entrada sem nota'
$entradaId = $primeira.id
Conferir ($primeira.usuario_id -eq $engenheiroId) 'ator vem do token'
Conferir ($null -eq $primeira.xml_nota_fiscal) 'entrada dispensa nota fiscal'
Conferir ($primeira.justificativa -eq 'Material recebido sem nota fiscal') 'justificativa fica aparada'
Conferir (@($primeira.itens).Count -eq 1 -and $primeira.itens[0].quantidade -eq '1.25') 'resposta traz o item com quantidade decimal'
VerificarBanco $saldo '1.25' 'upsert cria saldo para produto sem estoque'
VerificarBanco "SELECT COUNT(*)::text FROM item_entrada WHERE entrada_id = $entradaId AND produto_id = $produtoId AND quantidade = 1.25" '1' 'item persistido no banco'
VerificarBanco "SELECT COUNT(*)::text FROM log_sistema WHERE usuario_id = $engenheiroId AND acao = 'ENTRADA_MANUAL entrada=$entradaId obra=$obraId produto=$produtoId quantidade=1.25 saldo=1.25'" '1' 'log registra entrada, obra, produto, quantidade, saldo e ator'

$entrada.itens = @(@{ produto_id = $produtoId; quantidade = 2.75 })
$segunda = Chamar POST '/entradas' $c.master @{ entrada = $entrada } 201 'master soma ao saldo existente'
VerificarBanco $saldo '4.00' 'upsert acumula no saldo existente'
VerificarBanco "SELECT COUNT(*)::text FROM log_sistema WHERE acao = 'ENTRADA_MANUAL entrada=$($segunda.id) obra=$obraId produto=$produtoId quantidade=2.75 saldo=4.00'" '1' 'log usa o saldo acumulado retornado pelo PostgreSQL'
$entrada.itens = @(@{ produto_id = $produtoId; quantidade = 0.01 })
Chamar POST '/entradas' $c.engenheiro @{ entrada = $entrada } 201 'soma um centesimo' | Out-Null
VerificarBanco $saldo '4.01' 'PostgreSQL preserva a precisao decimal'

$antes = (ExecutarBanco -Argumentos @('consultar', $estado)).resultado
Chamar POST '/entradas' $null @{ entrada = $entrada } 401 'sem token nao grava' | Out-Null
Chamar POST '/entradas' $c.pedreiro @{ entrada = $entrada } 403 'pedreiro nao grava' | Out-Null
Chamar POST '/entradas' $c.masterB @{ entrada = $entrada } 404 'outra empresa nao acessa a obra' | Out-Null
foreach ($obra in @($obraB.id, 2147483647)) {
    Chamar POST '/entradas' $c.engenheiro @{ entrada = @{
        obra_id = $obra; justificativa = 'Teste'; itens = $entrada.itens
    } } 404 'obra alheia ou inexistente nao grava' | Out-Null
}
foreach ($produto in @($produtoB.id, 2147483647)) {
    Chamar POST '/entradas' $c.engenheiro @{ entrada = @{
        obra_id = $obraId; justificativa = 'Teste'; itens = @(
            @{ produto_id = $produtoId; quantidade = 1 },
            @{ produto_id = $produto; quantidade = 1 }
        )
    } } 400 'produto alheio ou inexistente impede toda a entrada' | Out-Null
}
foreach ($justificativa in @($null, '', '   ', 123, ('a' * 256))) {
    Chamar POST '/entradas' $c.engenheiro @{ entrada = @{
        obra_id = $obraId; justificativa = $justificativa; itens = $entrada.itens
    } } 400 'justificativa invalida nao grava' | Out-Null
}
foreach ($quantidade in @($null, '1', 0, -1, 0.001, 10000000000)) {
    Chamar POST '/entradas' $c.engenheiro @{ entrada = @{
        obra_id = $obraId; justificativa = 'Teste'
        itens = @(@{ produto_id = $produtoId; quantidade = $quantidade })
    } } 400 'quantidade invalida nao grava' | Out-Null
}
Chamar POST '/entradas' $c.engenheiro @{ entrada = @{
    obra_id = $obraId; justificativa = 'Teste'; itens = @()
} } 400 'lista vazia nao grava' | Out-Null
Chamar POST '/entradas' $c.engenheiro @{ entrada = @{
    obra_id = $obraId; justificativa = 'Teste'; itens = @(
        @{ produto_id = $produtoId; quantidade = 1 },
        @{ produto_id = $produtoId; quantidade = 2 }
    )
} } 400 'produto repetido nao grava' | Out-Null
VerificarBanco $estado $antes 'recusas nao alteram entradas, itens, saldos ou logs de nenhuma empresa'

ExecutarBanco -Argumentos @('estoque', "$obraId", "$segundoId", '9999999999.99') | Out-Null
$antes = (ExecutarBanco -Argumentos @('consultar', $estado)).resultado
Chamar POST '/entradas' $c.engenheiro @{ entrada = @{
    obra_id = $obraId; justificativa = 'Teste de estouro'; itens = @(
        @{ produto_id = $produtoId; quantidade = 1 },
        @{ produto_id = $segundoId; quantidade = 0.01 }
    )
} } 409 'estouro real do saldo no segundo item retorna conflito' | Out-Null
VerificarBanco $estado $antes 'estouro reverte entrada, itens, primeiro saldo e primeiro log'
VerificarBanco $contagem '3' 'entrada que estourou nao foi persistida'
VerificarBanco $registros '3' 'entrada que estourou nao deixou log'

ExecutarBanco -Argumentos @('estoque', "$obraId", "$segundoId", '0') | Out-Null
$itens = @(
    @{ produto_id = $produtoId; quantidade = 0.25 },
    @{ produto_id = $segundoId; quantidade = 0.50 }
)
$simultaneos = 8
Add-Type -AssemblyName System.Net.Http
$cliente = [System.Net.Http.HttpClient]::new()
$cliente.Timeout = [TimeSpan]::FromSeconds(60)
$cliente.DefaultRequestHeaders.Authorization =
    [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $c.engenheiro)
$tarefas = @()
$conteudos = @()
$respostas = @()
try {
    for ($i = 0; $i -lt $simultaneos; $i++) {
        $ordenados = if ($i % 2 -eq 0) { @($itens[0], $itens[1]) } else { @($itens[1], $itens[0]) }
        $json = @{ entrada = @{
            obra_id = $obraId; justificativa = 'Entrada concorrente'; itens = $ordenados
        } } | ConvertTo-Json -Depth 6
        $conteudo = [System.Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, 'application/json')
        $conteudos += $conteudo
        $tarefas += $cliente.PostAsync("$global:BaseUrl/entradas", $conteudo)
    }
    [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tarefas)
    foreach ($tarefa in $tarefas) {
        $resposta = $tarefa.Result
        $respostas += $resposta
        Conferir ([int]$resposta.StatusCode -eq 201) "entrada concorrente conclui sem deadlock (veio $([int]$resposta.StatusCode))"
    }
}
finally {
    foreach ($resposta in $respostas) { $resposta.Dispose() }
    foreach ($conteudo in $conteudos) { $conteudo.Dispose() }
    $cliente.Dispose()
}
VerificarBanco $saldo '6.01' 'somas concorrentes nao perdem atualizacoes'
VerificarBanco "SELECT quantidade::text FROM estoque WHERE obra_id = $obraId AND produto_id = $segundoId" '4.00' 'segundo produto recebe todas as somas concorrentes'
VerificarBanco $contagem '11' 'todas as entradas concorrentes foram persistidas'
VerificarBanco $registros '19' 'cada item confirmado deixa uma linha auditavel'
VerificarBanco "SELECT COUNT(*)::text FROM estoque WHERE obra_id = $obraId" '2' 'constraint mantem um saldo por obra e produto'
VerificarBanco "SELECT COUNT(*)::text FROM estoque WHERE obra_id = $($obraB.id)" '0' 'estoque de outra empresa continua intacto'

FinalizarCaso
