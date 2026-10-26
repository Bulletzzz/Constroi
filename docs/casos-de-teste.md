# Casos de teste E2E — Constrói

Disciplina: Qualidade e Teste de Software
Sistema sob teste: Constrói (app Flutter Web + API Dart Frog + PostgreSQL)
Tipo: end-to-end automatizado, caixa-branca quanto aos seletores
Execução: `npx cypress run` na pasta `e2e/`

## Por que estes casos, e não os do roteiro anterior

O roteiro consolidado do Desafio 4 cobre o Cinemec e os portais do governo federal,
sistemas públicos de terceiros. Testes E2E automatizados exigem seletores dedicados
no código, e não temos acesso ao código daqueles sistemas. Por isso os casos abaixo
são novos, escritos sobre o nosso próprio sistema, preservando as mesmas categorias
do roteiro original: caminho feliz, regra de negócio e validação.

## Como o sistema foi preparado para ser testável

O Constrói é Flutter Web. Desde a versão 3.29 o Flutter não tem mais renderizador
HTML: a interface inteira é desenhada em canvas e não existe DOM de componente,
então não há onde colocar um atributo `data-cy`.

A solução tem três partes:

1. `SemanticsBinding.instance.ensureSemantics()` no `main()` liga a árvore de
   acessibilidade, que o Flutter publica como elementos `flt-semantics` no DOM.
2. Os widgets testados recebem `Semantics(identifier: 'nome')`, que o motor
   renderiza como `flt-semantics-identifier="nome"`.
3. Um observador no `web/index.html` espelha esse atributo para `data-cy`, e marca
   também os `input` que o Flutter cria dentro de um campo de texto: o habilitado
   recebe o sufixo `-campo` e o desabilitado, `-inativo`.

Resultado: os testes usam exclusivamente `[data-cy=...]`, sem nenhum seletor por
classe, texto, posição ou tipo de elemento. E o app ganhou de brinde a árvore de
acessibilidade que antes não existia, passando a ser legível por leitor de tela.

## Identificadores disponíveis

| Identificador | Onde |
|---|---|
| `login-email`, `login-senha` | campos da tela de acesso |
| `login-email-campo`, `login-senha-campo` | o `input` editável dentro de cada campo |
| `login-entrar` | botão de envio |
| `login-erro` | mensagem de falha de autenticação |
| `painel-total-itens` | indicador de materiais distintos |
| `painel-rupturas-criticas` | indicador de saldos zerados |
| `painel-estoque-baixo` | indicador de saldos no mínimo ou abaixo |
| `painel-requisicoes-pendentes` | indicador de pedidos aguardando |
| `painel-valor-estimado` | indicador financeiro, só engenheiro e master |
| `custos-obra` | seletor de obra da tela de custos |
| `custos-periodo-semana`, `custos-periodo-mes`, `custos-periodo-total` | botões de período; o ativo tem estado semântico selecionado |
| `custos-resumo` | cartão com o custo do período selecionado |
| `custos-orcamento` | cartão com orçamento, saldo e percentual consumido |
| `custos-lancamentos` | seção de lançamentos do período, inclusive quando vazia |
| `custos-lancamento` | cada lançamento; o identificador se repete nas linhas |
| `estoque-novo-item` | botão que abre o cadastro, só para engenheiro e master |
| `cadastro-titulo` | cabeçalho da tela de cadastro |
| `cadastro-tipo-produto`, `cadastro-tipo-equipamento` | escolha do tipo; o ativo tem estado semântico selecionado |
| `cadastro-nome` | nome do item |
| `cadastro-codigo` | SKU do produto ou patrimônio do equipamento |
| `cadastro-gerar-codigo` | botão que sugere um código a partir do nome |
| `cadastro-categoria`, `cadastro-unidade`, `cadastro-minimo` | campos só do produto |
| `cadastro-status` | status, campo só do equipamento |
| `cadastro-erro` | mensagem de erro vinda da API |
| `cadastro-cancelar`, `cadastro-salvar` | ações do rodapé |
| `estoque-busca` | campo de busca por SKU ou nome |
| `estoque-linha` | linha de saldo na tabela |
| `estoque-vazio` | aviso de resultado sem itens |
| `estoque-importar-nfe` | acesso à importação/anexo, somente engenheiro e master |
| `nfe-modo-importar`, `nfe-modo-anexar` | escolha entre nova entrada e anexo |
| `nfe-obra` | seleção da obra de destino da importação |
| `nfe-entrada`, `nfe-entrada-campo` | número da entrada existente e input editável |
| `nfe-arquivo`, `nfe-arquivo-nome` | seletor de XML e nome do arquivo escolhido |
| `nfe-arquivo-campo` | input de arquivo criado pelo plugin no Web, disponível após abrir o seletor |
| `nfe-revisar`, `nfe-previa`, `nfe-chave` | revisão local antes de enviar à API |
| `nfe-material` | material lido do XML; repete por item |
| `nfe-confirmar`, `nfe-editar` | confirmar envio ou alterar os dados |
| `nfe-erro`, `nfe-conflito` | falhas gerais/422 e conflitos 409, respectivamente |
| `nfe-material-pendente` | material e motivo do 422; repete por pendência |
| `nfe-obras-erro`, `nfe-obras-tentar`, `nfe-obras-vazio` | falha, nova tentativa e ausência de obras |
| `nfe-sucesso`, `nfe-concluir` | resultado confirmado e retorno ao estoque |
| `equipe-obra` | seletor de obra da tela de equipe |
| `equipe-busca` | campo de busca por pessoa, e-mail ou perfil |
| `equipe-busca-campo` | input editável da busca, gerado pelo espelhamento no DOM |
| `equipe-pessoa` | linha clicável que abre o perfil; o identificador se repete nas pessoas |
| `equipe-vazio` | aviso de obra sem equipe, busca sem resultados ou ausência de obras |
| `equipe-erro` | falha ao consultar obras ou equipe, com nova tentativa |
| `nav-painel`, `nav-estoque`, `nav-custos`, `nav-equipe`, `nav-requisicoes` | navegação inferior |

