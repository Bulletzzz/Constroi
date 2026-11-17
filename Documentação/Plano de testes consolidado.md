# Plano de testes consolidado

Responsável: Eduardo Sochodolak (QA) · Fechamento: 17/11/2026 · Base: `origin/main`
em `41faa50`, mais a branch `qa/plano-de-testes-final`

Este documento é a entrega de QA do semestre. Diz o que foi testado, como, o que
foi encontrado e — tão importante quanto — o que não deu para testar.

Números são medidos, nunca estimados. Onde não medi, está escrito que não medi.

---

## 1. O que existe de teste, em camadas

| Camada | Quantidade | Onde roda | Medido em |
|---|---|---|---|
| Unidade na API | 324 | `cd constroi_api && dart test` | 17/11/2026 |
| Widget no aplicativo | 289 | `cd constroi_app && flutter test` | 17/11/2026 |
| Integração Dart | 149 | `dart test integration_test/` | 17/11/2026 |
| Integração ponta a ponta | 23 casos, 722 chamadas | `.\testes\executar.ps1` | 17/11/2026 |
| Interface ponta a ponta | 7 casos, 9 testes | Cypress, `e2e/` | 05/11/2026 |

As quatro primeiras passaram inteiras nesta data. O Cypress não foi reexecutado
no fechamento; vale a última medição, com a data ao lado.

**Unidade** cobre validadores, consultas montadas e respostas de rota com banco
simulado. **Widget** cobre tela: estados de carga, erro, vazio, filtros,
paginação, legibilidade e estouro de layout. **Integração Dart** fala com um
PostgreSQL 17 descartável com TLS e cobre migrations, transações, concorrência e
a auditoria. **Ponta a ponta** fala com a API e o banco reais e, depois de cada
chamada, confere no banco se gravou — resposta 200 com nada gravado é
exatamente o erro que essa suíte existe para pegar.

### Testes manuais

O que não está automatizado e foi conferido à mão, com o aplicativo rodando:

| Verificação | Como |
|---|---|
| Leitura das telas com dados reais | Navegação pelos seis perfis de tela com a empresa semeada |
| Ícone e nome do aplicativo no Android | Instalação do APK em aparelho físico |
| Download do APK pelo QR | Leitura do código em aparelho de terceiro |
| Aparência em projetor | Conferência de contraste fora do monitor de desenvolvimento |

---

## 2. Varredura adversarial

Feita no fechamento, tratando o sistema como alvo: tentar ler o que não é meu,
agir com papel que não tenho e derrubar o servidor com entrada malformada.

### Superfície pública

Sondagem de todas as rotas sem token, contra a API publicada.

| Rota | Sem token | Avaliação |
|---|---|---|
| `GET /health` | 200 | Público por projeto; **vazava a exceção** — ver defeito 7 |
| `POST /login` | 400 | Precisa ser público |
| `POST /empresas` e `/empresa` | 400 | **Era falha** — ver defeito 1 |
| `GET /` | 200 | **Anunciava o framework** — ver defeito 8 |
| Outras 14 rotas | 401 | Correto; as 11 principais ficaram no caso 01 |

### Autenticação

| Tentativa | Resultado |
|---|---|
| Sem cabeçalho `Authorization` | 401 |
| `Bearer` vazio, lixo ou duplicado | 401 |
| Token forjado com `alg=none` | 401 |
| Esquema `Basic` | 401 |
| Token sem esquema | 401 |

O `alg=none` é a forja clássica de JWT: trocar o algoritmo por "nenhum" e
mandar um token sem assinatura. A verificação rejeita.

### Isolamento entre empresas

Caso 10, ampliado de 13 para **47 verificações**. Com o token da empresa B,
tentativa de ler e escrever dado da empresa A em todas as rotas.

