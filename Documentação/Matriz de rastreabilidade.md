# Matriz de rastreabilidade

Responsável: Eduardo Sochodolak (QA) · Última verificação: 10/11/2026 · Base: `origin/main` em
`0a86a1d`, mais a branch `fix/ajustes-de-uso` onde indicado

OBS: Infelizmente tem q usar emoji q fica mais visual

Liga cada requisito funcional ao que existe de fato no projeto. A coluna **Rota** e a coluna
**Teste** foram conferidas contra o código, não contra o que estava planejado.

## Como ler

| Marca | Significado |
|---|---|
| ✅ | Existe e foi verificado |
| 🟡 | Existe parcialmente — a observação diz o que falta |
| ❌ | Não existe |

A coluna **Protótipo** é a tela desenhada no Figma. A coluna **App** é a tela funcionando
dentro do aplicativo Flutter.

---

## Requisitos funcionais

| RF | Nome | Rota | Protótipo | App | Teste |
|---|---|---|---|---|---|
| RF01 | Cadastro de empresa | ✅ `POST /empresas` | ❌ | ❌ | ✅ caso 02 |
| RF02 | Autenticação | ✅ `POST /login` | ✅ 01_Login | ✅ Login | ✅ casos 02, 03, 09 + E2E 01, 02, 07 |
| RF03 | Manutenção de usuários | ✅ `/usuarios` (4 rotas) | ❌ | ✅ Administração | ✅ caso 08 + unitário com mock |
| RF04 | Consulta de estoque | ✅ `GET /estoque` | ✅ 03_Estoque | ✅ Estoque | ✅ caso 14 + E2E 05 + 31 widgets |
| RF05 | Solicitação de produtos | ✅ `POST /pedidos` | ✅ 04_Requisição | ✅ Requisição | ✅ casos 11, 12, 13 |
| RF06 | Avaliação de pedidos | ✅ `PATCH /pedidos/{id}` | ✅ 05_Aprovações | ✅ Aprovações | ✅ casos 15, 16, 17 |
| RF07 | Entrada de estoque manual | ✅ `POST /entradas` | 🟡 dentro de 05_Aprovações | ❌ | ✅ caso 22 |
| RF08 | Entrada via XML da NF-e | ✅ `POST /entradas/xml` | ❌ | ✅ Importação NF-e | ✅ caso 19 |
| RF09 | Anexar XML a registro existente | ✅ `PATCH /entradas/{id}/xml` | ❌ | ✅ Importação NF-e | ✅ caso 20 |
| RF10 | Manutenção de produtos | ✅ `/produtos` (4 rotas) | ✅ 07_Cadastro | 🟡 cria, não edita | ✅ caso 06 |
| RF11 | Manutenção de equipamentos | ✅ `/equipamentos` (4 rotas) | ✅ 07_Cadastro | 🟡 cria, não edita | ✅ caso 07 |
| RF12 | Controle de empréstimos | ✅ `/emprestimos` (2 rotas) | ✅ 07_Cadastro | ❌ | ✅ caso 23 |
| RF13 | Painel da obra | ✅ `GET /painel` | ✅ 02_Painel | ✅ Painel | ✅ caso 18 + E2E 03, 06 |
| RF14 | Consulta e lançamento de custos | ✅ `GET /custos`, `POST /custos/despesas` | ✅ 06_Custos | ✅ Custos | ✅ caso 21 + 39 unitários + widget do formulário |
| RF15 | Consulta de equipe | ✅ `GET /obras/{id}/equipe` | ✅ 08_Equipe | ✅ Equipe | ✅ caso 05 |
| RF16 | Consulta de logs | ✅ `GET /logs` | 🟡 dentro de 08_Equipe | ✅ Administração, aba Logs | ✅ `integration_test/logs_test.dart` + 15 unitários do texto do evento |

A tela de cadastro entrou na main pela PR #38. RF10 e RF11 criam pelo aplicativo; editar e
inativar continuam só pela API.

RF13, RF14, RF15 e RF16 entraram na Definição de requisitos em 08/11/2026 para cobrir as
telas de Painel, Custos, Equipe e a consulta de Logs, que já existiam sem requisito.

---

## Cobertura, em número

| Camada | ✅ completo | 🟡 parcial | ❌ ausente |
|---|---|---|---|
| Rota na API | 16 | 0 | 0 |
| Tela desenhada no Figma | 10 | 2 | 4 |
| Tela funcionando no aplicativo | 11 | 2 | 3 |
| Teste automatizado | 16 | 0 | 0 |

Até 05/11 esta tabela trazia uma coluna só de "cobertos", e eu contava com dois critérios
diferentes: o Figma somava apenas ✅ (10 de 16) e o aplicativo somava ✅ mais 🟡 (13 de 16).
Era erro meu de leitura, não mudança de escopo. Agora cada marca tem a sua coluna.

Em 22/09 eram 5 rotas, 0 telas e 0 testes. O fluxo central — pedir, aprovar, baixar estoque —
está inteiro, com rota, tela e teste de concorrência. A tela de Importação de NF-e atende o
RF08 e o RF09 na mesma rota, e a de Administração fecha o RF03.

