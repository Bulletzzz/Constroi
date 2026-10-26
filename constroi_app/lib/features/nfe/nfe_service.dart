import 'package:http/http.dart' as http;

import '../../core/api/api_client.dart';
import '../painel/painel_model.dart';
import 'nfe_preview.dart';

class NfeResultado {
  const NfeResultado(this.id, this.obraId, this.chave);
  final int id;
  final int obraId;
  final String chave;
}

class NfeService {
  NfeService({required ApiClient api}) : _api = api;
  final ApiClient _api;

  Future<List<ObraPainel>> obras() async {
    final dados = await _api.get('obras').timeout(const Duration(seconds: 15));
    try {
      return ((dados as Map)['obras'] as List)
          .map((e) => ObraPainel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw const ApiException(502, 'Não foi possível ler a lista de obras.');
    }
  }

  Future<NfeResultado> importar(NfePreview nota, int obraId) {
    _validarId(obraId);
    return _enviar(
      nota,
      'POST',
      'entradas/xml',
      fields: {'obra_id': '$obraId'},
    );
  }

  Future<NfeResultado> anexar(NfePreview nota, int entradaId) {
    _validarId(entradaId);
    return _enviar(nota, 'PATCH', 'entradas/$entradaId/xml');
  }

  Future<NfeResultado> _enviar(
    NfePreview nota,
    String metodo,
    String caminho, {
    Map<String, String> fields = const {},
  }) async {
    final dados = await _api
        .multipart(
          metodo,
          caminho,
          fields: fields,
          files: [
            http.MultipartFile.fromBytes(
              'xml',
              nota.bytes,
              filename: nota.nomeArquivo,
            ),
          ],
        )
        .timeout(const Duration(seconds: 30));
    if (dados is! Map ||
        dados['id'] is! int ||
        dados['obra_id'] is! int ||
        dados['chave_nfe'] != nota.chave ||
        (metodo == 'PATCH' && dados['xml_anexado'] != true)) {
      throw const ApiException(
        502,
        'O servidor não confirmou o resultado. Confira a entrada antes de tentar novamente.',
      );
    }
    return NfeResultado(
      dados['id'] as int,
      dados['obra_id'] as int,
      dados['chave_nfe'] as String,
    );
  }

  void _validarId(int id) {
    if (id <= 0 || id > 2147483647) throw ArgumentError.value(id, 'id');
  }
}