## Massa de dados

Cada caso cria o próprio cenário no `before`, por chamadas à API: empresa, usuário
master, engenheiro, pedreiro, obra, produto e vínculo do pedreiro com a obra. Cada
cenário usa um sufixo aleatório, então os casos não disputam dados entre si e podem
rodar em qualquer ordem.

A preparação usa `cy.request`; todas as asserções de interface usam `data-cy`.

---

## CT-E2E-01 — Login com credenciais válidas

**Categoria:** caminho feliz
**Técnica:** partição de equivalência, classe válida
**Nível:** sistema

**Pré-condição:** empresa e engenheiro criados pela API.

**Passos**
1. Abrir a aplicação.
2. Preencher `login-email` com o e-mail do engenheiro.
3. Preencher `login-senha` com a senha válida.
4. Acionar `login-entrar`.

**Resultado esperado**
- A navegação inferior aparece (`nav-painel` existe).
- A tela de acesso desaparece (`login-email` não existe mais).
- O painel renderiza seus indicadores (`painel-total-itens` existe).
- Nenhuma mensagem de erro é exibida (`login-erro` não existe).

---

## CT-E2E-02 — Login com senha incorreta

**Categoria:** validação
**Técnica:** partição de equivalência, classe inválida
**Nível:** sistema

**Pré-condição:** empresa e engenheiro criados pela API.

**Passos**
1. Abrir a aplicação.
2. Preencher `login-email` com e-mail existente.
3. Preencher `login-senha` com senha errada.
4. Acionar `login-entrar`.

**Resultado esperado**
- `login-erro` aparece e seu texto informa credencial inválida.
- A tela de acesso permanece (`login-email` continua existindo).
- Nenhuma rota interna é liberada (`nav-painel` não existe).

**Observação:** a API responde 401 genérico tanto para senha errada quanto para
e-mail inexistente, de propósito, para não permitir descobrir quais e-mails estão
cadastrados. O teste valida a mensagem ao operador, não o código HTTP.

---

## CT-E2E-03 — Painel reflete os pedidos registrados na API

**Categoria:** regra de negócio
**Técnica:** teste baseado em estado
**Nível:** integração entre interface e serviço

**Pré-condição:** cenário completo, incluindo pedreiro vinculado à obra.

