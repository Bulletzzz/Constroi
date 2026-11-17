import 'package:constroi_api/ambiente.dart';
import 'package:test/test.dart';

void main() {
  const nomeFlag = 'AUDITORIA_CONEXAO_ESTRITA';
  test('flag ausente mantem modo estrito desligado por padrao', () {
    expect(interpretarBooleano(nomeFlag, null), isFalse);
  });

  test('flag true aceita caixa variada e espacos nas bordas', () {
    for (final valor in [
      'true',
      'True',
      'TRUE',
      'tRuE',
      ' true ',
      '\tTRUE\n',
    ]) {
      expect(interpretarBooleano(nomeFlag, valor), isTrue, reason: valor);
    }
  });

  test('flag false aceita caixa variada e espacos nas bordas', () {
    for (final valor in ['false', 'False', 'FALSE', 'fAlSe', ' false ']) {
      expect(interpretarBooleano(nomeFlag, valor), isFalse, reason: valor);
    }
  });

  test('flag invalida e vazio falham sem expor o valor configurado', () {
    for (final valor in ['', ' ', '1', '0', 'yes', 'on', 'tru', 'SEGREDO']) {
      expect(
        () => interpretarBooleano(nomeFlag, valor),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'nome', contains(nomeFlag))
              .having((e) => e.message, 'segredo', isNot(contains('SEGREDO'))),
        ),
      );
    }
  });

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

  group('escolherVariavel', () {
    test('o ambiente do sistema vence o .env', () {
      expect(
        escolherVariavel('postgresql://teste', 'postgresql://producao'),
        equals('postgresql://teste'),
      );
    });

    test('cai para o .env quando o sistema nao define', () {
      expect(escolherVariavel(null, 'do-arquivo'), equals('do-arquivo'));
      expect(escolherVariavel('', 'do-arquivo'), equals('do-arquivo'));
      expect(escolherVariavel('   ', 'do-arquivo'), equals('do-arquivo'));
    });

    test('devolve nulo quando nenhum dos dois define', () {
      expect(escolherVariavel(null, null), isNull);
      expect(escolherVariavel('', '  '), isNull);
    });

    test('remove espacos nas bordas dos dois lados', () {
      expect(escolherVariavel(' do-sistema ', null), equals('do-sistema'));
      expect(escolherVariavel(null, ' do-arquivo '), equals('do-arquivo'));
    });
  });
}
