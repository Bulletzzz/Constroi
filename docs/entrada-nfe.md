# Entrada por XML da NF-e (RF09, card 75)

`POST /entradas/xml`, autenticado como engenheiro/master, recebe multipart:

- `obra_id`: inteiro positivo da empresa autenticada.
- `xml`: um arquivo XML UTF-8, até 2 MiB, contendo `NFe` ou `nfeProc` no namespace `http://www.portalfiscal.inf.br/nfe`.

O arquivo deve trazer `infNFe/@Id=NFe` seguido de 44 dígitos e de 1 a 200 itens
com `cProd`, `xProd`, `uCom` e `qCom`. O parser usa `package:xml`, aceita namespace
padrão ou prefixado, rejeita DTD/entidades e não busca arquivos ou URLs externos.
Ele extrai dados; não valida assinatura, autorização SEFAZ, preços ou situação
fiscal da nota. Quantidades precisam caber em NUMERIC(12,2); zeros extras são
aceitos, mas valores com precisão maior não são arredondados.

O vínculo procura primeiro o SKU igual a `cProd`, depois nome igual a `xProd`,
sempre na empresa da sessão e sem diferenciar maiúsculas. O nome precisa ser
único e a unidade comercial precisa ser a mesma do cadastro. Não há conversão
automática de unidades ou criação automática de produtos. Código do fornecedor
que não corresponde ao SKU interno exige cadastro compatível ou nome único.

Retornos:

- **201**: `id`, `obra_id`, `chave_nfe`, `data`, `itens` (produto/quantidade) e
  `saldos` (produto/saldo final). Quantidades são strings decimais.
- **400**: formulário/XML/obra_id inválido; **401/403**: autenticação/perfil;
  **404**: obra inexistente ou de outra empresa; **413**: upload excedido.
- **422**: `materiais_pendentes` com código, nome, unidade e motivo
  (`nao_encontrado`, `ambiguo`, `unidade_diferente`). Nenhuma escrita ocorre.
- **409**: chave já registrada na empresa ou estoque excederia o limite numérico.

Entrada, itens, acréscimos de estoque e log são gravados na mesma transação.
O XML original permanece em `entrada_estoque.xml_nota_fiscal`. O ator vem do token.
Os saldos são atualizados em ordem de produto com UPSERT e aritmética NUMERIC;
materiais repetidos são agregados. Falha em qualquer escrita reverte tudo.
A constraint da migration **011** impede reimportações, inclusive concorrentes.
As migrations 010 (recusa) e 012 (campos do pedido) são independentes da 011.
Não há dependência da futura entrada manual (`POST /entradas`, card 74).

```powershell
curl.exe -X POST http://localhost:8080/entradas/xml `
  -H "Authorization: Bearer SEU_TOKEN" `
  -F "obra_id=1" -F "xml=@nota.xml;type=application/xml"
```

## Validação local

Na pasta `constroi_api`, rode `dart test`. Para HTTP + PostgreSQL real:

```powershell
$env:CONSTROI_TEST_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55434/constroi_test_nfe?sslmode=require&max_connection_count=10'
dart test integration_test/nfe_test.dart --reporter expanded
```

A suíte só aceita banco local descartável `constroi_test_*`, recria `public` e
não carrega `.env`. Cobre importação multipart, decimais, permissões, isolamento,
materiais pendentes, reenvio/concorrência, limites e rollback após falha no log.
O runner de migrations deve ser executado duas vezes em outro banco local vazio:
primeira aplicação completa, segunda sem alterações. Nenhum comando exige Neon
ou implantação Docker para validar esta entrega.

## Anexar XML a uma entrada existente (RF10, card 76)

`PATCH /entradas/{id}/xml`, com o mesmo multipart (`xml`) e perfil
engenheiro/master, anexa o documento original e sua chave à entrada da empresa.
Não exige `obra_id`: a obra é a da entrada já registrada. Os itens e quantidades
do XML são lidos e validados, mas não substituem o lançamento manual. O fluxo
não insere itens nem altera qualquer saldo de estoque.

Retorna **200** com `id`, `obra_id`, `chave_nfe` e `xml_anexado: true`.
ID inválido retorna **400**; entrada inexistente ou de outra empresa, **404**.
Entrada que já possui XML (inclusive legado) e chave já usada na empresa retornam
**409**, sem sobrescrever documento ou repetir log. As validações de upload e
XML são as mesmas do POST. O log `ANEXO_NFE` usa o ator autenticado e é confirmado
na mesma transação do anexo; falha no log reverte XML e metadados.

O bloqueio de linha serializa anexações à mesma entrada. A constraint da
migration 011 impede anexações da mesma nota em entradas diferentes, inclusive
em concorrência com importações pelo POST. Não requer outra migration.

```powershell
curl.exe -X PATCH http://localhost:8080/entradas/7/xml `
  -H "Authorization: Bearer SEU_TOKEN" `
  -F "xml=@nota.xml;type=application/xml"
```

A suíte `integration_test/nfe_test.dart` também cobre anexação, reenvio, disputa
pela mesma entrada/chave, XML legado, isolamento, permissões e rollback do log,
verificando que as linhas de itens e estoque permanecem iguais.
