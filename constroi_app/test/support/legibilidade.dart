import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const contrasteMinimo = 4.5;

double contraste(Color fundo, Color texto) {
  final a = fundo.computeLuminance();
  final b = texto.computeLuminance();
  final claro = a > b ? a : b;
  final escuro = a > b ? b : a;
  return (claro + 0.05) / (escuro + 0.05);
}

void conferirDropdownsLegiveis(WidgetTester tester) {
  final alvos = find.byWidgetPredicate((w) => w is DropdownButton);
  expect(alvos, findsWidgets);

  for (final elemento in alvos.evaluate()) {
    final menu = elemento.widget as DropdownButton<dynamic>;
    final tema = Theme.of(elemento);
    final fundo = menu.dropdownColor ?? tema.canvasColor;
    final texto = menu.style?.color ?? tema.textTheme.titleMedium?.color;
    if (texto == null) continue;
    expect(
      contraste(fundo, texto),
      greaterThanOrEqualTo(contrasteMinimo),
      reason: 'menu de $fundo com texto $texto fica ilegivel',
    );
  }
}

void conferirCamposLegiveis(WidgetTester tester) {
  final alvos = find.byType(TextField);
  expect(alvos, findsWidgets);

  for (final elemento in alvos.evaluate()) {
    final campo = elemento.widget as TextField;
    final decoracao = campo.decoration;
    final texto = campo.style?.color;
    if (decoracao == null || texto == null) continue;

    final tema = Theme.of(elemento).inputDecorationTheme;
    if (!(decoracao.filled ?? tema.filled)) continue;

    final fundo = decoracao.fillColor ?? tema.fillColor;
    if (fundo == null) continue;
    expect(
      contraste(fundo, texto),
      greaterThanOrEqualTo(contrasteMinimo),
      reason: 'campo de $fundo com texto $texto fica ilegivel',
    );
  }
}
