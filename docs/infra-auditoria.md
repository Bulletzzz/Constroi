# Conexões e limite de transação da auditoria — card 84

Esta entrega prepara o provisionamento e a validação. A troca das conexões no
Neon/Docker deve ser combinada com a equipe e validada em branch de homologação
antes de alterar o ambiente compartilhado. Não modifica a conexão ativa ao rodar
tests/build nem habilita relatórios. A tabela da auditoria é criada pela
migration 013 do card 83, aplicada pelo dono das migrations.

## Ativação gradual

`AUDITORIA_CONEXAO_ESTRITA` fica **desligada por padrão** quando ausente ou `false`,
inclusive no Compose. Nesse estado, a API mantém o contrato atual de conexão,
com TLS e pool de 10 conexões por padrão: aceita a credencial existente, sem
exigir o novo papel, PostgreSQL 17+, endpoint direto ou timeout provisionado.
Não instala o guard nem altera `transaction_timeout` da sessão. Portanto, o
limite de 30 s e a margem de 31 s ainda não estão garantidos para relatórios.

Após provisionar e validar cada ambiente com a equipe, configure
`AUDITORIA_CONEXAO_ESTRITA=true` junto da `DATABASE_URL` restrita e reinicie a
API. A flag aceita `true`/`false` sem diferenciar maiúsculas e ignora espaços nas
bordas. Valores diferentes, inclusive `1`, `0`, texto vazio ou somente espaços,
geram erro de configuração com o nome da variável, sem expor o valor informado.
`TRUE` habilita as mesmas verificações; um valor inválido impede o uso do pool
em vez de desligar a proteção silenciosamente.
`DATABASE_TRANSACTION_TIMEOUT_MS` só é usado nesse modo. O diagnóstico
`bin/verificar_auditoria.dart` sempre faz a validação estrita, mesmo com a flag
desligada, para testar a configuração candidata antes de ativá-la no runtime.

## Papéis, ambientes e segredos

- `DATABASE_URL` no modo estrito: conexão direta como `constroi_api_execucao`, sem
  administração, ownership ou possibilidade de assumir o papel de migrations.
- `MIGRATION_DATABASE_URL`: conexão direta do dono das migrations, somente no
  job/terminal de manutenção. O runner usa `.env.migrations` ou o arquivo indicado
  por `MIGRATION_ENV_FILE`; não carrega o `.env` da API e não tem fallback.
- Copie `.env.example` para `.env` e `.env.migrations.example` para
  `.env.migrations`. Preencha cada segredo pelo cofre do ambiente. Os arquivos
  reais são ignorados pelo Git e excluídos do contexto Docker (`.env*`).

`Database/infra/auditoria_papeis.sql` é um roteiro manual, fora do executor de
migrations. Executado como o mesmo dono que aplicará migrations, cria o papel
limitado sem senha, configura o timeout por banco e concede CRUD nas tabelas
atuais, exceto alteração/exclusão da auditoria e escrita no controle de migrations.
Não transfere ownership. Revoga CREATE de PUBLIC no banco/schema: coordene esse
efeito com quem mantém o ambiente. Para tabela de auditoria existente também
revoga UPDATE/DELETE/TRUNCATE/TRIGGER de PUBLIC.

As permissões padrão de objetos futuros concedem apenas SELECT/INSERT e uso
das sequences. Assim, a futura tabela de auditoria já nasce sem UPDATE/DELETE
para a API, desde que criada pelo mesmo dono. Reexecute o roteiro após novas
migrations para liberar CRUD nas outras tabelas; auditoria continua protegida.
Grants herdados ou de coluna são verificados pelo guard da API: se houver
UPDATE indevido, a conexão é recusada. O roteiro não torna o histórico imutável
para o administrador nem substitui a revisão da migration do card 83.

