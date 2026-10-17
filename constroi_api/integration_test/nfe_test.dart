import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/anexo_nfe.dart';
import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/entrada_nfe.dart';
import 'package:constroi_api/nfe.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../routes/entradas/[id]/xml.dart' as rota_anexo;
import '../routes/entradas/_middleware.dart' as protecao;
import '../routes/entradas/xml.dart' as rota;
import '../test/fixtures/nfe.dart';

Future<Object?> importarParaTeste(Pool<void> banco, String xml) => importarNfe(
  banco,
  usuario: const UsuarioAutenticado(
    id: 1,
    empresaId: 1,
    nivel: Nivel.engenheiro,
  ),
  obraId: 1,
  nota: lerNfe(utf8.encode(xml)),
);

void main() {
  late Pool<void> banco;
  late HttpServer servidor;
  late HttpClient cliente;
  const segredo = 'segredo-local-descartavel-nfe';
  Future<Result> sql(String texto, [Map<String, Object?>? parametros]) =>
      banco.execute(Sql.named(texto), parameters: parametros);
  Future<({int status, Map<String, dynamic> body})> enviar({
    String? xml,
    int obra = 1,
    int empresa = 1,
    Nivel? nivel = Nivel.engenheiro,
    String? corpoBruto,
    String? entrada,
  }) async {
    final caminho = entrada == null
        ? '/entradas/xml'
        : '/entradas/$entrada/xml';
    final uri = Uri.parse('http://127.0.0.1:${servidor.port}$caminho');
    final req = entrada == null
        ? await cliente.postUrl(uri)
        : await cliente.patchUrl(uri);
    if (nivel != null) {
      final token = JWT(
        {'empresa_id': empresa, 'tipo': nivel.name},
        subject: empresa == 1 ? '1' : '2',
      ).sign(SecretKey(segredo));
      req.headers.set(
        'Authorization',
        'Bearer $token',
      );
    }
    req.headers.set('Content-Type', 'multipart/form-data; boundary=local-nfe');
    req.write(
      corpoBruto ??
          '--local-nfe\r\nContent-Disposition: form-data; name="obra_id"\r\n\r\n$obra\r\n--local-nfe\r\nContent-Disposition: form-data; name="xml"; filename="nota.xml"\r\nContent-Type: application/xml\r\n\r\n${xml ?? xmlNfe()}\r\n--local-nfe--\r\n',
    );
    final res = await req.close();
    return (
      status: res.statusCode,
      body:
          jsonDecode(await utf8.decoder.bind(res).join())
              as Map<String, dynamic>,
    );
  }

  Future<List<List<Object?>>> estado() async => (await sql(
    '''SELECT (SELECT count(*) FROM entrada_estoque), (SELECT count(*) FROM item_entrada), (SELECT count(*) FROM log_sistema), (SELECT quantidade::text FROM estoque WHERE obra_id=1 AND produto_id=1)''',
  )).map((r) => r.toList()).toList();
  setUpAll(() async {
    final url = Platform.environment['CONSTROI_TEST_DATABASE_URL'] ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['postgresql', 'postgres'].contains(uri.scheme) ||
        !['localhost', '127.0.0.1', '::1'].contains(uri.host) ||
        uri.pathSegments.length != 1 ||
        !uri.pathSegments.single.startsWith('constroi_test_')) {
      throw StateError(
        'Use CONSTROI_TEST_DATABASE_URL local descartavel constroi_test_*. '
        'Nunca le .env.',
      );
    }
    banco = Pool<void>.withUrl(url);
    addTearDown(() => banco.close());
    await banco.execute(
      'DROP SCHEMA public CASCADE; CREATE SCHEMA public;',
      queryMode: QueryMode.simple,
    );
    await banco.execute(
      await File('../Database/schema.sql').readAsString(),
      queryMode: QueryMode.simple,
    );
    final handler = protecao
        .middleware((context) {
          final partes = context.request.uri.pathSegments;
          return partes.length == 3
              ? rota_anexo.onRequest(context, partes[1])
              : rota.onRequest(context);
        })
        .use(provider<Pool<void>>((_) => banco))
        .use(
          provider<UsuarioAutenticado?>(
            (ctx) => autenticar(ctx.request.headers['authorization'], segredo),
          ),
        );
    servidor = await serve(handler, InternetAddress.loopbackIPv4, 0);
    addTearDown(() => servidor.close(force: true));
    cliente = HttpClient();
    addTearDown(() => cliente.close(force: true));
  });
  setUp(() async {
    await banco.execute('''
      DROP TRIGGER IF EXISTS falha_nfe ON log_sistema;
      DROP FUNCTION IF EXISTS falha_nfe_teste();
      TRUNCATE empresa RESTART IDENTITY CASCADE;
      INSERT INTO empresa (id,nome,cnpj) VALUES (1,'A','A'),(2,'B','B');
      INSERT INTO usuario (id,empresa_id,nome,email,senha_hash,tipo) VALUES (1,1,'Eng A','a@a','hash','engenheiro'),(2,2,'Eng B','b@b','hash','engenheiro');
      INSERT INTO obra (id,empresa_id,nome,endereco,status) VALUES (1,1,'A','Rua','ativa'),(2,2,'B','Rua','ativa');
      INSERT INTO produto (id,empresa_id,nome,unidade,sku) VALUES (1,1,'Cimento','saco','CIM-01'),(2,1,'Areia','kg','ARE-01'),(3,2,'Cimento','saco','CIM-01');
      INSERT INTO estoque (obra_id,produto_id,quantidade) VALUES (1,1,5);
    ''', queryMode: QueryMode.simple);
  });
  test(
    'HTTP importa XML original, itens, saldo e ator na mesma transacao',
    () async {
      final xml = xmlNfe();
      final res = await enviar(xml: xml);
      expect(res.status, 201, reason: '${res.body}');
      expect(res.body['saldos'], [
        {'produto_id': 1, 'saldo': '6.25'},
      ]);
      expect(
        (await sql(
          'SELECT xml_nota_fiscal,usuario_id,empresa_nfe_id '
          'FROM entrada_estoque',
        )).single.toList(),
        [xml, 1, 1],
      );
      expect(
        (await sql('SELECT usuario_id,acao FROM log_sistema')).single[0],
        1,
      );
    },
  );
  test(
    'sem token 401, pedreiro 403, obra alheia/inexistente 404 e nenhum efeito',
    () async {
      final antes = await estado();
      expect((await enviar(nivel: null)).status, 401);
      expect((await enviar(nivel: Nivel.pedreiro)).status, 403);
      expect((await enviar(obra: 2)).status, 404);
      expect((await enviar(obra: 999)).status, 404);
      expect(await estado(), antes);
    },
  );
  test(
    'avisa materiais desconhecidos, ambiguos e unidade diferente sem gravar',
    () async {
      final antes = await estado();
      final res = await enviar(
        xml: xmlNfe(
          itens: materialXml() + materialXml(codigo: 'X', nome: 'Outro'),
        ),
      );
      expect(res.status, 422);
      expect(
        ((res.body['materiais_pendentes'] as List).single
            as Map<String, dynamic>)['motivo'],
        'nao_encontrado',
      );
      expect(
        (await enviar(
          xml: xmlNfe(itens: materialXml(unidade: 'kg')),
        )).status,
        422,
      );
      await sql(
        'INSERT INTO produto (id,empresa_id,nome,unidade) '
        "VALUES (4,1,'Duplicado','saco'),(5,1,'Duplicado','saco')",
      );
      expect(
        (await enviar(
          xml: xmlNfe(
            itens: materialXml(codigo: 'X', nome: 'Duplicado'),
          ),
        )).status,
        422,
      );
      expect(await estado(), antes);
    },
  );
  test(
    'casa nome unico sem SKU e agrega repeticoes com precisao decimal',
    () async {
      await sql('UPDATE produto SET sku=NULL WHERE id=1');
      final res = await enviar(
        xml: xmlNfe(
          itens:
              materialXml(quantidade: '0.01') + materialXml(quantidade: '0.02'),
        ),
      );
      expect(res.status, 201);
      expect(res.body['saldos'], [
        {'produto_id': 1, 'saldo': '5.03'},
      ]);
      expect((await sql('SELECT count(*) FROM item_entrada')).single[0], 2);
    },
  );
  test(
    'reenvio da mesma chave e conflito concorrente nao duplicam estoque',
    () async {
      final respostas = await Future.wait([enviar(), enviar()]);
      expect(respostas.map((r) => r.status).toList()..sort(), [201, 409]);
      final depois = await estado();
      expect((await enviar()).status, 409);
      expect(await estado(), depois);
      expect(depois.single, [1, 1, 1, '6.25']);
    },
  );
  test(
    'chaves sao isoladas por empresa e material de outra empresa nao e usado',
    () async {
      expect((await enviar()).status, 201);
      expect((await enviar(empresa: 2, obra: 2)).status, 201);
      await banco.execute(
        'DELETE FROM estoque WHERE obra_id=1; '
        'DELETE FROM item_entrada WHERE produto_id=1; '
        'DELETE FROM produto WHERE id=1',
        queryMode: QueryMode.simple,
      );
      expect((await enviar(xml: xmlNfe(chave: '2' * 44))).status, 422);
    },
  );
  test(
    'XML malformado, DTD, formulario e upload excedido tem erro controlado',
    () async {
      final antes = await estado();
      expect((await enviar(xml: '<NFe>')).status, 400);
      expect((await enviar(xml: '<!DOCTYPE NFe>${xmlNfe()}')).status, 400);
      expect((await enviar(corpoBruto: '--local-nfe--\r\n')).status, 400);
      expect(
        (await enviar(corpoBruto: 'x' * (2 * 1024 * 1024 + 65537))).status,
        413,
      );
      expect(await estado(), antes);
    },
  );
  test('falha no log reverte entrada, todos os itens e saldos', () async {
    await banco.execute(
      r"""CREATE FUNCTION falha_nfe_teste() RETURNS trigger AS $$ BEGIN RAISE EXCEPTION 'falha injetada'; END; $$ LANGUAGE plpgsql; CREATE TRIGGER falha_nfe BEFORE INSERT ON log_sistema FOR EACH ROW EXECUTE FUNCTION falha_nfe_teste();""",
      queryMode: QueryMode.simple,
    );
    // Erros inesperados do banco propagam para garantir o rollback.
    final antes = await estado();
    await expectLater(
      importarParaTeste(
        banco,
        xmlNfe(
          itens:
              materialXml() +
              materialXml(codigo: 'ARE-01', nome: 'Areia', unidade: 'kg'),
        ),
      ),
      throwsA(isA<ServerException>()),
    );
    expect(await estado(), antes);
  });
  test('estouro de NUMERIC reverte tudo e retorna 409', () async {
    await sql('UPDATE estoque SET quantidade=9999999999.99');
    final antes = await estado();
    expect((await enviar()).status, 409);
    expect(await estado(), antes);
  });

  Future<int> entradaManual({int obra = 1, int usuario = 1}) async {
    final id =
        (await sql(
              'INSERT INTO entrada_estoque (usuario_id,obra_id,justificativa) '
              "VALUES (@usuario,@obra,'manual') RETURNING id",
              {'usuario': usuario, 'obra': obra},
            )).single[0]!
            as int;
    await sql(
      'INSERT INTO item_entrada (entrada_id,produto_id,quantidade) '
      'VALUES (@entrada,@produto,1.25)',
      {'entrada': id, 'produto': obra == 1 ? 1 : 3},
    );
    return id;
  }

  test(
    'PATCH anexa XML original sem somar ou reescrever itens/estoque',
    () async {
      final id = await entradaManual();
      final saldoAntes = await sql('SELECT * FROM estoque ORDER BY id');
      final itensAntes = await sql('SELECT * FROM item_entrada ORDER BY id');
      final xml = xmlNfe();
      final res = await enviar(entrada: '$id', xml: xml);
      expect(res.status, 200, reason: '${res.body}');
      expect(res.body['xml_anexado'], true);
      expect(
        (await sql(
          'SELECT xml_nota_fiscal,justificativa FROM entrada_estoque',
        )).single.toList(),
        [xml, 'manual'],
      );
      expect(
        (await sql('SELECT * FROM estoque ORDER BY id')).map((r) => r.toList()),
        saldoAntes.map((r) => r.toList()),
      );
      expect(
        (await sql(
          'SELECT * FROM item_entrada ORDER BY id',
        )).map((r) => r.toList()),
        itensAntes.map((r) => r.toList()),
      );
      expect(
        (await sql('SELECT acao FROM log_sistema')).single[0],
        contains('ANEXO_NFE'),
      );
    },
  );

  test('repeticao e duas anexacoes simultaneas nao sobrescrevem XML', () async {
    final id = await entradaManual();
    final respostas = await Future.wait([
      enviar(entrada: '$id'),
      enviar(entrada: '$id'),
    ]);
    expect(respostas.map((r) => r.status).toList()..sort(), [200, 409]);
    final depois = await estado();
    expect(
      (await enviar(
        entrada: '$id',
        xml: xmlNfe(chave: '2' * 44),
      )).status,
      409,
    );
    expect(await estado(), depois);
    expect(depois.single, [1, 1, 1, '5.00']);
  });

  test('anexo restringe perfil, empresa e ids sem alterar entrada', () async {
    final alheia = await entradaManual(obra: 2, usuario: 2);
    final antes = await estado();
    expect((await enviar(entrada: '$alheia')).status, 404);
    expect((await enviar(entrada: '999')).status, 404);
    for (final id in ['0', 'abc', '2147483648']) {
      expect((await enviar(entrada: id)).status, 400);
    }
    expect((await enviar(entrada: '$alheia', nivel: null)).status, 401);
    expect(
      (await enviar(entrada: '$alheia', nivel: Nivel.pedreiro)).status,
      403,
    );
    expect(await estado(), antes);
  });

  test(
    'entrada legada com XML e XML malformado nao sao sobrescritos',
    () async {
      final id = await entradaManual();
      expect((await enviar(entrada: '$id', xml: '<NFe>')).status, 400);
      await sql("UPDATE entrada_estoque SET xml_nota_fiscal='<legado/>'");
      expect((await enviar(entrada: '$id')).status, 409);
      expect(
        (await sql('SELECT xml_nota_fiscal FROM entrada_estoque')).single[0],
        '<legado/>',
      );
      expect((await sql('SELECT count(*) FROM log_sistema')).single[0], 0);
    },
  );

  test('mesma chave em entradas diferentes permite so um anexo', () async {
    final a = await entradaManual();
    final b = await entradaManual();
    final respostas = await Future.wait([
      enviar(entrada: '$a'),
      enviar(entrada: '$b'),
    ]);
    expect(respostas.map((r) => r.status).toList()..sort(), [200, 409]);
    expect(
      (await sql(
        'SELECT count(*) FROM entrada_estoque '
        'WHERE xml_nota_fiscal IS NOT NULL',
      )).single[0],
      1,
    );
    expect((await estado()).single, [2, 2, 1, '5.00']);
  });

  test('anexo nao reutiliza chave ja importada pelo POST', () async {
    expect((await enviar()).status, 201);
    final id = await entradaManual();
    final antes = await estado();
    expect((await enviar(entrada: '$id')).status, 409);
    expect(await estado(), antes);
  });

  test('falha no log do anexo reverte XML e metadados', () async {
    final id = await entradaManual();
    await banco.execute(r'''
      CREATE FUNCTION falha_nfe_teste() RETURNS trigger AS $$
      BEGIN RAISE EXCEPTION 'falha injetada'; END; $$ LANGUAGE plpgsql;
      CREATE TRIGGER falha_nfe BEFORE INSERT ON log_sistema
      FOR EACH ROW EXECUTE FUNCTION falha_nfe_teste();
    ''', queryMode: QueryMode.simple);
    await expectLater(
      anexarNfe(
        banco,
        usuario: const UsuarioAutenticado(
          id: 1,
          empresaId: 1,
          nivel: Nivel.engenheiro,
        ),
        entradaId: id,
        nota: lerNfe(utf8.encode(xmlNfe())),
      ),
      throwsA(isA<ServerException>()),
    );
    expect(
      (await sql(
        'SELECT xml_nota_fiscal,empresa_nfe_id,chave_nfe FROM entrada_estoque',
      )).single.toList(),
      [null, null, null],
    );
    expect((await estado()).single, [1, 1, 0, '5.00']);
  });
}
