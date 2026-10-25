<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Assets/ConstroiLogoMarca.svg">
  <img alt="Constrói" src="Assets/ConstroiLogoMarca2.svg" width="420">
</picture>

Aplicativo de controle de estoque, materiais e equipamentos para canteiro de obra.

Projeto da disciplina Optativa II (Gestão de Projetos) 

## O problema

Em obra, material e equipamento são pedidos de boca. O pedreiro precisa de cimento, avisa
o engenheiro, e o pedido se perde entre o WhatsApp e o caderno. Ninguém sabe o que foi
pedido, o que foi entregue, o que ainda tem em estoque nem quanto já foi gasto.

O Constrói põe esse fluxo no celular, com rastro de tudo.

## Como funciona

1. O **pedreiro** abre uma requisição de material pela obra onde está e recebe um protocolo
   para acompanhar.
2. O **engenheiro** analisa o pedido e decide: baixa direto do estoque, compra ou aluga.
3. A entrada de material pode ser lançada na mão ou pelo **XML da nota fiscal**, que lê os
   produtos automaticamente.
4. Equipamento sai por **empréstimo** e volta por devolução, sempre com responsável.
5. Toda movimentação fica registrada em log.

## Perfis de acesso

Cada perfil herda tudo que o anterior pode fazer.

| Perfil | O que faz |
|---|---|
| **Pedreiro** | Solicita material, acompanha o próprio pedido, consulta estoque |
| **Engenheiro** | Tudo do pedreiro, mais: aprova e recusa pedidos, dá entrada de estoque, mantém produtos e equipamentos, registra empréstimos |
| **Master** | Tudo do engenheiro, mais: cadastra a empresa, gerencia usuários, consulta os logs |

## Tecnologias

| Camada | Escolha |
|---|---|
| Aplicativo | Flutter / Dart |
| API | Dart Frog |
| Banco | PostgreSQL no Neon |
| Autenticação | bcrypt + JWT |
| Ambiente | Docker Compose |
| Protótipo | Figma |
| Gestão | Trello (Kanban) |

## Estrutura de pastas

```
Constroi/
├── constroi_app/            aplicativo Flutter
│   ├── lib/                 código do app
│   ├── assets/              logos usados em tela
│   └── test/
│
├── constroi_api/            API em Dart Frog
│   ├── routes/              cada arquivo vira um endpoint
│   │   ├── _middleware.dart      conexão do banco e leitura do token
│   │   ├── login.dart
│   │   ├── health.dart
│   │   ├── eu/                   dados do usuário logado
│   │   ├── usuarios/             restrito ao master
│   │   ├── produtos/             restrito ao engenheiro
│   │   └── equipamentos/         restrito ao engenheiro
│   ├── lib/                 regras reaproveitadas entre rotas
│   │   ├── banco.dart            pool de conexão
│   │   ├── ambiente.dart         leitura do .env
│   │   ├── autenticacao.dart     perfis e leitura do token
│   │   ├── permissao.dart        trava de nível por pasta
│   │   ├── senha.dart            hash e conferência
│   │   └── token.dart            geração do JWT
│   ├── migrations/          versões do schema, aplicadas em ordem
│   ├── bin/                 utilitários de linha de comando
│   └── test/
│
├── Assets/                  logos e marca
├── Database/                schema de referência
├── Documentação/            requisitos, casos de uso e diagramas
└── docker-compose.yml
```

Dentro de `routes/`, o caminho do arquivo **é** a URL: `routes/produtos/[id].dart`
responde em `/produtos/42`. O `_middleware.dart` de cada pasta define o nível mínimo de
acesso daquele trecho.

## Endpoints

| Método | Rota | Nível |
|---|---|---|
| `POST` | `/login` | público |
| `GET` | `/health` | público |
| `GET` | `/eu` | pedreiro |
| `GET` `POST` | `/usuarios` | master |
| `GET` `PATCH` | `/usuarios/{id}` | master |
| `PATCH` | `/usuarios/{id}/inativar` | master |
| `GET` `POST` | `/produtos` | engenheiro |
| `GET` | `/estoque` (filtros opcionais `obra_id`, `categoria_id`) | pedreiro (vínculo ativo com as obras consultadas) |
| `GET` `PATCH` | `/produtos/{id}` | engenheiro |
| `GET` | `/custos` (filtros `obra_id`, `periodo`, `limit`, `offset`) | engenheiro |
| `GET` `POST` | `/equipamentos` | engenheiro |
| `GET` `PATCH` | `/equipamentos/{id}` | engenheiro |
| `GET` `POST` | `/pedidos` | pedreiro |
| `GET` | `/pedidos/{id}` | pedreiro |
| `PATCH` | `/pedidos/{id}` | engenheiro |
| `POST` | `/entradas` | engenheiro |

Nas rotas de escrita, o objeto vai dentro de uma chave com o nome do recurso:

