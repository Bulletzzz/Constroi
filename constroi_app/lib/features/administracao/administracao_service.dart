import '../../core/api/api_client.dart';
import '../../navigation/perfil_usuario.dart';

class UsuarioAdmin {
  UsuarioAdmin.fromJson(Map dados)
    : id = dados['id'] as int,
      nome = dados['nome'] as String,
      email = dados['email'] as String,
      perfil = PerfilUsuario.porNome(dados['tipo']),
      ativo = dados['ativo'] as bool;

  final int id;
  final String nome;
  final String email;
  final PerfilUsuario? perfil;
  final bool ativo;

  String get papel => switch (perfil) {
    PerfilUsuario.master => 'Master',
    PerfilUsuario.engenheiro => 'Engenheiro',
    PerfilUsuario.pedreiro => 'Pedreiro',
    null => 'Perfil não informado',
  };
}

class RegistroLog {
  RegistroLog.fromJson(Map dados)
    : id = dados['id'] as int,
      usuarioId = dados['usuario_id'] as int,
      acao = dados['acao'] as String,
      quando = DateTime.parse(dados['data'] as String).toLocal();

  final int id;
  final int usuarioId;
  final String acao;
  final DateTime quando;

  String get evento => acao.split(' ').first;

  String get detalhe => acao.length > evento.length
      ? acao.substring(evento.length).trim()
      : '';

  String get momento =>
      '${_doisDigitos(quando.day)}/${_doisDigitos(quando.month)}/'
      '${quando.year} ${_doisDigitos(quando.hour)}:'
      '${_doisDigitos(quando.minute)}';

  static String _doisDigitos(int valor) => valor.toString().padLeft(2, '0');
}

class PaginaDeLogs {
  const PaginaDeLogs({required this.registros, required this.temMais});

  final List<RegistroLog> registros;
  final bool temMais;
}

String diaParaApi(DateTime dia) =>
    '${dia.year.toString().padLeft(4, '0')}-'
    '${dia.month.toString().padLeft(2, '0')}-'
    '${dia.day.toString().padLeft(2, '0')}';

class AdministracaoService {
  AdministracaoService({required ApiClient api}) : _api = api;

  final ApiClient _api;

  static const tamanhoDaPagina = 50;
  static const offsetMaximo = 10000;

  Future<List<UsuarioAdmin>> usuarios() async {
    final resposta = await _api
        .get('usuarios')
        .timeout(const Duration(seconds: 15));
    try {
      return ((resposta as Map)['usuarios'] as List)
          .map((e) => UsuarioAdmin.fromJson(e as Map))
          .toList();
    } catch (_) {
      throw const ApiException(
        502,
        'Resposta de usuários inválida. Tente novamente.',
      );
    }
  }

  Future<UsuarioAdmin> criar({
    required String nome,
    required String email,
    required String senha,
    required PerfilUsuario perfil,
  }) async {
    final resposta = await _api
        .post(
          'usuarios',
          body: {
            'usuario': {
              'nome': nome,
              'email': email,
              'senha': senha,
              'tipo': perfil.name,
            },
          },
        )
        .timeout(const Duration(seconds: 20));
    return _usuarioDaResposta(resposta, 'criar');
  }

  Future<UsuarioAdmin> inativar(int id) async {
    final resposta = await _api
        .patch('usuarios/$id/inativar')
        .timeout(const Duration(seconds: 20));
    return _usuarioDaResposta(resposta, 'inativar');
  }

  Future<PaginaDeLogs> logs({
    int? usuarioId,
    DateTime? inicio,
    DateTime? fim,
    int pagina = 0,
  }) async {
    final resposta = await _api
        .get(
          'logs',
          query: {
            'limit': '$tamanhoDaPagina',
            'offset': '${pagina * tamanhoDaPagina}',
            if (usuarioId != null) 'usuario_id': '$usuarioId',
            if (inicio != null) 'data_inicio': diaParaApi(inicio),
            if (fim != null) 'data_fim': diaParaApi(diaSeguinte(fim)),
          },
        )
        .timeout(const Duration(seconds: 15));
    try {
      final dados = resposta as Map;
      return PaginaDeLogs(
        registros: (dados['logs'] as List)
            .map((e) => RegistroLog.fromJson(e as Map))
            .toList(),
        temMais: (dados['paginacao'] as Map)['tem_mais'] as bool,
      );
    } catch (_) {
      throw const ApiException(
        502,
        'Resposta de logs inválida. Tente novamente.',
      );
    }
  }

  UsuarioAdmin _usuarioDaResposta(Object? resposta, String acao) {
    try {
      return UsuarioAdmin.fromJson(resposta! as Map);
    } catch (_) {
      throw ApiException(502, 'Resposta inválida ao $acao o usuário.');
    }
  }
}

DateTime diaSeguinte(DateTime dia) =>
    DateTime(dia.year, dia.month, dia.day + 1);
