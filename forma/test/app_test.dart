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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Manrope')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Manrope.ttf').readAsBytesSync(),
          ),
        ),
      );
    await loader.load();
  });
  void phone(WidgetTester tester, {Size size = const Size(390, 844)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final engine = RiskEngine.fromJson(
    jsonDecode(File('assets/course_risk.json').readAsStringSync()),
  );
  final payload = jsonDecode(
    File('assets/demo_student.json').readAsStringSync(),
  );
  List<Map<String, dynamic>> sampleCourses() => (payload['courses'] as List)
      .map((course) => Map<String, dynamic>.from(course as Map))
      .toList();

  test('Courses survive closing and reopening local storage', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await StudentStore.open();
    await store.save(sampleCourses().first);
    final reopened = await StudentStore.open();
    expect(reopened.courses.first['name'], 'Mathematics');
    await reopened.remove('math');
    expect((await StudentStore.open()).courses, isEmpty);
  });
  test('Derived reversed-scale grades use the original scale in the UI', () {
    final course = sampleCourses()[1]
      ..remove('current_grade')
      ..remove('current_grade_available_on');
    final result = engine.predictCourse(course, DateTime.utc(2026, 10, 7));
    expect(rawCurrentGrade(course, result), closeTo(4.15, 1e-10));
  });
  testWidgets('Dated assessment entry saves a score and updates the forecast', (
    tester,
  ) async {
    phone(tester);
    final store = StudentStore.memory(
      profile: const StudentProfile(name: 'Ahmed', grade: 'Grade 11', age: 17),
      demo: true,
    );
    await tester.pumpWidget(ElThanawiyaApp(engine: engine, store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add course'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('name')), 'Biology');
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Add assessment'),
      180,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.bySemanticsLabel('Add assessment'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('assessment_score')),
      '63',
    );
    await tester.tap(find.text('Save assessment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save course'));
    await tester.pumpAndSettle();
    expect(store.courses.single['assessments'][0]['score'], 63);
    expect(find.text('1 of 1 courses'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'About sheet remains readable on a small screen with large text',
    (tester) async {
      phone(tester, size: const Size(320, 760));
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ElThanawiyaApp(
          engine: engine,
          store: StudentStore.memory(
            profile: const StudentProfile(
              name: 'Ahmed',
              grade: 'Grade 11',
              age: 17,
            ),
            demo: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('About El-Thanawiya'));
      await tester.pumpAndSettle();
      expect(find.text('About El-Thanawiya'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Empty app opens the form and saves a real course', (
    tester,
  ) async {
    phone(tester);
    final store = StudentStore.memory(
      profile: const StudentProfile(name: 'Ahmed', grade: 'Grade 11', age: 17),
      demo: true,
    );
    await tester.pumpWidget(ElThanawiyaApp(engine: engine, store: store));
    await tester.pumpAndSettle();
    expect(find.text('No courses yet'), findsOneWidget);
    await tester.tap(find.text('Add course'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('name')), 'Physics');
    await tester.enterText(find.byKey(const ValueKey('current_grade')), '40');
    await tester.tap(find.text('Save course'));
    await tester.pumpAndSettle();
    expect(store.courses.single['name'], 'Physics');
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('At risk'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Missing grades do not count as zero risk; detail and edit work',
    (tester) async {
      phone(tester);
      final store = StudentStore.memory(
        profile: const StudentProfile(
          name: 'Ahmed',
          grade: 'Grade 11',
          age: 17,
        ),
        courses: sampleCourses(),
        demo: true,
      );
      await tester.pumpWidget(ElThanawiyaApp(engine: engine, store: store));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3 courses'), findsOneWidget);
      expect(find.text('71%'), findsOneWidget);
      await tester.tap(find.text('German'));
      await tester.pumpAndSettle();
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('4.5'), findsWidgets);
      await tester.tap(find.bySemanticsLabel('Edit course'));
      await tester.pumpAndSettle();
      expect(find.text('Edit course'), findsOneWidget);
      expect(find.text('Lower is better'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Narrow screens and large text remain usable', (tester) async {
    phone(tester, size: const Size(320, 760));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = StudentStore.memory(
      profile: const StudentProfile(name: 'Ahmed', grade: 'Grade 11', age: 17),
      courses: sampleCourses(),
      demo: true,
    );
    await tester.pumpWidget(ElThanawiyaApp(engine: engine, store: store));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Add course'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
