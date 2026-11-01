# Matriz de rastreabilidade

Responsável: Eduardo Sochodolak (QA) · Última verificação: 01/11/2026 · Base: `origin/main` em
`795135f`, mais a tela de Administração desta branch onde indicado

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
| RF07 | Entrada de estoque manual | ❌ | 🟡 dentro de 05_Aprovações | ❌ | ❌ |
| RF08 | Entrada via XML da NF-e | ✅ `POST /entradas/xml` | ❌ | ❌ | ✅ caso 19 |
| RF09 | Anexar XML a registro existente | ✅ `PATCH /entradas/{id}/xml` | ❌ | ❌ | ✅ caso 20 |
| RF10 | Manutenção de produtos | ✅ `/produtos` (4 rotas) | ✅ 07_Cadastro | 🟡 cria, não edita | ✅ caso 06 |
| RF11 | Manutenção de equipamentos | ✅ `/equipamentos` (4 rotas) | ✅ 07_Cadastro | 🟡 cria, não edita | ✅ caso 07 |
| RF12 | Controle de empréstimos | ❌ | ✅ 07_Cadastro | ❌ | ❌ |

A tela de cadastro entrou na main pela PR #38. RF10 e RF11 criam pelo aplicativo; editar e
inativar continuam só pela API.

### Telas sem RF numerado

Existem, funcionam e são testadas, mas nenhuma corresponde a requisito do documento.

| Tela | Rota | Teste |
|---|---|---|
| Painel | ✅ `GET /painel` | ✅ caso 18 + E2E 03, 06 |
| Custos | ✅ `GET /custos` | ✅ caso 21 (nesta branch) + unitário com mock |
| Equipe | ✅ `/obras/{id}/equipe` | ✅ caso 05 |

---

## Cobertura, em número

| Camada | Cobertos | Total |
|---|---|---|
| Rota na API | 10 | 12 |
| Tela desenhada no Figma | 7 | 12 |
| Tela funcionando no aplicativo | 7 | 12 |
| Teste automatizado | 10 | 12 |

Em 22/09 eram 5 rotas, 0 telas e 0 testes. O fluxo central — pedir, aprovar, baixar estoque —
está inteiro, com rota, tela e teste de concorrência. A sétima tela é a Administração, que
fecha o RF03.

**O que falta é entrada manual (RF07) e empréstimo (RF12).**

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

### 2. RF07 não existe, e a ordem ficou estranha

Entrada de estoque **manual** não tem rota. A entrada **por XML** tem rota, teste e 32
verificações. Ou seja: dá para dar entrada lendo uma nota fiscal, e não dá para dar entrada
digitando — que é o caminho mais simples e o que o RF08 do documento prevê explicitamente
("entrada pode ser sem nota fiscal").

O Pedro abriu a PR #41 com `POST /entradas`, em revisão. Até ela entrar, quem recebe material
sem nota não registra nada.

### 3. A importação de NF-e não tem tela

RF08 e RF09 têm rota, caso de integração e 53 verificações somadas — e **nenhuma tela**. Só
funciona por chamada direta à API.

É a funcionalidade mais vistosa da apresentação e hoje não dá para demonstrar pelo aplicativo.
O cartão foi aberto depois da regressão de outubro e o Andrew abriu a PR #42, em revisão.

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

### 6. Três telas sem requisito

Painel, Custos e Equipe estão prontas, em uso e testadas, e não correspondem a RF nenhum. O
mesmo apontamento de 22/09 continua: ou viram requisito, ou ficam como funcionalidade que
ninguém pode cobrar.

### 7. Consultar Logs tem rota e tela, e segue sem RF numerado

`GET /logs` é exclusivo do Master da própria empresa, com filtros por usuário/período e
paginação; o helper único grava os eventos das rotas de escrita na mesma transação da
alteração. O contrato e a cobertura estão em `constroi_api/README.md` e
`constroi_api/integration_test/logs_test.dart`.

A consulta agora tem tela: é a segunda aba da Administração, com filtro por autor e por
período. O caso de uso continua no diagrama e a atribuição de um RF numerado segue pendente
de decisão de requisitos — ou seja, existe funcionalidade pronta de ponta a ponta que
ninguém pode cobrar na entrega.

### 8. A tabela de RF do PDF continua quebrada

A numeração desta matriz é a minha leitura da ordem dos nomes. Segue pendente de confirmação
do Pedro.

---

## Sobre os testes

| Camada | Quantidade |
|---|---|
| Unidade na API (`dart test test/`) | 223 |
| Widget no app (`flutter test`) | 207 |
| Integração (`.\testes\executar.ps1`) | 21 casos, 523 verificações |
| Ponta a ponta (Cypress) | 7 casos, 9 testes |

Números medidos em 26/10/2026, não deduzidos. A integração inclui o caso 21 desta branch;
na main são 20 casos e 472 verificações.

Na primeira execução de 26/10 os casos 19 e 20 vieram vermelhos — 53 verificações — porque
faltava a migration 011 no banco compartilhado. Depois de reaplicada, os 21 casos passam.
Está registrado no buraco 1.

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
3. Levar os buracos 2 e 3 para o Johann priorizar — é funcionalidade faltando, com PR aberta
   nos dois casos.
4. Reconferir ao fim de cada semana. A coluna **Teste** é a que mais envelhece.