| Rota | Leitura cruzada | Escrita cruzada |
|---|---|---|
| `/obras`, `/produtos`, `/usuarios`, `/eu` | não vaza | 404 |
| `/estoque`, `/painel`, `/custos` | não vaza | 404 na obra alheia |
| `/logs` | não traz evento de pessoa da A | — |
| `/pedidos` | lista vazia | 404 ao criar na obra da A |
| `/equipamentos`, `/emprestimos` | listas vazias | — |
| `POST /custos/despesas` | — | 404, nada gravado |

Nenhum vazamento. O nome de produto é único por empresa, não global: a B
consegue cadastrar "Cimento" mesmo existindo o mesmo nome na A.

### Autorização por papel

Caso 09, ampliado de 15 para **37 verificações**.

| Grupo de rotas | Nível mínimo | Pedreiro | Engenheiro | Master |
|---|---|---|---|---|
| `/estoque`, `/painel`, `/pedidos`, `/obras`, `/produtos`, `/categorias`, `/eu` | pedreiro | 200 | 200 | 200 |
| `/custos`, `/entradas`, `/equipamentos`, `/emprestimos` | engenheiro | 403 | 200 | 200 |
| `/logs`, `/usuarios` | master | 403 | 403 | 200 |

Escalada de privilégio testada: engenheiro pedindo para criar usuário `master`
recebe 403 e **nada é gravado**, confirmado no banco.

---

## 3. Defeitos encontrados e corrigidos

### Defeito 1 — cadastro de empresa aberto na internet

`POST /empresas` e o alias `/empresa` não tinham autenticação alguma. Na rede
local era inofensivo. Com a API publicada, qualquer pessoa que soubesse o
endereço criava empresas e usuários master no banco, sem limite.

Evidência: sem token, a rota respondia **400 validando o corpo**, não 401.

Correção: a rota passa a exigir o cabeçalho `x-chave-de-cadastro` **se** a
variável `CHAVE_DE_CADASTRO` existir no ambiente. Ausente em desenvolvimento e
em teste, o comportamento é o de antes — por isso as 23 suítes de ponta a ponta,
que criam empresa em todo cenário, seguem passando sem alteração.

### Defeito 2 — erro 500 em rota pública por tipo errado

`{"email":123}` no `/login` derrubava o handler. O mesmo em `/empresas`. Causa
única: o padrão `as String?`, que lança exceção quando o valor não é texto, sem
nada capturando — 29 ocorrências em 7 arquivos.

| Corpo enviado | Antes | Depois |
|---|---|---|
| `{"email":123,"senha":"x"}` | 500 | 400 |
| `{"empresa":{"nome":123}}` | 500 | 400 |
| `{"cnpj":[]}` | 500 | 400 |

Correção: extrator único que trata tipo errado como campo ausente. `POST
/empresas` não tinha nenhum teste unitário; ganhou 12.

### Defeito 3 — buraco de cobertura nos casos de segurança

Os casos 09 e 10 foram escritos cedo e nunca acompanharam as rotas novas.
Custos, logs, painel, estoque, empréstimos e equipamentos nunca tinham sido
testados contra leitura cruzada nem contra papel insuficiente.

Não havia falha no código — a varredura passou de primeira. O defeito era a
ausência de prova, que agora existe e trava regressão.

### Defeito 4 — senha de demonstração inutilizável

A senha gerada para os usuários semeados continha `#`. O leitor de `.env` do
Dart corta a linha a partir da cerquilha, então o seed gravou no banco apenas o
trecho anterior, enquanto o arquivo exibia a senha inteira. Quem lesse o arquivo
tomava 401.

Correção: senha gerada sem caracteres que o `.env` interpreta, e a regra escrita
no `.env.example`. Os três perfis foram verificados entrando depois da troca.

### Defeito 5 — cabeçalho do cliente derrubava o login público

