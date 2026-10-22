# Refatoração da suíte E2E

A suíte da A1 passava, mas era frágil de manter: seletor espalhado, espera fixa e
dado dentro do teste. Aqui está o que estava errado, o que virou e por quê.

Cobertura não mudou: os 7 testes da A1 continuam, com os mesmos nomes de caso.
Entraram mais 2, de stub.

## Smells

| # | Onde estava | Problema | Solução |
|---|---|---|---|
| 1 | `support/e2e.js`, `afterEach` | `cy.wait(1500)` em todo teste, só para o vídeo não cortar no fim. Jogava fora ~10s por execução e atrasava a falha | Removido. A evidência passa a ser o relatório da execução, não os últimos quadros do vídeo |
| 2 | 5 specs | `[data-cy=...]` escrito direto nos testes, repetido entre arquivos. Trocar um identificador obrigava a caçar em todos | Page objects em `cypress/pages/`. O seletor aparece uma vez, no objeto da tela |
| 3 | 5 specs | `{ timeout: 30000 }` e `{ timeout: 60000 }` espalhados sem critério — a mesma espera tinha número diferente em arquivos diferentes | `defaultCommandTimeout` para tudo e uma constante só, `TEMPO_CARGA_APP`, usada apenas onde o Flutter sobe do zero |
| 4 | 5 specs | O mesmo `before` com a semeadura copiado literalmente cinco vezes | `cy.semearCenario()`, um comando |
| 5 | spec 02 e semeadura | Dado dentro do teste: `'SenhaErrada#9'`, CNPJ, endereço, nome do produto | `fixtures/credenciais.json` e `fixtures/empresa.json` |
| 6 | `support/e2e.js` | `semearEmpresa` era um bloco de 90 linhas com 8 chamadas encadeadas, impossível de ler e de reaproveitar em parte | Quebrado em `criarEmpresa`, `criarUsuario`, `criarObra`, `criarProduto` e `vincularPedreiro` |
| 7 | toda a suíte | Nenhum stub. Tudo dependia da API real, então caminho de falha era intestável | `cy.intercept` nos casos 06 e 07 |
| 8 | spec 05 | Semeava empresa, 3 usuários, obra, produto e vínculo para um teste que não usava nada disso | Mantido por enquanto: o segundo teste do arquivo usa. Ver "O que ficou de fora" |
| 9 | `support/e2e.js` | O teste se comportava diferente conforme `Cypress.config('video')` | Some junto com o `cy.wait` do item 1 |
| 10 | `cypress.config.js` + fixture | A senha padrão existia em dois lugares depois das fixtures | Ficou só na fixture |
| 11 | `package.json` | `"cypress": "^15.6.0"` deixava o runner flutuar. Entre uma execução e outra a versão mudava sozinha, e a suíte quebrou por binário ausente sem ninguém ter tocado em teste nenhum | Versão fixada em `15.21.1` |

## Como ficou

```
cypress/
  e2e/        os 7 casos
  fixtures/   credenciais, empresa, painel
  pages/      login, painel, estoque, navegacao
  support/    e2e.js (só registra), comandos.js, cenario.js
```

### Page objects

Um por tela, mais `navegacao`, que é o menu inferior — componente compartilhado,
mesma regra: o seletor mora lá.

Nenhum spec escreve `[data-cy=...]`. Quem precisa de um seletor pede à tela.

### Comandos

| Comando | Substitui |
|---|---|
| `cy.entrarComo(email)` | abrir o app, preencher os dois campos, enviar e esperar o menu — repetido em 6 dos 7 testes |
| `cy.irPara(secao)` | clicar no item do menu e esperar a tela daquela seção aparecer |
| `cy.semearCenario()` | o `before` que estava copiado em cinco arquivos |

Mais três de apoio, que existem para os page objects não repetirem sintaxe:
`cy.porIdentificador`, `cy.naoExiste` e `cy.digitar`.

O `cy.digitar` guarda uma particularidade desta aplicação: o Flutter Web desenha
em canvas e o campo editável aparece no DOM com o sufixo `-campo`, espelhado pela
árvore de acessibilidade. Clicar no container e digitar no `-campo` é um detalhe
que não precisa estar em teste nenhum.

### Dados

`credenciais.json` tem a senha padrão, a senha errada e um e-mail inexistente.
`empresa.json` tem o modelo de empresa, obra e produto usado na semeadura.

Usados em dois cenários, um deles de falha:

- **01 login válido** — senha padrão vinda da fixture
- **02 login inválido** — senha errada vinda da fixture, cenário de falha

### Stubs

- **06 painel com stub** — `cy.intercept` devolve `painel.json`. Prova que a tela
  mostra o que a API respondeu, sem depender do estado do banco. Os números da
  fixture são propositalmente distantes de qualquer valor real (137, 9, 41), para
  que um número vindo de outro lugar não passe por acaso.
- **07 login com API fora** — `cy.intercept` devolve 503 no login. Prova que a
  aplicação avisa e não deixa entrar quando o servidor falha. Esse caminho não
  tinha como ser testado antes, porque exigiria derrubar a API de verdade.

### Estabilidade

Nenhuma espera fixa sobrou. Toda espera é por uma condição: a tela de login
existir, o menu aparecer, a tela da seção carregar, a requisição interceptada
chegar.

`retries` está desligado de propósito. Teste que só passa na segunda tentativa
está escondendo instabilidade, e o objetivo aqui era justamente não ter nenhuma.

## O que ficou de fora, e por quê

**A suíte não limpa o que cria.** Cada execução deixa uma empresa e três usuários
no banco, para sempre. Hoje há cerca de 60 empresas órfãs acumuladas de execuções
antigas. Resolver isso é um cartão próprio, não cabia aqui sem mudar a API.

**O `Cypress.env()` está a caminho de sair.** A execução avisa que
`allowCypressEnv` é inseguro e será removido numa versão maior; a suíte ainda usa
`Cypress.env('apiUrl')` na semeadura. A migração para `cy.env()` não entrou aqui
para não mexer numa suíte que acabou de ficar verde às vésperas da entrega, mas
está mapeada.

**A tela de erro do painel não tem identificador.** O primeiro desenho do caso 07
era interceptar o painel com 503 e afirmar a mensagem de erro. Não dá: o widget de
erro do painel não é exposto na árvore de acessibilidade, e em canvas o que não
tem identificador não existe para o teste. Por isso o cenário de falha ficou no
login, que tem `login-erro`. Vale um cartão para o painel e as outras telas
exporem os próprios estados de erro.