```json
{ "produto": { "nome": "Cimento Portland CP-II", "unidade": "saco" } }
```

Para criar um pedido, envie o token no cabeçalho `Authorization: Bearer <token>`:

```json
{
  "pedido": {
    "obra_id": 1,
    "justificativa": "Material para concretagem",
    "itens": [
      { "produto_id": 1, "quantidade": 10 },
      { "produto_id": 2, "quantidade": 2.5 }
    ]
  }
}
```

O `POST /pedidos` retorna `201` com o pedido, seus itens e o protocolo único
no formato `PED-` seguido de 32 caracteres hexadecimais. O status inicial é sempre
`pendente` e o solicitante vem do token. Pedido e itens são gravados na mesma
transação. A obra e os produtos precisam pertencer à empresa do token; pedreiros
também precisam de vínculo ativo com a obra. A justificativa é opcional, com até
255 caracteres. Cada pedido deve ter de 1 a 200 itens, sem repetir produtos,
e as quantidades devem ser números positivos com até duas casas decimais,
limitados a `9999999999.99`.

Uma colisão de protocolo gera uma nova tentativa, até cinco vezes. Se todas
colidirem, a API retorna `503` sem gravar o pedido. Dados inválidos retornam `400`,
ausência de token válido retorna `401`, pedreiro sem vínculo retorna `403` e obra
inexistente ou de outra empresa retorna `404`.

O `GET /pedidos` retorna `{ "pedidos": [...] }`, com os pedidos mais recentes
primeiro. A paginação usa `limit` (padrão 50, de 1 a 200) e `offset` (padrão 0,
maior ou igual a zero), por exemplo: `/pedidos?limit=50&offset=50` para a segunda
página. Valores de paginação inválidos retornam `400`.
Os filtros opcionais `obra_id`, `status` e `protocolo` podem ser usados
juntos, por exemplo: `/pedidos?obra_id=1&status=pendente` ou
`/pedidos?protocolo=PED-0123456789ABCDEF0123456789ABCDEF`.
Status e protocolo são comparados pelo valor completo, sem diferenciar maiúsculas
de minúsculas. Uma busca sem resultados retorna uma lista vazia; filtros vazios,
IDs inválidos ou textos maiores que os campos do banco retornam `400`.

Pedreiros consultam apenas os próprios pedidos, inclusive após o fim do vínculo
com a obra. Engenheiros e masters consultam todos os pedidos da sua empresa.
Essas regras valem também para buscas por protocolo e pelo ID do pedido.
O `GET /pedidos/{id}` retorna o pedido com a lista `itens`, incluindo
`id`, `produto_id`, `produto_nome`, `unidade` e `quantidade` em texto.
Pedidos inexistentes ou sem permissão de acesso retornam `404`.

O `PATCH /pedidos/{id}` aceita `{"pedido":{"status":"aprovado"}}` para aprovar
com baixa atômica de estoque, ou
`{"pedido":{"status":"recusado","justificativa":"Material desnecessário"}}`
para recusar. Exige engenheiro/master. A recusa exige justificativa aparada de
1 a 255 caracteres; dados inválidos retornam `400`. O motivo da recusa fica em
`justificativa_recusa`, preservando a justificativa original. A decisão fica
registrada em `log_sistema` na mesma transação. Pedido já decidido retorna `409`,
inclusive em decisões concorrentes. Aplique a migration 010 antes de usar.

Para dar entrada manual de estoque, envie `POST /entradas` com o token de um
engenheiro ou master:

```json
{
  "entrada": {
    "obra_id": 1,
    "justificativa": "Material recebido sem nota fiscal",
    "itens": [
      { "produto_id": 1, "quantidade": 10 },
      { "produto_id": 2, "quantidade": 2.5 }
    ]
  }
}
```

A justificativa é obrigatória, com até 255 caracteres. Não é necessário enviar
nota fiscal. A obra e os produtos devem pertencer à empresa do token, os produtos
não podem se repetir e as quantidades devem ser positivas, com até duas casas
decimais e valor máximo de `9999999999.99`.

A API retorna `201` com a entrada e seus itens. A entrada, os itens, a soma no
estoque da obra e o log do usuário são gravados na mesma transação. Se o produto
ainda não tiver estoque nessa obra, o saldo é criado. Se qualquer gravação falhar,
toda a operação é revertida. Saldo acima do limite do banco retorna `409`.

## Rodando o projeto

### App e API com Docker

