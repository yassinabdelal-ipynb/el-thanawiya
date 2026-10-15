import 'package:flutter/material.dart';
import '../data/student_store.dart';
import '../domain/risk_engine.dart';
import 'design.dart';
import 'course_form.dart';

class CourseDetailPage extends StatelessWidget {
  final RiskEngine engine;
  final StudentStore store;
  final String courseId;
  final DateTime asOf;
  const CourseDetailPage({
    super.key,
    required this.engine,
    required this.store,
    required this.courseId,
    required this.asOf,
  });
  Future<void> _remove(BuildContext context, String name) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.of(context).canvas,
        title: Text('Remove $name?'),
        content: const Text('Its grades will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    try {
      await store.remove(courseId);
      if (context.mounted) Navigator.pop(context);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove the course. Try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final matches = store.courses.where((course) => course['id'] == courseId);
      if (matches.isEmpty) return const Scaffold(body: SizedBox.shrink());
      final course = matches.first;
      Map<String, dynamic> result;
      try {
        result = engine.predictCourse(course, asOf);
      } on FormatException catch (error) {
        result = {'status': 'unavailable', 'reason': error.message};
      }
      final score = (result['risk_score'] as num?)?.toDouble();
      final focus = (result['focus'] as List?) ?? [];
      final marks =
          ((course['assessments'] ?? []) as List)
              .where(
                (mark) =>
                    mark['type'] != 'final_exam' &&
                    mark['score'] != null &&
                    !parseDay(mark['available_on'], 'grade date').isAfter(asOf),
              )
              .toList()
            ..sort(
              (a, b) => (a['available_on'] as String).compareTo(
                b['available_on'] as String,
              ),
            );
      final current = rawCurrentGrade(course, result);
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 32),
                children: [
                  PageHeader(
                    title: course['name'] as String,
                    trailing: SoftButton(
                      label: 'Edit course',
                      onPressed: () => Navigator.push(
                        context,
                        softRoute(
                          CourseFormPage(
                            engine: engine,
                            store: store,
                            asOf: asOf,
                            course: course,
                          ),
                        ),
                      ),
                      child: const Icon(Icons.edit_outlined),
                    ),
                  ),
                  Center(
                    child: Text(
                      'Course risk',
                      style: TextStyle(
                        fontSize: 13,
                        color: Palette.of(context).muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: RiskDial(
                      score: score,
                      alert: result['alert'] == true,
                      size: 224,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      score == null
                          ? 'Pending'
                          : result['alert'] == true
                          ? 'Needs attention'
                          : 'Lower risk',
                      style: TextStyle(
                        color: result['alert'] == true
                            ? Palette.of(context).clay
                            : Palette.of(context).sage,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          label: 'Current grade',
                          value: current != null
                              ? numeric(current)
                              : result['current_grade_percent'] != null
                              ? '${numeric(result['current_grade_percent'] as num)}%'
                              : '—',
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _Metric(
                          label: 'Passing grade',
                          value: numeric(course['passing_grade'] as num),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  if (score == null)
                    SoftPanel(
                      inset: true,
                      child: Text(
                        result['status'] == 'insufficient_data'
                            ? 'Add a current grade or a graded assessment.'
                            : result['reason'] as String,
                        style: const TextStyle(fontSize: 13, height: 1.6),
                      ),
                    ),
                  if (focus.isNotEmpty) ...[
                    const Text(
                      'Focus',
                      style: TextStyle(
                        fontSize: 20,
                        letterSpacing: -.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    for (var i = 0; i < focus.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 15),
                        child: SoftPanel(
                          inset: true,
                          padding: const EdgeInsets.all(18),
                          radius: 20,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (i + 1).toString().padLeft(2, '0'),
                                style: TextStyle(
                                  color: Palette.of(context).sage,
                                  fontSize: 12,
                                  height: 1.7,
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      focus[i]['observation'] as String,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      focus[i]['action'] as String,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.7,
                                        color: Palette.of(context).muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Grades',
                          style: TextStyle(
                            fontSize: 20,
                            letterSpacing: -.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${marks.length} recorded',
                        style: TextStyle(
                          fontSize: 11,
                          color: Palette.of(context).muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (marks.length > 1) ...[
                    SoftPanel(
                      child: SizedBox(
                        height: 120,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _HistoryPainter(
                            marks: marks,
                            course: course,
                            palette: Palette.of(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (marks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No assessments recorded.',
                        style: TextStyle(
                          color: Palette.of(context).muted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  for (var i = marks.length - 1; i >= 0; i--)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Palette.of(context).line,
                            width: .8,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  marks[i]['label'] as String? ??
                                      'Assessment ${i + 1}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  marks[i]['available_on'] as String,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Palette.of(context).muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            numeric(marks[i]['score'] as num),
                            style: const TextStyle(
                              fontSize: 22,
                              letterSpacing: -.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (result['coverage_note'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text(
                        result['coverage_note'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          color: Palette.of(context).muted,
                          height: 1.6,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed: () =>
                          _remove(context, course['name'] as String),
                      child: Text(
                        'Remove course',
                        style: TextStyle(
                          color: Palette.of(context).muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _Metric extends StatelessWidget {
  final String label, value;
  const _Metric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => SoftPanel(
    radius: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Palette.of(context).muted),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            letterSpacing: -1,
          ),
        ),
      ],
    ),
  );
}

class _HistoryPainter extends CustomPainter {
  final List<dynamic> marks;
  final Map<String, dynamic> course;
  final Palette palette;
  const _HistoryPainter({
    required this.marks,
    required this.course,
    required this.palette,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final recent = marks.skip(marks.length > 6 ? marks.length - 6 : 0).toList();
    final passing = normalized(
      course['passing_grade'],
      course['grade_min'] ?? 0,
      course['grade_max'] ?? 100,
      course['higher_is_better'] ?? true,
    );
    final plotHeight = size.height - 30;
    final passY = 15 + (1 - passing) * (plotHeight - 25);
    final dash = Paint()
      ..color = palette.line
      ..strokeWidth = 1;
    for (var x = 4.0; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, passY), Offset(x + 4, passY), dash);
    }
    final points = <Offset>[];
    for (var i = 0; i < recent.length; i++) {
      final mark = recent[i] as Map;
      final quality = normalized(
        mark['score'],
        mark['grade_min'] ?? course['grade_min'] ?? 0,
        mark['grade_max'] ?? course['grade_max'] ?? 100,
        mark['higher_is_better'] ?? course['higher_is_better'] ?? true,
      );
      points.add(
        Offset(
          12 + i / (recent.length - 1) * (size.width - 24),
          15 + (1 - quality) * (plotHeight - 25),
        ),
      );
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = palette.sage
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 5, Paint()..color = palette.canvas);
      canvas.drawCircle(points[i], 3, Paint()..color = palette.sage);
      final label = TextPainter(
        text: TextSpan(
          text: numeric(recent[i]['score'] as num),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 10,
            color: palette.muted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          (points[i].dx - label.width / 2).clamp(0, size.width - label.width),
          size.height - 15,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_HistoryPainter oldDelegate) => true;
}
