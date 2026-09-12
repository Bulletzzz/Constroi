import 'package:constroi_api/ambiente.dart';
import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/banco.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Handler middleware(Handler handler) {
  return handler
      .use(provider<Pool<void>>((_) => banco))
      .use(
        provider<UsuarioAutenticado?>((context) {
          final segredo = variavel('JWT_SECRET');
          if (segredo == null) return null;
          return autenticar(
            context.request.headers['authorization'],
            segredo,
          );
        }),
      );
}
