import 'dart:convert';
import 'dart:math' as math;

const featureNames = [
  'current_grade',
  'latest_grade',
  'grade_trend',
  'grade_std',
  'progress',
  'assessment_count',
  'graded_fraction',
  'overdue_fraction',
  'late_fraction',
  'passing_grade',
  'previous_failures',
  'study_time',
  'activities',
  'university',
];

double number(dynamic value, String name, {double? min, double? max}) {
  if (value is! num ||
      !value.isFinite ||
      (min != null && value < min) ||
      (max != null && value > max)) {
    throw FormatException('$name is outside its valid range.');
  }
  return value.toDouble();
}

DateTime parseDay(dynamic value, String name) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw FormatException('Choose a valid $name.');
  }
  final day = DateTime.tryParse('${value}T00:00:00Z');
  if (day == null || dateKey(day) != value) {
    throw FormatException('Choose a valid $name.');
  }
  return day;
}

String dateKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
DateTime calendarDay(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day);

double normalized(dynamic grade, dynamic low, dynamic high, dynamic direction) {
  final minimum = number(low, 'Minimum grade');
  final maximum = number(high, 'Maximum grade');
  if (maximum <= minimum) {
    throw const FormatException('Maximum grade must exceed minimum grade.');
  }
  if (direction is! bool) {
    throw const FormatException('Invalid grading direction.');
  }
  final value =
      (number(grade, 'Grade', min: minimum, max: maximum) - minimum) /
      (maximum - minimum);
  return direction ? value : 1 - value;
}

class PreparedCourse {
  final List<double?>? features;
  final Map<String, dynamic> details;
  const PreparedCourse(this.features, this.details);
}

class _Mark {
  final DateTime available;
  final double score, weight;
  final int order;
  const _Mark(this.available, this.score, this.weight, this.order);
}

