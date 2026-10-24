import 'package:constroi_api/produtos.dart';
import 'package:test/test.dart';

void main() {
  group('categoria de custo', () {
    test('aceita inteiro positivo em numero ou texto', () {
      expect(validarCategoriaCusto(3), 3);
      expect(validarCategoriaCusto('3'), 3);
      expect(validarCategoriaCusto(null), isNull);
    });

    test('recusa zero, negativo, texto e estouro de INTEGER', () {
      for (final valor in [0, -1, 'dois', '', 2147483648]) {
        expect(validarCategoriaCusto(valor), isNull, reason: '$valor');
      }
    });
  });

  group('produtos', () {
    test(
      'SKU opcional e aparado; tipos e tamanhos invalidos sao recusados',
      () {
        expect(validarSkuProduto(' CIM-01 '), (valido: true, valor: 'CIM-01'));
        expect(validarSkuProduto(null), (valido: true, valor: null));
        expect(validarSkuProduto(' '), (valido: true, valor: null));
        expect(validarSkuProduto(12).valido, isFalse);
        expect(validarSkuProduto('a' * 51).valido, isFalse);
      },
    );
    test('minimo respeita precisao e limites de NUMERIC(12,2)', () {
      for (final valor in [0, 5, 4.5, '4,50', '9999999999.99']) {
        expect(validarEstoqueMinimo(valor), isNotNull);
      }
      for (final valor in [
        null,
        true,
        -1,
        0.001,
        '1.001',
        '10000000000',
        double.infinity,
        double.nan,
        '',
        'abc',
      ]) {
        expect(validarEstoqueMinimo(valor), isNull);
      }
    });
    test('nome e unidade validos sao aceitos', () {
      expect(validarNomeProduto('Cimento'), equals('Cimento'));
      expect(validarNomeProduto('  '), isNull);
      expect(validarUnidadeProduto('kg'), equals('kg'));
      expect(validarUnidadeProduto('m2'), equals('m2'));
    });

    test('nome e unidade invalidos sao rejeitados', () {
      expect(validarNomeProduto(''), isNull);
      expect(validarUnidadeProduto(''), isNull);
      expect(validarUnidadeProduto('caixa grande'), isNull);
    });
  });
}
