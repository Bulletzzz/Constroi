import '../../core/api/api_client.dart';
import '../../navigation/perfil_usuario.dart';

class ObraEquipe {
  ObraEquipe.fromJson(Map dados)
    : id = dados['id'] as int,
      nome = dados['nome'] as String;
  final int id;
  final String nome;
}

class PessoaEquipe {
  PessoaEquipe.fromJson(Map dados)
    : id = dados['usuario_id'] as int,
      nome = dados['nome'] as String,
      email = dados['email'] as String,
      perfil = PerfilUsuario.porNome(dados['tipo']),
      inicio = dados['data_inicio'] == null
          ? null
          : DateTime.parse(dados['data_inicio'] as String).toLocal();

  final int id;
  final String nome;
  final String email;
  final PerfilUsuario? perfil;
  final DateTime? inicio;

  String get papel => switch (perfil) {
    PerfilUsuario.master => 'Master',
    PerfilUsuario.engenheiro => 'Engenheiro',
    PerfilUsuario.pedreiro => 'Pedreiro',
    null => 'Perfil não informado',
  };

  String? get desde => inicio == null
      ? null
      : '${inicio!.day.toString().padLeft(2, '0')}/'
            '${inicio!.month.toString().padLeft(2, '0')}/${inicio!.year}';
}

class EquipeService {
  EquipeService({required ApiClient api}) : _api = api;
  final ApiClient _api;

  Future<List<ObraEquipe>> obras() async {
    final resposta = await _api
        .get('obras')
        .timeout(const Duration(seconds: 15));
    try {
      return ((resposta as Map)['obras'] as List)
          .map((e) => ObraEquipe.fromJson(e as Map))
          .toList();
    } catch (_) {
      throw const ApiException(
        502,
        'Resposta de obras inválida. Tente novamente.',
      );
    }
  }

  Future<List<PessoaEquipe>> listar(int obraId) async {
    final resposta = await _api
        .get('obras/$obraId/equipe')
        .timeout(const Duration(seconds: 15));
    try {
      return ((resposta as Map)['equipe'] as List)
          .map((e) => PessoaEquipe.fromJson(e as Map))
          .toList();
    } catch (_) {
      throw const ApiException(
        502,
        'Resposta de equipe inválida. Tente novamente.',
      );
    }
  }
}
