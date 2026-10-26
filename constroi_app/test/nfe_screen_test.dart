import 'dart:async';
import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/features/nfe/nfe_file_picker.dart';
import 'package:constroi_app/features/nfe/nfe_preview.dart';
import 'package:constroi_app/features/nfe/nfe_screen.dart';
import 'package:constroi_app/features/nfe/nfe_service.dart';
import 'package:constroi_app/navigation/perfil_usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_client_test.dart' show MemoryTokenStorage;
import 'support/nfe_fixture.dart';

http.Response resposta(Object dados, [int status = 200]) => http.Response(
  jsonEncode(dados),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Finder id(String valor) => find.bySemanticsIdentifier(valor);

Future<void> tocar(WidgetTester tester, String identificador) async {
  final alvo = id(identificador);
  final scrollable = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    alvo,
    200,
    scrollable: scrollable,
    maxScrolls: 80,
  );
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<List<http.Request>> abrir(
  WidgetTester tester, {
  Future<http.Response> Function(http.Request)? enviar,
  EscolherXml? arquivo,
  List<Map<String, Object>> obras = const [
    {'id': 7, 'nome': 'Obra Centro'},
  ],
  Future<http.Response> Function()? carregar,
  PerfilUsuario perfil = PerfilUsuario.engenheiro,
  double escala = 1,
}) async {
  final chamadas = <http.Request>[];
  final api = ApiClient(
    config: ApiConfig('https://api.constroi.test'),
    sessions: SessionManager(MemoryTokenStorage()),
    httpClient: MockClient((request) async {
      chamadas.add(request);
      if (request.method == 'GET') {
        return carregar == null ? resposta({'obras': obras}) : await carregar();
      }
      return enviar == null
          ? resposta(resultadoNfe(anexo: request.method == 'PATCH'))
          : await enviar(request);
    }),
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('captura-nfe'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: NfeScreen(
          service: NfeService(api: api),
          perfil: perfil,
          selecionarArquivo:
              arquivo ??
              () async => NfePreview.ler('nota.xml', utf8.encode(xmlNfe())),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return chamadas;
}

Future<void> revisar(WidgetTester tester, {bool anexo = false}) async {
  if (anexo) {
    await tocar(tester, 'nfe-modo-anexar');
    await tester.enterText(find.byType(TextField), '42');
  }
  await tocar(tester, 'nfe-arquivo');
  await tocar(tester, 'nfe-revisar');
}

void main() {
  testWidgets('só grava após revisar materiais e confirmar a obra escolhida', (
    tester,
  ) async {
    final chamadas = await abrir(
      tester,
      obras: [
        {'id': 7, 'nome': 'Obra Centro'},
        {'id': 8, 'nome': 'Obra Norte'},
      ],
    );
    await tocar(tester, 'nfe-obra');
    await tester.tap(find.text('Obra Norte').last);
    await tester.pumpAndSettle();
    await revisar(tester);
    expect(find.text('Cimento CP-II'), findsOneWidget);
    expect(find.text('Código: CIM-01'), findsOneWidget);
    expect(find.text('Quantidade: 1,25 SC'), findsOneWidget);
    expect(find.text('Destino: Obra Norte'), findsOneWidget);
    expect(chamadas.where((r) => r.method != 'GET'), isEmpty);
    await tocar(tester, 'nfe-confirmar');
    expect(id('nfe-sucesso'), findsOneWidget);
    expect(chamadas.last.method, 'POST');
    expect(chamadas.last.body, contains('name="obra_id"\r\n\r\n8\r\n'));
    expect(id('nfe-confirmar'), findsNothing);
  });

  testWidgets(
    'anexa à entrada existente sem mandar obra e explica a limitação do anexo',
    (tester) async {
      final chamadas = await abrir(tester, obras: []);
      await revisar(tester, anexo: true);
      expect(find.textContaining('não compara'), findsOneWidget);
      expect(chamadas.where((r) => r.method != 'GET'), isEmpty);
      await tocar(tester, 'nfe-confirmar');
      expect(chamadas.last.method, 'PATCH');
      expect(chamadas.last.url.path, '/entradas/42/xml');
      expect(chamadas.last.body, isNot(contains('name="obra_id"')));
      expect(find.text('XML anexado com sucesso.'), findsOneWidget);
    },
  );

  testWidgets(
    '422 lista todos os materiais e motivos e permite nova confirmação',
    (tester) async {
      var tentativas = 0;
      final chamadas = await abrir(
        tester,
        enviar: (_) async => ++tentativas == 1
            ? resposta(pendenciasNfe, 422)
            : resposta(resultadoNfe()),
      );
      await revisar(tester);
      await tocar(tester, 'nfe-confirmar');
      expect(id('nfe-material-pendente'), findsNWidgets(3));
      expect(find.textContaining('Material não encontrado.'), findsOneWidget);
      expect(find.textContaining('Mais de um material'), findsOneWidget);
      expect(find.textContaining('unidade cadastrada.'), findsOneWidget);
      expect(id('nfe-sucesso'), findsNothing);
      await tocar(tester, 'nfe-confirmar');
      expect(id('nfe-sucesso'), findsOneWidget);
      expect(chamadas.where((r) => r.method == 'POST'), hasLength(2));
    },
  );

  for (final mensagem in [
    'Esta NF-e ja foi registrada na empresa.',
    'A entrada ja possui um XML anexado.',
    'A entrada excede a quantidade maxima do estoque.',
  ]) {
    testWidgets('409 preserva a causa: $mensagem', (tester) async {
      await abrir(
        tester,
        enviar: (_) async => resposta({'erro': mensagem}, 409),
      );
      await revisar(tester);
      await tocar(tester, 'nfe-confirmar');
      expect(id('nfe-conflito'), findsOneWidget);
      expect(find.text(mensagem), findsOneWidget);
      expect(id('nfe-sucesso'), findsNothing);
    });
  }

  for (final status in [400, 403, 404, 413, 500]) {
    testWidgets('exibe falha $status sem perder a revisão', (tester) async {
      await abrir(
        tester,
        enviar: (_) async => resposta({'erro': 'Falha $status'}, status),
      );
      await revisar(tester, anexo: true);
      await tocar(tester, 'nfe-confirmar');
      expect(find.text('Falha $status'), findsOneWidget);
      expect(id('nfe-previa'), findsOneWidget);
      expect(id('nfe-sucesso'), findsNothing);
    });
  }

  testWidgets(
    'falha de conexão não indica sucesso e mantém arquivo para tentar de novo',
    (tester) async {
      await abrir(
        tester,
        enviar: (_) async => throw http.ClientException('offline'),
      );
      await revisar(tester);
      await tocar(tester, 'nfe-confirmar');
      expect(
        find.textContaining('se a nota já foi registrada'),
        findsOneWidget,
      );
      expect(id('nfe-previa'), findsOneWidget);
    },
  );

  testWidgets('bloqueia duplo envio e saída enquanto aguarda a resposta', (
    tester,
  ) async {
    final pendente = Completer<http.Response>();
    final chamadas = await abrir(tester, enviar: (_) => pendente.future);
    await revisar(tester);
    await tester.ensureVisible(id('nfe-confirmar'));
    await tester.pumpAndSettle();
    await tester.tap(id('nfe-confirmar'));
    await tester.pump();
    await tester.tap(id('nfe-confirmar'));
    await tester.pump();
    expect(chamadas.where((r) => r.method == 'POST'), hasLength(1));
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: id('nfe-editar'),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );
    pendente.complete(resposta(resultadoNfe()));
    await tester.pumpAndSettle();
    expect(id('nfe-sucesso'), findsOneWidget);
  });

  testWidgets('valida arquivo e número da entrada antes de revisar', (
    tester,
  ) async {
    final chamadas = await abrir(tester);
    await tocar(tester, 'nfe-revisar');
    expect(find.text('Escolha o arquivo XML da NF-e.'), findsOneWidget);
    await tocar(tester, 'nfe-modo-anexar');
    for (final valor in ['', '0', '2147483648']) {
      await tester.enterText(find.byType(TextField), valor);
      await tocar(tester, 'nfe-revisar');
      expect(find.textContaining('maior que zero'), findsOneWidget);
    }
    expect(chamadas.where((r) => r.method != 'GET'), isEmpty);
  });

  testWidgets(
    'cancelar seletor preserva a seleção, arquivo inválido limpa a seleção anterior',
    (tester) async {
      var escolhas = 0;
      final chamadas = await abrir(
        tester,
        arquivo: () async {
          escolhas++;
          if (escolhas == 2) return null;
          if (escolhas == 3) throw const FormatException('XML inválido');
          return NfePreview.ler('nota.xml', utf8.encode(xmlNfe()));
        },
      );
      await tocar(tester, 'nfe-arquivo');
      await tocar(tester, 'nfe-arquivo');
      expect(find.text('nota.xml'), findsOneWidget);
      await tocar(tester, 'nfe-arquivo');
      expect(find.text('nota.xml'), findsNothing);
      expect(find.text('XML inválido'), findsOneWidget);
      expect(chamadas.where((r) => r.method != 'GET'), isEmpty);
    },
  );

  testWidgets('pedreiro não vê o formulário nem consulta a API', (
    tester,
  ) async {
    final chamadas = await abrir(tester, perfil: PerfilUsuario.pedreiro);
    expect(find.textContaining('Acesso exclusivo'), findsOneWidget);
    expect(chamadas, isEmpty);
    expect(id('nfe-arquivo'), findsNothing);
  });

  testWidgets('master pode usar a tela', (tester) async {
    await abrir(tester, perfil: PerfilUsuario.master);
    expect(id('nfe-arquivo'), findsOneWidget);
  });

  testWidgets('obras vazias bloqueiam importação mas permitem anexar', (
    tester,
  ) async {
    await abrir(tester, obras: []);
    expect(id('nfe-obras-vazio'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.descendant(
              of: id('nfe-revisar'),
              matching: find.byType(ElevatedButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tocar(tester, 'nfe-modo-anexar');
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('erro ao carregar obras permite nova tentativa', (tester) async {
    var tentativas = 0;
    await abrir(
      tester,
      carregar: () async => ++tentativas == 1
          ? resposta({'erro': 'Falha ao consultar obras'}, 503)
          : resposta({
              'obras': [
                {'id': 7, 'nome': 'Obra Centro'},
              ],
            }),
    );
    expect(id('nfe-obras-erro'), findsOneWidget);
    await tocar(tester, 'nfe-obras-tentar');
    expect(id('nfe-obra'), findsOneWidget);
    expect(id('nfe-obras-erro'), findsNothing);
  });

  for (final tamanho in [
    const Size(320, 640),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'varredura de formulário, prévia, erro, anexo e sucesso em $tamanho',
      (tester) async {
        tester.view.physicalSize = tamanho;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var tentativas = 0;
        await abrir(
          tester,
          escala: 1.4,
          arquivo: () async => NfePreview.ler(
            'nota-fiscal-com-nome-longo-para-conferencia-de-materiais.xml',
            utf8.encode(
              xmlNfe(
                nome:
                    'Cimento composto de alta resistência para estruturas e fundações',
              ),
            ),
          ),
          enviar: (r) async => ++tentativas == 1
              ? resposta(pendenciasNfe, 422)
              : resposta(resultadoNfe(anexo: r.method == 'PATCH')),
        );
        expect(tester.takeException(), isNull);
        await revisar(tester);
        expect(id('nfe-material'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tocar(tester, 'nfe-confirmar');
        await tester.ensureVisible(id('nfe-material-pendente').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tocar(tester, 'nfe-editar');
        await tocar(tester, 'nfe-modo-anexar');
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '42');
        await tocar(tester, 'nfe-revisar');
        expect(tester.takeException(), isNull);
        await tocar(tester, 'nfe-confirmar');
        expect(id('nfe-sucesso'), findsOneWidget);
        await tester.ensureVisible(id('nfe-concluir'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
