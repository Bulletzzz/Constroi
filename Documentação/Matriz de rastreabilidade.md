# Matriz de rastreabilidade

Responsável: Eduardo Sochodolak (QA) · Última verificação: 24/10/2026 · Base: `origin/main` em
`0a7789d`, mais a branch `feat/tela-cadastro` onde indicado

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
| RF03 | Manutenção de usuários | ✅ `/usuarios` (4 rotas) | ❌ | ❌ | ✅ caso 08 |
| RF04 | Consulta de estoque | ✅ `GET /estoque` | ✅ 03_Estoque | ✅ Estoque | ✅ caso 14 + E2E 05 |
| RF05 | Solicitação de produtos | ✅ `POST /pedidos` | ✅ 04_Requisição | ✅ Requisição | ✅ casos 11, 12, 13 |
| RF06 | Avaliação de pedidos | ✅ `PATCH /pedidos/{id}` | ✅ 05_Aprovações | ✅ Aprovações | ✅ casos 15, 16, 17 |
| RF07 | Entrada de estoque manual | ❌ | 🟡 dentro de 05_Aprovações | ❌ | ❌ |
| RF08 | Entrada via XML da NF-e | ✅ `POST /entradas/xml` | ❌ | ❌ | ✅ caso 19 |
| RF09 | Anexar XML a registro existente | ✅ `PATCH /entradas/{id}/xml` | ❌ | ❌ | ✅ caso 20 |
| RF10 | Manutenção de produtos | ✅ `/produtos` (4 rotas) | ✅ 07_Cadastro | 🟡 cria, não edita | ✅ caso 06 |
| RF11 | Manutenção de equipamentos | ✅ `/equipamentos` (4 rotas) | ✅ 07_Cadastro | 🟡 cria, não edita | ✅ caso 07 |
| RF12 | Controle de empréstimos | ❌ | ✅ 07_Cadastro | ❌ | ❌ |

A coluna **App** de RF10 e RF11 depende da branch `feat/tela-cadastro`, em revisão (PR #38).
Enquanto ela não entrar, os dois seguem sem tela no aplicativo.

### Telas sem RF numerado

Existem, funcionam e são testadas, mas nenhuma corresponde a requisito do documento.

| Tela | Rota | Teste |
|---|---|---|
| Painel | ✅ `GET /painel` | ✅ caso 18 + E2E 03, 06 |
| Custos | ✅ `GET /custos` | 🟡 só unitário com mock — **a consulta não roda contra banco em teste nenhum** |
| Equipe | ✅ `/obras/{id}/equipe` | ✅ caso 05 |

---

## Cobertura, em número

| Camada | Cobertos | Total |
|---|---|---|
| Rota na API | 10 | 12 |
| Tela desenhada no Figma | 7 | 12 |
| Tela funcionando no aplicativo | 6 | 12 |
| Teste automatizado | 10 | 12 |

Em 22/09 eram 5 rotas, 0 telas e 0 testes. O fluxo central — pedir, aprovar, baixar estoque —
está inteiro, com rota, tela e teste de concorrência.

**O que falta é entrada manual (RF07) e empréstimo (RF12).**

---

## Buracos, em ordem de urgência

### 1. RF07 não existe, e a ordem ficou estranha

Entrada de estoque **manual** não tem rota. A entrada **por XML** tem rota, teste e 32
verificações. Ou seja: dá para dar entrada lendo uma nota fiscal, e não dá para dar entrada
digitando — que é o caminho mais simples e o que o RF08 do documento prevê explicitamente
("entrada pode ser sem nota fiscal").

Cartão existe no backlog, com o Pedro. Até ele andar, quem recebe material sem nota não
registra nada.

### 2. A importação de NF-e não tem tela

RF08 e RF09 têm rota, caso de integração e 53 verificações somadas — e **nenhuma tela**. Só
funciona por chamada direta à API.

É a funcionalidade mais vistosa da apresentação e hoje não dá para demonstrar pelo aplicativo.
Não existe cartão para essa tela em nenhuma semana do plano.

### 3. A tela de Custos não é testada contra banco

`constroi_api/lib/custos.dart` tem 86 linhas de SQL com CTEs, filtro de período com fuso e
agregação por obra. O teste da rota é mock, não existe caso de integração, e o Cypress só
confere que o item do menu aparece.

Conferi na mão durante a revisão da PR #33 e os números batem. Mas trocar um operador naquela
consulta hoje passa verde em tudo.

### 4. RF01 e RF03 continuam sem tela

Cadastro de empresa e manutenção de usuários têm rota e teste, e não têm tela nem no Figma.
Ninguém cria conta pelo aplicativo. Há cartão na semana 6 (Tela de Administração) para o RF03;
para o RF01 não há.

### 5. Três telas sem requisito

Painel, Custos e Equipe estão prontas, em uso e testadas, e não correspondem a RF nenhum. O
mesmo apontamento de 22/09 continua: ou viram requisito, ou ficam como funcionalidade que
ninguém pode cobrar.

### 6. Consultar Logs segue sem RF e sem rota

A tabela `log_sistema` recebe escrita de várias rotas hoje, mas não existe `GET /logs`. O caso
de uso está no diagrama como exclusivo do Master. Cartão no backlog.

### 7. A tabela de RF do PDF continua quebrada

A numeração desta matriz é a minha leitura da ordem dos nomes. Segue pendente de confirmação
do Pedro.

---

## Sobre os testes

| Camada | `main` hoje | com a PR #38 |
|---|---|---|
| Unidade na API (`dart test`) | 217 | 219 |
| Widget no app (`flutter test`) | 119 | 132 |
| Integração (`.\testes\executar.ps1`) | 20 casos, 460 verificações | 20 casos, 472 |
| Ponta a ponta (Cypress) | 7 casos, 9 testes | igual |

Os dois números foram medidos, não deduzidos: a coluna da esquerda rodando contra
`origin/main`, a da direita contra a branch `feat/tela-cadastro`.

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

1. Confirmar a numeração dos RF com o Pedro.
2. Levar os buracos 1 a 4 para o Johann priorizar — os dois primeiros são funcionalidade
   faltando, os dois seguintes são risco de regressão silenciosa.
3. Reconferir ao fim de cada semana. A coluna **Teste** é a que mais envelhece.
