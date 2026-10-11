# API do Constrói

API em Dart Frog com PostgreSQL/Neon.

## Painel

`GET /painel` fornece indicadores e entradas recentes para a tela Figma 02.
Aceita `obra_id` opcional, `limit` (1 a 50, padrão 5) e `offset` (0 a 10000).
Exige autenticação e limita os dados à empresa e às obras permitidas ao perfil.
Valores financeiros ficam disponíveis somente para engenheiro e master.
As fórmulas e limites dos dados estão em `Documentação/Tela de Painel.txt`.
Não requer migration adicional.
Falhas internas registram o tipo, a causa e a pilha no stdout do servidor.
URLs PostgreSQL são omitidas do diagnóstico para não registrar credenciais.
A resposta HTTP 503 continua genérica, sem expor detalhes internos ao app.

## Baixa de estoque em transação (RNF20, card 66)

`PATCH /pedidos/{id}` com `{"pedido":{"status":"aprovado"}}` aprova o pedido
e baixa seus materiais. Exige engenheiro/master e restringe pedido, obra,
solicitante e produtos à empresa autenticada. O GET de detalhe continua igual.
A recusa pertence ao card 65 e pode ser integrada depois no mesmo PATCH.

O serviço `lib/baixa_estoque.dart` bloqueia o pedido com `FOR UPDATE`, exige
status pendente, bloqueia os itens e depois os saldos em ordem de produto.
Quantidades de itens repetidos são somadas no SQL. Aprovação, todas as baixas
e um registro `BAIXA_ESTOQUE` por material em `log_sistema` são confirmados na
mesma transação. O log registra ator, pedido, obra, produto, quantidade, saldo
final e protocolo. Comparação e subtração usam NUMERIC no PostgreSQL.

Pedido inexistente/de outra empresa retorna 404. Pedido sem itens ou com
materiais inválidos retorna 400. Pedido já decidido ou falta de saldo
(inclusive registro ausente) retornam 409. Uma falha em qualquer item, log ou
aprovação reverte tudo; falta de saldo mantém
o pedido pendente. Aprovações concorrentes do mesmo pedido não duplicam a
baixa. Não há nova migration: a proteção `ck_estoque_quantidade` já existe.

Além de `dart test`, há uma suíte explícita de integração com PostgreSQL real
e servidor HTTP local usando o handler e middleware de pedidos. Ela valida
duas requisições realmente bloqueadas ao mesmo tempo no banco, a disputa pelo
último material, reaprovação concorrente, ordem oposta de itens, decimais,
isolamento de empresas, permissões, rollback após falhas injetadas e o CHECK
contra saldo negativo. PGlite não substitui essa validação de concorrência.

Execute na pasta `constroi_api`, com um banco local **descartável** já criado.
A suíte exige host loopback e nome `constroi_test_*`, não lê `.env` e recria
o schema `public` com `Database/schema.sql`; todos os dados desse schema são
apagados. Configuração ausente/inadequada ou falha no banco faz a suíte falhar,
sem pular os cenários.

```powershell
$env:CONSTROI_TEST_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55434/constroi_test_baixa?sslmode=require&max_connection_count=10'
dart test integration_test/baixa_estoque_test.dart --reporter expanded
```

## Migrations

As migrations ficam em `migrations/` e são executadas em ordem numérica. A tabela `schema_migrations` registra cada arquivo aplicado, impedindo a execução duplicada.

- `001_schema_inicial.sql`: tabelas principais
- `002_tabelas_login.sql`: autenticação, sessões e tentativas de login
- `003_catalogo_timestamps.sql`: datas de criação e atualização do catálogo
- `004_usuario_obra.sql`: vínculo histórico da equipe com as obras
- `005_custos_obra.sql`: orçamento, categorias, preços históricos e despesas
- `006_usuario_tipo.sql`: converte o perfil legado `admin` para `master` e restringe os perfis aos níveis aceitos pela API
- `007_corrige_colunas_legadas.sql`: alinha `pedido.protocolo` e as colunas de data com o que a `001` declara, recriando as views de custo
- `008_protege_estoque.sql`: devolve ao `estoque` o `CHECK (quantidade >= 0)` e o `UNIQUE (obra_id, produto_id)` que a `001` declara
- `009_consulta_estoque.sql`: SKU opcional e estoque mínimo por produto, com SKU único por empresa (sem diferenciar maiúsculas)

Crie `constroi_api/.env` a partir de `.env.example`. A conexão remota deve conter `sslmode=require`; nunca envie o `.env` ao GitHub.

O pool abre até 10 conexões. Para mudar, acrescente `max_connection_count` na própria `DATABASE_URL`.

```powershell
cd constroi_api
dart pub get
dart run bin/migrate.dart
```

O arquivo `Database/schema.sql` representa o estado consolidado depois das migrations 001 a 009 e serve para inicializar um banco vazio. Bancos existentes devem ser atualizados exclusivamente pelo executor de migrations.

Para criar uma alteração futura, adicione uma nova migration numerada. Não edite uma migration que já tenha sido aplicada.

## Consulta de estoque (RF05)

