# Tela de Cadastro

Figma 07. Cria produto e equipamento pelo aplicativo — antes isso só existia por
chamada direta na API.

Entra pela tela de Estoque, no botão **NOVO ITEM**, visível apenas para
engenheiro e master. É página cheia, com CANCELAR e SALVAR ITEM, sem a barra
inferior: o Figma mostra assim, e as duas rotas usadas exigem nível de
engenheiro.

## Os dois formulários

O tipo é escolhido no topo e muda os campos abaixo.

| Campo | Produto | Equipamento |
|---|---|---|
| Nome | obrigatório, 2 a 150 caracteres | igual |
| Código | `sku`, opcional, até 50 | `patrimonio`, **obrigatório**, até 50 |
| Categoria | opcional, vem de `GET /categorias` | — |
| Unidade | obrigatória, 20 valores | — |
| Estoque mínimo | opcional, até duas casas, aceita vírgula | — |
| Status | — | obrigatório, 5 valores |

O botão GERAR sugere um código a partir do nome. É sugestão: quem decide se o
código já existe é o banco, que devolve 409 e a tela mostra.

## O que não está na tela, e por quê

**Localização, fornecedor e valor unitário** aparecem no Figma e não existem em
coluna nenhuma do banco. Não há requisito nem cartão para eles.

**Status do equipamento** é o contrário: a API exige e o Figma não mostra. Sem
ele o cadastro devolve 400, então a tela tem o campo mesmo sem o desenho.

**O bloco de empréstimo** do Figma 07 pertence a uma tela de edição, não de
cadastro: a lista "empréstimos ativos" só faz sentido para um equipamento que já
existe. As rotas são do cartão *Empréstimo e devolução de equipamento*.

## Mudanças na API

A tela precisou de três coisas que não existiam:

- `GET /categorias` devolve as categorias de custo, nível pedreiro
- `POST /produtos` aceita `categoria_custo_id`
- `PATCH /produtos/{id}` aceita `categoria_custo_id`, inclusive nulo para limpar

Antes disso a coluna `produto.categoria_custo_id` era insetável pela API: existia
na tabela, era lida pelo Estoque e pelos Custos, e nenhuma rota escrevia nela.
Produto criado pelo aplicativo nasceria sem categoria e sumiria do relatório de
custos por categoria.

Categoria inexistente devolve 400, não 500: a violação de chave estrangeira é
traduzida na rota.

## Onde está testado

- `constroi_api/test/produtos_test.dart` — o validador de categoria
- `testes/casos/06_produtos.ps1` — categorias contra banco real: lista, cria com
  categoria, recusa categoria zero e inexistente, define e limpa pelo PATCH
- `constroi_app/test/cadastro_test.dart` — troca de tipo, validação de cada
  campo, envio, erro da API na tela, geração de código e varredura de layout em
  três tamanhos com fonte ampliada