**Todo RF tem rota e teste; o empréstimo (RF12) fechou com a PR #49. Sem tela: RF01, RF07 e
RF12.**

---

## Buracos, em ordem de urgência

### 1. ~~O banco compartilhado estava sem a migration 011~~ — corrigido em 26/10

`schema_migrations` no Neon tinha 001 a 010 e a 012; a `011_entrada_nfe.sql` havia sumido,
junto com a coluna `empresa_nfe_id` de `entrada_estoque`. `POST /entradas/xml` e
`PATCH /entradas/{id}/xml` respondiam 500 com `42703`, e os casos 19 e 20 ficavam vermelhos
— 53 verificações. Não era regressão de código.

Ninguém tinha percebido porque nenhuma tela usa essas rotas ainda, e o Andrew estava
construindo a tela da PR #42 justamente em cima delas. O runner reaplicou só a 011 e os dois
casos voltaram ao verde.

Fica a pergunta em aberto de como a migration saiu de um banco compartilhado: ninguém
assumiu, e não há registro. Enquanto não houver resposta, vale rodar a suíte inteira antes
de confiar no ambiente.

### 2. ~~RF07 não existe, e a ordem ficou estranha~~ — corrigido em 05/11

A PR #41 entrou com `POST /entradas` e o caso 22, 62 verificações: saldo, rollback do estouro
numérico, isolamento entre empresas e oito entradas simultâneas sem deadlock. Quem recebe
material sem nota já registra.

Falta a tela: o RF07 só funciona por chamada direta à API. Não há cartão para isso.

### 3. ~~A importação de NF-e não tem tela~~ — corrigido pela PR #42

A tela de Importação de NF-e cobre os dois requisitos na mesma rota: `POST /entradas/xml` para
importar e `PATCH /entradas/{id}/xml` para anexar a um registro existente. Dá para demonstrar
pelo aplicativo.

### 4. ~~A tela de Custos não é testada contra banco~~ — fechado nesta branch

O caso 21 cobre as 86 linhas de SQL de `constroi_api/lib/custos.dart` contra o banco:
total, mês e semana com valores calculados na mão, orçamento parcial e isolamento entre
empresas. Quatro mutações na consulta foram injetadas e todas quebraram o caso — trocar
`'week'` por `'month'` no filtro de período, somar orçamento mesmo com obra sem orçamento,
arredondar o percentual em duas casas e tirar o filtro de empresa de `obras_visiveis`.

O que continuava fora era quem alimenta a tela: até 09/11 não havia rota para criar despesa
nem caminho para gravar preço de material, e o caso 21 semeava `despesa_obra` e
`item_entrada.valor_unitario` direto no banco. Fechou nesta branch, pelos dois lados:

- `POST /custos/despesas` grava serviços e locações, restrito a engenheiro ou master, com o
  evento `CRIACAO_DESPESA` na mesma transação. A tela de Custos ganhou o botão
  **LANÇAR DESPESA** com obra, categoria, descrição e valor. 39 unitários na rota e 5
  widgets no formulário.
- O preço do material passou a vir da NF-e: o parser lê `vUnCom`, que antes era descartado,
  e grava `item_entrada.valor_unitario` junto da categoria do produto. Produto sem categoria
  entra sem preço, porque a constraint exige as duas colunas juntas.

Uma decisão técnica a registrar: `valor_unitario` é `NUMERIC(14,2)` e a NF-e permite até dez
decimais no preço unitário, então o valor é arredondado para o centavo com `BigInt`, nunca
com `double`. O total do lançamento sai de quantidade × preço arredondado, com diferença
máxima de meio centavo por unidade comprada. Guardar o preço com mais casas exigiria
migration e é cartão à parte.

### 5. RF01 continua sem tela

Cadastro de empresa tem rota e teste, e não tem tela nem no Figma. Ninguém cria a própria
empresa pelo aplicativo — a primeira conta de cada empresa nasce por chamada direta à API.
Não há cartão para isso.

O RF03 fechou: a tela de Administração entrou na semana 6 e lista, cria e inativa usuário
pelo aplicativo. Continua sem protótipo no Figma, então o desenho é decisão de implementação,
não de design.

### 6. ~~Três telas sem requisito~~ — corrigido em 08/11

Painel, Custos e Equipe viraram RF13, RF14 e RF15 na Definição de requisitos
(`Definicao de requisitos.md`, de onde o PDF é gerado) e entraram na tabela de requisitos
acima. O apontamento de 22/09 está fechado.

### 7. ~~Consultar Logs tem rota e tela, e segue sem RF numerado~~ — corrigido em 08/11

`GET /logs` é exclusivo do Master da própria empresa, com filtros por usuário/período e
paginação; o helper único grava os eventos das rotas de escrita na mesma transação da
alteração. O contrato e a cobertura estão em `constroi_api/README.md` e
`constroi_api/integration_test/logs_test.dart`.

A consulta agora tem tela: é a segunda aba da Administração, com filtro por autor e por
período. Virou o RF16 na Definição de requisitos, junto com Painel, Custos e Equipe.

### 8. ~~As telas abriam vazias porque o banco de demonstração não tinha dado~~ — corrigido em 10/11

