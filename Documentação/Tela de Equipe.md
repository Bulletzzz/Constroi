# Tela de Equipe — Figma 08

Implementa `/equipe` com lista de pessoas por obra, perfil de cada pessoa, busca
por nome/e-mail/perfil e detalhes ao tocar na linha. Os detalhes mostram nome,
perfil, e-mail e início do vínculo. Os perfis são os existentes na API: Pedreiro,
Engenheiro e Master; perfis desconhecidos são identificados como não informados.

O serviço consulta `GET /obras` e depois `GET /obras/{id}/equipe`. A seleção inicial
é a primeira obra disponível; mudar a obra limpa a busca e carrega sua equipe.
O backend já filtra a empresa e permite ao pedreiro consultar apenas obras com
vínculo ativo. Engenheiro e master consultam as obras da empresa.

Há estados de carregamento, falha com nova tentativa, ausência de obras, obra
sem equipe e busca sem resultados. Puxar para atualizar recarrega obras e equipe,
preservando a obra selecionada quando ainda disponível. Respostas atrasadas de
outra obra são descartadas.

A interface usa cabeçalho, navegação, cores, busca e listagem inspirados no Figma
08. O recorte é o checklist do cartão: pessoas por obra e seus perfis. Cadastro
de usuários, alteração de permissões e logs de auditoria desenhados no mesmo
quadro não fazem parte desta entrega. A tela não impõe o rótulo “acesso master”
do protótipo, pois a autorização de leitura já definida no projeto inclui o
pedreiro vinculado à obra. “Vínculo ativo” descreve a participação na obra, não
o estado de login da conta.

Não há alteração de API, schema ou migration.

Na pasta `constroi_app`, execute `flutter test test/equipe_test.dart`. Os testes
cobrem consulta por obra, perfis, busca, detalhes, navegação do pedreiro, estados
vazios e de erro, resposta atrasada e seletores semânticos. O layout e o diálogo
de perfil são verificados com fonte ampliada em 320×640, 844×390 e 1280×800.
Os identificadores usados pelo Cypress estão em
[`docs/casos-de-teste.md`](../docs/casos-de-teste.md).
