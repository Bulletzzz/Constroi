import 'package:constroi_api/usuarios.dart';
import 'package:test/test.dart';

void main() {
  group('tipo de usuario', () {
    test('aceita e normaliza os tres perfis suportados', () {
      expect(validarTipoUsuario('pedreiro'), 'pedreiro');
      expect(validarTipoUsuario(' Engenheiro '), 'engenheiro');
      expect(validarTipoUsuario('MASTER'), 'master');
    });

    test('recusa perfil desconhecido', () {
      expect(validarTipoUsuario('admin'), isNull);
      expect(validarTipoUsuario(''), isNull);
      expect(validarTipoUsuario(null), isNull);
    });
  });
}