PreparedCourse prepareCourse(
  Map<String, dynamic> course,
  DateTime asOf, {
  String education = 'high_school',
}) {
  final name = course['name'];
  if (name is! String || name.trim().isEmpty) {
    throw const FormatException('Enter a course name.');
  }
  if (!['high_school', 'university'].contains(education)) {
    throw const FormatException('Invalid education level.');
  }
  if (['G3', 'final_grade', 'target', 'actual_fail'].any(course.containsKey)) {
    throw const FormatException('Final outcomes cannot be prediction inputs.');
  }
  final start = parseDay(course['term_start'], 'term start');
  final end = parseDay(course['term_end'], 'term end');
  asOf = calendarDay(asOf);
  if (!end.isAfter(start) || asOf.isBefore(start) || !asOf.isBefore(end)) {
    throw const FormatException('The prediction date must be inside the term.');
  }
  final low = course['grade_min'] ?? 0;
  final high = course['grade_max'] ?? 100;
  final direction = course['higher_is_better'] ?? true;
  final passing = normalized(course['passing_grade'], low, high, direction);
  final progress = asOf.difference(start).inDays / end.difference(start).inDays;
  final raw = course['assessments'] ?? <dynamic>[];
  if (raw is! List) throw const FormatException('Invalid assessment history.');
  final known = <_Mark>[];
  var totalWeight = 0.0, plannedCount = 0, dueCount = 0, overdue = 0;
  var submittedCount = 0, lateCount = 0;
  for (var index = 0; index < raw.length; index++) {
    if (raw[index] is! Map) throw const FormatException('Invalid assessment.');
    final record = Map<String, dynamic>.from(raw[index] as Map);
    final kind = record['type'] ?? 'assessment';
    if (!['assessment', 'period', 'final_exam'].contains(kind)) {
      throw const FormatException('Invalid assessment type.');
    }
    if (kind == 'final_exam') continue;
    final due = parseDay(record['due_date'], 'due date');
    if (due.isBefore(start) || due.isAfter(end)) {
      throw const FormatException('Assessment dates must belong to this term.');
    }
    final weight = number(record['weight'] ?? 1, 'Assessment weight', min: 0);
    totalWeight += weight;
    plannedCount++;
    final submitted =
        record['submitted_on'] == null || record['submitted_on'] == ''
        ? null
        : parseDay(record['submitted_on'], 'submission date');
    if (submitted != null && submitted.isBefore(start)) {
      throw const FormatException('Submission must follow the term start.');
    }
    if (!due.isAfter(asOf)) {
      dueCount++;
      if (submitted == null || submitted.isAfter(asOf)) overdue++;
    }
    if (submitted != null && !submitted.isAfter(asOf)) {
      submittedCount++;
      if (submitted.isAfter(due)) lateCount++;
    }
    if (record['score'] != null) {
      final available = parseDay(record['available_on'], 'grade date');
      if (available.isBefore(start) ||
          (submitted != null && available.isBefore(submitted))) {
        throw const FormatException(
          'Grade date must follow submission and term start.',
        );
      }
      if (!available.isAfter(asOf)) {
        known.add(
          _Mark(
            available,
            normalized(
              record['score'],
              record['grade_min'] ?? low,
              record['grade_max'] ?? high,
              record['higher_is_better'] ?? direction,
            ),
            weight,
            index,
          ),
        );
      }
    }
  }
  known.sort((a, b) {
    final comparison = a.available.compareTo(b.available);
    return comparison == 0 ? a.order.compareTo(b.order) : comparison;
  });
  double? current;
  if (course['current_grade'] != null) {
    final available = parseDay(
      course['current_grade_available_on'],
      'current grade date',
    );
    if (available.isBefore(start) || available.isAfter(asOf)) {
      throw const FormatException('Current grade must be known by today.');
    }
    current = normalized(course['current_grade'], low, high, direction);
  } else if (known.isNotEmpty) {
    final weight = known.fold(0.0, (sum, mark) => sum + mark.weight);
    current = weight > 0
        ? known.fold(0.0, (sum, mark) => sum + mark.score * mark.weight) /
              weight
        : known.fold(0.0, (sum, mark) => sum + mark.score) / known.length;
  }
  final credits = number(course['credits'] ?? 1, 'Credits', min: .000001);
  if (current == null) {
    return PreparedCourse(null, {
      'name': name.trim(),
      'status': 'insufficient_data',
      'reason': 'At least one observed grade is required',
      'credits': credits,
    });
  }
  final complete = course['assessment_schedule_complete'] ?? false;
  if (complete is! bool) {
    throw const FormatException('Invalid assessment schedule.');
  }
  double? gradedFraction, overdueFraction;
  if (complete && plannedCount > 0) {
    gradedFraction = totalWeight > 0
        ? known.fold(0.0, (sum, mark) => sum + mark.weight) / totalWeight
        : known.length / plannedCount;
    overdueFraction = dueCount > 0 ? overdue / dueCount : 0;
  }
  double? previous, study, activities;
  if (course['previous_failures'] != null) {
    final failures = number(
      course['previous_failures'],
      'Previous failures',
      min: 0,
      max: 10,
    );
    if (failures != failures.roundToDouble()) {
      throw const FormatException('Previous failures must be a whole number.');
    }
    previous = math.min(failures, 4) / 4;
  }
  if (course['study_hours_per_week'] != null) {
    final hours = number(
      course['study_hours_per_week'],
      'Study hours',
      min: 0,
      max: 168,
    );
    study =
        (hours < 2
            ? 1
            : hours < 5
            ? 2
            : hours <= 10
            ? 3
            : 4) /
        4;
  }
  if (course['extracurricular_participation'] != null) {
    final activity = course['extracurricular_participation'];
    if (activity is! bool) {
      throw const FormatException('Invalid activities value.');
    }
    activities = activity ? 1 : 0;
  }
  final grades = known.isEmpty
      ? [current]
      : known.map((mark) => mark.score).toList();
  final recent = grades.skip(math.max(0, grades.length - 5)).toList();
  final mean = recent.reduce((a, b) => a + b) / recent.length;
  final std = math.sqrt(
    recent.fold(0.0, (sum, grade) => sum + math.pow(grade - mean, 2)) /
        recent.length,
  );
  final values = <double?>[
    current,
    grades.last,
    grades.length > 1 ? grades.last - grades[grades.length - 2] : null,
    grades.length > 1 ? std : null,
    progress,
    math.log(1 + grades.length),
    gradedFraction,
    overdueFraction,
    submittedCount > 0 ? lateCount / submittedCount : null,
    passing,
    previous,
    study,
    activities,
    education == 'university' ? 1 : 0,
  ];
  final focus = <Map<String, String>>[];
  if (current < passing) {
    focus.add({
      'observation': 'Current grade is below the passing threshold',
      'action':
          'Review the lowest-scoring work and the remaining assessment weights',
    });
  }
  if (complete && overdue > 0) {
    focus.add({
      'observation': '$overdue overdue assessments',
      'action':
          'Check which submissions can still receive credit and their deadlines',
    });
  }
  if (grades.length > 1 && grades.last < grades[grades.length - 2]) {
    focus.add({
      'observation': 'The latest assessment score declined',
      'action':
          'Review the assessed topic and ask for clarification where needed',
    });
  }
  return PreparedCourse(values, {
    'name': name.trim(),
    'status': 'predicted',
    'credits': credits,
    'current_grade_percent': current * 100,
    'passing_grade_percent': passing * 100,
    'term_progress': progress,
    'observed_assessments': known.length,
    'optional_fields_missing': [
      for (var i = 0; i < values.length; i++)
        if (values[i] == null) featureNames[i],
    ],
    'focus': focus,
    if (progress < .25 || progress > .75)
      'coverage_note':
          'This timing is outside the main assessment checkpoints used in evaluation',
  });
}

