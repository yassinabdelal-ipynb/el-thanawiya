// Render accurate, sample-only app surfaces for the cinematic advertisement.
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
  testWidgets('Capture actual UI for the product film', (tester) async {
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fonts = FontLoader('Manrope')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Manrope.ttf').readAsBytesSync(),
          ),
        ),
      );
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final engine = RiskEngine.fromJson(
      jsonDecode(File('assets/course_risk.json').readAsStringSync()),
    );
    final demo = jsonDecode(
      File('assets/demo_student.json').readAsStringSync(),
    );
    const screen = ValueKey('film_screen');
    Future<void> capture(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(screen),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../el-thanawiya-film/screens/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> mount(Widget child) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(RepaintBoundary(key: screen, child: child));
    }

    await mount(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(dark: true),
        home: const SplashPage(),
      ),
    );
    for (var i = 0; i < 44; i++) {
      await tester.pump(const Duration(milliseconds: 42));
      await capture('loading-flow/${(i + 1).toString().padLeft(4, '0')}');
    }
    final setup = StudentStore.memory();
    await mount(ElThanawiyaApp(engine: engine, store: setup));
    await tester.pumpAndSettle();
    await capture('profile-empty');
    await tester.enterText(find.byKey(const ValueKey('profile_name')), 'Ahmed');
    await tester.enterText(
      find.byKey(const ValueKey('profile_grade')),
      'Grade 11',
    );
    await tester.enterText(find.byKey(const ValueKey('profile_age')), '17');
    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await capture('profile-filled');
    final store = StudentStore.memory(
      profile: const StudentProfile(name: 'Ahmed', grade: 'Grade 11', age: 17),
      demo: true,
      courses: (demo['courses'] as List)
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList(),
    );
    await mount(ElThanawiyaApp(engine: engine, store: store));
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(milliseconds: 42));
      await capture('overview-flow/${(i + 1).toString().padLeft(4, '0')}');
    }
    await tester.pumpAndSettle();
    await capture('overview');
    await tester.tap(find.text('German'));
    await tester.pumpAndSettle();
    await capture('course');
    final list = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(list, const Offset(0, -600));
    await tester.pumpAndSettle();
    await capture('course-history');
    await tester.drag(list, const Offset(0, 900));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Edit course'));
    await tester.pumpAndSettle();
    await capture('course-form');
    final form = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Add assessment'),
      180,
      scrollable: form,
    );
    await tester.pumpAndSettle();
    await capture('course-schedule');
    await tester.tap(find.bySemanticsLabel('Add assessment'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('assessment_score')),
      '4.5',
    );
    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await capture('assessment');
    await tester.tap(find.text('Save assessment'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(ExpansionTile),
      180,
      scrollable: form,
    );
    await tester.drag(form, const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await tester.drag(form, const Offset(0, -480));
    await tester.pumpAndSettle();
    await capture('optional');
    await mount(ElThanawiyaApp(engine: engine, store: store));
    await store.toggleNightMode();
    await tester.pumpAndSettle();
    await capture('overview-night');
    await tester.tap(find.text('German'));
    await tester.pumpAndSettle();
    await capture('course-night');
    debugDisableShadows = true;
    expect(tester.takeException(), isNull);
  });
}
