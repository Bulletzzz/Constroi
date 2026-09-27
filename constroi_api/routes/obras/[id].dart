import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/obras.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String idDaRota) async {
  final id = int.tryParse(idDaRota);
  if (id == null) return _erro(HttpStatus.badRequest, 'Id da obra invalido.');

  final metodo = context.request.method;
  if (metodo == HttpMethod.get) return _buscar(context, id);
  if (metodo == HttpMethod.patch) return _editar(context, id);
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _buscar(RequestContext context, int id) async {
  final banco = context.read<Pool<void>>();
  final usuario = context.usuario;
  final todas = usuario.nivel.alcanca(Nivel.engenheiro);

  final encontrados = await banco.execute(
    Sql.named('''
      SELECT o.id, o.nome, o.endereco, o.status, o.orcamento_total, o.empresa_id
      FROM obra o
      WHERE o.id = @id
        AND o.empresa_id = @empresa
        AND (
          @todas
          OR EXISTS (
            SELECT 1 FROM usuario_obra uo
            WHERE uo.obra_id = o.id
              AND uo.usuario_id = @usuario
              AND uo.data_fim IS NULL
          )
        )
      LIMIT 1
    '''),
    parameters: {
      'id': id,
      'empresa': usuario.empresaId,
      'usuario': usuario.id,
      'todas': todas,
    },
  );

  if (encontrados.isEmpty) {
    return _erro(HttpStatus.notFound, 'Obra nao encontrada.');
  }

  return Response.json(body: dadosDaObra(encontrados.first.toColumnMap()));
}

Future<Response> _editar(RequestContext context, int id) async {
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

  final campos = <String, dynamic>{};
  final partes = <String>[];

  if (dados.containsKey('nome')) {
    final nome = validarNomeObra(dados['nome']);
    if (nome == null) {
      return _erro(HttpStatus.badRequest, 'Nome da obra invalido.');
    }
    campos['nome'] = nome;
    partes.add('nome = @nome');
  }

  if (dados.containsKey('endereco')) {
    final endereco = validarEnderecoObra(dados['endereco']);
    if (endereco == null) {
      return _erro(HttpStatus.badRequest, 'Endereco da obra invalido.');
    }
    campos['endereco'] = endereco;
    partes.add('endereco = @endereco');
  }

  if (dados.containsKey('status')) {
    final status = validarStatusObra(dados['status']);
    if (status == null) {
      return _erro(
        HttpStatus.badRequest,
        'Status invalido. Use planejamento, ativa, pausada ou concluida.',
      );
    }
    campos['status'] = status;
    partes.add('status = @status');
  }

  if (dados.containsKey('orcamento_total')) {
    final orcamento = validarOrcamentoObra(dados['orcamento_total']);
    if (!orcamento.valido) {
      return _erro(
        HttpStatus.badRequest,
        'O orcamento total deve ser um numero maior ou igual a zero.',
      );
    }
    campos['orcamento'] = orcamento.valor;
    partes.add('orcamento_total = @orcamento');
  }

  if (partes.isEmpty) {
    return _erro(
      HttpStatus.badRequest,
      'Informe campos validos para atualizar.',
    );
  }

  campos['id'] = id;
  campos['empresa'] = context.usuario.empresaId;
  final atualizado = await context.read<Pool<void>>().execute(
    Sql.named('''
      UPDATE obra
      SET ${partes.join(', ')}
      WHERE id = @id AND empresa_id = @empresa
      RETURNING id, nome, endereco, status, orcamento_total, empresa_id
    '''),
    parameters: campos,
  );

  if (atualizado.isEmpty) {
    return _erro(HttpStatus.notFound, 'Obra nao encontrada.');
  }

  return Response.json(body: dadosDaObra(atualizado.first.toColumnMap()));
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
