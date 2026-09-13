import 'package:dart_frog/dart_frog.dart';

import 'empresas.dart' as empresas;

Future<Response> onRequest(RequestContext context) =>
    empresas.onRequest(context);
