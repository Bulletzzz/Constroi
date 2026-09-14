import 'package:constroi_api/produtos.dart';
import 'package:test/test.dart';

void main() {
  group('produtos', () {
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
