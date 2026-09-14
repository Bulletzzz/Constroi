import 'package:constroi_api/equipamentos.dart';
import 'package:test/test.dart';

void main() {
  group('equipamentos', () {
    test('nome, patrimonio e status validos sao aceitos', () {
      expect(
        validarNomeEquipamento('Betoneira 400L'),
        equals('Betoneira 400L'),
      );
      expect(validarPatrimonio('PT-001'), equals('PT-001'));
      expect(validarStatusEquipamento('disponivel'), equals('disponivel'));
      expect(validarStatusEquipamento('em_uso'), equals('em_uso'));
    });

    test('dados invalidos sao rejeitados', () {
      expect(validarNomeEquipamento(''), isNull);
      expect(validarPatrimonio(''), isNull);
      expect(validarStatusEquipamento('ativo'), isNull);
      expect(validarStatusEquipamento(''), isNull);
    });
  });
}
