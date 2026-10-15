import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/student_store.dart';
import '../domain/risk_engine.dart';
import 'design.dart';

class CourseFormPage extends StatefulWidget {
  final RiskEngine engine;
  final StudentStore store;
  final DateTime asOf;
  final Map<String, dynamic>? course;
  const CourseFormPage({
    super.key,
    required this.engine,
    required this.store,
    required this.asOf,
    this.course,
  });
  @override
  State<CourseFormPage> createState() => _CourseFormPageState();
}

class _CourseFormPageState extends State<CourseFormPage> {
  final fields = <String, TextEditingController>{};
  final formKey = GlobalKey<FormState>();
  late DateTime start, end, gradeDate;
  late List<Map<String, dynamic>> assessments;
  bool higher = true, complete = false, saving = false;
  bool? activities;
  String? error;
  @override
  void initState() {
    super.initState();
    final course = widget.course ?? <String, dynamic>{};
    final defaults = <String, dynamic>{
      'name': '',
      'current_grade': '',
      'grade_min': 0,
      'grade_max': 100,
      'passing_grade': 50,
      'credits': 1,
      'study_hours_per_week': '',
      'previous_failures': '',
    };
    for (final entry in defaults.entries) {
      fields[entry.key] = TextEditingController(
        text: (course[entry.key] ?? entry.value).toString(),
      );
    }
    final year = widget.asOf.year;
    start = course['term_start'] != null
        ? parseDay(course['term_start'], 'term start')
        : DateTime.utc(year, widget.asOf.month < 7 ? 1 : 9, 1);
    if (start.isAfter(widget.asOf)) start = DateTime.utc(year, 7, 1);
    end = course['term_end'] != null
        ? parseDay(course['term_end'], 'term end')
        : DateTime.utc(
            widget.asOf.month < 7 ? year : year + 1,
            widget.asOf.month < 7 ? 7 : 1,
            1,
          );
    gradeDate = course['current_grade_available_on'] != null
        ? parseDay(course['current_grade_available_on'], 'grade date')
        : widget.asOf;
    higher = course['higher_is_better'] as bool? ?? true;
    complete = course['assessment_schedule_complete'] as bool? ?? false;
    activities = course['extracurricular_participation'] as bool?;
    assessments =
        ((jsonDecode(jsonEncode(course['assessments'] ?? []))) as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  double? _value(String key) {
    final text = fields[key]!.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null || !value.isFinite) {
      throw const FormatException('Enter valid numbers.');
    }
    return value;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final current = _value('current_grade');
      final course = <String, dynamic>{
        'id':
            widget.course?['id'] ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        'name': fields['name']!.text.trim(),
        'term_start': dateKey(start),
        'term_end': dateKey(end),
        'grade_min': _value('grade_min'),
        'grade_max': _value('grade_max'),
        'passing_grade': _value('passing_grade'),
        'higher_is_better': higher,
        'credits': _value('credits'),
        'assessment_schedule_complete': complete,
        'assessments': assessments,
        'current_grade': ?current,
        if (current != null) 'current_grade_available_on': dateKey(gradeDate),
        if (_value('study_hours_per_week') != null)
          'study_hours_per_week': _value('study_hours_per_week'),
        if (_value('previous_failures') != null)
          'previous_failures': _value('previous_failures'),
        'extracurricular_participation': ?activities,
      };
      normalized(
        course['passing_grade'],
        course['grade_min'],
        course['grade_max'],
        higher,
      );
      number(course['credits'], 'Credits', min: .000001);
      if (course['study_hours_per_week'] != null) {
        number(course['study_hours_per_week'], 'Study hours', min: 0, max: 168);
      }
      if (course['previous_failures'] != null) {
        final value = number(
          course['previous_failures'],
          'Previous failures',
          min: 0,
          max: 10,
        );
        if (value != value.roundToDouble()) {
          throw const FormatException(
            'Previous failures must be a whole number.',
          );
        }
      }
      for (final record in assessments) {
        if (record['score'] != null) {
          normalized(
            record['score'],
            course['grade_min'],
            course['grade_max'],
            higher,
          );
        }
      }
      prepareCourse(course, widget.asOf);
      await widget.store.save(course);
      if (mounted) {
        setState(() => saving = false);
        Navigator.pop(context);
      }
    } on FormatException catch (problem) {
      if (mounted) {
        setState(() {
          error = problem.message;
          saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not save. Please try again.';
          saving = false;
        });
      }
    }
  }

