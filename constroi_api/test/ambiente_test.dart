import 'package:constroi_api/ambiente.dart';
import 'package:test/test.dart';

void main() {
  test('remove channel_binding da URL gerada pelo Neon', () {
    final resultado = normalizarDatabaseUrl(
      'postgresql://usuario:senha@host/neondb'
      '?sslmode=require&channel_binding=require',
    );

    final uri = Uri.parse(resultado);
    expect(uri.queryParameters['sslmode'], 'require');
    expect(uri.queryParameters.containsKey('channel_binding'), isFalse);
    expect(uri.host, 'host');
  });

  test('preserva URL que não possui channel_binding', () {
    const entrada = 'postgresql://usuario:senha@host/neondb?sslmode=require';
    expect(normalizarDatabaseUrl(entrada), entrada);
  });

  test('recusa URL sem sslmode', () {
    const senha = 'SENHA_SECRETA_NAO_PODE_VAZAR';
    late Object erro;

    try {
      normalizarDatabaseUrl(
        'postgresql://usuario:$senha@host/neondb',
      );
    } catch (excecao) {
      erro = excecao;
    }

    expect(erro, isA<FormatException>());
    expect(erro.toString(), isNot(contains(senha)));
    expect(
      erro.toString(),
      contains('A conexao remota deve usar sslmode=require'),
    );
  });

  test('recusa URL que perde sslmode ao remover channel_binding', () {
    expect(
      () => normalizarDatabaseUrl(
        'postgresql://usuario:senha@host/neondb?channel_binding=require',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
