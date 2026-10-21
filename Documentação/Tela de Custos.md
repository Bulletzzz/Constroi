# Tela de Custos — Figma 06

Implementa a consulta de custos em `/custos`, disponível para engenheiro e master.
A modelagem já estava definida na migration `005_custos_obra.sql`; não há nova
migration nem alteração de preços históricos.

## Contrato da API

`GET /custos` usa a empresa do token. Pedreiro recebe 403 e a ausência de token
recebe 401. Uma obra inexistente ou de outra empresa recebe 404.

Filtros opcionais:

- `obra_id`: inteiro positivo; omitido, consulta todas as obras da empresa.
- `periodo`: `total` (padrão), `mes` ou `semana`.
- `limit`: de 1 a 100, padrão 20; `offset`: inteiro de 0 a 2147483647.

Mês e semana começam à meia-noite em `America/Sao_Paulo`; a semana começa na
segunda-feira. Os filtros se aplicam ao custo do período, às categorias e aos
lançamentos. Orçamento, saldo e percentual consumido sempre consideram o custo
acumulado de todo o histórico, com essa distinção indicada na tela.

A resposta traz `obras`, `obra_id`, `periodo`, `resumo`, `totais_por_obra`,
`categorias`, `lancamentos` e `paginacao` (`limite`, `offset`, `tem_mais`).
Valores monetários são decimais em texto. Os totais são calculados antes da
paginação, no mesmo snapshot dos lançamentos. A tela formata os valores em reais
sem converter dinheiro para ponto flutuante.

Falhas de consulta retornam 503 com mensagem genérica. O log do servidor preserva
a causa e a pilha do erro, removendo URLs de conexão PostgreSQL.

O cálculo usa `vw_lancamento_custo` e `vw_resumo_custo_obra`: compras com preço
histórico mais despesas, sem duplicar saídas de estoque. Entradas sem preço não
entram no custo; a quantidade dessas pendências aparece na tela. Se alguma obra
selecionada não tiver orçamento, o orçamento consolidado e o saldo ficam nulos.
Orçamento zero é preservado; o percentual fica nulo para evitar divisão por zero.

## Interface

Segue a estrutura do Figma 06: cabeçalho e navegação existentes, seleção de obra,
período, custo destacado, orçamento com barra, categorias e lançamentos. Inclui
totais por obra na visão consolidada, carregamento, erro com nova tentativa,
atualização ao puxar e estado vazio. Respostas atrasadas não substituem o filtro
atual. Falha na próxima página preserva os lançamentos já carregados.

Não exibe valores fictícios de comparação mensal. A lista identifica os lançamentos
do período em ordem de data, com paginação, em vez de rotulá-los como “maiores saídas”.

## Validação

Na pasta `constroi_api`: `dart test test/routes/custos_test.dart`.
Na pasta `constroi_app`: `flutter test test/custos_test.dart test/navigation_test.dart`.
Os testes cobrem acesso, filtros, paginação, diagnóstico de falhas sem expor URLs
de conexão, navegação, troca de obra/período, respostas atrasadas e seletores
semânticos. O layout é verificado com fonte ampliada em 320×640, 844×390 e
1280×800. Os identificadores usados pelo Cypress estão em
[`docs/casos-de-teste.md`](../docs/casos-de-teste.md).
