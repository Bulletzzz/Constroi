# Tela de Administração — sem protótipo no Figma

Implementa `/administracao`, restrita ao master pela mesma guarda das outras rotas:
quem não tem o perfil nem vê o item na navegação nem alcança o caminho direto.
A tela tem duas abas, Usuários e Logs, e fecha o RF03 e a consulta de eventos que
a Tela de Equipe deixou explicitamente de fora.

A aba de Usuários lista as pessoas da empresa com nome, e-mail e perfil, marca a
própria linha como "Você" e mostra quantas contas estão ativas. O cadastro pede
nome, e-mail, senha e perfil, valida tamanho e formato antes de chamar a API e
exibe no próprio formulário a recusa que vier do servidor — a política de senha
continua sendo a do backend, o app só evita a ida óbvia. Inativar pede confirmação,
explica que o histórico de ações permanece registrado e troca a ação por um selo
INATIVO na linha.

A aba de Logs consulta `GET /logs` com filtro por autor e por período e paginação
de 50 em 50. O autor é resolvido pelo nome da lista de usuários; quem não estiver
mais na lista aparece como `Usuário #id`. A data final escolhida é inclusiva para
quem usa a tela, então o serviço envia o dia seguinte, porque a API trata
`data_fim` como exclusiva. O avanço de página respeita o teto de offset da API, de
modo que o botão desabilita antes de a consulta ser recusada.

Toda escrita — cadastro ou inativação — descarta os eventos já carregados, para
que voltar à aba de Logs mostre o que acabou de acontecer e não a consulta
anterior.

Há estados de carregamento, falha com nova tentativa, ausência de pessoas e
ausência de eventos para o filtro. Puxar para atualizar recarrega a aba visível.
Respostas atrasadas de consultas substituídas são descartadas.

Não há alteração de API, schema ou migration: as quatro rotas de `/usuarios` e a
rota `/logs` já existiam.

Na pasta `constroi_app`, execute `flutter test test/administracao_test.dart`. Os
testes cobrem a guarda de perfil, o contrato do serviço, cadastro e recusa,
inativação com confirmação e com cancelamento, recarga dos eventos depois de uma
escrita, filtros, paginação e estados vazios e de erro. O layout é verificado com
fonte ampliada em 320×640, 844×390 e 1280×800. Os identificadores usados pelo
Cypress estão em [`docs/casos-de-teste.md`](../docs/casos-de-teste.md).
