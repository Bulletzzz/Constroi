import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/permissao.dart';
import 'package:dart_frog/dart_frog.dart';

Handler middleware(Handler handler) =>
    handler.use(exigirNivel(Nivel.pedreiro));
