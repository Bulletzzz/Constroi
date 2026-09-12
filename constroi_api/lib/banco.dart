import 'package:constroi_api/ambiente.dart';
import 'package:postgres/postgres.dart';

Pool<void>? _pool;

/// Pool de conexoes com o Neon, criado na primeira vez que e usado.
Pool<void> get banco {
  final url = variavel('DATABASE_URL');
  if (url == null) {
    throw StateError('DATABASE_URL nao configurada. Confira o .env');
  }
  return _pool ??= Pool.withUrl(url);
}