O `/login` grava a tentativa em `tentativa_login` com o IP e o navegador de
quem chamou. O IP ia direto do cabeçalho `X-Forwarded-For` para uma coluna
`INET`, e o `User-Agent` para uma coluna de 500 caracteres, sem conferir nada.
Qualquer um podia mandar texto no lugar do IP, ou um `User-Agent` longo, e
receber 500 de uma rota que não exige token.

| Cabeçalho enviado | Antes | Depois |
|---|---|---|
| `X-Forwarded-For: nao-e-ip` | 500 | 200 |
| `X-Forwarded-For: 1.2.3.4, 5.6.7.8` | 200 | 200 |
| `User-Agent` com 2000 caracteres | 500 | 200 |

Correção: o IP só entra na coluna se o Dart conseguir interpretá-lo como
endereço; o `User-Agent` é cortado em 500. Valor inválido virou campo nulo, não
erro. Cinco casos verificados, todos 200.

### Defeito 6 — token assinado e malformado estourava em toda requisição

`autenticar` roda em cada chamada da API. Ela convertia o conteúdo do token com
`as Map<String, dynamic>`, `as int?` e `as String?`, protegida por um `catch`
de `JWTException`. Só que tipo errado não lança `JWTException`, lança
`TypeError` — que passava direto. Um token **assinado com o segredo correto**
mas com `empresa_id` em texto, ou com conteúdo que não fosse objeto, virava 500
na função mais executada do sistema.

Exige o segredo, então não é porta de entrada; é negação de serviço por quem já
tem conta, e mancha de confiabilidade no ponto pior possível.

Correção: as três conversões passaram a ser verificações (`is Map`, `is int`,
`is String`). Conteúdo inesperado agora devolve "não autenticado", não exceção.
Dois testes novos em `permissao_test.dart` mandam payloads hostis assinados.

### Defeito 7 — `/health` devolvia a exceção crua para quem não tem token

`GET /health` é público e sem autenticação. Na falha de conexão ele respondia
`{"status":"erro","detalhe":"<exceção>"}`. A exceção do driver do PostgreSQL
carrega a string de conexão, ou seja a `DATABASE_URL` com a senha do Neon.

O curioso é que o projeto já conhecia esse risco: `/categorias` apaga a URL da
mensagem antes de registrar, com comentário explicando o porquê. A defesa existia
na rota autenticada e faltava na pública.

Correção: a limpeza virou `lib/diagnostico.dart`, usada nos dois lugares. O
`/health` registra o diagnóstico no servidor e devolve apenas `{"status":"erro"}`.
Três testes cobrem o helper, inclusive URL no meio da pilha. O caso 01 passou a
conferir que a resposta não traz `detalhe` nem a palavra `postgres`.

### Defeito 8 — a raiz anunciava o framework

`GET /` respondia `Welcome to Dart Frog!`, texto que veio do gerador do projeto
e nunca foi trocado. É a primeira URL que qualquer um abre, e entregava a
tecnologia do servidor de graça. Baixa gravidade, custo de correção nenhum.

Correção: `{"servico":"constroi-api","status":"ok"}`. Segue 200, que é o que o
health check do Fly espera nessa rota.

### Defeito 9 — o `.env` vencia a variavel de ambiente

`lib/ambiente.dart` carregava o `.env` com `includePlatformEnvironment: true`,
e nessa biblioteca **o arquivo sobrepoe o ambiente**. Quem exportasse
`DATABASE_URL` apontando para um banco de teste era ignorado em silencio: o
servidor subia e conectava no banco do `.env`, que e o de producao.

O proprio projeto já tinha a ordem certa em outro lugar. `bin/testar_banco.dart`
le o ambiente primeiro e só depois o arquivo, com um comentario dizendo que o
`-DatabaseUrl` do runner deve prevalecer. A ordem estava invertida na biblioteca
que o servidor usa.

