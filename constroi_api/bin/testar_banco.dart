import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/ambiente.dart';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

/// Apoio ao testar_rotas.ps1, usando o mesmo driver das migrations.
Future<void> main(List<String> argumentos) async {
  Pool<void>? conexao;
  try {
    final comando = argumentos.isEmpty ? '' : argumentos.first;
    if (!{'validar', 'consultar', 'estoque'}.contains(comando) ||
        (comando == 'validar' && argumentos.length != 1) ||
        (comando == 'consultar' && argumentos.length != 2) ||
        (comando == 'estoque' && argumentos.length != 4)) {
      throw const FormatException(
        'Uso: dart run bin/testar_banco.dart validar | consultar SQL | '
        'estoque OBRA_ID PRODUTO_ID QUANTIDADE',
      );
    }

    int? obra;
    int? produto;
    if (comando == 'estoque') {
      obra = _id(argumentos[1]);
      produto = _id(argumentos[2]);
      if (!RegExp(r'^(0|[1-9]\d{0,9})(\.\d{1,2})?$').hasMatch(argumentos[3])) {
        throw const FormatException('Quantidade de teste invalida.');
      }
    }

    final envPath = Platform.environment['DATABASE_ENV_FILE'] ?? '.env';
    final ambiente = DotEnv()
      ..load(File(envPath).existsSync() ? [envPath] : []);
    // O -DatabaseUrl do runner deve prevalecer sobre o arquivo .env.
    final databaseUrl = Platform.environment['DATABASE_URL']?.trim();
    final url = databaseUrl == null || databaseUrl.isEmpty
        ? ambiente['DATABASE_URL']?.trim()
        : databaseUrl;
    if (url == null || url.isEmpty) {
      throw const FormatException(
        'DATABASE_URL nao configurada. Use .env, a variavel de ambiente '
        'ou -DatabaseUrl no testar_rotas.ps1.',
      );
    }
    conexao = Pool<void>.withUrl(normalizarDatabaseUrl(url));

    final Map<String, Object?> resposta;
    switch (comando) {
      case 'validar':
        await conexao.execute('SELECT 1');
        resposta = {'ok': true};
      case 'consultar':
        final resultado = await conexao.execute(argumentos[1]);
        if (resultado.length != 1 || resultado.single.length != 1) {
          throw const FormatException('A verificacao deve retornar um valor.');
        }
        resposta = {'resultado': resultado.single[0].toString()};
      case 'estoque':
        resposta = await conexao.runTx((transacao) async {
          final categoria = await transacao.execute(
            Sql.named('''
              SELECT c.id, c.nome
              FROM obra o
              JOIN produto p ON p.empresa_id = o.empresa_id
              CROSS JOIN categoria_custo c
              WHERE o.id = @obra AND p.id = @produto AND c.nome = @categoria
            '''),
            parameters: {
              'obra': obra,
              'produto': produto,
              'categoria': 'Aço e vergalhão',
            },
          );
          if (categoria.length != 1) {
            throw const FormatException(
              'Obra/produto da mesma empresa ou categoria de teste '
              'nao encontrados. Confira os IDs e as migrations.',
            );
          }
          final categoriaId = categoria.single[0]! as int;
          await transacao.execute(
            Sql.named('''
              UPDATE produto SET categoria_custo_id = @categoria
              WHERE id = @produto
            '''),
            parameters: {'categoria': categoriaId, 'produto': produto},
          );
          final saldo = await transacao.execute(
            Sql.named('''
              INSERT INTO estoque (obra_id, produto_id, quantidade)
              VALUES (@obra, @produto, CAST(@quantidade AS NUMERIC))
              ON CONFLICT (obra_id, produto_id)
              DO UPDATE SET quantidade = EXCLUDED.quantidade
              RETURNING CAST(quantidade AS TEXT)
            '''),
            parameters: {
              'obra': obra,
              'produto': produto,
              'quantidade': argumentos[3],
            },
          );
          return {
            'categoria_custo_id': categoriaId,
            'categoria_nome': categoria.single[1],
            'quantidade': saldo.single[0],
          };
        });
      default:
        throw StateError('Comando de teste desconhecido.');
    }
    stdout.writeln(jsonEncode(resposta));
  } on FormatException catch (erro) {
    stderr.writeln(erro.message);
    exitCode = 1;
  } on ServerException catch (erro) {
    stderr.writeln('Falha no banco de testes: ${erro.message}');
    exitCode = 1;
  } catch (_) {
    stderr.writeln(
      'Falha ao acessar o banco de testes. Confira DATABASE_URL e a conexao.',
    );
    exitCode = 1;
  } finally {
    await conexao?.close();
  }
}

int _id(String valor) {
  final id = int.tryParse(valor);
  if (id == null || id < 1 || id > 2147483647) {
    throw const FormatException('ID de teste invalido.');
  }
  return id;
}
