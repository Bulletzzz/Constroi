import '../../core/api/api_client.dart';
import 'custos_model.dart';

class CustosService {
  CustosService({required ApiClient api}) : _api = api;
  final ApiClient _api;

  Future<DadosCustos> carregar({
    int? obraId,
    String periodo = 'total',
    int offset = 0,
  }) async {
    final resposta = await _api
        .get(
          'custos',
          query: {
            if (obraId != null) 'obra_id': '$obraId',
            'periodo': periodo,
            'limit': '20',
            'offset': '$offset',
          },
        )
        .timeout(const Duration(seconds: 15));
    try {
      return DadosCustos.fromJson(resposta as Map);
    } catch (_) {
      throw const ApiException(
        502,
        'Resposta de custos inválida. Tente novamente.',
      );
    }
  }
}
