import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

final _ambiente = DotEnv(includePlatformEnvironment: true)..load();

Pool<void>? _pool;

/// Pool de conexoes com o Neon, criado na primeira vez que e usado.
Pool<void> get banco {
  final url = _ambiente['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    throw StateError('DATABASE_URL nao configurada. Confira o .env');
  }
  return _pool ??= Pool.withUrl(url);
}
