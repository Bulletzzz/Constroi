. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'Autenticacao e hierarquia de permissao'

$c = NovoCenario -ComUsuarios -ComObra -ComProduto
$marca = $c.marca

Chamar GET '/eu' $null $null 401 'sem token' | Out-Null
Chamar GET '/eu' 'token-adulterado' $null 401 'token invalido' | Out-Null
Chamar GET '/eu' 'Bearer' $null 401 'token vazio' | Out-Null

Chamar POST '/login' $null @{ email = "master.$marca@teste.com"; senha = 'errada' } 401 'senha errada' | Out-Null
Chamar POST '/login' $null @{ email = "ninguem.$marca@teste.com"; senha = $global:SenhaPadrao } 401 'email inexistente' | Out-Null
Chamar POST '/login' $null @{ email = "master.$marca@teste.com" } 400 'corpo incompleto' | Out-Null
Chamar POST '/login' $null @{} 400 'corpo vazio' | Out-Null

Chamar GET '/produtos' $c.pedreiro $null 200 'pedreiro le o catalogo para requisitar' | Out-Null
Chamar POST '/produtos' $c.pedreiro @{ produto = @{ nome = 'X'; unidade = 'un' } } 403 'pedreiro nao cadastra produto' | Out-Null
Chamar GET '/usuarios' $c.engenheiro $null 403 'engenheiro nao le usuarios' | Out-Null
Chamar GET '/produtos' $c.engenheiro $null 200 'engenheiro le produtos' | Out-Null
Chamar GET '/usuarios' $c.master $null 200 'master le usuarios' | Out-Null
Chamar GET '/produtos' $c.master $null 200 'master alcanca nivel de engenheiro' | Out-Null

$eu = Chamar GET '/eu' $c.master $null 200 'GET /eu nao vaza senha'
Conferir ($null -eq $eu.senha -and $null -eq $eu.senha_hash) 'resposta de /eu nao traz hash de senha'

# Varredura de papel: cada grupo de rotas so aceita quem alcanca o nivel minimo.
# custos, emprestimos, entradas e equipamentos exigem engenheiro; logs exige master.
Chamar GET '/custos' $c.pedreiro $null 403 'pedreiro nao le custos' | Out-Null
Chamar GET '/custos' $c.engenheiro $null 200 'engenheiro le custos' | Out-Null

Chamar POST '/custos/despesas' $c.pedreiro @{
    despesa = @{ obra_id = $c.obra.id; categoria_custo_id = 1; descricao = 'X'; valor = '1.00' }
} 403 'pedreiro nao lanca despesa' | Out-Null

Chamar GET '/emprestimos' $c.pedreiro $null 403 'pedreiro nao le emprestimos' | Out-Null
Chamar GET '/emprestimos' $c.engenheiro $null 200 'engenheiro le emprestimos' | Out-Null

Chamar POST '/entradas' $c.pedreiro @{
    entrada = @{ obra_id = $c.obra.id; justificativa = 'X'; itens = @(@{ produto_id = $c.produto.id; quantidade = 1 }) }
} 403 'pedreiro nao registra entrada' | Out-Null

Chamar GET '/equipamentos' $c.pedreiro $null 403 'pedreiro nao le equipamentos' | Out-Null
Chamar GET '/equipamentos' $c.engenheiro $null 200 'engenheiro le equipamentos' | Out-Null

Chamar GET '/logs' $c.pedreiro $null 403 'pedreiro nao le logs' | Out-Null
Chamar GET '/logs' $c.engenheiro $null 403 'engenheiro nao le logs' | Out-Null
Chamar GET '/logs' $c.master $null 200 'master le logs' | Out-Null

# Leitura de chao de obra continua liberada para o pedreiro.
Chamar GET '/estoque' $c.pedreiro $null 200 'pedreiro le estoque' | Out-Null
Chamar GET '/painel' $c.pedreiro $null 200 'pedreiro le painel' | Out-Null
Chamar GET '/categorias' $c.pedreiro $null 200 'pedreiro le categorias' | Out-Null
Chamar GET '/pedidos' $c.pedreiro $null 200 'pedreiro le os proprios pedidos' | Out-Null

# Token de outro papel nao vira master trocando o corpo.
Chamar POST '/usuarios' $c.engenheiro @{
    usuario = @{ nome = 'Intruso'; email = "intruso.$($c.marca)@teste.com"; senha = $global:SenhaPadrao; tipo = 'master' }
} 403 'engenheiro nao cria master' | Out-Null
VerificarBanco "SELECT COUNT(*)::text FROM usuario WHERE email = 'intruso.$($c.marca)@teste.com'" '0' `
    'nenhum usuario foi criado pela tentativa'

FinalizarCaso
