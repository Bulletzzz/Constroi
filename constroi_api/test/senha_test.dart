import 'package:constroi_api/senha.dart';
import 'package:test/test.dart';

void main() {
  group('comprimento minimo', () {
    test('senha com 7 caracteres e recusada', () {
      expect(erroDaSenha('Ab#3xyz'), contains('$minimoDaSenha caracteres'));
    });

    test('senha vazia e recusada', () {
      expect(erroDaSenha(''), isNotNull);
    });

    test('senha com exatamente 8 caracteres passa', () {
      expect(erroDaSenha('Ab#3xyzQ'), isNull);
    });
  });

  group('senhas comuns', () {
    test('12345678 e recusada mesmo tendo 8 caracteres', () {
      final erro = erroDaSenha('12345678');
      expect(erro, isNotNull);
      expect(erro, contains('comum'));
    });

    test('password e recusada', () {
      expect(erroDaSenha('password'), contains('comum'));
    });

    test('senha123 e recusada', () {
      expect(erroDaSenha('senha123'), contains('comum'));
    });

    test('maiuscula nao escapa da lista', () {
      expect(erroDaSenha('SENHA123'), contains('comum'));
      expect(erroDaSenha('PassWord'), contains('comum'));
    });
  });

  group('senha aceitavel', () {
    test('senha longa e fora da lista passa', () {
      expect(erroDaSenha('Senha#Forte123'), isNull);
    });

    test('frase longa passa', () {
      expect(erroDaSenha('cimento na obra do bairro'), isNull);
    });
  });

  group('mensagens', () {
    test('curta e comum devolvem motivos diferentes', () {
      expect(erroDaSenha('123'), isNot(equals(erroDaSenha('12345678'))));
    });
  });

  group('hash continua funcionando', () {
    test('senha confere com o proprio hash', () {
      final hash = gerarHash('Senha#Forte123');
      expect(senhaConfere('Senha#Forte123', hash), isTrue);
      expect(senhaConfere('outra senha', hash), isFalse);
    });
  });
}
