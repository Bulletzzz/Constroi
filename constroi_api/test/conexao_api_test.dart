import 'package:constroi_api/conexao_api.dart';
import 'package:test/test.dart';

void main() {
  const runtime = 'postgresql://app:segredo@host/db?sslmode=require';
  const migration = 'postgresql://dono:outro-segredo@host/db?sslmode=require';
  test('runtime exige TLS, endpoint direto, identidade e limite de pool', () {
    expect(validarUrlApi(runtime).host, 'host');
    for (final url in [
      'postgresql://app:segredo@host/db',
      'postgresql://app:segredo@ep-pooler.neon.tech/db?sslmode=require',
      '$runtime&host=outro',
      '$runtime&user=dono',
      '$runtime&max_connection_count=0',
      '$runtime&max_connection_count=51',
      'postgresql://host/db?sslmode=require',
    ]) {
      try {
        validarUrlApi(url);
        fail('URL insegura foi aceita');
      } on FormatException catch (erro) {
        expect('$erro', isNot(contains('segredo')));
      }
    }
  });
  test('migration usa somente ambiente proprio sem fallback', () {
    expect(
      () => urlDeMigration({'DATABASE_URL': runtime}),
      throwsFormatException,
    );
    expect(urlDeMigration({'MIGRATION_DATABASE_URL': migration}), migration);
    expect(
      () => urlDeMigration({
        'DATABASE_URL': runtime,
        'MIGRATION_DATABASE_URL': runtime,
      }),
      throwsFormatException,
    );
    expect(
      () => urlDeMigration({
        'DATABASE_URL': runtime,
        'MIGRATION_DATABASE_URL': runtime.replaceFirst('app:', '%61pp:'),
      }),
      throwsFormatException,
    );
  });
  test(
    'cap nao pode ser desligado ou aumentado, margem e maior que cap',
    () async {
      for (final limite in [0, -1, 30001]) {
        expect(
          () => criarPoolApi(runtime, conexaoEstrita: true, limiteMs: limite),
          throwsFormatException,
        );
      }
      final pool = criarPoolApi(runtime, conexaoEstrita: true);
      await pool.close();
      expect(margemFechamentoAuditoriaMs, greaterThan(limiteMaximoTransacaoMs));
    },
  );
  test('pooler atual continua aceito ate ativar o modo estrito', () async {
    const url =
        'postgresql://app:segredo@ep-pooler.neon.tech/db?sslmode=require';
    final padrao = criarPoolApi(url);
    await padrao.close();
    expect(
      () => criarPoolApi(url, conexaoEstrita: true),
      throwsFormatException,
    );
  });
}
