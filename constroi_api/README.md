# API do Constrói

API em Dart Frog com PostgreSQL/Neon.

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
Para validar a integração com um banco configurado e API em execução, rode
`./testar_rotas.ps1 -BaseUrl http://localhost:8080`.
O banco é lido de `.env` (ou `DATABASE_ENV_FILE`), da variável `DATABASE_URL`
ou do parâmetro `-DatabaseUrl`, que prevalece sobre o arquivo. Use o mesmo banco
da API. O runner chama `dart run bin/testar_banco.dart` para verificar os vínculos
e preparar saldos/categoria, usando o driver já instalado para as migrations;
não precisa de `psql` nem de Node.js para a suíte HTTP.

O preparo é obrigatório: configuração ausente, falha de conexão ou de SQL
encerra a suíte com erro, sem pular os casos de estoque nem anunciar sucesso.
O cenário usa um pedreiro próprio, saldo igual ao mínimo (5) e depois acima dele
(6), verificando nome, unidade, SKU, mínimo, indicador de estoque baixo, categoria
com acentos, filtros e encerramento do vínculo. O helper limita o preparo à
obra/produto informados e exige que pertençam à mesma empresa.
