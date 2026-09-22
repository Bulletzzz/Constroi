# Matriz de rastreabilidade

Responsável: Eduardo Sochodolak (QA) · Última verificação: 22/09/2026 · Base: `origin/main` em `fdfb341`

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
dentro do aplicativo Flutter. Hoje as duas são coisas bem diferentes.

---

## Requisitos funcionais

| RF | Nome | Ator | Caso de uso | Rota | Protótipo | App | Teste |
|---|---|---|---|---|---|---|---|
| RF01 | Cadastro de empresa | Master | ❌ | ✅ `POST /empresas` | ❌ | ❌ | 🟡 manual |
| RF02 | Autenticação | Todos | ❌ | ✅ `POST /login` | ✅ 01_Login | ❌ | 🟡 parcial |
| RF03 | Manutenção de usuários | Master | ✅ Manter Usuários | ✅ `/usuarios` (4 rotas) | ❌ | ❌ | 🟡 manual |
| RF04 | Consulta de estoque | Pedreiro | 🟡 embutido em Manter Estoque | ❌ | ✅ 03_Estoque | ❌ | ❌ |
| RF05 | Solicitação de produtos | Pedreiro | ✅ Solicitar Pedido + Gerar Protocolo | ❌ | ✅ 04_Requisição | ❌ | ❌ |
| RF06 | Avaliação de pedidos | Engenheiro | ✅ Analisar Pedidos | ❌ | ✅ 05_Aprovações | ❌ | ❌ |
| RF07 | Entrada de estoque manual | Engenheiro | ✅ Solicitar Entrada | ❌ | 🟡 dentro de 05_Aprovações | ❌ | ❌ |
| RF08 | Entrada via XML da NF-e | Engenheiro | ✅ Anexar XML (NF-e) | ❌ | ❌ | ❌ | ❌ |
| RF09 | Anexar XML a registro existente | Engenheiro | ✅ Anexar XML (NF-e) | ❌ | ❌ | ❌ | ❌ |
| RF10 | Manutenção de produtos | Engenheiro | 🟡 embutido em Manter Estoque | ✅ `/produtos` (4 rotas) | ✅ 07_Cadastro | ❌ | 🟡 só validador |
| RF11 | Manutenção de equipamentos | Engenheiro | ❌ | ✅ `/equipamentos` (4 rotas) | ✅ 07_Cadastro | ❌ | 🟡 só validador |
| RF12 | Controle de empréstimos | Engenheiro | ❌ | ❌ | ❌ | ❌ | ❌ |

### Onde está cada coisa

| RF | Arquivo |
|---|---|
| RF01 | `constroi_api/routes/empresas.dart` |
| RF02 | `constroi_api/routes/login.dart`, `lib/senha.dart`, `lib/token.dart` |
| RF03 | `constroi_api/routes/usuarios/` |
| RF10 | `constroi_api/routes/produtos/`, `lib/produtos.dart` |
| RF11 | `constroi_api/routes/equipamentos/`, `lib/equipamentos.dart` |

---

## Cobertura, em número

| Camada | Cobertos | Total |
|---|---|---|
| Caso de uso no diagrama UML | 5 | 12 |
| Rota na API | 5 | 12 |
| Tela desenhada no Figma | 7 | 12 |
| Tela funcionando no aplicativo | **0** | 12 |
| Teste automatizado de verdade | **0** | 12 |

Os 5 requisitos com rota são justamente os de cadastro. **Nenhum requisito do fluxo principal
do produto — pedir, aprovar, baixar estoque, dar entrada — tem rota.**

---

## Buracos, em ordem de urgência

Esta é a lista para o Johann priorizar.

### 1. O fluxo central do produto não existe em lugar nenhum

RF05, RF06 e RF07 têm caso de uso e têm tela desenhada, mas **nenhuma rota**. São a razão de
o sistema existir: o pedreiro pedir e o engenheiro aprovar. Sem eles o Constrói é um cadastro
de produtos.

### 2. Nenhuma tela foi implementada

