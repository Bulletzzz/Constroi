import 'package:constroi_api/ambiente.dart';
import 'package:constroi_api/conexao_api.dart';
import 'package:postgres/postgres.dart';

Pool<void>? _pool;

/// Pool de conexoes com o Neon, criado na primeira vez que e usado.
Pool<void> get banco {
  final url = variavel('DATABASE_URL');
  if (url == null) {
    throw StateError('DATABASE_URL nao configurada. Confira o .env');
  }
  final limite = int.tryParse(
    variavel('DATABASE_TRANSACTION_TIMEOUT_MS') ?? '30000',
  );
  if (limite == null) {
    throw StateError('DATABASE_TRANSACTION_TIMEOUT_MS invalido.');
  }
  return _pool ??= criarPoolApi(
    url,
    limiteMs: limite,
  );
}
