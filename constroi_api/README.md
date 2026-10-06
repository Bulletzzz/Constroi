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

Crie `constroi_api/.env` a partir de `.env.example`. A conexão remota deve conter `sslmode=require`; nunca envie o `.env` ao GitHub.

O pool abre até 10 conexões. Para mudar, acrescente `max_connection_count` na própria `DATABASE_URL`.

```powershell
cd constroi_api
dart pub get
dart run bin/migrate.dart
```

O arquivo `Database/schema.sql` representa o estado consolidado depois das migrations 001 a 006 e serve para inicializar um banco vazio. Bancos existentes devem ser atualizados exclusivamente pelo executor de migrations.

Para criar uma alteração futura, adicione uma nova migration numerada. Não edite uma migration que já tenha sido aplicada.