Após aplicar a migration 009, `GET /estoque` retorna os saldos das obras acessíveis,
incluindo saldo zero. `obra_id=7` restringe a consulta àquela obra. Uma obra sem registros retorna
`{"estoque": []}`; produtos sem registro de estoque não são inventados na lista.
O acesso exige token de pedreiro ou superior. Pedreiros precisam de vínculo ativo;
engenheiro/master consultam qualquer obra da própria empresa. Sem `obra_id`,
pedreiros veem somente obras com vínculo ativo; gestores veem todas da sua empresa.
Um `obra_id` explícito inexistente, de outra empresa ou sem vínculo permitido
retorna 404. Sem obras acessíveis, a consulta geral retorna lista vazia.
Escrita em `/estoque` retorna 405.

Filtros combináveis:

| Parâmetro | Regra |
|---|---|
| `obra_id` | Opcional; inteiro positivo até 2147483647 |
| `categoria_id` | Opcional; inteiro positivo até 2147483647, filtra `produto.categoria_custo_id` |
| `busca` | Trecho literal do nome ou SKU, sem diferenciar maiúsculas; até 150 caracteres |
| `baixo` | `true` para somente saldo menor ou igual ao mínimo; padrão `false` |
| `limit` | De 1 a 200; padrão 50 |
| `offset` | De 0 a 10000; padrão 0 |

Exemplo: `GET /estoque?obra_id=7&categoria_id=2&busca=CIM&baixo=true&limit=50&offset=0`.
Ordenação por nome/ID do produto, obra e ID do saldo para paginação estável entre obras.
Categorias inexistentes ou sem saldos visíveis retornam lista vazia. Produtos sem
categoria continuam na consulta sem filtro, com os dois campos de categoria nulos.
O contrato usa `produto_nome` (não `nome`) e `categoria_custo_id`/`categoria_nome`.
Retorno:

```json
{"estoque": [{"id": 1, "obra_id": 7, "produto_id": 2, "produto_nome": "Cimento",
  "categoria_custo_id": 2, "categoria_nome": "Cimento e agregados",
  "unidade": "saco", "sku": "CIM-01", "quantidade": "4.50",
  "estoque_minimo": "5.00", "baixo": true}]}
```

Quantidades são strings decimais para preservar a precisão. O cadastro de produto
aceita `sku` e `estoque_minimo` em `POST /produtos` e `PATCH /produtos/{id}`,
restritos a engenheiro/master. SKU tem até 50 caracteres, é aparado e pode ser
removido com `null` ou texto vazio; duplicata na mesma empresa retorna 409.
O mínimo é não negativo, tem até duas casas e máximo 9999999999.99; aceita número
JSON ou string decimal (ponto ou vírgula). Omitir na criação usa zero; no PATCH
preserva o valor. Mínimo `null` é inválido. Ambos aparecem nas respostas de produto.

A regra de mínimo é por produto, compartilhada entre obras da empresa. Produtos
existentes ficam sem SKU e com mínimo zero, marcando baixo apenas saldo zero.
O card backend não inclui a tela Flutter (card separado).

### Testes do contrato de estoque

`dart test` verifica resposta, parâmetros, validação e permissões das rotas.
O teste SQL abaixo também executa as consultas reais da rota em PostgreSQL em
memória, verificando `produto_nome`, categorias, filtros e isolamento entre
obras/empresas. Os dados vêm do SQL, sem respostas previamente montadas por mocks.

```powershell
# Na pasta constroi_api, com Node.js instalado:
npm install --prefix .dart_tool/sql-validation --no-save @electric-sql/pglite@0.5.8
node test/sql/estoque_contract.mjs
```

A dependência fica na pasta ignorada `.dart_tool`, fora do runtime da API.
PGlite não valida TLS/pool do driver Dart nem a integração HTTP; o teste remove
apenas a declaração de extensão pgcrypto, indisponível nesse ambiente.
Para validar a integração com um banco configurado e API em execução, rode a
suíte da pasta `testes/` na raiz do repositório.

```powershell
.\testes\executar.ps1
.\testes\executar.ps1 -Listar
.\testes\executar.ps1 -Caso 14_consulta_de_estoque -Detalhado
```

Cada arquivo em `testes/casos/` é um caso independente: monta o próprio cenário
com uma marca única, roda as asserções e apaga o que criou. Casos não compartilham
dados, então uma falha aponta um defeito real e não contaminação de um caso anterior.
O runner mostra ok/FALHA por caso, lista as asserções quebradas, imprime o comando
para repetir só aquele caso e sai com código 1 se algo falhou. `-SemLimpeza` preserva
os dados no banco e informa as marcas usadas.

O banco é lido de `.env` (ou `DATABASE_ENV_FILE`), da variável `DATABASE_URL` ou do
parâmetro `-DatabaseUrl`, que prevalece sobre o arquivo. Use o mesmo banco da API.
Os casos chamam `dart run bin/testar_banco.dart` para conferir o que a resposta HTTP
não mostra e para preparar saldos/categoria; não precisa de `psql` nem de Node.js.
O preparo é obrigatório: configuração ausente ou falha de conexão encerra a suíte
antes de criar qualquer dado, sem pular caso nem anunciar sucesso.
