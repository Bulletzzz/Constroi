import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/obras.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  final metodo = context.request.method;
  if (metodo == HttpMethod.get) return _listar(context);
  if (metodo == HttpMethod.post) return _criar(context);
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _listar(RequestContext context) async {
  final banco = context.read<Pool<void>>();
  final usuario = context.usuario;
  final apenasVinculadas = !usuario.nivel.alcanca(Nivel.engenheiro);

  final linhas = await banco.execute(
    Sql.named('''
      SELECT o.id, o.nome, o.endereco, o.status, o.orcamento_total, o.empresa_id
      FROM obra o
      WHERE o.empresa_id = @empresa
        AND (
          @todas
          OR EXISTS (
            SELECT 1 FROM usuario_obra uo
            WHERE uo.obra_id = o.id
              AND uo.usuario_id = @usuario
              AND uo.data_fim IS NULL
          )
        )
      ORDER BY o.nome, o.id
    '''),
    parameters: {
      'empresa': usuario.empresaId,
      'usuario': usuario.id,
      'todas': !apenasVinculadas,
    },
  );

  final obras = linhas
      .map((linha) => dadosDaObra(linha.toColumnMap()))
      .toList();

  return Response.json(body: {'obras': obras});
}

Future<Response> _criar(RequestContext context) async {
  if (!context.usuario.nivel.alcanca(Nivel.engenheiro)) {
    return _erro(
      HttpStatus.forbidden,
      'Esta acao e restrita ao perfil engenheiro ou superior.',
    );
  }

  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final dados = corpo['obra'];
  if (dados is! Map<String, dynamic>) {
    return _erro(
      HttpStatus.badRequest,
      'Envie o objeto dentro da chave "obra".',
    );
  }

  final nome = validarNomeObra(dados['nome']);
  final endereco = validarEnderecoObra(dados['endereco']);
  final status = validarStatusObra(dados['status']);
  if (nome == null || endereco == null || status == null) {
    return _erro(
      HttpStatus.badRequest,
      'Informe nome, endereco e status validos da obra.',
    );
  }

  final orcamento = validarOrcamentoObra(dados['orcamento_total']);
  if (!orcamento.valido) {
    return _erro(
      HttpStatus.badRequest,
      'O orcamento total deve ser um numero maior ou igual a zero.',
    );
  }

  final banco = context.read<Pool<void>>();
  final resultado = await banco.execute(
    Sql.named('''
      INSERT INTO obra (empresa_id, nome, endereco, status, orcamento_total)
      VALUES (@empresa, @nome, @endereco, @status, @orcamento)
      RETURNING id, nome, endereco, status, orcamento_total, empresa_id
    '''),
    parameters: {
      'empresa': context.usuario.empresaId,
      'nome': nome,
      'endereco': endereco,
      'status': status,
      'orcamento': orcamento.valor,
    },
  );

  return Response.json(
    statusCode: HttpStatus.created,
    body: dadosDaObra(resultado.first.toColumnMap()),
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