**Passos**
1. Autenticar como engenheiro.
2. Ler o indicador `painel-requisicoes-pendentes`.
3. Criar dois pedidos pela API, em nome do pedreiro.
4. Sair do painel e voltar, pela navegação inferior.
5. Ler o indicador novamente.

**Resultado esperado**
- Na primeira leitura o indicador mostra zero.
- As duas criações retornam HTTP 201.
- Na segunda leitura o indicador mostra dois.

**Observação:** o retorno ao painel é feito pela navegação, e não por recarga da
página, porque a sessão do Constrói vive apenas em memória — recarregar desconecta
o usuário. Essa é uma decisão de projeto e está documentada aqui para que o teste
não pareça arbitrário.

---

## CT-E2E-04 — Navegação respeita o perfil do usuário

**Categoria:** regra de negócio
**Técnica:** tabela de decisão por perfil
**Nível:** sistema

**Pré-condição:** cenário com engenheiro e pedreiro na mesma empresa.

**Passos**
1. Autenticar como engenheiro e inspecionar a navegação.
2. Reabrir a aplicação, autenticar como pedreiro e inspecionar a navegação.

**Resultado esperado**
- Para o engenheiro: `nav-painel`, `nav-estoque` e `nav-custos` existem.
- Para o pedreiro: `nav-painel` e `nav-estoque` existem, `nav-custos` não existe.

A rota de custos exige nível de engenheiro. O teste confirma que a restrição é
aplicada na montagem da interface, e não apenas no servidor.

---

## CT-E2E-05 — Rota protegida exige sessão

**Categoria:** validação
**Técnica:** teste de caminho negativo
**Nível:** sistema

**Pré-condição:** nenhuma sessão ativa no navegador.

**Passos**
1. Abrir diretamente o endereço do estoque, sem autenticar.
2. Em seguida, autenticar e navegar ao estoque pela barra inferior.

**Resultado esperado**
- Sem sessão: a tela de acesso é exibida (`login-email` existe), e nem a navegação
  nem o conteúdo do estoque aparecem (`nav-estoque` e `estoque-busca` não existem).
- Com sessão: `estoque-busca` aparece e a tela de acesso some.

---

## CT-E2E-06 — Painel mostra o que a API responde

**Categoria:** contrato
**Técnica:** resposta controlada por stub
**Nível:** sistema

**Pré-condição:** cenário semeado e `GET /painel` interceptado com `painel.json`.

**Passos**
1. Interceptar a consulta do painel e devolver a fixture.
2. Autenticar como engenheiro e esperar a resposta interceptada.

**Resultado esperado**
- `painel-total-itens`, `painel-rupturas-criticas` e `painel-requisicoes-pendentes`
  exibem exatamente os números da fixture.

Os valores da fixture são distantes de qualquer saldo real (137, 9 e 41) para que
um número vindo de outra origem não passe por coincidência. O caso prova que a
tela mostra o que a API respondeu, sem depender do estado do banco.

---

## CT-E2E-07 — Login quando a API falha

**Categoria:** validação
**Técnica:** injeção de falha por stub
**Nível:** sistema

**Pré-condição:** cenário semeado e `POST /login` interceptado com 503.

**Passos**
1. Interceptar o login e devolver erro de serviço indisponível.
2. Preencher credenciais válidas e enviar.

**Resultado esperado**
- `login-erro` aparece.
- A tela de acesso continua visível e `nav-painel` não existe.

As credenciais são válidas: quem recusa é o servidor. Esse caminho não tinha como
ser exercitado antes do stub, porque exigiria derrubar a API de verdade no meio
da execução.

---

## Resumo da execução

| Caso | Testes | Resultado |
|---|---|---|
| CT-E2E-01 | 1 | passou |
| CT-E2E-02 | 1 | passou |
| CT-E2E-03 | 1 | passou |
| CT-E2E-04 | 2 | passou |
| CT-E2E-05 | 2 | passou |
| CT-E2E-06 | 1 | passou |
| CT-E2E-07 | 1 | passou |
| **Total** | **9** | **9 passaram** |

Evidências em `e2e/evidencias/`: um vídeo por caso e a saída completa da execução
em `execucao-completa.txt`.
