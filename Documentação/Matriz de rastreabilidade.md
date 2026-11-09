# Matriz de rastreabilidade

Responsável: Eduardo Sochodolak (QA) · Última verificação: 05/11/2026 · Base: `origin/main` em
`6ee328b`, mais a tela de Administração desta branch onde indicado

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
| RF04 | Consulta de estoque | ✅ `GET /estoque` | ✅ 03_Estoque | ✅ Estoque | ✅ caso 14 + E2E 05 |
| RF05 | Solicitação de produtos | ✅ `POST /pedidos` | ✅ 04_Requisição | ✅ Requisição | ✅ casos 11, 12, 13 |
| RF06 | Avaliação de pedidos | ✅ `PATCH /pedidos/{id}` | ✅ 05_Aprovações | ✅ Aprovações | ✅ casos 15, 16, 17 |
| RF07 | Entrada de estoque manual | ✅ `POST /entradas` | 🟡 dentro de 05_Aprovações | ❌ | ✅ caso 22 |
| RF08 | Entrada via XML da NF-e | ✅ `POST /entradas/xml` | ❌ | ✅ Importação NF-e | ✅ caso 19 |
| RF09 | Anexar XML a registro existente | ✅ `PATCH /entradas/{id}/xml` | ❌ | ✅ Importação NF-e | ✅ caso 20 |
| RF10 | Manutenção de produtos | ✅ `/produtos` (4 rotas) | ✅ 07_Cadastro | 🟡 cria, não edita | ✅ caso 06 |
| RF11 | Manutenção de equipamentos | ✅ `/equipamentos` (4 rotas) | ✅ 07_Cadastro | 🟡 cria, não edita | ✅ caso 07 |
| RF12 | Controle de empréstimos | ✅ `/emprestimos` (2 rotas) | ✅ 07_Cadastro | ❌ | ✅ caso 23 |
| RF13 | Painel da obra | ✅ `GET /painel` | ✅ 02_Painel | ✅ Painel | ✅ caso 18 + E2E 03, 06 |
| RF14 | Consulta de custos | ✅ `GET /custos` | ✅ 06_Custos | ✅ Custos | ✅ caso 21 + unitário com mock |
| RF15 | Consulta de equipe | ✅ `GET /obras/{id}/equipe` | ✅ 08_Equipe | ✅ Equipe | ✅ caso 05 |
| RF16 | Consulta de logs | ✅ `GET /logs` | 🟡 dentro de 08_Equipe | ✅ Administração, aba Logs | ✅ `integration_test/logs_test.dart` |

A tela de cadastro entrou na main pela PR #38. RF10 e RF11 criam pelo aplicativo; editar e
inativar continuam só pela API.

RF13, RF14, RF15 e RF16 entraram na Definição de requisitos em 08/11/2026 para cobrir as
telas de Painel, Custos, Equipe e a consulta de Logs, que já existiam sem requisito.

---

## Cobertura, em número

| Camada | Cobertos | Total |
|---|---|---|
| Rota na API | 16 | 16 |
| Tela desenhada no Figma | 10 | 16 |
| Tela funcionando no aplicativo | 13 | 16 |
| Teste automatizado | 16 | 16 |

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

O que continua fora: não há rota para criar despesa nem para gravar preço na entrada, então
o caso semeia `despesa_obra` e `item_entrada.valor_unitario` direto no banco.

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

### 8. A tabela de RF do PDF continua quebrada

A numeração desta matriz é a minha leitura da ordem dos nomes. Segue pendente de confirmação
do Pedro.

---

## Sobre os testes

| Camada | Quantidade |
|---|---|
| Unidade na API (`dart test test/`) | 242 |
| Widget no app (`flutter test`) | 209 |
| Integração (`.\testes\executar.ps1`) | 22 casos, 585 verificações |
| Ponta a ponta (Cypress) | 7 casos, 9 testes |

Números medidos em 05/11/2026, não deduzidos, com a main já mesclada nesta branch. Os 22
casos passaram inteiros em 21 minutos. Os 209 testes de widget incluem os 23 da tela de
Administração desta branch; na main são 186.

A integração cresceu 62 verificações desde 26/10, todas do caso 22 que veio com a PR #41. As
PRs #40, #45 e #46 entraram sem caso novo: a cobertura dos logs mora em
`constroi_api/integration_test/logs_test.dart`, que roda fora deste runner — vale um caso
aqui dentro, e não há cartão para isso.

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

1. Descobrir como a migration 011 saiu do Neon e combinar quem mexe no banco compartilhado.
2. Confirmar a numeração dos RF com o Pedro.
3. Levar ao Johann o que sobrou de funcionalidade faltando: as telas do RF01, do RF07 e do
   RF12, que hoje só funcionam por chamada direta à API.
4. Reconferir ao fim de cada semana. A coluna **Teste** é a que mais envelhece.
