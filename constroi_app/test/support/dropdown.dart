import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void conferirDropdownsLegiveis(WidgetTester tester) {
  final encontrados = tester
      .widgetList(find.byWidgetPredicate((w) => w is DropdownButton))
      .cast<DropdownButton<dynamic>>()
      .toList();

  expect(encontrados, isNotEmpty);
  for (final menu in encontrados) {
    expect(
      menu.dropdownColor,
      isNotNull,
      reason: 'o menu herda o fundo escuro do tema e some com o texto',
    );
    expect(menu.dropdownColor, isNot(menu.style?.color));
  }
}
