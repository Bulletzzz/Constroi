import 'package:constroi_app/features/estoque/exportacao.dart';
import 'package:constroi_app/features/estoque/item_estoque.dart';
import 'package:flutter_test/flutter_test.dart';

ItemEstoque item({
  String nome = 'Cimento CP-II',
  String? sku = 'CIM-01',
  String quantidade = '12.50',
  bool baixo = false,
  String? categoria = 'Alvenaria',
}) => ItemEstoque(
  id: 1,
  obraId: 7,
  produtoId: 20,
  produtoNome: nome,
  unidade: 'saco',
  quantidade: quantidade,
  estoqueMinimo: '5.00',
  baixo: baixo,
  sku: sku,
  categoriaNome: categoria,
);

void main() {
  test('o cabecalho e a linha trazem as colunas do estoque', () {
    final linhas = csvDoEstoque([item()]).split('\r\n');

    expect(linhas, hasLength(2));
    expect(
      linhas.first,
      'SKU;Produto;Unidade;Quantidade;Estoque minimo;'
      'Abaixo do minimo;Categoria;Obra',
    );
    expect(linhas.last, 'CIM-01;Cimento CP-II;saco;12.50;5.00;nao;Alvenaria;7');
  });

  test('item sem sku e sem categoria nao quebra a planilha', () {
    final linha = csvDoEstoque([
      item(sku: null, categoria: null, baixo: true),
    ]).split('\r\n').last;

    expect(linha, 'ID-20;Cimento CP-II;saco;12.50;5.00;sim;;7');
  });

  test('nome com ponto e virgula ou aspas vira celula escapada', () {
    final linha = csvDoEstoque([
      item(nome: 'Tubo 1"; PVC'),
    ]).split('\r\n').last;

    expect(linha, contains('"Tubo 1""; PVC"'));
    expect(linha.split(';'), hasLength(9));
  });

  test('lista vazia devolve apenas o cabecalho', () {
    expect(csvDoEstoque(const []).split('\r\n'), hasLength(1));
  });

  test('o nome do arquivo carrega data e hora com dois digitos', () {
    expect(
      nomeDoArquivo(DateTime(2026, 11, 5, 9, 7)),
      'estoque-20261105-0907.csv',
    );
  });
}
