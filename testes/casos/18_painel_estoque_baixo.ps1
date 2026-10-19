. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Painel: rupturas e estoque baixo contra o banco'

$c = NovoCenario -ComObra -ComProduto
$obraId = $c.obra.id
$produtoId = $c.produto.id
$rotaPainel = "/painel?obra_id=$obraId"

function Indicadores {
    param([string]$Rota, [string]$Rotulo)
    return (Chamar GET $Rota $c.engenheiro $null 200 $Rotulo).indicadores
}

Chamar PATCH "/produtos/$produtoId" $c.engenheiro @{
    produto = @{ estoque_minimo = '5.00' }
} 200 'configura minimo 5' | Out-Null

ExecutarBanco -Argumentos @('estoque', "$obraId", "$produtoId", '5') | Out-Null
$igual = Indicadores $rotaPainel 'painel com saldo igual ao minimo'
Conferir ([int]$igual.estoque_baixo -eq 1) "saldo igual ao minimo conta como baixo (veio $($igual.estoque_baixo))"
Conferir ([int]$igual.rupturas_criticas -eq 0) "saldo igual ao minimo nao e ruptura (veio $($igual.rupturas_criticas))"

ExecutarBanco -Argumentos @('estoque', "$obraId", "$produtoId", '6') | Out-Null
$acima = Indicadores $rotaPainel 'painel com saldo um acima do minimo'
Conferir ([int]$acima.estoque_baixo -eq 0) "saldo um acima do minimo nao conta (veio $($acima.estoque_baixo))"
Conferir ([int]$acima.rupturas_criticas -eq 0) "saldo acima do minimo nao e ruptura (veio $($acima.rupturas_criticas))"

ExecutarBanco -Argumentos @('estoque', "$obraId", "$produtoId", '0') | Out-Null
$zerado = Indicadores $rotaPainel 'painel com saldo zero'
Conferir ([int]$zerado.estoque_baixo -eq 1) "saldo zero conta como baixo (veio $($zerado.estoque_baixo))"
Conferir ([int]$zerado.rupturas_criticas -eq 1) "saldo zero conta como ruptura (veio $($zerado.rupturas_criticas))"

$segunda = Chamar POST '/obras' $c.engenheiro @{
    obra = @{ nome = "Obra Beta $($c.marca)"; endereco = 'Rua de teste, 456'; status = 'ativa' }
} 201 'cria segunda obra'
ExecutarBanco -Argumentos @('estoque', "$($segunda.id)", "$produtoId", '0') | Out-Null
$geral = Indicadores '/painel' 'painel com todas as obras'
Conferir ([int]$geral.total_itens -eq 1) "total de itens conta o produto uma vez (veio $($geral.total_itens))"
Conferir ([int]$geral.estoque_baixo -eq 2) "estoque baixo conta por obra (veio $($geral.estoque_baixo))"
Conferir ([int]$geral.rupturas_criticas -eq 2) "rupturas contam por obra (veio $($geral.rupturas_criticas))"

FinalizarCaso