Encontrado do pior jeito: ao preparar a execucao ponta a ponta contra um
PostgreSQL descartavel, subi o servidor com `DATABASE_URL` apontando para ele e
a suite escreveu no Neon. O `dart_frog build` copia o `.env` para dentro de
`build/`, então rodar o servidor de lá reabilita o arquivo. Vinte e duas
empresas de teste foram criadas na base real e removidas depois.

Não é vazamento: `.dockerignore` exclui `.env`, `.env*` e `build/`, e a imagem
de producao só contém `/app/servidor` — conferido rodando a imagem. O `.env`
também está no `.gitignore`, assim como `build/`. O risco era escrita acidental
em producao, não exposicao de credencial.

Correção: a decisao virou `escolherVariavel(doSistema, doArquivo)`, com o
ambiente vencendo, e 4 testes a cobrem. Como a imagem de producao não tem
`.env`, o comportamento do que está publicado não muda.

Lição de processo, que vale mais que a correção: **provar o alvo antes de rodar
a suite**. A execucao definitiva criou uma empresa pela API e confirmou que ela
aparecia no banco descartavel e não aparecia no Neon, antes de disparar os 23
casos.

### Defeitos corrigidos antes deste fechamento

Registrados aqui porque compõem o semestre:

| # | Defeito | Origem |
|---|---|---|
| 10 | Exportação do estoque levava só a página visível | Paginação introduzida na PR #48 |
| 11 | Exportação permitida durante o carregamento, com dado do filtro anterior | PR #48 |
| 12 | Atalho de requisições perdia a obra escolhida | Argumentos de rota descartados no `main.dart` |
| 13 | Histórico limitado a 50 pedidos, sem próxima página | PR #48 |
| 14 | Situação desconhecida de pedido contava como pendente | PR #48 |
| 15 | Preço da NF-e podia estourar `NUMERIC(14,2)` e virar 500 | PR #48 |
| 16 | Nome de produto com `=` virava fórmula no CSV exportado | Exportação |
| 17 | 32 testes e o caso 19 quebrados por regra de quantidade inteira | Commit `fad194d` |

Os de 10 a 13 vieram da revisão do Bernardo na PR #48; os demais, de revisão
própria.

---

## 4. Requisitos não funcionais: o que deu para testar

| RNF | Exigência | Situação | Evidência |
|---|---|---|---|
| RNF01 | Comunicação criptografada | ✅ | `sslmode` exigido no normalizador; API em HTTPS com `force_https`; o aplicativo recusa HTTP fora de depuração |
| RNF03 | Senha com hash e salt | ✅ | bcrypt custo 12, conferido no banco pelos casos 02 e 03 |
| RNF04 | Política de senha | ✅ | Caso 03: tamanho mínimo, lista de senhas comuns, símbolos |
| RNF05 | Bloqueio após falhas | ✅ | Casos 03 e 08: cinco erros criam bloqueio, verificado no banco |
| RNF09 | Consulta em até 2 segundos | ✅ | Medido, 7 amostras por rota: mediana 496–505 ms; pior caso 994 ms em pedidos pendentes |
| RNF11 | Sem movimentação duplicada no reenvio | ✅ | Caso 19 (mesma chave de NF-e devolve 409), caso 12 (protocolo concorrente), índice único de movimentação |
| RNF15 | Interface responsiva | ✅ | Testes de estouro em 320×640, 844×390 e 1280×800 com texto ampliado em 1,4× |
| RNF20 | Integridade e concorrência | ✅ | Caso 16: saldo 1, oito aprovações simultâneas, uma passa, sete recebem 409, nenhum 5xx, saldo final 0 e um único registro no log |

### Parciais, com o que falta dito

