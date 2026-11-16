# Plano de testes consolidado

Responsável: Eduardo Sochodolak (QA) · Fechamento: 16/11/2026 · Base: `origin/main`
em `41faa50`, mais a branch `qa/plano-de-testes-final`

Este documento é a entrega de QA do semestre. Diz o que foi testado, como, o que
foi encontrado e — tão importante quanto — o que não deu para testar.

Números são medidos, nunca estimados. Onde não medi, está escrito que não medi.

---

## 1. O que existe de teste, em camadas

| Camada | Quantidade | Onde roda | Medido em |
|---|---|---|---|
| Unidade na API | 313 | `cd constroi_api && dart test` | 16/11/2026 |
| Widget no aplicativo | 289 | `cd constroi_app && flutter test` | 16/11/2026 |
| Integração Dart | 149 | `dart test integration_test/` | 16/11/2026 |
| Integração ponta a ponta | 23 casos, 706 chamadas | `.\testes\executar.ps1` | 16/11/2026 |
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
| `GET /health` | 200 | Esperado; expõe apenas disponibilidade do banco |
| `POST /login` | 400 | Precisa ser público |
| `POST /empresas` e `/empresa` | 400 | **Era falha** — ver defeito 1 |
| Outras 14 rotas | 401 | Correto |

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

### Defeitos corrigidos antes deste fechamento

Registrados aqui porque compõem o semestre:

| # | Defeito | Origem |
|---|---|---|
| 5 | Exportação do estoque levava só a página visível | Paginação introduzida na PR #48 |
| 6 | Exportação permitida durante o carregamento, com dado do filtro anterior | PR #48 |
| 7 | Atalho de requisições perdia a obra escolhida | Argumentos de rota descartados no `main.dart` |
| 8 | Histórico limitado a 50 pedidos, sem próxima página | PR #48 |
| 9 | Situação desconhecida de pedido contava como pendente | PR #48 |
| 10 | Preço da NF-e podia estourar `NUMERIC(14,2)` e virar 500 | PR #48 |
| 11 | Nome de produto com `=` virava fórmula no CSV exportado | Exportação |
| 12 | 32 testes e o caso 19 quebrados por regra de quantidade inteira | Commit `fad194d` |

Os de 5 a 8 vieram da revisão do Bernardo na PR #48; os demais, de revisão
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

O detalhe de cada caso está em `testes/README.md`; o contrato de cada rota, em
`constroi_api/README.md`.
