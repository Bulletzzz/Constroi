# Suíte de integração

Fala com a API e o banco de verdade, nada simulado. Depois de cada chamada vai
conferir no banco se gravou mesmo — resposta 200 com nada gravado é o erro que
esta suíte existe para pegar.

Rode antes de abrir pull request.

## O que precisa estar de pé

- A API respondendo, normalmente em `http://localhost:8080` pelo Docker
- `dart` no PATH, porque as verificações no banco passam por `constroi_api/bin/testar_banco.dart`

As verificações no banco usam o `constroi_api/.env` que você já tem. Só precisa
de `DATABASE_URL` no ambiente, ou do `-DatabaseUrl`, quando quiser mirar um banco
diferente do que está no `.env`.

Na raiz do repositório:

```powershell
docker compose --env-file constroi_api/.env up -d --build
.\testes\executar.ps1
```

Cada caso cria a própria empresa, usuários, obra e produtos, e apaga tudo no
fim. Não precisa de banco limpo e duas pessoas podem rodar ao mesmo tempo contra
o mesmo banco sem uma derrubar a outra.

## Comandos

```powershell
.\testes\executar.ps1                  # roda todos
.\testes\executar.ps1 -Listar          # só mostra os nomes
.\testes\executar.ps1 -Caso 16         # roda um só, casa por pedaço do nome
.\testes\executar.ps1 -Detalhado       # mostra cada verificação e o corpo das respostas
.\testes\executar.ps1 -SemLimpeza      # deixa os dados no banco e imprime as marcas
```

Dá para apontar para outro ambiente:

```powershell
.\testes\executar.ps1 -BaseUrl http://localhost:8081 -DatabaseUrl 'postgresql://...'
```

Sai com 0 quando tudo passa e 1 quando algo falha. Quando um caso quebra, ele
imprime a linha pronta para repetir só aquele.

## Casos

| Arquivo | O que prova |
|---|---|
| `01_saude` | a API responde e enxerga o banco |
| `02_empresa_e_login` | cadastro de empresa, login e os três perfis |
| `03_politica_de_senha` | senha fraca é recusada e o perfil aceito é validado |
| `04_obras` | criação, edição e validação de obra |
| `05_equipe_da_obra` | vínculo, duplicata e encerramento |
| `06_produtos` | catálogo, SKU e estoque mínimo |
| `07_equipamentos` | cadastro e status |
| `08_usuarios` | leitura, edição e inativação |
| `09_autenticacao_e_permissao` | hierarquia de níveis em cada rota |
| `10_isolamento_entre_empresas` | dado de outra empresa responde 404, nunca 403 |
| `11_pedidos_criacao` | criação e validação dos itens |
| `12_pedidos_protocolo_concorrente` | protocolo único sob concorrência |
| `13_pedidos_leitura` | leitura, filtros e isolamento |
| `14_consulta_de_estoque` | filtros, contrato e vínculo; saldo igual ao mínimo conta como baixo |
| `15_aprovacao_e_baixa` | aprovar debita o estoque na mesma operação |
| `16_concorrencia_na_baixa` | **RNF20**: oito aprovações simultâneas no último saldo |
| `17_recusa_de_pedido` | recusa exige justificativa e registra |
| `18_painel_estoque_baixo` | rupturas e estoque baixo contados contra o banco |
| `19_entrada_por_xml` | importação soma a quantidade certa; material fora do catálogo e XML inválido não gravam nada |
| `20_anexo_de_xml` | anexar documento não mexe no estoque e não aceita duas vezes |

## Escrever um caso novo

Copia um curto, por exemplo o `18`. O esqueleto é:

```powershell
. (Join-Path $PSScriptRoot '..\comum\apoio.ps1')

IniciarCaso 'O que este caso prova'

$c = NovoCenario -ComObra -ComProduto

Chamar GET "/estoque?obra_id=$($c.obra.id)" $c.engenheiro $null 200 'rotulo da verificacao' | Out-Null
Conferir ($algo -eq $esperado) "mensagem que diz o que veio"
VerificarBanco "SELECT ...::text FROM ..." 'esperado' 'o que isso prova'

FinalizarCaso
```

O caso precisa terminar em `FinalizarCaso`, senão o runner acusa.

### Ferramentas do `comum/apoio.ps1`

| Função | Para quê |
|---|---|
| `NovoCenario` | cria empresa, usuários e, conforme as opções, obra, produto, equipe e uma segunda empresa |
| `Chamar` | chamada JSON; confere o status e devolve o corpo quando dá certo |
| `EnviarArquivo` | upload multipart, que o `Chamar` não faz; devolve o corpo inclusive nos erros |
| `MontarNfe` | monta uma NF-e de teste com chave, material, quantidade e unidade |
| `Entrar` | faz login e devolve o token |
| `Conferir` | afirma uma condição qualquer |
| `VerificarBanco` | roda um SELECT que devolve um valor e compara |
| `ExecutarBanco` | ponte para o `testar_banco.dart`: `validar`, `consultar SQL` e `estoque OBRA PRODUTO QUANTIDADE` |

Opções do `NovoCenario`: `-ComUsuarios`, `-ComObra`, `-ComProduto`, `-ComEquipe`,
`-ComEmpresaB`. Ele devolve `marca`, `master`, `engenheiro`, `pedreiro`,
`engenheiroUsuario`, `pedreiroUsuario`, `obra`, `produto`, `rotaEquipe` e
`masterB`, conforme o que foi pedido.

### Por que os casos não se misturam

`NovoCenario` gera uma **marca** única e todo registro criado leva essa marca no
nome. No fim, `FinalizarCaso` apaga tudo daquela marca numa consulta só.

Se um caso novo criar registro em tabela que a limpeza ainda não conhece, a
limpeza falha no FK e derruba a limpeza de todas as marcas da execução — não só a
do caso. Nesse caso, acrescenta a tabela em `LimparMarca`, no `comum/apoio.ps1`.

Cuidado com `ON DELETE CASCADE`: dentro do mesmo statement com CTEs a cascata não
resolve, porque a FK é checada antes de ela rodar. Apaga a tabela filha
explicitamente.
