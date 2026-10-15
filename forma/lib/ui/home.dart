import 'package:flutter/material.dart';
import '../data/student_store.dart';
import '../domain/risk_engine.dart';
import 'design.dart';
import 'course_detail.dart';
import 'course_form.dart';
import 'night_button.dart';

class HomePage extends StatefulWidget {
  final RiskEngine engine;
  final StudentStore store;
  const HomePage({super.key, required this.engine, required this.store});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  DateTime get today => widget.store.demo
      ? DateTime.utc(2026, 10, 7)
      : calendarDay(DateTime.now());
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() {});
  }

  void _about() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Palette.of(context).canvas,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'About El-Thanawiya',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              const Text(
                'Course risk is an estimate of failing a course. Term priority is the credit-weighted average of available course risks, not the chance of failing the whole term.',
                style: TextStyle(height: 1.7, fontSize: 14),
              ),
              const SizedBox(height: 14),
              const Text(
                'The research model was evaluated on historical Mathematics and Portuguese courses and university modules. Its accuracy on other high-school subjects has not been established.',
                style: TextStyle(height: 1.7, fontSize: 14),
              ),
              const SizedBox(height: 14),
              const Text(
                'Your profile and grades stay on this device. Predictions work offline. There are no accounts, ads, or analytics.',
                style: TextStyle(height: 1.7, fontSize: 14),
              ),
              if (widget.store.demo)
                const Padding(
                  padding: EdgeInsets.only(top: 18),
                  child: Text('Sample data · preview only'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final courses = widget.store.courses;
      final results = <Map<String, dynamic>>[];
      for (final course in courses) {
        try {
          results.add(widget.engine.predictCourse(course, today));
        } on FormatException catch (error) {
          results.add({
            'id': course['id'],
            'name': course['name'],
            'status': 'unavailable',
            'reason': error.message,
          });
        }
      }
      final predicted = results
          .where((r) => r['status'] == 'predicted')
          .toList();
      final credits = predicted.fold(
        0.0,
        (sum, r) => sum + (r['credits'] as num),
      );
      final priority = credits > 0
          ? predicted.fold(
                  0.0,
                  (sum, r) =>
                      sum + (r['credits'] as num) * (r['risk_score'] as num),
                ) /
                credits
          : null;
      final anyAlert = predicted.any((r) => r['alert'] == true);
      final sorted = List<int>.generate(courses.length, (i) => i)
        ..sort(
          (a, b) => ((results[b]['risk_score'] ?? -1) as num).compareTo(
            (results[a]['risk_score'] ?? -1) as num,
          ),
        );
      final day = today;
      final months = [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC',
      ];
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(26, 24, 26, 120),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Hi, ${widget.store.profile!.name}',
                              key: const ValueKey('student_greeting'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 25,
                                letterSpacing: -.9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (MediaQuery.sizeOf(context).width >= 500 &&
                              MediaQuery.textScalerOf(context).scale(1) < 1.3)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(
                                '${months[day.month - 1]} ${day.day}',
                                style: TextStyle(
                                  color: Palette.of(context).muted,
                                  fontSize: 11,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                          NightButton(store: widget.store),
                          const SizedBox(width: 10),
                          SoftButton(
                            label: 'About El-Thanawiya',
                            onPressed: _about,
                            child: const Icon(Icons.more_horiz_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: Text(
                          'Term priority',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .3,
                            color: Palette.of(context).muted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: RiskDial(score: priority, alert: anyAlert),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: SoftPanel(
                          inset: true,
                          radius: 30,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            courses.isEmpty
                                ? 'No courses yet'
                                : '${predicted.length} of ${courses.length} courses',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Palette.of(context).muted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 38),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Courses',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.5,
                              ),
                            ),
                          ),
                          if (courses.isNotEmpty)
                            Text(
                              '${courses.length.toString().padLeft(2, '0')} total',
                              style: TextStyle(
                                fontSize: 11,
                                color: Palette.of(context).muted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      if (courses.isEmpty)
                        SoftPanel(
                          child: Column(
                            children: [
                              Icon(
                                Icons.menu_book_rounded,
                                color: Palette.of(context).sage,
                                size: 32,
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Start with one course.',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Add its current grade to see your risk.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Palette.of(context).muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (final i in sorted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: CourseCard(
                            course: courses[i],
                            result: results[i],
                            onTap: () => Navigator.push(
                              context,
                              softRoute(
                                CourseDetailPage(
                                  engine: widget.engine,
                                  store: widget.store,
                                  courseId: courses[i]['id'] as String,
                                  asOf: today,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Positioned(
                    left: 26,
                    right: 26,
                    bottom: 20,
                    child: SoftButton(
                      filled: true,
                      onPressed: () => Navigator.push(
                        context,
                        softRoute(
                          CourseFormPage(
                            engine: widget.engine,
                            store: widget.store,
                            asOf: today,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 19,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, size: 22),
                          SizedBox(width: 9),
                          Flexible(child: Text('Add course')),
                        ],
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

class CourseCard extends StatelessWidget {
  final Map<String, dynamic> course, result;
  final VoidCallback onTap;
  const CourseCard({
    super.key,
    required this.course,
    required this.result,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final score = (result['risk_score'] as num?)?.toDouble();
    final alert = result['alert'] == true;
    final grade = rawCurrentGrade(course, result);
    final gradeText = grade != null
        ? '${numeric(grade)} / ${numeric((course['grade_max'] ?? 100) as num)}'
        : result['status'] == 'predicted'
        ? '${numeric(result['current_grade_percent'] as num)}%'
        : '—';
    return Semantics(
      button: true,
      label:
          '${course['name']}, ${score == null ? 'no risk available' : 'risk ${score.toStringAsFixed(1)} percent'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(25),
          child: SoftPanel(
            padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 21),
            child: Row(
              children: [
                SoftPanel(
                  inset: true,
                  radius: 16,
                  padding: const EdgeInsets.all(13),
                  child: Text(
                    (course['name'] as String).substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Palette.of(context).sage,
                    ),
                  ),
                ),
                const SizedBox(width: 17),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course['name'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.4,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        score == null
                            ? result['status'] == 'insufficient_data'
                                  ? 'Add a grade'
                                  : 'Check term dates'
                            : 'Grade  $gradeText',
                        style: TextStyle(
                          fontSize: 11,
                          color: Palette.of(context).muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      riskText(score),
                      style: TextStyle(
                        fontSize: 25,
                        letterSpacing: -1,
                        fontWeight: FontWeight.w500,
                        color: alert
                            ? Palette.of(context).clay
                            : Palette.of(context).ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      score == null
                          ? 'Pending'
                          : alert
                          ? 'At risk'
                          : 'Lower risk',
                      style: TextStyle(
                        fontSize: 10,
                        color: alert
                            ? Palette.of(context).clay
                            : Palette.of(context).muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
