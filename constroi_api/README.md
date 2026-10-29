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
solicitante e produtos à empresa autenticada.

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
baixa. A proteção `ck_estoque_quantidade` já existe.

## Auditoria estruturada das baixas (card 83)

A migration `013_movimentacao_estoque.sql` cria um movimento `saida_pedido`
por produto/pedido aprovado. A gravação ocorre no mesmo `runTx` da baixa,
depois do UPDATE condicionado ao saldo, mantendo locks ordenados e agregação
de itens repetidos. Falha no movimento reverte saldos, logs e aprovação.
Reaprovação continua retornando 409, sem duplicar registros.

O movimento guarda empresa/obra/pedido, aprovador autenticado, quantidade,
saldos anterior/posterior e cópias de nome, unidade e protocolo. Os decimais
são calculados no PostgreSQL; a data vem de `clock_timestamp()` do banco.
FKs compostas impedem vínculos entre empresas ou com outra obra do pedido;
ON DELETE RESTRICT preserva o histórico. Checks rejeitam quantidades inválidas,
NaN, saldos negativos/inconsistentes e tipos fora deste escopo.

Os logs `BAIXA_ESTOQUE` continuam intactos, inclusive os anteriores à mudança.
Não há backfill: os logs antigos não permitem reconstruir os saldos históricos.
Esta entrega não inclui entradas, ajustes, estornos, telas ou endpoint de relatório.
Os índices preparam consultas por empresa, obra, produto e aprovador no período.
Não some quantidades de unidades diferentes nem movimentos e logs legados juntos.

Antes de ativar o escritor em cada ambiente autorizado, aplique a migration
com o dono das migrations e valide a conexão restrita conforme
[infra-auditoria.md](../docs/infra-auditoria.md). Os privilégios padrão desse
mesmo dono concedem INSERT/SELECT à tabela nova; reexecute o roteiro e o
diagnóstico para conferir ausência de UPDATE/DELETE/TRUNCATE no runtime.
Não altere a flag/credencial ativa sem o rollout combinado com a equipe.

Na implantação, retire os escritores antigos e registre a versão e o horário
do banco a partir do qual todos os aprovadores usam o novo código. Essa é a
cobertura inicial da auditoria, não a data da criação da tabela nem uma
reconstrução dos logs antigos. Ausência de movimentos antes desse marco não
significa ausência de saídas. Um relatório fechado futuro ainda depende da
validação efetiva do limite total de transação e da margem da infraestrutura.

Validação local, com a mesma URL descartável descrita abaixo:

```powershell
dart test integration_test/auditoria_estoque_test.dart --reporter expanded
dart test integration_test/baixa_estoque_test.dart --reporter expanded
dart test integration_test/infra_auditoria_test.dart --reporter expanded
```

Rode essas suítes em sequência, pois recriam o schema compartilhado. Elas
comparam migration/schema consolidado, migram banco com histórico sem backfill,
verificam constraints e permissões reais, oito aprovações disputando saldo 1
(um 200/sete 409/um log/um movimento), reaprovação, decimais e rollback após
falha no segundo movimento. A suíte de infraestrutura define sua senha
descartável apenas no teste, permitindo autenticação SCRAM sem senha no SQL
de provisionamento.

## Aprovar e recusar pedido (RF07, card 65)

O mesmo `PATCH /pedidos/{id}` aceita
`{"pedido":{"status":"recusado","justificativa":"Material desnecessário"}}`.
A justificativa da recusa é obrigatória, aparada e limitada a 255 caracteres;
ausência, texto vazio, tipo inválido ou tamanho excedido retornam 400.
A permissão usa o middleware `exigirNivel(Nivel.engenheiro)` no PATCH desta rota,
mantendo GET e POST disponíveis ao pedreiro conforme as regras existentes.

A migration `010_justificativa_recusa.sql` acrescenta `pedido.justificativa_recusa`.
O motivo enviado na recusa fica nesse campo, preservando `pedido.justificativa`,
que contém o motivo original da solicitação. Os dois campos aparecem nas
respostas de criação, decisão, listagem e detalhe.

