import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forma/data/student_store.dart';
import 'package:forma/domain/risk_engine.dart';
import 'package:forma/main.dart';
import 'package:forma/ui/design.dart';
import 'package:forma/ui/splash_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = RiskEngine.fromJson(
    jsonDecode(File('assets/course_risk.json').readAsStringSync()),
  );
  final payload = jsonDecode(
    File('assets/demo_student.json').readAsStringSync(),
  );
  List<Map<String, dynamic>> courses() => (payload['courses'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList();
  const profile = StudentProfile(name: 'Sara', grade: 'Grade 11', age: 17);
  setUpAll(() async {
    final font = FontLoader('Manrope')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Manrope.ttf').readAsBytesSync(),
          ),
        ),
      );
    await font.load();
  });
  void phone(WidgetTester tester, {Size size = const Size(390, 844)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test(
    'Profile and night mode survive restart without altering saved courses',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await StudentStore.open();
      await store.save(courses().first);
      await store.saveProfile(profile);
      await store.toggleNightMode();
      final reopened = await StudentStore.open();
      expect(reopened.profile!.toJson(), profile.toJson());
      expect(reopened.darkMode, isTrue);
      expect(reopened.courses.single['name'], 'Mathematics');
      await reopened.toggleNightMode();
      expect((await StudentStore.open()).darkMode, isFalse);
    },
  );
  test(
    'Updating the original app retains courses and requests the missing profile',
    () async {
      SharedPreferences.setMockInitialValues({
        'courses_v1': jsonEncode(courses()),
      });
      final store = await StudentStore.open();
      expect(store.profile, isNull);
      expect(store.courses.length, 3);
      await store.saveProfile(profile);
      expect((await StudentStore.open()).courses.length, 3);
    },
  );
  test('Profile rejects blank details, fractional and impossible ages', () {
    for (final invalid in [
      {'name': '', 'grade': '11', 'age': 17},
      {'name': 'Sara', 'grade': '', 'age': 17},
      {'name': 'Sara', 'grade': '11', 'age': 17.5},
      {'name': 'Sara', 'grade': '11', 'age': 0},
      {'name': 'Sara', 'grade': '11', 'age': 121},
    ]) {
      expect(() => StudentProfile.fromJson(invalid), throwsFormatException);
    }
  });
  testWidgets(
    'First run asks for name, school grade and age, then greets the entered name',
    (tester) async {
      phone(tester);
      final store = StudentStore.memory(demo: true);
      await tester.pumpWidget(ElThanawiyaApp(engine: engine, store: store));
      await tester.pumpAndSettle();
      expect(find.text('El-Thanawiya'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your name'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('profile_name')),
        'Sara',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile_grade')),
        'Grade 11',
      );
      await tester.enterText(find.byKey(const ValueKey('profile_age')), '17');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Hi, Sara'), findsOneWidget);
      expect(store.profile!.age, 17);
      expect(find.byKey(const ValueKey('profile_name')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Night mode updates home, course details and entry fields without changing predictions',
    (tester) async {
      phone(tester);
      final store = StudentStore.memory(
        profile: profile,
        courses: courses(),
        demo: true,
      );
      final probability = engine.predictCourse(
        store.courses[1],
        DateTime.utc(2026, 10, 7),
      )['failure_probability'];
      await tester.pumpWidget(ElThanawiyaApp(engine: engine, store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Use night mode'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('student_greeting'))),
        ).brightness,
        Brightness.dark,
      );
      await tester.tap(find.text('German'));
      await tester.pumpAndSettle();
      expect(find.text('71%'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Edit course'));
      await tester.pumpAndSettle();
      final context = tester.element(
        find.byKey(const ValueKey('current_grade')),
      );
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(Palette.of(context).canvas, Palette.night.canvas);
      expect(
        engine.predictCourse(
          store.courses[1],
          DateTime.utc(2026, 10, 7),
        )['failure_probability'],
        probability,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'First-run setup supports night mode and large text on a small phone',
    (tester) async {
      phone(tester, size: const Size(320, 760));
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = StudentStore.memory(darkMode: true);
      await tester.pumpWidget(ElThanawiyaApp(engine: engine, store: store));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Use light mode'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('The loading ring rotates and is disposed cleanly', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(theme: appTheme(), home: const SplashPage()),
    );
    final finder = find.byKey(const ValueKey('loading_rotation'));
    final before = List<double>.from(
      tester.widget<Transform>(finder).transform.storage,
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      tester.widget<Transform>(finder).transform.storage.toList(),
      isNot(equals(before)),
    );
    expect(find.text('El-Thanawiya'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets('Reduced-motion preference stops the loading rotation', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SplashPage(),
        ),
      ),
    );
    final finder = find.byKey(const ValueKey('loading_rotation'));
    final before = List<double>.from(
      tester.widget<Transform>(finder).transform.storage,
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      tester.widget<Transform>(finder).transform.storage.toList(),
      equals(before),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
