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

## Aprovação de pedido (RNF20)

`POST /pedidos/{id}/aprovar` é restrito a engenheiro e master. Na mesma transação, a rota
trava o pedido e as linhas de estoque da obra com `SELECT ... FOR UPDATE`, confere o saldo,
dá baixa, marca o pedido como `aprovado` e grava uma linha em `log_sistema` por item.
Sem saldo, responde 409 com a lista `faltando`, e o pedido continua `pendente`.
O `CHECK (quantidade >= 0)` do estoque é a última barreira e também vira 409.

O teste de concorrência roda contra um Postgres descartável, porque recria o schema:

```sh
TESTE_DATABASE_URL=postgres://postgres:senha@localhost:5432/constroi dart test test/integracao
```

Sem a variável, o teste é pulado. Nunca aponte para o Neon.

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

Crie `constroi_api/.env` a partir de `.env.example`. A conexão remota deve conter `sslmode=require`; nunca envie o `.env` ao GitHub.

O pool abre até 10 conexões. Para mudar, acrescente `max_connection_count` na própria `DATABASE_URL`.

```powershell
cd constroi_api
dart pub get
dart run bin/migrate.dart
```

O arquivo `Database/schema.sql` representa o estado consolidado depois das migrations 001 a 006 e serve para inicializar um banco vazio. Bancos existentes devem ser atualizados exclusivamente pelo executor de migrations.

Para criar uma alteração futura, adicione uma nova migration numerada. Não edite uma migration que já tenha sido aplicada.