No Neon, crie o papel restrito via SQL: papéis criados pelo Console/API/CLI
recebem membership em `neon_superuser`. Não use esses papéis no runtime.
[Referência do Neon](https://github.com/neondatabase/website/blob/main/content/docs/manage/roles.md).
Defina a senha fora do script, por exemplo com `\password constroi_api_execucao`
num terminal administrativo protegido. Não grave senha no SQL, Git, histórico
de comandos ou logs. Use TLS `verify-full` quando possível; `require` também é
aceito pelo contrato existente.

## Limite efetivo e fechamento futuro

Com o modo estrito ligado, exige PostgreSQL **17+** com `transaction_timeout` configurado no papel/banco
entre **1 e 30000 ms**. A API verifica o limite e o perfil em toda conexão física;
recusa perfil administrativo, ownership, CREATE no banco/schema ou UPDATE na
auditoria. O guard também rejeita membership em `neon_superuser` e grants de
UPDATE em colunas ou membership em `pg_write_all_data`. Após a verificação, o
pool aplica no máximo o menor valor entre
o limite do papel e `DATABASE_TRANSACTION_TIMEOUT_MS` (padrão 30000).

O timeout do PostgreSQL cobre a transação inteira, incluindo queries sucessivas,
espera por locks e inatividade. Seu estouro encerra a conexão e reverte as
escritas; o pool precisa abrir/validar outra conexão. Um timeout de query sozinho
não daria essa garantia. [Documentação do PostgreSQL 17](https://www.postgresql.org/docs/17/runtime-config-client.html).

O maior limite permitido para os escritores desta API é **30 s**. A margem
publicada é **31 s**, estritamente maior, nas constantes de `conexao_api.dart` e
no diagnóstico. Todo escritor adicional precisa de limite validado antes de
participar de um relatório fechado; acesso administrativo/ad hoc não é escritor
auditável automaticamente. Não desabilite/aumente o timeout durante o fluxo.
Relatório futuro só pode fechar período quando o relógio do banco passar de
`fim + margem`, mantendo período/filtros fixos conforme a proposta do PR #19.
Esta entrega não anuncia um relatório como fechado.

No modo estrito, use endpoint direto; o pool do driver já limita as conexões. Endpoints Neon com
`-pooler` são rejeitados. Não passe por PgBouncer em modo transaction pooling:
as validações/configurações de sessão devem valer para a conexão inteira.

## Roteiro coordenado por ambiente

1. Combinar janela e responsáveis, obter backup/branch de homologação e confirmar
   PostgreSQL 17+; preparar as duas credenciais distintas no cofre.
2. Rodar `dart run bin/migrate.dart` com `.env.migrations`. Rodar novamente e
   confirmar que nenhuma migration é reaplicada.
3. Executar `Database/infra/auditoria_papeis.sql` como esse mesmo dono. No psql,
   prefira um serviço libpq com credencial externa ao repositório:
   `psql service=constroi_migrations -v ON_ERROR_STOP=1 -f Database/infra/auditoria_papeis.sql`.
   Criar a senha do papel restrito sem colocar o segredo em argumentos/logs.
4. Montar um `.env.api-candidata` com DATABASE_URL restrita; na pasta da API,
   definir `API_ENV_FILE=.env.api-candidata` e rodar
   `dart run bin/verificar_auditoria.dart`. Ele não substitui a configuração
   ativa e não escreve dados; verifica permissões e publica limite/margem.
   `auditoria_instalada=false` significa que falta a migration do card 83.
5. Executar a regressão em homologação com a conexão restrita. O checklist do
   card 83 continua necessário para schema/gravação e concorrência reais.
6. Só após alinhamento e diagnóstico aprovado, substituir DATABASE_URL pela
   credencial restrita no ambiente autorizado, ativar
   `AUDITORIA_CONEXAO_ESTRITA=true` e reiniciar a API. Validar cada ambiente
   (local, Docker, Neon). Se a ativação falhar, restaurar a configuração anterior
   completa (URL e flag) e investigar com a equipe. Enquanto a flag estiver
   desligada, não considerar a conexão aprovada nem anunciar relatório fechado.

No Docker, `api` recebe somente DATABASE_URL, AUDITORIA_CONEXAO_ESTRITA,
DATABASE_TRANSACTION_TIMEOUT_MS e JWT_SECRET por whitelist. A flag tem padrão
`false`; a credencial de migrations fica apenas no serviço
opcional `migrate` (perfil `tools`), via `.env.migrations`:

```sh
docker compose --env-file constroi_api/.env --profile tools run --rm migrate
docker compose --env-file constroi_api/.env up --build
```

## Evidência local reproduzível

Na pasta `constroi_api`, com PostgreSQL 17+ local descartável e usuário de teste
que possa criar papéis. A suíte recria public; nunca aponte para dados reais.

```powershell
$env:CONSTROI_TEST_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55434/constroi_test_infra?sslmode=require&max_connection_count=10'
dart test integration_test/infra_auditoria_test.dart --reporter expanded
```

A suíte aplica migrations com o papel próprio, executa novamente como no-op,
provisiona o papel restrito com o SQL real e usa a tabela de auditoria da
migration 013 para verificar permissões. Uma fixture separada confere os
privilégios padrão de objetos futuros. A senha descartável do papel é criada
somente dentro do teste, sem alterar o SQL de provisionamento, permitindo
rodar também no PostgreSQL com autenticação SCRAM do README.
Cobre compatibilidade com a credencial privilegiada e timeout zero quando a
flag está desligada, e diagnóstico estrito independentemente da flag. Com a
flag ligada, cobre INSERT/SELECT permitidos; UPDATE/DELETE/TRUNCATE/DDL recusados; rejeição de
credencial privilegiada, UPDATE de coluna e timeout desligado; diagnóstico sem
URL; encerramento/rollback em várias queries curtas, inatividade e lock real.
Os testes usam limites menores para evidenciar o comportamento do mesmo guard
sem esperar 30 segundos. A regressão também aprova um pedido e confere baixa/log
com a conexão restrita real, incluindo o movimento estruturado. A suíte do
card 83 também provisiona a infraestrutura antes da 013 para verificar os
privilégios padrão na tabela nova. Não substituem a validação do rollout no Neon.