Doze requisitos, sete telas desenhadas, zero telas funcionando. O `constroi_app/lib/` tem um
arquivo só, e ele ainda é o contador padrão do Flutter.

### 3. Requisitos sem tela nem prevista

**RF01** (cadastro de empresa) e **RF03** (manutenção de usuários) têm rota funcionando e
**não têm tela no Figma**. Hoje só dá para usar por chamada direta na API — o que significa
que ninguém consegue criar uma conta no sistema pelo aplicativo.

**RF08 e RF09** (XML da nota fiscal) não têm rota nem tela. É a funcionalidade que mais
aparece na apresentação e é a menos existente.

**RF12** (empréstimo de equipamento) não tem absolutamente nada: sem caso de uso, sem rota,
sem tela, sem teste.

### 4. Telas sem requisito por trás

O caminho inverso, e vale decidir o que fazer com elas:

| Tela | Situação |
|---|---|
| 02_Painel | Não corresponde a nenhum RF. Os KPIs que mostra não vêm de requisito nenhum. |
| 06_Custos | Não há RF de custo, e não há campo de valor em nenhuma das 12 tabelas. |
| 08_Equipe | Não há RF de equipe, e nada no banco liga usuário a obra. |

Ou vira requisito e entra na documentação, ou sai do escopo. Do jeito que está, são três telas
que ninguém pode cobrar e ninguém pode testar.

### 5. Casos de uso sem RF

**Consultar Logs** está no diagrama como caso de uso do Master e não tem requisito funcional
numerado. A tabela `log_sistema` existe no banco desde a migration 001 e ninguém escreve nela.

### 6. A tabela de RF no PDF está quebrada

No documento `Definicao de requisitos.pdf`, os IDs saíram desalinhados das descrições e dos
atores — RF01 aparece colado na descrição errada. **A numeração desta matriz é a minha leitura
da ordem dos nomes**, e precisa ser confirmada pelo Pedro antes de virar referência oficial.

---

## Sobre os testes

O que existe hoje em `constroi_api/test/`:

| Arquivo | O que cobre de verdade |
|---|---|
| `permissao_test.dart` | 16 casos: hierarquia dos três perfis, leitura e recusa de token |
| `produtos_test.dart` | 2 casos, só as funções de validação de nome e unidade |
| `equipamentos_test.dart` | 2 casos, só as funções de validação |
| `routes/index_test.dart` | 1 caso, a rota de boas-vindas gerada pelo template |

**Nenhum teste automatizado sobe o servidor e chama uma rota.** Foi exatamente por isso que o
pull request #1 passou na análise estática e nos testes com o projeto sem compilar — o defeito
só aparecia ao executar.

Os fluxos ficam cobertos por teste manual, em `constroi_api/testar_rotas.ps1`: 25 chamadas
cobrindo os três CRUDs, os códigos de permissão e os corpos inválidos. É melhor que nada, mas
depende de alguém lembrar de rodar.

### Requisitos não funcionais com evidência

Só os que já dá para afirmar. A triagem completa dos 20 RNFs é outro cartão.

| RNF | Situação |
|---|---|
| RNF01 comunicação criptografada | ✅ conexão ao Neon exige `sslmode=require` |
| RNF03 senha com hash e salt | ✅ bcrypt custo 12, verificado no banco |
| RNF04 política de senha | 🟡 exige 6 caracteres, **não bloqueia senha comum** — `12345678` passa |
| RNF05 bloqueio por tentativa | 🟡 implementado pelo Pedro, sem teste automatizado |
| RNF20 estoque sem valor negativo | 🟡 restrição existe no banco, **a rota de baixa não existe para testar** |

---

## O que fazer com este documento

1. Confirmar a numeração dos RF com o Pedro, por causa da tabela quebrada no PDF.
2. Levar os itens 1 a 5 da lista de buracos para o Johann priorizar.
3. Reconferir a cada fim de semana do plano — a coluna **Teste** é a que mais envelhece.
