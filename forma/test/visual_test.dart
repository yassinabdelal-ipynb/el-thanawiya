import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forma/data/student_store.dart';
import 'package:forma/domain/risk_engine.dart';
import 'package:forma/main.dart';
import 'package:forma/ui/design.dart';
import 'package:forma/ui/splash_page.dart';

void main() {
  testWidgets('Render the real Flutter screens at Android phone size', (
    tester,
  ) async {
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('Manrope')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Manrope.ttf').readAsBytesSync(),
          ),
        ),
      );
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final engine = RiskEngine.fromJson(
      jsonDecode(File('assets/course_risk.json').readAsStringSync()),
    );
    final payload = jsonDecode(
      File('assets/demo_student.json').readAsStringSync(),
    );
    final store = StudentStore.memory(
      profile: const StudentProfile(name: 'Ahmed', grade: 'Grade 11', age: 17),
      demo: true,
      courses: (payload['courses'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );
    const key = ValueKey('screen');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ElThanawiyaApp(engine: engine, store: store),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> screenshot(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('design/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await screenshot('overview');
    await tester.tap(find.bySemanticsLabel('Use night mode'));
    await tester.pumpAndSettle();
    await screenshot('overview-night');
    await tester.tap(find.text('German'));
    await tester.pumpAndSettle();
    await screenshot('course-night');
    await tester.tap(find.bySemanticsLabel('Edit course'));
    await tester.pumpAndSettle();
    await screenshot('edit-course-night');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final firstRun = StudentStore.memory();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ElThanawiyaApp(engine: engine, store: firstRun),
      ),
    );
    await tester.pumpAndSettle();
    await screenshot('first-run');
    await tester.tap(find.bySemanticsLabel('Use night mode'));
    await tester.pumpAndSettle();
    await screenshot('first-run-night');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(dark: true),
          home: const SplashPage(animate: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await screenshot('loading-night');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: const SplashPage(animate: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await screenshot('loading');
    debugDisableShadows = true;
    expect(tester.takeException(), isNull);
  });
}
