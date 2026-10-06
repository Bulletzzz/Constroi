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
| `GET` `PATCH` | `/produtos/{id}` | engenheiro |
| `GET` `POST` | `/equipamentos` | engenheiro |
| `GET` `PATCH` | `/equipamentos/{id}` | engenheiro |
| `GET` `POST` | `/pedidos` | pedreiro |
| `GET` | `/pedidos/{id}` | pedreiro |

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

## Rodando o projeto

Cada pessoa precisa do próprio `constroi_api/.env`, que não vai para o repositório. Copie
o modelo e preencha:

```
DATABASE_URL=postgresql://usuario:senha@host.neon.tech/constroi?sslmode=require
JWT_SECRET=uma-chave-longa-e-aleatoria
```

A URL tem que ser a conexão **direct** do Neon, sem `channel_binding`.

Com Docker, sobe app e API juntos:

```bash
docker compose up --build
```

- Aplicativo: http://localhost:8090
- API: http://localhost:8080

Para mexer só na API, sem container:

```bash
cd constroi_api
dart pub get
dart run bin/migrate.dart
dart_frog dev
```

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
