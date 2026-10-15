# Testes E2E com Cypress — Constrói

Suíte end-to-end que exercita o app Flutter Web contra a API e o banco reais.
Os casos estão descritos em [`docs/casos-de-teste.md`](../docs/casos-de-teste.md).

## Pré-requisitos

- Node.js 18 ou superior
- Docker, para subir o app e a API
- `constroi_api/.env` configurado com a `DATABASE_URL`

## Subir o sistema

Na raiz do repositório:

```bash
docker compose up -d --build
```

Isso publica o app em `http://localhost:8090` e a API em `http://localhost:8080`.
Confirme antes de rodar os testes:

```bash
curl -s -o /dev/null -w "app %{http_code}\n" http://localhost:8090/
```

```bash
curl -s -o /dev/null -w "api %{http_code}\n" http://localhost:8080/health
```

## Instalar e executar

```bash
cd e2e
```

```bash
npm install
```

Modo interativo, para acompanhar e depurar:

```bash
npm run cy:open
```

Modo headless, que é o usado para gerar as evidências:

```bash
npm run cy:run
```

Para rodar um caso isolado:

```bash
npx cypress run --spec cypress/e2e/03_painel_reflete_api.cy.js
```

Em máquina modesta, prefira um caso por vez: o app é renderizado em canvas e a
gravação de vídeo é a parte mais cara da execução. Para desligar o vídeo:

```bash
npx cypress run --config video=false
```

## Endereços

A configuração aceita variáveis de ambiente, úteis se as portas mudarem:

| Variável | Padrão |
|---|---|
| `CONSTROI_APP_URL` | `http://localhost:8090` |
| `CONSTROI_API_URL` | `http://localhost:8080` |

## Estrutura

```
e2e/
├── cypress.config.js          baseUrl, pastas e variáveis
├── cypress/
│   ├── e2e/                   um arquivo por caso de teste
│   └── support/e2e.js         comandos de apoio e massa de dados
└── evidencias/                vídeos e saída da execução
```

## Comandos de apoio

| Comando | O que faz |
|---|---|
| `cy.semearEmpresa()` | cria empresa, master, engenheiro, pedreiro, obra, produto e vínculo |
| `cy.criarPedido(cenario, qtd)` | registra um pedido em nome do pedreiro |
| `cy.abrirApp(caminho)` | abre a aplicação e espera o Flutter terminar de carregar |
| `cy.preencher(id, texto)` | foca o campo e digita, tratando o input que o Flutter cria |
| `cy.entrarNaTela(email)` | preenche e envia o formulário de acesso |
| `cy.chamarApi(metodo, rota, corpo, token)` | chamada direta à API, usada no preparo |

Cada execução cria dados com um sufixo aleatório, então os casos não disputam
registros entre si e podem rodar em qualquer ordem.

## Como os seletores funcionam neste projeto

O Constrói é Flutter Web. Desde a versão 3.29 o Flutter não tem mais renderizador
HTML: a interface é desenhada em canvas e não existe DOM de componente, então não
há onde escrever um `data-cy` diretamente.

A ponte tem três partes:

1. `SemanticsBinding.instance.ensureSemantics()` em `constroi_app/lib/main.dart`
   liga a árvore de acessibilidade, que o Flutter publica no DOM.
2. Os widgets testados usam `Semantics(identifier: 'nome')`, que vira
   `flt-semantics-identifier="nome"`.
3. Um `MutationObserver` em `constroi_app/web/index.html` espelha esse atributo
   para `data-cy`, e também marca os `input` que o Flutter cria dentro de um campo
   de texto, com os sufixos `-campo` e `-inativo`.

Por isso os testes selecionam **exclusivamente** por `[data-cy=...]`, sem recorrer
a classe, texto, posição ou tipo de elemento. A lista de identificadores está em
`docs/casos-de-teste.md`.

Para instrumentar um elemento novo, envolva o widget em `Semantics(identifier: ...)`
e reconstrua a imagem do app. Campos de texto merecem `textField: true` e botões,
`button: true`, porque isso melhora a árvore de acessibilidade além do teste.

## Detalhes que afetam quem for escrever casos novos

Campos de texto do Flutter publicam dois `input` dentro do nó semântico: um
desabilitado, que é a representação estática, e outro habilitado, criado quando o
campo recebe foco. O espelho marca os dois, para que nenhum teste precise recorrer
a seletor de elemento: o habilitado vira `nome-campo` e o desabilitado,
`nome-inativo`. Por isso `cy.preencher` clica no nó e depois digita em
`[data-cy=nome-campo]`.

A sessão do Constrói vive apenas em memória. Recarregar a página desconecta o
usuário, então para atualizar uma tela navegue para outra e volte, em vez de usar
`cy.reload()`.

O primeiro carregamento baixa o CanvasKit e as fontes, e só depois a árvore de
acessibilidade existe. `cy.abrirApp` já espera por isso com folga; se criar um
caso que não use esse comando, lembre de dar o mesmo tempo.

## Evidências

`evidencias/` guarda um vídeo por caso e `execucao-completa.txt`, com a saída da
execução dos cinco casos em sequência.
