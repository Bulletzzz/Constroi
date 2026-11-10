import '../../core/catalogo/opcoes.dart';
import 'item_estoque.dart';

const _colunas = [
  'SKU',
  'Produto',
  'Unidade',
  'Quantidade',
  'Estoque minimo',
  'Abaixo do minimo',
  'Categoria',
  'Obra',
];

String csvDoEstoque(List<ItemEstoque> itens) {
  final linhas = <String>[_linha(_colunas)];
  for (final item in itens) {
    linhas.add(
      _linha([
        item.identificacao,
        item.produtoNome,
        item.unidade,
        formatarQuantidade(item.quantidade),
        item.estoqueMinimo,
        item.baixo ? 'sim' : 'nao',
        item.categoriaNome ?? '',
        '${item.obraId}',
      ]),
    );
  }
  return linhas.join('\r\n');
}

String nomeDoArquivo(DateTime agora) =>
    'estoque-${agora.year}'
    '${_dois(agora.month)}${_dois(agora.day)}-'
    '${_dois(agora.hour)}${_dois(agora.minute)}.csv';

String _linha(List<String> valores) => valores.map(_celula).join(';');

String _celula(String valor) {
  final limpo = valor.replaceAll('"', '""');
  return limpo.contains(RegExp('[;"\r\n]')) ? '"$limpo"' : limpo;
}

String _dois(int valor) => valor.toString().padLeft(2, '0');
