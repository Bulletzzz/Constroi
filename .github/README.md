# Protecao da main

O ruleset [Protecao da main](https://github.com/Bulletzzz/Constroi/rules/24766942)
exige pull request, uma aprovacao de outra pessoa, aprovacao do ultimo push e
resolucao das conversas. Novos commits invalidam as aprovacoes anteriores.
Force push e exclusao da main ficam bloqueados. A lista de bypass esta vazia.

O workflow `protecao-main.yml` oferece duas checagens obrigatorias:

- `API - analise e testes`: instala as dependencias com o lockfile, executa
  `dart analyze` e os testes da API com Dart 3.11.
- `Politica de coautoria`: confere os commits novos e o titulo/corpo do PR,
  rejeitando trailers `Co-Authored-By` com Claude ou `noreply@anthropic.com`.
  Mencoes em prosa e coautores humanos continuam permitidos.

Os testes da API executados aqui nao precisam de banco nem Docker. O runner
HTTP `testar_rotas.ps1` depende de uma API e banco configurados e deve ser
executado separadamente quando a mudanca exigir essa validacao.

A branch deve estar atualizada com a main e as duas checagens devem passar
antes do merge. Depois da integracao deste workflow, atualize os PRs que ja
estavam abertos para que tambem executem as checagens.

A politica verifica metadados existentes antes do merge. Mensagens editadas
manualmente na tela de merge tambem precisam ser conferidas pelo responsavel.
Mudancas neste workflow ou nestes scripts devem ser avaliadas na revisao.