A recusa bloqueia o pedido com `FOR UPDATE OF p`, exige status pendente e grava
status, justificativa da recusa e log `RECUSA_PEDIDO` na mesma transação.
O log identifica o usuário autenticado, pedido, obra e protocolo; o motivo
completo fica no pedido. A recusa não altera o estoque nem depende de saldo.
Pedido inexistente/de outra empresa retorna 404 e pedido já decidido retorna 409.
Recusas concorrentes e disputa entre aprovação e recusa confirmam uma única
decisão. Uma falha no log reverte também o status e a justificativa da recusa.
A aprovação continua usando `aprovarPedidoComBaixa` e seus logs `BAIXA_ESTOQUE`.

Execute também `..\testes\executar.ps1 -Caso 17_recusa_de_pedido`, com a API em
execução e o banco atualizado pela migration 010.

Além de `dart test`, há uma suíte explícita de integração com PostgreSQL real
e servidor HTTP local usando o handler e middleware de pedidos. Ela valida
duas requisições realmente bloqueadas ao mesmo tempo no banco, a disputa pelo
último material, reaprovação concorrente, ordem oposta de itens, decimais,
isolamento de empresas, permissões, recusa, disputa entre decisões,
rollback após falhas injetadas e o CHECK
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

## Integração com PostgreSQL local e TLS

`dart test` coleta apenas `test/`. Os testes em `integration_test/` precisam
ser chamados explicitamente e usam um PostgreSQL **local descartável**, com
banco chamado `constroi_test_*`. Eles apagam e recriam o schema `public`.
Não use a conexão do Neon ou o banco de desenvolvimento com dados importantes.

