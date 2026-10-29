import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/ambiente.dart';
import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/senha.dart';
import 'package:constroi_api/token.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/login.dart' as rota;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

class _TransacaoFalsa extends Mock implements TxSession {}

class _LinhaFalsa extends Mock implements ResultRow {}

class _ArquivoFalso extends Mock implements File {}

Result _resultado([Map<String, dynamic>? dados]) {
  final linhas = <ResultRow>[];
  if (dados != null) {
    final linha = _LinhaFalsa();
    when(linha.toColumnMap).thenReturn(dados);
    linhas.add(linha);
  }
  return Result(
    rows: linhas,
    affectedRows: linhas.length,
    schema: ResultSchema([]),
  );
}

void main() {
  const segredo = 'segredo-apenas-deste-teste';
  const senha = 'Senha#Forte123';
  const email = 'pessoa@teste.com';
  late String hash;
  late _ContextoFalso contexto;
  late _BancoFalso banco;
  late _TransacaoFalsa transacao;
  late Map<String, dynamic>? usuario;
  late List<Map<String, Object?>> consultas;
  late List<Map<String, Object?>> gravacoesDaSessao;

  void requisicao(String senhaEnviada, {String emailEnviado = email}) {
    when(() => contexto.request).thenReturn(
      Request.post(
        Uri.parse('http://localhost/login'),
        headers: {'x-forwarded-for': '127.0.0.1', 'user-agent': 'teste'},
        body: jsonEncode({'email': emailEnviado, 'senha': senhaEnviada}),
      ),
    );
  }

  setUpAll(() {
    registerFallbackValue(Sql.named('SELECT 1'));
    registerFallbackValue((TxSession _) async {});
    hash = gerarHash(senha);

    // Inicializa a configuracao deste isolate sem ler ou alterar um .env real.
    final arquivo = _ArquivoFalso();
    when(arquivo.existsSync).thenReturn(true);
    when(arquivo.readAsLinesSync).thenReturn(['JWT_SECRET=$segredo']);
    IOOverrides.runZoned(
      () => expect(variavel('JWT_SECRET'), segredo),
      createFile: (_) => arquivo,
    );
  });

  setUp(() {
    contexto = _ContextoFalso();
    banco = _BancoFalso();
    transacao = _TransacaoFalsa();
    consultas = [];
    gravacoesDaSessao = [];
    usuario = {
      'id': 7,
      'empresa_id': 2,
      'nome': 'Pessoa de teste',
      'email': email,
      'tipo': 'engenheiro',
      'senha_hash': hash,
      'ativo': true,
      'bloqueado_ate': null,
      'tentativas_login': 0,
    };
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    when(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((chamada) async {
      consultas.add(
        Map<String, Object?>.from(chamada.namedArguments[#parameters] as Map),
      );
      return consultas.length == 1 ? _resultado(usuario) : _resultado();
    });
    when(() => banco.runTx<void>(any())).thenAnswer((chamada) async {
      final executar =
          chamada.positionalArguments.first as Future<void> Function(TxSession);
      await executar(transacao);
    });
    when(
      () => transacao.execute(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((chamada) async {
      gravacoesDaSessao.add(
        Map<String, Object?>.from(chamada.namedArguments[#parameters] as Map),
      );
      return _resultado();
    });
    requisicao('OutraSenha#9');
  });

  Future<void> conferirFalhaGenerica({required int? usuarioId}) async {
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.unauthorized);
    expect(jsonDecode(await resposta.body()), {
      'erro': 'Email ou senha invalidos.',
    });
    expect(consultas.last, {
      'usuario': usuarioId,
      'email': resumir(email),
      'ip': '127.0.0.1',
      'sucesso': false,
    });
    expect(gravacoesDaSessao, isEmpty);
    verifyNever(() => banco.runTx<void>(any()));
  }

  test(
    'email inexistente retorna 401 generico e registra a tentativa',
    () async {
      usuario = null;
      await conferirFalhaGenerica(usuarioId: null);
      expect(consultas, hasLength(2));
    },
  );

  test('conta ativa com senha errada retorna o mesmo 401 generico', () async {
    await conferirFalhaGenerica(usuarioId: 7);
    expect(consultas[1], {'id': 7, 'tentativas': 1, 'bloqueadoAte': null});
  });

  test('conta inativa com senha errada nao revela a inativacao', () async {
    usuario!['ativo'] = false;
    usuario!['tentativas_login'] = 4;
    await conferirFalhaGenerica(usuarioId: 7);
    expect(consultas, hasLength(2));
  });

  test(
    'conta bloqueada com senha errada nao revela nem altera o bloqueio',
    () async {
      usuario!['bloqueado_ate'] = DateTime.now().toUtc().add(
        const Duration(minutes: 8),
      );
      await conferirFalhaGenerica(usuarioId: 7);
      expect(consultas, hasLength(2));
    },
  );

  test('conta inativa e bloqueada com senha errada retorna 401', () async {
    usuario!['ativo'] = false;
    usuario!['bloqueado_ate'] = DateTime.now().toUtc().add(
      const Duration(minutes: 8),
    );
    await conferirFalhaGenerica(usuarioId: 7);
    expect(consultas, hasLength(2));
  });

  test(
    'quinta senha errada cria bloqueio mas continua respondendo 401',
    () async {
      usuario!['tentativas_login'] = 4;
      final antes = DateTime.now().toUtc();
      await conferirFalhaGenerica(usuarioId: 7);
      expect(consultas[1]['tentativas'], 0);
      final prazo = consultas[1]['bloqueadoAte']! as DateTime;
      expect(prazo.isAfter(antes.add(const Duration(minutes: 9))), isTrue);
      expect(
        prazo.isBefore(DateTime.now().toUtc().add(const Duration(minutes: 11))),
        isTrue,
      );
    },
  );

  test(
    'bloqueio expirado reinicia contagem na primeira senha errada',
    () async {
      usuario!['tentativas_login'] = 4;
      usuario!['bloqueado_ate'] = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );
      await conferirFalhaGenerica(usuarioId: 7);
      expect(consultas[1], {'id': 7, 'tentativas': 1, 'bloqueadoAte': null});
    },
  );

  test('senha correta de conta inativa continua recebendo 403', () async {
    usuario!['ativo'] = false;
    requisicao(senha);
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.forbidden);
    expect(jsonDecode(await resposta.body()), {
      'erro': 'Usuario inativo. Procure o administrador.',
    });
    expect(consultas, hasLength(2));
    expect(consultas.last['sucesso'], isFalse);
    expect(gravacoesDaSessao, isEmpty);
    verifyNever(() => banco.runTx<void>(any()));
  });

  test('senha correta de conta bloqueada continua recebendo 429', () async {
    usuario!['bloqueado_ate'] = DateTime.now().toUtc().add(
      const Duration(minutes: 8),
    );
    requisicao(senha);
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.tooManyRequests);
    expect(jsonDecode(await resposta.body()), {
      'erro': 'Muitas tentativas. Tente novamente mais tarde.',
    });
    expect(consultas, hasLength(2));
    expect(consultas.last['sucesso'], isFalse);
    expect(gravacoesDaSessao, isEmpty);
    verifyNever(() => banco.runTx<void>(any()));
  });

  for (final bloqueioExpirado in [false, true]) {
    test(
      'login valido cria sessao; bloqueio expirado = $bloqueioExpirado',
      () async {
        usuario!['tentativas_login'] = 3;
        if (bloqueioExpirado) {
          usuario!['bloqueado_ate'] = DateTime.now().toUtc().subtract(
            const Duration(minutes: 1),
          );
        }
        requisicao(senha, emailEnviado: '  $email  ');
        final resposta = await rota.onRequest(contexto);
        final dados = jsonDecode(await resposta.body()) as Map<String, dynamic>;
        expect(resposta.statusCode, HttpStatus.ok);
        expect(dados['usuario'], {
          'id': 7,
          'nome': 'Pessoa de teste',
          'email': email,
          'tipo': 'engenheiro',
          'empresa_id': 2,
        });
        expect(dados['usuario'], isNot(contains('senha_hash')));
        final autenticado = autenticar('Bearer ${dados['token']}', segredo)!;
        expect(autenticado.id, 7);
        expect(autenticado.empresaId, 2);
        expect(autenticado.nivel, Nivel.engenheiro);
        expect(gravacoesDaSessao, hasLength(3));
        expect(gravacoesDaSessao.first, {'id': 7});
        expect(gravacoesDaSessao[1]['usuario'], 7);
        expect(
          gravacoesDaSessao[1]['hash'],
          resumir(dados['refresh_token'] as String),
        );
        expect(consultas.last['sucesso'], isTrue);
        expect(gravacoesDaSessao.last, {
          'usuario': 7,
          'acao': 'LOGIN usuario=7',
        });
        verify(() => banco.runTx<void>(any())).called(1);
      },
    );
  }
}