class _Layer {
  final List<List<double>> weight;
  final List<double> bias;
  _Layer(Map<String, dynamic> json)
    : weight = (json['weight'] as List)
          .map(
            (row) => (row as List).map((n) => (n as num).toDouble()).toList(),
          )
          .toList(),
      bias = (json['bias'] as List).map((n) => (n as num).toDouble()).toList();
  List<double> apply(List<double> input) => [
    for (var i = 0; i < bias.length; i++)
      bias[i] +
          List.generate(
            input.length,
            (j) => input[j] * weight[i][j],
          ).fold(0.0, (a, b) => a + b),
  ];
}

/// Executes the frozen PyTorch weights, preprocessing and calibration in Dart.
class RiskEngine {
  final List<double> median, mean, scale, calibration;
  final List<_Layer> _layers;
  final double marginStrength, threshold;
  final String scope, sourceHash;
  RiskEngine.fromJson(Map<String, dynamic> json)
    : median = _doubles(json['median']),
      mean = _doubles(json['mean']),
      scale = _doubles(json['scale']),
      calibration = _doubles(json['calibration']),
      _layers = (json['layers'] as List)
          .map((layer) => _Layer(Map<String, dynamic>.from(layer as Map)))
          .toList(),
      marginStrength = (json['margin_strength'] as num).toDouble(),
      threshold = (json['threshold'] as num).toDouble(),
      scope = json['scope'] as String,
      sourceHash = json['source_sha256'] as String {
    if (json['schema_version'] != 1 ||
        jsonEncode(json['features']) != jsonEncode(featureNames)) {
      throw const FormatException('Unsupported model schema.');
    }
  }
  static List<double> _doubles(dynamic list) =>
      (list as List).map((n) => (n as num).toDouble()).toList();
  static double _sigmoid(double value) => value >= 0
      ? 1 / (1 + math.exp(-value))
      : math.exp(value) / (1 + math.exp(value));
  double probability(List<double?> features) {
    if (features.length != featureNames.length ||
        features.any((v) => v != null && !v.isFinite)) {
      throw const FormatException('Invalid model features.');
    }
    final filled = [
      for (var i = 0; i < features.length; i++) features[i] ?? median[i],
    ];
    var values = [
      for (var i = 0; i < filled.length; i++) (filled[i] - mean[i]) / scale[i],
      ...features.map((value) => value == null ? 1.0 : 0.0),
    ];
    for (var i = 0; i < _layers.length; i++) {
      values = _layers[i].apply(values);
      if (i < _layers.length - 1) {
        values = values.map((value) => value * _sigmoid(value)).toList();
      }
    }
    final raw =
        values.single -
        math.log(1 + math.exp(marginStrength)) * (filled[0] - filled[9]);
    return _sigmoid(
      calibration[0] * raw + calibration[1] * filled.last + calibration[2],
    );
  }

  Map<String, dynamic> predictCourse(
    Map<String, dynamic> course,
    DateTime asOf, {
    String education = 'high_school',
  }) {
    final prepared = prepareCourse(course, asOf, education: education);
    final details = {...prepared.details, 'id': course['id'] ?? course['name']};
    if (prepared.features != null) {
      final p = probability(prepared.features!);
      details.addAll({
        'failure_probability': p,
        'risk_score': p * 100,
        'alert': p >= threshold,
      });
    }
    return details;
  }
}