Painel sem movimentações, Custos sem lançamento e Estoque com quatro saldos: não era defeito
de tela, era ausência de dado. `constroi_api/bin/semear.dart` preenche a empresa de teste com
um histórico de 70 dias — 4 obras com orçamento, 18 produtos, 9 equipamentos, equipes,
13 entradas com preço, 33 pedidos nos três estados, 42 baixas, 11 despesas, 7 empréstimos e
252 eventos. É idempotente: roda duas vezes e o banco fica igual.

Os saldos foram desenhados para exercitar os casos de borda das telas: 2 rupturas, 7 abaixo
do mínimo, uma obra concluída com sobra, um empréstimo atrasado e uma obra de propósito
acima do orçamento (108,4%). Dois usuários ficam inativos para a reativação ter alvo.

### 9. A tabela de RF do PDF continua quebrada

A numeração desta matriz é a minha leitura da ordem dos nomes. Segue pendente de confirmação
do Pedro.

---

## Sobre os testes

| Camada | Quantidade | Medido em |
|---|---|---|
| Unidade na API (`dart test test/`) | 294 | 10/11/2026 |
| Widget no app (`flutter test`) | 279 | 10/11/2026 |
| Integração Dart (`dart test integration_test/`) | 149 | 10/11/2026 |
| Integração (`.\testes\executar.ps1`) | 23 casos, 659 verificações | 09/11/2026 |
| Ponta a ponta (Cypress) | 7 casos, 9 testes | 05/11/2026 |

Números medidos, não deduzidos. Os de unidade, widget e integração Dart são da branch
`fix/ajustes-de-uso` em 10/11; na main a unidade e o widget são 242 e 209. As 9 suítes de
`integration_test/` rodaram em 1min47 contra um PostgreSQL 17 descartável com TLS, com o
`max_connection_count=20` da PR #50 passado pela URL. O runner de `testes/` e o Cypress não
foram rodados hoje; valem a última medição, com a data ao lado.

A API cresceu 52 unitários nesta branch: 39 da rota de despesa, 8 do filtro de zerados e 5
do preço da NF-e. O app cresceu 63: 15 do texto legível do evento, 2 da reativação de
usuário, 2 dos nomes do catálogo nos eventos, 7 dos indicadores clicáveis, 2 do filtro de
saldo e 12 do lançamento de despesa, mais os ajustes dos que já existiam.

`constroi_api/integration_test/` roda fora do runner de `testes/` e ganhou dois casos de
preço da NF-e nesta branch, os dois verdes contra banco. A cobertura dos logs também mora
lá — vale um caso dentro do runner, e não há cartão para isso.

O commit `fad194d`, do Andrew, quebrou 32 testes ao exigir quantidade inteira em `un` e
`saco` sem atualizar as fixtures: 17 unitários da API (`SELECT id` virou `SELECT id,
unidade` e as linhas falsas tinham uma coluna só), 10 de integração da NF-e (a fixture
importava 1,25 saco) e 5 de widget. Todos corrigidos nesta branch, e a regra dele ganhou
teste de rota, que não existia.

A suíte de integração fala com a API e o banco reais e confere o resultado no banco, não só a
resposta. Como rodar está em `testes/README.md`.

### Requisitos não funcionais com evidência

| RNF | Situação |
|---|---|
| RNF01 comunicação criptografada | ✅ `sslmode=require` exigido no normalizador |
| RNF03 senha com hash e salt | ✅ bcrypt custo 12, verificado no banco |
| RNF04 política de senha | ✅ caso 03 cobre tamanho, lista de senhas comuns e símbolos |
| RNF05 bloqueio por tentativa | ✅ coberto nos testes de login |
| RNF20 estoque sem valor negativo | ✅ caso 16: saldo 1, 8 aprovações simultâneas, 1 passa, 7 recebem 409, nenhum 5xx, saldo final 0 e **um único registro no log** |

A triagem completa dos 20 RNFs continua sendo outro cartão.

---

## O que fazer com este documento

1. Rodar o runner de integração e o Cypress nesta branch e trocar os números de 09/11 e
   05/11 pelos de agora, inclusive os dois casos novos de preço da NF-e.
2. Descobrir como a migration 011 saiu do Neon e combinar quem mexe no banco compartilhado.
   Em 10/11 apareceu um segundo sinal de desvio: no Neon, `item_pedido_pedido_id_fkey` e
   `item_entrada_entrada_id_fkey` estão sem `ON DELETE CASCADE`, embora a migration 001 e o
   `Database/schema.sql` declarem o cascade. Aquelas tabelas não foram criadas pelo executor
   de migrations.
3. Confirmar a numeração dos RF com o Pedro.
4. Levar ao Johann o que sobrou de funcionalidade faltando: as telas do RF01, do RF07 e do
   RF12, que hoje só funcionam por chamada direta à API.
5. Decidir se `item_entrada.valor_unitario` passa a `NUMERIC(14,4)` para guardar o preço da
   NF-e sem arredondar. Exige migration.
6. Reconferir ao fim de cada semana. A coluna **Teste** é a que mais envelhece.
