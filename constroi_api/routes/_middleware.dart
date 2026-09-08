import 'package:constroi_api/banco.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Handler middleware(Handler handler) {
  return handler.use(provider<Pool<void>>((_) => banco));
}