  Future<void> _mark([int? index]) async {
    double minimum, maximum;
    try {
      minimum = _value('grade_min') ?? 0;
      maximum = _value('grade_max') ?? 100;
      normalized(minimum, minimum, maximum, true);
    } on FormatException catch (problem) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem.message)));
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.of(context).canvas,
      showDragHandle: true,
      builder: (context) => AssessmentSheet(
        asOf: widget.asOf,
        start: start,
        end: end,
        minimum: minimum,
        maximum: maximum,
        record: index == null ? null : assessments[index],
        count: assessments.length,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          assessments.add(result);
        } else {
          assessments[index] = result;
        }
      });
    }
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    bool text = false,
  }) => TextFormField(
    key: ValueKey(key),
    controller: fields[key],
    maxLength: text ? 80 : null,
    decoration: InputDecoration(labelText: label, counterText: ''),
    keyboardType: text
        ? TextInputType.text
        : const TextInputType.numberWithOptions(decimal: true, signed: true),
    textCapitalization: text
        ? TextCapitalization.words
        : TextCapitalization.none,
    inputFormatters: text
        ? []
        : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
    validator: (value) {
      if (required && (value == null || value.trim().isEmpty)) {
        return 'Required';
      }
      if (!text &&
          value != null &&
          value.isNotEmpty &&
          double.tryParse(value.replaceAll(',', '.')) == null) {
        return 'Invalid number';
      }
      return null;
    },
  );
  @override
  Widget build(BuildContext context) => Form(
    key: formKey,
    child: PopScope(
      canPop: !saving,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
                      children: [
                        PageHeader(
                          title: widget.course == null
                              ? 'Add course'
                              : 'Edit course',
                        ),
                        _field(
                          'name',
                          'Course name',
                          required: true,
                          text: true,
                        ),
                        const SizedBox(height: 24),
                        _field('current_grade', 'Current grade'),
                        const SizedBox(height: 14),
                        DateField(
                          label: 'Grade recorded',
                          value: gradeDate,
                          onChanged: (value) =>
                              setState(() => gradeDate = value),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'Grading',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _field(
                                'grade_min',
                                'Minimum',
                                required: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _field(
                                'grade_max',
                                'Maximum',
                                required: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _field(
                                'passing_grade',
                                'Passing grade',
                                required: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _field(
                                'credits',
                                'Credits',
                                required: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        DirectionSelector(
                          higher: higher,
                          onChanged: (value) => setState(() => higher = value),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: DateField(
                                label: 'Term starts',
                                value: start,
                                onChanged: (value) =>
                                    setState(() => start = value),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DateField(
                                label: 'Term ends',
                                value: end,
                                onChanged: (value) =>
                                    setState(() => end = value),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Assessments',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            SoftButton(
                              label: 'Add assessment',
                              onPressed: _mark,
                              child: const Icon(Icons.add_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        for (var i = 0; i < assessments.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SoftPanel(
                              inset: true,
                              radius: 18,
                              padding: const EdgeInsets.fromLTRB(15, 6, 4, 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => _mark(i),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        child: Text(
                                          '${assessments[i]['label'] ?? 'Assessment ${i + 1}'}  ·  ${assessments[i]['score'] == null ? 'Pending' : numeric(assessments[i]['score'] as num)}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove assessment',
                                    onPressed: () =>
                                        setState(() => assessments.removeAt(i)),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          activeTrackColor: Palette.of(context).sage,
                          title: const Text(
                            'Full term schedule',
                            style: TextStyle(fontSize: 13),
                          ),
                          secondary: Tooltip(
                            message:
                                'Enable only after entering every assessment for the term. This lets the model calculate coverage and overdue work.',
                            child: Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: Palette.of(context).muted,
                            ),
                          ),
                          value: complete,
                          onChanged: (value) =>
                              setState(() => complete = value),
                        ),
                        const SizedBox(height: 12),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(top: 12),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          title: const Text(
                            'Optional inputs',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _field(
                                    'study_hours_per_week',
                                    'Study hours / week',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _field(
                                    'previous_failures',
                                    'Past failures',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Extracurricular activities',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Palette.of(context).muted,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                for (final choice in <bool?>[null, false, true])
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(
                                          choice == null
                                              ? 'Unknown'
                                              : choice
                                              ? 'Yes'
                                              : 'No',
                                        ),
                                        selected: activities == choice,
                                        showCheckmark: false,
                                        onSelected: (_) =>
                                            setState(() => activities = choice),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Palette.of(context).clay,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 8, 26, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: SoftButton(
                        filled: true,
                        onPressed: saving ? null : _save,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Text(saving ? 'Saving…' : 'Save course'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class DirectionSelector extends StatelessWidget {
  final bool higher;
  final ValueChanged<bool> onChanged;
  const DirectionSelector({
    super.key,
    required this.higher,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SoftPanel(
    inset: true,
    radius: 18,
    padding: const EdgeInsets.all(5),
    child: Row(
      children: [
        for (final choice in [true, false])
          Expanded(
            child: Material(
              color: choice == higher
                  ? Palette.of(context).ink
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                onTap: () => onChanged(choice),
                borderRadius: BorderRadius.circular(13),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Text(
                    choice ? 'Higher is better' : 'Lower is better',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: choice == higher
                          ? Palette.of(context).canvas
                          : Palette.of(context).muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(17),
    onTap: () async {
      final selected = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (selected != null) onChanged(calendarDay(selected));
    },
    child: InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(
            child: Text(dateKey(value), style: const TextStyle(fontSize: 12)),
          ),
          Icon(
            Icons.calendar_today_outlined,
            size: 15,
            color: Palette.of(context).muted,
          ),
        ],
      ),
    ),
  );
}

class AssessmentSheet extends StatefulWidget {
  final Map<String, dynamic>? record;
  final DateTime asOf, start, end;
  final double minimum, maximum;
  final int count;
  const AssessmentSheet({
    super.key,
    this.record,
    required this.asOf,
    required this.start,
    required this.end,
    required this.minimum,
    required this.maximum,
    required this.count,
  });
  @override
  State<AssessmentSheet> createState() => _AssessmentSheetState();
}

class _AssessmentSheetState extends State<AssessmentSheet> {
  late TextEditingController label, score, weight;
  late DateTime due, available, submission;
  bool submitted = true;
  String? error;
  @override
  void initState() {
    super.initState();
    final record = widget.record ?? {};
    label = TextEditingController(
      text: record['label'] as String? ?? 'Assessment ${widget.count + 1}',
    );
    score = TextEditingController(text: (record['score'] ?? '').toString());
    weight = TextEditingController(text: (record['weight'] ?? 1).toString());
    due = record['due_date'] == null
        ? widget.asOf
        : parseDay(record['due_date'], 'due date');
    available = record['available_on'] == null
        ? widget.asOf
        : parseDay(record['available_on'], 'grade date');
    submission = record['submitted_on'] == null
        ? widget.asOf
        : parseDay(record['submitted_on'], 'submission');
    submitted = widget.record == null || record['submitted_on'] != null;
  }

  @override
  void dispose() {
    label.dispose();
    score.dispose();
    weight.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final value = score.text.trim().isEmpty
          ? null
          : double.tryParse(score.text.replaceAll(',', '.'));
      if (score.text.trim().isNotEmpty && value == null) {
        throw const FormatException('Enter a valid score.');
      }
      if (value != null) {
        number(value, 'Score', min: widget.minimum, max: widget.maximum);
      }
      final markWeight = number(
        double.tryParse(weight.text.replaceAll(',', '.')),
        'Weight',
        min: 0,
      );
      if (due.isBefore(widget.start) || due.isAfter(widget.end)) {
        throw const FormatException('Due date must belong to this term.');
      }
      if (submitted && submission.isBefore(widget.start)) {
        throw const FormatException('Submission must follow term start.');
      }
      if (value != null &&
          (available.isBefore(widget.start) ||
              (submitted && available.isBefore(submission)))) {
        throw const FormatException(
          'Grade date must follow submission and term start.',
        );
      }
      Navigator.pop(context, <String, dynamic>{
        'label': label.text.trim().isEmpty
            ? 'Assessment ${widget.count + 1}'
            : label.text.trim(),
        'type': 'assessment',
        'due_date': dateKey(due),
        'weight': markWeight,
        if (submitted) 'submitted_on': dateKey(submission),
        'score': ?value,
        if (value != null) 'available_on': dateKey(available),
      });
    } on FormatException catch (problem) {
      setState(() => error = problem.message);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        26,
        4,
        26,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assessment',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('assessment_label'),
              controller: label,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Name',
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('assessment_score'),
                    controller: score,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Score (optional)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: weight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Weight'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DateField(
              label: 'Due date',
              value: due,
              onChanged: (value) => setState(() => due = value),
            ),
            const SizedBox(height: 14),
            DateField(
              label: 'Grade available',
              value: available,
              onChanged: (value) => setState(() => available = value),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: submitted,
              activeTrackColor: Palette.of(context).sage,
              title: const Text('Submitted', style: TextStyle(fontSize: 13)),
              onChanged: (value) => setState(() => submitted = value),
            ),
            if (submitted)
              DateField(
                label: 'Submission date',
                value: submission,
                onChanged: (value) => setState(() => submission = value),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Palette.of(context).clay),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: SoftButton(
                filled: true,
                onPressed: _save,
                child: const Center(child: Text('Save assessment')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
