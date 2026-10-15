import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:forma/domain/risk_engine.dart';

void main() {
  final engine = RiskEngine.fromJson(
    jsonDecode(File('assets/course_risk.json').readAsStringSync()),
  );
  final fixture =
      jsonDecode(File('test/fixtures/parity.json').readAsStringSync())
          as Map<String, dynamic>;
  test('600 offline predictions match the original PyTorch checkpoint', () {
    var maximumError = 0.0;
    for (final sample in fixture['vectors'] as List) {
      final features = (sample['features'] as List)
          .map((value) => (value as num?)?.toDouble())
          .toList();
      final actual = engine.probability(features);
      final expected = (sample['probability'] as num).toDouble();
      final error = (actual - expected).abs();
      if (error > maximumError) maximumError = error;
      expect(actual, closeTo(expected, .000002));
    }
    print('Maximum Dart/PyTorch absolute error: $maximumError');
  });
  test(
    'Dated history, reversed grades, missingness and schedule features match Python',
    () {
      for (final sample in fixture['payloads'] as List) {
        final payload = sample['payload'] as Map<String, dynamic>;
        final courses = payload['courses'] as List;
        final asOf = parseDay(payload['as_of'], 'date');
        for (var index = 0; index < courses.length; index++) {
          final expected = sample['expected'][index];
          final prepared = prepareCourse(
            courses[index] as Map<String, dynamic>,
            asOf,
            education: payload['education_level'] as String,
          );
          expect(prepared.details['status'], expected['details']['status']);
          final features = expected['features'] as List?;
          if (features == null) {
            expect(prepared.features, isNull);
            continue;
          }
          for (var j = 0; j < features.length; j++) {
            if (features[j] == null) {
              expect(prepared.features![j], isNull);
            } else {
              expect(
                prepared.features![j],
                closeTo((features[j] as num).toDouble(), 1e-12),
              );
            }
          }
          expect(
            engine.probability(prepared.features!),
            closeTo(expected['probability'] as num, .000002),
          );
        }
      }
    },
  );
  test('Unobserved courses have no fabricated probability', () {
    final sample = fixture['payloads'][0]['payload'];
    final result = engine.predictCourse(
      sample['courses'][2],
      parseDay(sample['as_of'], 'date'),
    );
    expect(result['status'], 'insufficient_data');
    expect(result.containsKey('failure_probability'), isFalse);
  });
  test('Subject names do not select a different model', () {
    final sample = fixture['payloads'][0]['payload'];
    final course = Map<String, dynamic>.from(sample['courses'][0]);
    final first = engine.predictCourse(
      course,
      parseDay(sample['as_of'], 'date'),
    );
    course['name'] = 'Physics';
    final second = engine.predictCourse(
      course,
      parseDay(sample['as_of'], 'date'),
    );
    expect(first['failure_probability'], second['failure_probability']);
  });
  test('Invalid dates, final outcomes and grading scales are rejected', () {
    expect(() => parseDay('2026-02-30', 'date'), throwsFormatException);
    expect(() => normalized(5, 5, 5, true), throwsFormatException);
    expect(
      () => normalized(double.infinity, 0, 100, true),
      throwsFormatException,
    );
    final sample = fixture['payloads'][0]['payload'];
    final course = Map<String, dynamic>.from(sample['courses'][0]);
    course['final_grade'] = 50;
    expect(
      () => prepareCourse(course, parseDay(sample['as_of'], 'date')),
      throwsFormatException,
    );
    course.remove('final_grade');
    course['current_grade_available_on'] = '2026-10-10';
    expect(
      () => prepareCourse(course, parseDay(sample['as_of'], 'date')),
      throwsFormatException,
    );
  });
}
