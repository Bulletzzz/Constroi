import '../../core/api/api_client.dart';
import 'painel_model.dart';

class PainelService {
  const PainelService(this._api);
  final ApiClient _api;

  Future<PainelDados> carregar({int? obraId, int offset = 0}) async {
    final resposta = await _api
        .get(
          'painel',
          query: {
            if (obraId != null) 'obra_id': '$obraId',
            'limit': '5',
            'offset': '$offset',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (resposta is! Map<String, dynamic>) {
      throw const FormatException('Resposta do painel invalida.');
    }
    return PainelDados.fromJson(resposta);
  }
}
