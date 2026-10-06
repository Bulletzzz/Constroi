import 'package:constroi_api/ambiente.dart';
import 'package:postgres/postgres.dart';

Pool<void>? _pool;

/// Pool de conexoes com o Neon, criado na primeira vez que e usado.
Pool<void> get banco {
  final url = variavel('DATABASE_URL');
  if (url == null) {
    throw StateError('DATABASE_URL nao configurada. Confira o .env');
  }
  return _pool ??= Pool.withUrl(
    _comLimiteDeConexoes(normalizarDatabaseUrl(url)),
  );
}

String _comLimiteDeConexoes(String url) {
  final uri = Uri.parse(url);
  final parametros = Map<String, String>.from(uri.queryParameters)
    ..putIfAbsent('max_connection_count', () => '10');
  return uri.replace(queryParameters: parametros).toString();
}
