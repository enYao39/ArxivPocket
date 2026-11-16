import 'dart:io';

import 'package:arxiv/models/paper.dart';
import 'package:arxiv/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDirectory;

  setUpAll(() {
    tempDirectory = Directory.systemTemp.createTempSync('home_page_test_');
    Hive.init(tempDirectory.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(PaperAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    tempDirectory.deleteSync(recursive: true);
  });

  testWidgets('HomePage builds CustomScrollView without sliver errors',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomePage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'dark matter');
    await tester.pump();
    expect(find.text('dark matter'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}
