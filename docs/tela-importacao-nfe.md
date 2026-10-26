# Tela de importação de NF-e

Acesso em **Estoque → Importar NF-e / Anexar XML**, para engenheiro e master.
A rota interna `/entradas/xml` usa a guarda de perfil do aplicativo.
A navegação inferior continua com os cinco módulos existentes.

## Fluxo

1. Selecionar a obra e um arquivo XML de até 2 MiB.
2. Revisar a chave da nota e os materiais: código, descrição, unidade e quantidade.
3. Confirmar para enviar `POST /entradas/xml`, em multipart com `xml` e `obra_id`.
4. Voltar ao estoque; a lista e os indicadores são consultados novamente.

No modo **Anexar a uma entrada**, informar o número da entrada existente,
selecionar o XML, revisar e confirmar. O envio usa `PATCH /entradas/{id}/xml`
somente com o arquivo. A obra é definida pela entrada no servidor.
O anexo é declaratório: não compara o conteúdo da nota com o lançamento
anterior e não altera materiais nem saldos. Essa informação aparece antes
da confirmação.

A API atual não possui consulta de entradas nem rota de prévia. Por isso,
o anexo usa o número informado e a prévia é feita no aplicativo, sem gravar
dados. O servidor continua responsável pela existência da entrada/obra,
permissões, catálogo e unicidade da chave.

## Validação e falhas

- Seleção cancelada preserva o arquivo anterior; seleção inválida o descarta.
- A leitura local valida extensão, tamanho, UTF-8, estrutura/namespace da NF-e,
  chave de 44 dígitos, 1 a 200 materiais e quantidades positivas compatíveis com
  duas casas decimais. Não arredonda quantidades e rejeita DTD/entidades.
- Os bytes originais são enviados sem reescrever o XML.
- As unidades da prévia são normalizadas em minúsculas, como no parser da API.
- Nenhuma chamada de gravação acontece antes da confirmação.
- O envio desabilita a confirmação e a edição; a saída fica bloqueada até a resposta.
- **422:** lista código, nome, unidade e motivo de cada material pendente:
  não encontrado, correspondência ambígua ou unidade diferente.
- **409:** preserva a mensagem do servidor, distinguindo nota já registrada,
  entrada que já tem XML e limite de estoque.
- **401:** reutiliza o encerramento da sessão do cliente de API.
- **400/403/404/413/500:** apresenta a mensagem e mantém a revisão.
- Falha de rede ou tempo esgotado avisa que o resultado não foi confirmado;
  o usuário deve conferir o registro antes de tentar novamente.

Não há alteração nas rotas, regras ou migrations da API.

## Verificação

Validação repetida após rebase sobre `53adba3` (`origin/main`, incluindo o
cadastro da PR #38), com Flutter 3.44.8 / Dart 3.12.2:

- 186 testes do aplicativo passaram (132 da base e 54 adicionados nesta entrega).
- Análise estática sem ocorrências.

A compilação Web foi concluída na revisão anterior (`0a1157d`), antes do rebase.
Nesta rodada foram repetidos `flutter test --no-pub` e `flutter analyze --no-pub`.

```powershell
Set-Location constroi_app
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub --no-web-resources-cdn --no-wasm-dry-run --dart-define=API_BASE_URL=/api
```

Os testes de NF-e cobrem leitura, upload multipart autenticado, preservação do
arquivo original, prévia sem gravação, anexo, erros, duplo clique, sessão
expirada, ausência de obras, seleção cancelada e recuperação após falha.
Os testes de navegação cobrem o acesso pelo estoque e a rota direta em cada perfil.

O app e a API leem a mesma fixture
[`contrato.xml`](../testes/fixtures/nfe/contrato.xml) e comparam chave, códigos,
nomes, unidades e quantidades com um único
[`contrato.json`](../testes/fixtures/nfe/contrato.json). O XML inclui unidades
em maiúsculas e mistas, espaços, entidade XML e quantidades com zeros extras.
Execute também `dart test test/nfe_test.dart` na pasta `constroi_api` (6 testes).

A varredura de layout percorre formulário, revisão, pendências, anexo e sucesso
em **320×640, 844×390 e 1280×800**, com texto ampliado em 1,4× e nomes longos.
Os identificadores estão em [casos-de-teste.md](casos-de-teste.md).
No Web, o observador também identifica o input temporário do plugin como
`nfe-arquivo-campo`, permitindo ao QA carregar o arquivo por seletor dedicado.
A busca do seletor fica em `marcar()`, somente para `nfe-arquivo`, e reutiliza
`marcarCampos()`. A criação posterior do input remarca o botão ainda conectado;
mutações dos demais elementos não fazem consultas globais ao documento.
O comportamento foi conferido em 8 verificações isoladas no navegador,
incluindo entrada/saída da tela e criação do input depois do botão.

As capturas abaixo foram renderizadas com dados simulados e texto em escala
normal. A validação HTTP usa cliente simulado; não houve execução do Cypress
com backend real nem teste do seletor em dispositivos Android/iOS físicos.

- [Formulário em 320×640](evidencias/nfe/formulario-320x640.png)
- [Prévia em 844×390](evidencias/nfe/previa-844x390.png)
- [Materiais pendentes em 1280×800](evidencias/nfe/pendencias-1280x800.png)

O seletor utiliza o plugin oficial [file_selector](https://pub.dev/packages/file_selector),
com filtros de extensão, MIME e tipo uniforme para as plataformas suportadas.
