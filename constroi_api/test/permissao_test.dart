import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/permissao.dart';
import 'package:constroi_api/token.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _ContextoFalso extends Mock implements RequestContext {}

const _segredo = 'segredo-de-teste-bem-comprido-para-hmac';

Future<Response> _passarPor(
  Nivel minimo,
  UsuarioAutenticado? usuario,
) async {
  final contexto = _ContextoFalso();
  when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(usuario);
  final protegido = exigirNivel(minimo)(
    (_) async => Response(body: 'passou'),
  );
  return await protegido(contexto);
}

UsuarioAutenticado _usuario(Nivel nivel) =>
    UsuarioAutenticado(id: 1, empresaId: 1, nivel: nivel);

void main() {
  group('hierarquia dos perfis', () {
    test('pedreiro so alcanca pedreiro', () {
      expect(Nivel.pedreiro.alcanca(Nivel.pedreiro), isTrue);
      expect(Nivel.pedreiro.alcanca(Nivel.engenheiro), isFalse);
      expect(Nivel.pedreiro.alcanca(Nivel.master), isFalse);
    });

    test('engenheiro alcanca pedreiro e engenheiro', () {
      expect(Nivel.engenheiro.alcanca(Nivel.pedreiro), isTrue);
      expect(Nivel.engenheiro.alcanca(Nivel.engenheiro), isTrue);
      expect(Nivel.engenheiro.alcanca(Nivel.master), isFalse);
    });

    test('master alcanca todos', () {
      expect(Nivel.master.alcanca(Nivel.pedreiro), isTrue);
      expect(Nivel.master.alcanca(Nivel.engenheiro), isTrue);
      expect(Nivel.master.alcanca(Nivel.master), isTrue);
    });
  });

  group('exigirNivel', () {
    test('sem token responde 401', () async {
      final resposta = await _passarPor(Nivel.pedreiro, null);
      expect(resposta.statusCode, equals(HttpStatus.unauthorized));
    });

    test('pedreiro em rota de engenheiro responde 403', () async {
      final resposta = await _passarPor(
        Nivel.engenheiro,
        _usuario(Nivel.pedreiro),
      );
      expect(resposta.statusCode, equals(HttpStatus.forbidden));
    });

    test('engenheiro em rota de master responde 403', () async {
      final resposta = await _passarPor(
        Nivel.master,
        _usuario(Nivel.engenheiro),
      );
      expect(resposta.statusCode, equals(HttpStatus.forbidden));
    });

    test('engenheiro passa em rota de pedreiro', () async {
      final resposta = await _passarPor(
        Nivel.pedreiro,
        _usuario(Nivel.engenheiro),
      );
      expect(resposta.statusCode, equals(HttpStatus.ok));
    });

    test('master passa em rota de master', () async {
      final resposta = await _passarPor(Nivel.master, _usuario(Nivel.master));
      expect(resposta.statusCode, equals(HttpStatus.ok));
    });
  });

  group('leitura do token', () {
    String tokenDe(Nivel nivel, {String segredo = _segredo}) => gerarToken(
          segredo: segredo,
          usuarioId: 7,
          empresaId: 3,
          tipo: nivel.name,
        );

    test('token valido devolve o usuario', () {
      final usuario = autenticar(
        'Bearer ${tokenDe(Nivel.engenheiro)}',
        _segredo,
      );
      expect(usuario, isNotNull);
      expect(usuario!.id, equals(7));
      expect(usuario.empresaId, equals(3));
      expect(usuario.nivel, equals(Nivel.engenheiro));
    });

    test('sem cabecalho devolve null', () {
      expect(autenticar(null, _segredo), isNull);
    });

    test('sem o prefixo Bearer devolve null', () {
      expect(autenticar(tokenDe(Nivel.master), _segredo), isNull);
    });

    test('token de outro segredo devolve null', () {
      final token = tokenDe(Nivel.master, segredo: 'outro-segredo-qualquer');
      expect(autenticar('Bearer $token', _segredo), isNull);
    });

    test('token estragado devolve null', () {
      expect(autenticar('Bearer nao-e-um-jwt', _segredo), isNull);
    });

    test('token expirado devolve null', () {
      final expirado = JWT(
        {'empresa_id': 3, 'tipo': 'master'},
        subject: '7',
      ).sign(SecretKey(_segredo), expiresIn: const Duration(seconds: -60));
      expect(autenticar('Bearer $expirado', _segredo), isNull);
    });

    test('tipo desconhecido no banco devolve null', () {
      final token = gerarToken(
        segredo: _segredo,
        usuarioId: 7,
        empresaId: 3,
        tipo: 'mestre-de-obras',
      );
      expect(autenticar('Bearer $token', _segredo), isNull);
    });
  });
}