Em uma máquina nova, instale o Docker com suporte a containers Linux e
[Docker Compose 2.24 ou superior](https://docs.docker.com/compose/install/).
Mantenha o Docker em execução e as portas `8090` e `8080` livres.
Não é necessário instalar Flutter, Dart ou Nginx: os builds acontecem nas imagens.
A primeira execução precisa de internet para baixar imagens e dependências.

Na raiz do repositório, copie `.env.example` para `.env` (`cp .env.example .env`
no Linux/macOS ou `Copy-Item .env.example .env` no PowerShell) e preencha
`DATABASE_URL` com a conexão de execução autorizada pela equipe e `JWT_SECRET`
com uma chave longa e aleatória. Esse arquivo não vai para o Git:

```
DATABASE_URL=postgresql://USUARIO_ATUAL:SENHA@host.neon.tech/constroi?sslmode=require
AUDITORIA_CONEXAO_ESTRITA=false
DATABASE_TRANSACTION_TIMEOUT_MS=30000
JWT_SECRET=uma-chave-longa-e-aleatoria
```

A URL exige TLS; `channel_binding` é removido pelo normalizador. A flag de
auditoria vem desligada para preservar a conexão atual. Após provisionar e
validar o papel restrito com a equipe, troque a URL por sua conexão **direct**
e ative `AUDITORIA_CONEXAO_ESTRITA=true`. A credencial de migrations fica
exclusivamente em `constroi_api/.env.migrations`, na variável
`MIGRATION_DATABASE_URL`. Veja o [roteiro de implantação coordenada](docs/infra-auditoria.md).

O banco Neon deve estar acessível e com as migrations aplicadas. Se precisar
preparar um banco novo, configure `constroi_api/.env.migrations` a partir do
modelo `constroi_api/.env.migrations.example` e execute uma vez:

```bash
docker compose --profile tools run --build --rm migrate
```

Com o ambiente configurado, um comando constrói as imagens ausentes e sobe
app e API juntos. O app aguarda a API confirmar a conexão com o banco:

```bash
docker compose up
```

- Aplicativo: http://localhost:8090
- API: http://localhost:8080
- Verificação do conjunto pelo proxy do app: http://localhost:8090/api/health

O Nginx serve o Flutter web e encaminha `/api/` para a API. O endereço `/api`
é definido durante o build web dentro da imagem. Os arquivos do renderizador
também ficam na imagem, sem depender de CDN na demonstração.

Após atualizar o código, use `docker compose up --build`. Para executar em
segundo plano, acrescente `-d`; confira os serviços com `docker compose ps` e
os logs com `docker compose logs -f`. Para encerrar, use `docker compose down`.
Se a API ficar sem saúde, confira o acesso ao banco e os logs de `api`.

Quem já usa `constroi_api/.env` pode manter o comando anterior:
`docker compose --env-file constroi_api/.env up --build`.

### API sem Docker

Para mexer só na API, instale o Dart e o Dart Frog CLI, copie
`constroi_api/.env.example` para `constroi_api/.env` e preencha a conexão de
execução e a chave JWT. Configure também `.env.migrations` antes de migrar:

```bash
cd constroi_api
dart pub get
dart run bin/migrate.dart
dart_frog dev
```

O runner de migrations lê `.env.migrations`, nunca usa `DATABASE_URL` como
fallback. Com `AUDITORIA_CONEXAO_ESTRITA=true`, a API recusa papéis
administrativos e transações sem limite efetivo.
Para validar uma conexão candidata sem substituir o `.env` ativo, use
`API_ENV_FILE` com `dart run bin/verificar_auditoria.dart`.

## Testes

O workflow [Docker do conjunto](.github/workflows/docker-conjunto.yml) valida
cada PR em uma máquina Ubuntu nova, sem reaproveitar builds do projeto. Ele
prepara um PostgreSQL descartável com TLS, aplica as migrations pelo serviço
existente e executa `docker compose up --build --wait`. A validação confere
os arquivos web, a API conectada ao banco, o proxy `/api/` e o acesso a uma
rota do app. O banco de teste existe apenas nesse workflow; a execução normal
continua usando o Neon configurado no `.env`.

```bash
cd constroi_api
dart test
```

```bash
cd constroi_app
flutter test
```

Com a API de pé, a suíte de integração fala com ela e com o banco de verdade e
confere o que foi gravado. Um comando roda todos os casos:

```powershell
.\testes\executar.ps1
```

Como escolher um caso, ler o detalhe e escrever um novo está em
[testes/README.md](testes/README.md). O Cypress, que abre o aplicativo num
navegador, está em [e2e/README.md](e2e/README.md).

## Equipe

| Integrante | Papel |
|---|---|
| Bernardo Küster Ragugnetti | Gerente de Projetos |
| Eduardo Sochodolak | Analista de Testes / QA |
| Pedro Henrique Moreira | Analista de Requisitos |
| Andrew Bertelli | Arquiteto de Software |
| Johann Matheus Pedroso da Silva | Product Owner |

Os cinco também atuam como desenvolvedores.

## Links

- [Trello](https://trello.com/invite/b/6a713687374d5c5d0e5f20b0/ATTI63842eb5c004d2fd79c8c1a12dcf22eeDF8D1A98/optativa-2)
- [Figma](https://www.figma.com/design/5EhEJLShF7j08ka8JCXD2u/Constroi?node-id=0-1)
