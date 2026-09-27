import 'package:constroi_api/obras.dart';
import 'package:test/test.dart';

void main() {
  group('obras', () {
    test('valida nome, endereco e os status permitidos', () {
      expect(validarNomeObra(' Obra Central '), equals('Obra Central'));
      expect(validarEnderecoObra(' Rua A, 10 '), equals('Rua A, 10'));
      expect(validarStatusObra('planejamento'), equals('planejamento'));
      expect(validarStatusObra('ATIVA'), equals('ativa'));
      expect(validarStatusObra('pausada'), equals('pausada'));
      expect(validarStatusObra('concluida'), equals('concluida'));
    });

    test('rejeita dados obrigatorios vazios e status desconhecido', () {
      expect(validarNomeObra(' '), isNull);
      expect(validarEnderecoObra(''), isNull);
      expect(validarStatusObra('cancelada'), isNull);
      expect(validarStatusObra(null), isNull);
    });
  });
}
