import 'package:postgres/postgres.dart';

const conexoesDeTeste = 20;

String urlComPoolDeTeste(String url) {
  final uri = Uri.parse(url);
  return uri
      .replace(
        queryParameters: {
          ...uri.queryParameters,
          'max_connection_count': '$conexoesDeTeste',
        },
      )
      .toString();
}

Pool<void> poolDeTeste(String url) =>
    Pool<void>.withUrl(urlComPoolDeTeste(url));