O PostgreSQL precisa aceitar **TLS**, e a URL precisa conter `sslmode=require`
(ou `verify-full` com certificado confiável). Acrescentar o parâmetro à URL
não habilita TLS no servidor. Um `postgres:17` sem configuração de certificado
não atende esse requisito. O exemplo abaixo usa a
[imagem oficial](https://github.com/docker-library/postgres/blob/master/17/bookworm/Dockerfile),
certificado autoassinado e senha exclusivos do teste local.

Com Docker em execução, rode em PowerShell (a porta 55435 deve estar livre):

```powershell
$iniciarPostgres = @'
command -v openssl >/dev/null || {
  apt-get update
  apt-get install -y --no-install-recommends openssl
}
install -d -m 700 -o postgres -g postgres /tmp/constroi-tls
openssl req -x509 -nodes -newkey rsa:2048 -days 7 -subj /CN=localhost \
  -keyout /tmp/constroi-tls/server.key -out /tmp/constroi-tls/server.crt
chown postgres:postgres /tmp/constroi-tls/server.key /tmp/constroi-tls/server.crt
chmod 600 /tmp/constroi-tls/server.key
exec docker-entrypoint.sh postgres -c ssl=on \
  -c ssl_cert_file=/tmp/constroi-tls/server.crt \
  -c ssl_key_file=/tmp/constroi-tls/server.key
'@

docker run --detach --name constroi-testes-pg `
  --publish 127.0.0.1:55435:5432 `
  --env POSTGRES_PASSWORD=senha-local-descartavel `
  --env POSTGRES_DB=constroi_test_integracao `
  postgres:17-bookworm bash -ceu $iniciarPostgres
```

Aguarde a inicialização (a primeira execução pode instalar o OpenSSL). Confira
`docker logs constroi-testes-pg` se houver falha. O primeiro comando abaixo deve
indicar que aceita conexões; o segundo deve retornar `ssl = t`, comprovando uma
conexão TCP com TLS, antes de executar os testes:

```powershell
docker exec constroi-testes-pg pg_isready -h 127.0.0.1 -U postgres -d constroi_test_integracao
docker exec --env PGPASSWORD=senha-local-descartavel constroi-testes-pg `
  psql 'host=127.0.0.1 user=postgres dbname=constroi_test_integracao sslmode=require' `
  -c 'SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();'
```

Na pasta `constroi_api`, instale as dependências e execute:

```powershell
dart pub get
$env:CONSTROI_TEST_DATABASE_URL = 'postgresql://postgres:senha-local-descartavel@127.0.0.1:55435/constroi_test_integracao?sslmode=require&max_connection_count=10'

# Todas as suítes, uma por vez: elas compartilham e recriam o mesmo schema.
dart test integration_test/ --concurrency=1 --reporter expanded

# Somente infraestrutura, incluindo a regressão de senha SCRAM/TLS.
dart test integration_test/infra_auditoria_test.dart --reporter expanded

# Somente a regressão da migration 011 (3 cenários).
dart test integration_test/migrations_nfe_test.dart --reporter expanded
```

Nesta revisão, a execução completa reúne **90 cenários** de integração:

| Suíte | Cenários |
|---|---:|
| `auditoria_estoque_test.dart` | 30 |
| `baixa_estoque_test.dart` | 26 |
| `infra_auditoria_test.dart` | 15 |
| `migrations_nfe_test.dart` | 3 |
| `nfe_test.dart` | 16 |

O total de 56 da PR #30 corresponde à revisão anterior à auditoria estruturada
e às novas regressões. Confira o total do checkout em teste, incluindo os 15
cenários da infraestrutura: falha no `setUpAll` não conta como suíte executada.

`infra_auditoria_test.dart` aplica `auditoria_papeis.sql` e, no `setUpAll`, gera
uma senha aleatória para o papel de teste. `ALTER ROLE ... PASSWORD` é executado
com `password_encryption=scram-sha-256` apenas nessa transação; a URL restrita
inclui essa senha. A regressão confere o verificador SCRAM e a conexão TLS do
papel real. A senha não é impressa nem adicionada ao SQL de provisionamento.
O mesmo preparo atende PostgreSQL com SCRAM (como o container acima) e trust.

Mantenha `max_connection_count=10`: os cenários de concorrência precisam de mais
de uma conexão. O teste de migrations remove essa opção somente da conexão
direta e do ambiente do runner, mantendo TLS. A suíte verifica schema consolidado
seguido do runner, reaplicação da 011 preservando XML/dados e aplicação em banco
vazio seguida de uma segunda rodada sem alterações.
Para encerrar e apagar **somente** o container e seu volume descartável:

```powershell
docker rm --force --volumes constroi-testes-pg
Remove-Item Env:CONSTROI_TEST_DATABASE_URL
```

## Requisição de material (RF06, Figma 04)

`POST /pedidos` aceita dois campos opcionais além dos itens:

| Campo | Regra |
|---|---|
| `local_obra` | Texto de 1 a 120 caracteres, aparado; `null` quando omitido |
| `urgencia` | `padrao` ou `urgente`; assume `padrao` quando omitido |

Os dois voltam em `GET /pedidos`, `GET /pedidos/{id}` e na resposta da aprovação.

A listagem aceita `com_itens=true`, que acrescenta os itens de cada pedido numa única
consulta extra, em vez de uma por pedido. Sem o parâmetro o corpo permanece como era,
para quem só precisa de status e protocolo não pagar pelo peso dos itens. Valor
diferente de `true` ou `false` retorna 400. `solicitante_nome` e `obra_nome` vêm sempre,
porque saem das tabelas já associadas e não custam consulta nem linha adicional.
Urgência fora da lista, local vazio ou acima do limite retornam 400 sem gravar nada.
Acrescentar níveis de urgência é só alterar o CHECK da migration em uma nova.

A leitura do catálogo passou a exigir apenas nível de pedreiro: quem requisita
precisa escolher o material. Criar, editar e remover produto continuam exigindo
engenheiro. A mudança está no `routes/produtos/_middleware.dart`, que decide o
nível pelo método da requisição.

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
- `010_justificativa_recusa.sql`: motivo da recusa separado da justificativa original do pedido
- `011_entrada_nfe.sql`: chave da NF-e única por empresa e vínculo com a obra da empresa; entradas antigas permanecem intactas
- `012_pedido_local_urgencia.sql`: local da obra e nível de urgência no pedido, com urgência restrita a `padrao` ou `urgente`
- `013_movimentacao_estoque.sql`: auditoria das saídas por aprovação, FKs compostas, unicidade por pedido/produto/tipo e índices de período

Crie `constroi_api/.env` a partir de `.env.example`. A conexão remota deve conter `sslmode=require`; nunca envie o `.env` ao GitHub.
`AUDITORIA_CONEXAO_ESTRITA` vem desligada por padrão, preservando a conexão
atual. Ative com `true` somente depois de provisionar e validar o papel restrito,
permissões e limites com a equipe, conforme
[infra-auditoria.md](../docs/infra-auditoria.md).
Aceita `true`/`false` sem diferenciar maiúsculas e com espaços nas bordas;
outros valores, inclusive vazio, geram erro de configuração.

O pool abre até 10 conexões. Para mudar, acrescente `max_connection_count` na própria `DATABASE_URL`.
Com a flag ligada, o máximo aceito é 50 e o servidor exige PostgreSQL 17+,
endpoint direto e papel restrito com timeout provisionado. Nesse modo, as
transações têm limite máximo de 30 segundos e margem publicada de 31 segundos
para o futuro fechamento dos relatórios. A configuração é validada em cada
conexão física. Com a flag desligada, essas garantias ainda não estão ativas.

```powershell
cd constroi_api
dart pub get
# Crie .env.migrations a partir de .env.migrations.example e configure
# MIGRATION_DATABASE_URL com o papel privilegiado, separado da API.
dart run bin/migrate.dart
```

O arquivo `Database/schema.sql` representa o estado consolidado das migrations listadas acima e serve para inicializar um banco vazio. Bancos existentes devem ser atualizados exclusivamente pelo executor de migrations.

Para criar uma alteração futura, adicione uma nova migration numerada. Não edite uma migration que já tenha sido aplicada.

A única exceção é a migration que falha ao rodar em banco vazio mas já está registrada em todos os ambientes: nesse caso a correção não muda o estado final do schema nem afeta banco existente, porque o arquivo não volta a rodar onde já foi aplicado. Explique o motivo no PR e comprove com uma execução a partir de banco vazio. Qualquer alteração que mude o schema resultante exige migration nova, sem exceção.

Para conferir o caminho de banco novo, use um PostgreSQL local descartável com
TLS, aponte `MIGRATION_DATABASE_URL` para ele e rode `dart run bin/migrate.dart`
duas vezes: a primeira aplica todas, a segunda não aplica nenhuma. O arquivo
padrão é `.env.migrations`, alterável por `MIGRATION_ENV_FILE`. Não há fallback
para `.env`, `DATABASE_ENV_FILE` ou `DATABASE_URL`.

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

### Gravação e consulta de logs (card 87)

`GET /logs` exige token de **master** (401 sem autenticação, 403 para os outros
perfis). Retorna somente eventos da empresa da sessão, inclusive os de
usuários inativos. O ID da empresa e o autor das escritas vêm da autenticação.

| Parâmetro | Regra |
|---|---|
| `usuario_id` | Inteiro positivo até 2147483647; usuário ausente ou de outra empresa retorna lista vazia |
| `data_inicio` | Limite inclusivo; `AAAA-MM-DD` em America/Sao_Paulo ou ISO 8601 com fuso explícito |
| `data_fim` | Limite exclusivo, no mesmo formato; deve ser posterior ao início |
| `limit` | Padrão 50, de 1 a 200 |
| `offset` | Padrão 0, de 0 a 10000 |

Exemplo: `GET /logs?usuario_id=7&data_inicio=2026-10-01&data_fim=2026-11-01&limit=50&offset=0`.
Datas sem horário representam a meia-noite em `America/Sao_Paulo`, conforme
as regras IANA do PostgreSQL (inclusive horário de verão histórico), como na
consulta de custos. `2026-10-29` a `2026-10-30` cobre de 29/10 00:00 até
30/10 00:00 em São Paulo, ou 29/10 03:00Z a 30/10 03:00Z.
Para um instante com horário, informe o fuso, como `2026-10-01T00:00:00-03:00`;
encode o sinal `+` como `%2B` quando usar um fuso positivo na URL.
Datas inexistentes, horários sem fuso, intervalos invertidos e limites inválidos
retornam 400. Os filtros podem ser combinados ou usados individualmente.

```json
{
  "logs": [
    {"id": 12, "usuario_id": 7,
     "acao": "ALTERACAO_PRODUTO produto=2", "data": "2026-10-29T12:00:00.000Z"}
  ],
  "paginacao": {"limit": 50, "offset": 0, "tem_mais": false}
}
```

A ordem é `data DESC, id DESC`, com datas de saída em UTC. `tem_mais` indica
se há uma próxima página no momento da consulta. Como a paginação usa offset,
novas gravações entre consultas podem deslocar as páginas; não é um relatório
de período fechado nem uma fotografia imutável.

Todas as escritas de negócio passam por `lib/logs.dart`, na mesma transação
da alteração. Falha no log reverte a escrita; validações, 404 e conflitos não
geram eventos de sucesso. A migration **014_log_empresa.sql** preenche
`empresa_id` nos logs existentes a partir do autor, preservando ID, texto e
instante; torna a empresa obrigatória e vincula `(usuario_id, empresa_id)` ao
usuário por FK composta. O helper obtém a empresa no banco, a partir do autor.
A 014 também pode ser reaplicada: preserva empresas já preenchidas, restaura
a FK e recria os índices ausentes sem alterar o histórico existente.
Os índices `(empresa_id, data DESC, id DESC)` e
`(empresa_id, usuario_id, data DESC, id DESC)` atendem a consulta padrão e a
consulta por usuário, respectivamente. A listagem não faz JOIN nem retorna
`usuario_nome`; o identificador do autor é `usuario_id`.

Na implantação, interrompa as escritas durante a aplicação da 014 e a troca
para esta versão da API: a versão antiga ainda insere sem `empresa_id` e a
nova exige a coluna. Execute o runner pelo ambiente exclusivo de migrations,
valide a versão registrada e retome com o novo código. Nenhuma migration é
aplicada automaticamente ao abrir o PR.

| Operação | Evento |
|---|---|
| Cadastro público de empresa e primeiro master | `CRIACAO_EMPRESA` (autor: master recém-criado) |
| Login válido | `LOGIN` |
| Criação/edição de usuário; inativação | `CRIACAO_USUARIO`, `ALTERACAO_USUARIO`, `INATIVACAO_USUARIO` |
| Criação/edição de produto | `CRIACAO_PRODUTO`, `ALTERACAO_PRODUTO` |
| Criação/edição de equipamento | `CRIACAO_EQUIPAMENTO`, `ALTERACAO_EQUIPAMENTO` |
| Criação/edição de obra | `CRIACAO_OBRA`, `ALTERACAO_OBRA` |
| Vincular/encerrar vínculo na equipe | `VINCULO_EQUIPE`, `ENCERRAMENTO_EQUIPE` |
| Criar pedido | `CRIACAO_PEDIDO` |
| Aprovar/recusar pedido | `BAIXA_ESTOQUE` por produto, `RECUSA_PEDIDO` (textos existentes preservados) |
| Importar/anexar NF-e | `ENTRADA_NFE`, `ANEXO_NFE` (textos existentes preservados) |

O helper recebe mensagens construídas pelo servidor com evento e IDs, sem
copiar corpo da requisição, senhas, hashes, tokens ou XML. Tentativas de login
malsucedidas continuam em `tentativa_login`, inclusive para e-mails inexistentes
(que não têm `usuario_id` para `log_sistema`). Consultas não geram novos logs.
A auditoria estruturada em `movimentacao_estoque` continua sendo gravada pela
baixa de estoque, sem reconstruir histórico anterior à ativação destes eventos.

`integration_test/logs_test.dart` exercita HTTP, middlewares e SQL reais:
perfis, empresas, filtros, paginação, rotas de escrita, ausência de segredos e
rollback forçando falha na inserção do log. Inclui os limites do dia em São
Paulo, a preservação de instantes com fuso explícito e o verão histórico.
`integration_test/migrations_logs_test.dart` confere upgrade com histórico,
instalação vazia, equivalência do schema consolidado, reaplicação da 014 com
restauração de índices/FK e preservação integral dos logs, FK entre empresas e
EXPLAIN ANALYZE das consultas reais com 50 mil registros, sem forçar o planner.
As evidências de plano ficam em `.dart_tool/logs-review46-explain.json`.
Usa o banco **local descartável**
`constroi_test_*` configurado em `CONSTROI_TEST_DATABASE_URL`, nunca o `.env`.
Para executar junto às demais suítes destrutivas, mantenha `--concurrency=1`:

```powershell
dart test test/
dart test integration_test/ --concurrency=1
```
