import 'package:constroi_api/ambiente.dart';
import 'package:postgres/postgres.dart';

const limiteMaximoTransacaoMs = 30000;
const margemFechamentoAuditoriaMs = 31000;

/// Aceita endpoint direto, sem overrides de host/usuario na query string.
Uri validarUrlApi(String valor) {
  try {
    final uri = Uri.parse(normalizarDatabaseUrl(valor));
    if (!['postgresql', 'postgres'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.host.contains(',') ||
        uri.host.contains('-pooler.') ||
        uri.pathSegments.length != 1 ||
        uri.pathSegments.single.isEmpty ||
        uri.userInfo.split(':').first.isEmpty ||
        uri.queryParameters.keys.any(
          (k) => !{'sslmode', 'max_connection_count'}.contains(k),
        )) {
      throw const FormatException();
    }
    final maximo = int.tryParse(
      uri.queryParameters['max_connection_count'] ?? '10',
    );
    for (final componente in uri.userInfo.split(':')) {
      Uri.decodeComponent(componente);
    }
    if (maximo == null || maximo < 1 || maximo > 50) {
      throw const FormatException();
    }
    return uri;
  } on Object {
    throw const FormatException(
      'DATABASE_URL invalida: use endpoint direto, TLS, usuario e banco '
      'explicitos; max_connection_count entre 1 e 50.',
    );
  }
}

String urlDeMigration(Map<String, String> ambiente) {
  final url = ambiente['MIGRATION_DATABASE_URL']?.trim() ?? '';
  if (url.isEmpty) {
    throw const FormatException(
      'Configure MIGRATION_DATABASE_URL no ambiente exclusivo de migrations. '
      'Nao ha fallback para DATABASE_URL.',
    );
  }
  final uri = validarUrlApi(url);
  final runtime = ambiente['DATABASE_URL']?.trim();
  if (runtime != null &&
      runtime.isNotEmpty &&
      Uri.decodeComponent(validarUrlApi(runtime).userInfo.split(':').first) ==
          Uri.decodeComponent(uri.userInfo.split(':').first)) {
    throw const FormatException(
      'API e migrations precisam de usuarios distintos.',
    );
  }
  // Connection.openFromUrl nao aceita parametros exclusivos do pool.
  final parametros = Map<String, String>.from(uri.queryParameters)
    ..remove('max_connection_count');
  return uri.replace(queryParameters: parametros).toString();
}

Pool<void> criarPoolApi(
  String url, {
  bool conexaoEstrita = false,
  int limiteMs = limiteMaximoTransacaoMs,
}) {
  if (!conexaoEstrita) {
    // Preserva o contrato atual ate o provisionamento coordenado da auditoria.
    final uri = Uri.parse(normalizarDatabaseUrl(url));
    final parametros = Map<String, String>.from(uri.queryParameters)
      ..putIfAbsent('max_connection_count', () => '10');
    return Pool<void>.withUrl(
      uri.replace(queryParameters: parametros).toString(),
    );
  }
  final uri = validarUrlApi(url);
  if (limiteMs <= 0 || limiteMs > limiteMaximoTransacaoMs) {
    throw const FormatException(
      'O limite de transacao deve ficar entre 1 e 30000 ms.',
    );
  }
  final credenciais = uri.userInfo.split(':');
  return Pool<void>.withEndpoints(
    [
      Endpoint(
        host: uri.host,
        port: uri.hasPort ? uri.port : 5432,
        database: uri.pathSegments.single,
        username: Uri.decodeComponent(credenciais.first),
        password: credenciais.length > 1
            ? Uri.decodeComponent(credenciais.skip(1).join(':'))
            : null,
      ),
    ],
    settings: PoolSettings(
      sslMode: uri.queryParameters['sslmode'] == 'verify-full'
          ? SslMode.verifyFull
          : SslMode.require,
      maxConnectionCount: int.parse(
        uri.queryParameters['max_connection_count'] ?? '10',
      ),
      applicationName: 'constroi-api',
      connectTimeout: const Duration(seconds: 10),
      queryTimeout: const Duration(seconds: 35),
      onOpen: (conexao) async {
        try {
          await validarSessaoApi(conexao, limiteMs: limiteMs);
        } on Object {
          // O driver pode falhar antes de adicionar a conexao ao pool.
          // Feche tambem nesse caminho para nao deixar o socket aberto.
          await conexao.close(force: true);
          rethrow;
        }
      },
    ),
  );
}

/// Executada a cada conexao fisica, antes de a entregar a qualquer rota.
Future<void> validarSessaoApi(
  Connection conexao, {
  int limiteMs = limiteMaximoTransacaoMs,
}) async {
  if (limiteMs <= 0 || limiteMs > limiteMaximoTransacaoMs) {
    throw const FormatException('Limite de transacao invalido.');
  }
  final linhas = await conexao.execute('''
    SELECT current_setting('server_version_num')::int AS versao,
      r.rolsuper OR r.rolcreatedb OR r.rolcreaterole OR r.rolreplication
        OR r.rolbypassrls OR pg_has_role(r.oid,d.datdba,'MEMBER')
        OR has_schema_privilege(current_user,'public','CREATE')
        OR has_database_privilege(current_user,current_database(),'CREATE')
        OR EXISTS (
          SELECT 1 FROM pg_roles p WHERE p.oid <> r.oid
          AND pg_has_role(r.oid,p.oid,'MEMBER')
          AND (p.rolsuper OR p.rolcreatedb OR p.rolcreaterole OR p.rolbypassrls
            OR p.rolname IN ('neon_superuser','pg_write_all_data'))
        ) OR EXISTS (
          SELECT 1 FROM pg_class c WHERE c.relnamespace='public'::regnamespace
          AND pg_has_role(r.oid,c.relowner,'MEMBER')
        ) AS privilegiado,
      CASE WHEN to_regclass('public.movimentacao_estoque') IS NULL THEN false
        ELSE has_table_privilege(current_user,'public.movimentacao_estoque','UPDATE,DELETE,TRUNCATE,TRIGGER')
          OR has_any_column_privilege(current_user,'public.movimentacao_estoque','UPDATE')
          OR NOT has_table_privilege(current_user,'public.movimentacao_estoque','INSERT')
          OR NOT has_table_privilege(current_user,'public.movimentacao_estoque','SELECT')
      END AS auditoria_insegura
    FROM pg_roles r CROSS JOIN pg_database d
    WHERE r.rolname=current_user AND d.datname=current_database()
  ''');
  final estado = linhas.single.toColumnMap();
  if ((estado['versao']! as int) < 170000 ||
      estado['privilegiado'] == true ||
      estado['auditoria_insegura'] == true) {
    throw StateError(
      'Conexao de execucao insegura. Exige PostgreSQL 17+, papel sem '
      'administracao/ownership e auditoria somente INSERT/SELECT.',
    );
  }
  final limite = await conexao.execute(
    "SELECT setting::int FROM pg_settings WHERE name='transaction_timeout'",
  );
  final valor = limite.single[0]! as int;
  if (valor <= 0 || valor > limiteMaximoTransacaoMs) {
    throw StateError(
      'Configure transaction_timeout do papel entre 1 e 30000 ms '
      'antes de iniciar a API.',
    );
  }
  // Nunca aumenta um limite menor imposto pelo administrador.
  final efetivo = valor < limiteMs ? valor : limiteMs;
  await conexao.execute(
    Sql.named("SELECT set_config('transaction_timeout',@valor,false)"),
    parameters: {'valor': '${efetivo}ms'},
  );
}