| RNF | Exigência | Situação | O que existe e o que falta |
|---|---|---|---|
| RNF02 | Dados sensíveis criptografados em trânsito **e em repouso** | 🟡 | Em trânsito, sim. Em repouso, só a senha. Nome, e-mail e dados de obra ficam em claro no banco |
| RNF06 | Sessão expira por inatividade | 🟡 | O token expira em 8 horas de tempo absoluto, não por inatividade. O token de renovação de 30 dias é emitido e nunca usado |
| RNF10 | Alerta visual ao perder conexão | 🟡 | O aplicativo mostra erro de conexão e botão de tentar de novo, com teste. Não detecta estado offline do aparelho |
| RNF14 | Retrocompatibilidade Android documentada | 🟡 | `minSdk` 24 declarado e o APK carrega nele. Não houve teste em versões antigas reais |
| RNF16 | Mensagens de erro claras e orientativas | 🟡 | Mensagens revisadas e cobertas por teste. Não há critério objetivo nem avaliação com usuário |
| RNF17 | Uso em canteiro | 🟡 | Botões de 44 a 48 px e contraste conferido. Não houve teste em campo, com luz do sol ou luva |
| RNF18 | Acessibilidade (WCAG) | 🟡 | Contraste verificado por razão calculada, mínimo 4,5, e redimensionamento em 1,4×. Falta leitor de tela, navegação por teclado e o resto da norma |

---

## 5. Requisitos não funcionais que não deu para testar

Lista honesta. Nenhum destes tem evidência, e dizer o contrário seria mentira.

| RNF | Exigência | Por que não |
|---|---|---|
| RNF07 | 2FA opcional para administradores | Não foi implementado. Não há o que testar |
| RNF08 | Movimentação refletida em até 1 segundo aos demais usuários | O sistema não tem tempo real; a tela busca quando é aberta. Medir exigiria uma funcionalidade que não existe |
| RNF12 | Backup automatizado com restauração testada | O provedor do banco tem recuperação por ponto no tempo, mas não há processo nosso, nem restauração ensaiada |
| RNF13 | Disponibilidade de 99,5% ao mês, monitorada | Não há monitoramento nem histórico. O número não existe para ser medido |
| RNF19 | Conformidade com diretrizes de privacidade | Não houve avaliação jurídica nem mapeamento de dados pessoais |

**Cinco dos vinte RNFs não têm evidência alguma.** Oito estão atendidos com
prova e sete estão parciais. Essa é a fotografia real no fechamento.

---

## 6. Duas decisões de projeto que valem registro

Nenhuma é falha, mas as duas geram pergunta em avaliação.

**Resposta diferente para obra alheia.** `GET /pedidos?obra_id=` de obra de
outra empresa devolve 200 com lista vazia; estoque, painel e custos devolvem
404. Os dois comportamentos são seguros — nenhum confirma a existência do
recurso —, mas a inconsistência é visível.

**Custos não filtram por vínculo.** A tela de custos mostra todas as obras da
empresa ao engenheiro, enquanto o painel restringe pelas obras em que a pessoa
está vinculada. É intencional: custo é visão de gestão.

---

## 7. Como reproduzir

```powershell
cd constroi_api
dart test
```

```powershell
cd constroi_app
flutter test
```

Integração Dart, com PostgreSQL 17 descartável e TLS, apontando
`CONSTROI_TEST_DATABASE_URL` para um banco `constroi_test_*`:

```powershell
cd constroi_api
dart test integration_test/ --concurrency=1
```

Ponta a ponta, com a API e o banco de pé:

```powershell
.\testes\executar.ps1
```

Sem argumento, o runner usa `http://localhost:8080` e a `DATABASE_URL` do
ambiente — que em desenvolvimento é a base real. Para rodar contra um banco
descartável, suba o servidor com `DATABASE_URL` apontando para ele e passe as
duas coisas ao runner, com `-BaseUrl` e `-DatabaseUrl`.

E confirme o alvo antes: crie uma empresa pela API e veja se ela aparece no
banco descartável e **não** aparece no banco real. O defeito 9 existiu porque
essa confirmação não foi feita.

O detalhe de cada caso está em `testes/README.md`; o contrato de cada rota, em
`constroi_api/README.md`.
