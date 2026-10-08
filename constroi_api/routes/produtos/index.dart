import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/produtos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  try {
    return await _responder(context);
  } on ServerException catch (erro) {
    if (erro.code == '23505' &&
        erro.constraintName == 'ux_produto_sku_empresa') {
      return _erro(HttpStatus.conflict, 'SKU ja cadastrado para esta empresa.');
    }
    rethrow;
  }
}

Future<Response> _responder(RequestContext context) async {
  final metodo = context.request.method;
  if (metodo == HttpMethod.get) {
    return _listar(context);
  }
  if (metodo == HttpMethod.post) {
    return _criar(context);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _listar(RequestContext context) async {
  final banco = context.read<Pool<void>>();
  final empresaId = context.usuario.empresaId;

  final linhas = await banco.execute(
    Sql.named('''
      SELECT id, nome, unidade, sku, estoque_minimo,
             empresa_id, criado_em, atualizado_em
      FROM produto
      WHERE empresa_id = @empresa
      ORDER BY nome, id
    '''),
    parameters: {'empresa': empresaId},
  );

  final produtos = linhas
      .map((linha) => dadosDoProduto(linha.toColumnMap()))
      .toList();

  return Response.json(body: {'produtos': produtos});
}

Future<Response> _criar(RequestContext context) async {
  final banco = context.read<Pool<void>>();

  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final dados = corpo['produto'];
  if (dados is! Map<String, dynamic>) {
    return _erro(
      HttpStatus.badRequest,
      'Envie o objeto dentro da chave "produto".',
    );
  }

  final nome = validarNomeProduto(dados['nome']);
  final unidade = validarUnidadeProduto(dados['unidade']);
  final sku = validarSkuProduto(dados['sku']);
  final minimo = validarEstoqueMinimo(
    dados.containsKey('estoque_minimo') ? dados['estoque_minimo'] : 0,
  );

  if (!sku.valido || minimo == null) {
    return _erro(HttpStatus.badRequest, 'SKU ou estoque minimo invalido.');
  }

  if (nome == null || unidade == null) {
    return _erro(
      HttpStatus.badRequest,
      'Informe nome e unidade validos do produto.',
    );
  }

  final empresaId = context.usuario.empresaId;
  final jaExiste = await banco.execute(
    Sql.named('''
      SELECT id
      FROM produto
      WHERE empresa_id = @empresa AND LOWER(nome) = LOWER(@nome)
      LIMIT 1
    '''),
    parameters: {'empresa': empresaId, 'nome': nome},
  );

  if (jaExiste.isNotEmpty) {
    return _erro(
      HttpStatus.conflict,
      'Produto ja cadastrado para esta empresa.',
    );
  }

  final resultado = await banco.execute(
    Sql.named('''
      INSERT INTO produto (empresa_id, nome, unidade, sku, estoque_minimo)
      VALUES (@empresa, @nome, @unidade, @sku, @minimo)
      RETURNING id, nome, unidade, sku, estoque_minimo, empresa_id
    '''),
    parameters: {
      'empresa': empresaId,
      'nome': nome,
      'unidade': unidade,
      'sku': sku.valor,
      'minimo': minimo,
    },
  );

  final linha = resultado.first.toColumnMap();
  return Response.json(
    statusCode: HttpStatus.created,
    body: dadosDoProduto(linha),
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
