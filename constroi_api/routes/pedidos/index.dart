import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  final metodo = context.request.method;
  if (metodo == HttpMethod.get) return _listar(context);
  if (metodo == HttpMethod.post) return _criar(context);
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _listar(RequestContext context) async {
  final filtros = context.request.uri.queryParameters;
  final limite = int.tryParse(filtros['limit'] ?? '50');
  final offset = int.tryParse(filtros['offset'] ?? '0');
  if (limite == null ||
      limite < 1 ||
      limite > 200 ||
      offset == null ||
      offset < 0) {
    return _erro(
      HttpStatus.badRequest,
      'Informe limit entre 1 e 200 e offset maior ou igual a zero.',
    );
  }

  final usuario = context.usuario;
  final condicoes = <String>[
    'o.empresa_id = @empresa',
    'u.empresa_id = @empresa',
    '(@todos OR p.usuario_id = @usuario)',
  ];
  final parametros = <String, Object?>{
    'empresa': usuario.empresaId,
    'usuario': usuario.id,
    'todos': usuario.nivel.alcanca(Nivel.engenheiro),
    'limit': limite,
    'offset': offset,
  };

  if (filtros.containsKey('obra_id')) {
    final obraId = validarIdPedido(int.tryParse(filtros['obra_id']!));
    if (obraId == null) {
      return _erro(HttpStatus.badRequest, 'Filtro obra_id invalido.');
    }
    condicoes.add('p.obra_id = @obra');
    parametros['obra'] = obraId;
  }

  if (filtros.containsKey('status')) {
    final status = filtros['status']!.trim().toLowerCase();
    if (status.isEmpty || status.length > 30) {
      return _erro(HttpStatus.badRequest, 'Filtro status invalido.');
    }
    condicoes.add('LOWER(p.status) = @status');
    parametros['status'] = status;
  }

  if (filtros.containsKey('protocolo')) {
    final protocolo = filtros['protocolo']!.trim().toUpperCase();
    if (protocolo.isEmpty || protocolo.length > 50) {
      return _erro(HttpStatus.badRequest, 'Filtro protocolo invalido.');
    }
    condicoes.add('UPPER(p.protocolo) = @protocolo');
    parametros['protocolo'] = protocolo;
  }

  final linhas = await context.read<Pool<void>>().execute(
    Sql.named('''
      SELECT p.id, p.usuario_id, p.obra_id, p.protocolo,
             p.status, p.justificativa, p.data
      FROM pedido p
      JOIN obra o ON o.id = p.obra_id
      JOIN usuario u ON u.id = p.usuario_id
      WHERE ${condicoes.join(' AND ')}
      ORDER BY p.data DESC, p.id DESC
      LIMIT @limit OFFSET @offset
    '''),
    parameters: parametros,
  );

  return Response.json(
    body: {
      'pedidos': linhas
          .map((linha) => dadosDoPedido(linha.toColumnMap()))
          .toList(),
    },
  );
}

Future<Response> _criar(RequestContext context) async {
  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final dados = corpo['pedido'];
  if (dados is! Map<String, dynamic>) {
    return _erro(
      HttpStatus.badRequest,
      'Envie o objeto dentro da chave "pedido".',
    );
  }

  final obraId = validarIdPedido(dados['obra_id']);
  final itens = validarItensPedido(dados['itens']);
  if (obraId == null || itens == null) {
    return _erro(
      HttpStatus.badRequest,
      'Informe obra_id e de 1 a 200 itens com produto_id valido, '
      'sem repeticao, e quantidade positiva com ate duas casas decimais.',
    );
  }

  final justificativa = dados['justificativa'];
  if (justificativa != null &&
      (justificativa is! String || justificativa.trim().length > 255)) {
    return _erro(
      HttpStatus.badRequest,
      'A justificativa deve ser um texto com ate 255 caracteres.',
    );
  }

  final usuario = context.usuario;
  final banco = context.read<Pool<void>>();
  final gerar = context.read<GeradorProtocolo>();

  return banco.runTx((transacao) async {
    final obras = await transacao.execute(
      Sql.named('''
        SELECT id FROM obra
        WHERE id = @obra AND empresa_id = @empresa
      '''),
      parameters: {'obra': obraId, 'empresa': usuario.empresaId},
    );
    if (obras.isEmpty) {
      return _erro(
        HttpStatus.notFound,
        'Obra nao encontrada para esta empresa.',
      );
    }

    if (!usuario.nivel.alcanca(Nivel.engenheiro)) {
      final vinculos = await transacao.execute(
        Sql.named('''
          SELECT id FROM usuario_obra
          WHERE obra_id = @obra AND usuario_id = @usuario
            AND empresa_id = @empresa AND data_fim IS NULL
        '''),
        parameters: {
          'obra': obraId,
          'usuario': usuario.id,
          'empresa': usuario.empresaId,
        },
      );
      if (vinculos.isEmpty) {
        return _erro(
          HttpStatus.forbidden,
          'Voce nao faz parte da equipe ativa desta obra.',
        );
      }
    }

    final produtos = await transacao.execute(
      Sql.named('''
        SELECT id FROM produto
        WHERE empresa_id = @empresa AND id = ANY(@produtos::int[])
      '''),
      parameters: {
        'empresa': usuario.empresaId,
        'produtos': itens.map((item) => item.produtoId).toList(),
      },
    );
    if (produtos.length != itens.length) {
      return _erro(
        HttpStatus.badRequest,
        'Todos os produtos devem existir e pertencer a sua empresa.',
      );
    }

    for (var tentativa = 0; tentativa < 5; tentativa++) {
      final pedidos = await transacao.execute(
        Sql.named('''
          INSERT INTO pedido
            (usuario_id, obra_id, protocolo, status, justificativa)
          VALUES (@usuario, @obra, @protocolo, 'pendente', @justificativa)
          ON CONFLICT (protocolo) DO NOTHING
          RETURNING id, usuario_id, obra_id, protocolo, status, justificativa, data
        '''),
        parameters: {
          'usuario': usuario.id,
          'obra': obraId,
          'protocolo': gerar(),
          'justificativa': (justificativa as String?)?.trim(),
        },
      );
      if (pedidos.isEmpty) continue;

      final pedido = dadosDoPedido(pedidos.first.toColumnMap());
      final itensCriados = <Map<String, dynamic>>[];
      for (final item in itens) {
        final resultado = await transacao.execute(
          Sql.named('''
            INSERT INTO item_pedido (pedido_id, produto_id, quantidade)
            VALUES (@pedido, @produto, @quantidade)
            RETURNING id, produto_id, quantidade
          '''),
          parameters: {
            'pedido': pedido['id'],
            'produto': item.produtoId,
            'quantidade': item.quantidade.toStringAsFixed(2),
          },
        );
        itensCriados.add(dadosDoItemPedido(resultado.first.toColumnMap()));
      }

      return Response.json(
        statusCode: HttpStatus.created,
        body: {
          ...pedido,
          'itens': itensCriados,
        },
      );
    }

    return _erro(
      HttpStatus.serviceUnavailable,
      'Nao foi possivel gerar um protocolo unico. Tente novamente.',
    );
  });
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
