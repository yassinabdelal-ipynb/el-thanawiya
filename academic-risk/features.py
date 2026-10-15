"""Shared numerical feature definitions and strict app-input validation."""
from __future__ import annotations

from datetime import date
import math
import numpy as np

from model import FEATURES


def number(value, name, low=None, high=None):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f'{name} must be a finite number')
    if low is not None and value < low or high is not None and value > high:
        raise ValueError(f'{name} must be between {low} and {high}')
    return float(value)


def parse_date(value, name):
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError):
        raise ValueError(f'{name} must be a date in YYYY-MM-DD format') from None


def normalize_grade(value, minimum, maximum, higher_is_better=True):
    if not isinstance(higher_is_better, bool):
        raise ValueError('higher_is_better must be true or false')
    low = number(minimum, 'grade_min')
    high = number(maximum, 'grade_max')
    if high <= low:
        raise ValueError('grade_max must exceed grade_min')
    grade = number(value, 'grade', low, high)
    result = (grade - low) / (high - low)
    return result if higher_is_better else 1 - result


def snapshot_features(current, history, progress, passing, university=0,
                      graded_fraction=None, overdue_fraction=None, late_fraction=None,
                      previous_failures=None, study_time=None, activities=None):
    grades = np.asarray(history, dtype=float)
    if not len(grades):
        grades = np.array([current], dtype=float)
    values = {
        'current_grade': float(current), 'latest_grade': float(grades[-1]),
        'grade_trend': float(grades[-1] - grades[-2]) if len(grades) > 1 else np.nan,
        'grade_std': float(np.std(grades[-5:])) if len(grades) > 1 else np.nan,
        'progress': float(progress), 'assessment_count': float(np.log1p(len(grades))),
        'graded_fraction': graded_fraction, 'overdue_fraction': overdue_fraction,
        'late_fraction': late_fraction, 'passing_grade': float(passing),
        'previous_failures': previous_failures, 'study_time': study_time,
        'activities': activities, 'university': float(university),
    }
    return {name: np.nan if values[name] is None else float(values[name]) for name in FEATURES}


def course_features(course: dict, as_of: date, education_level='high_school'):
    if not isinstance(course, dict):
        raise ValueError('Each course must be a JSON object')
    name = course.get('name')
    if not isinstance(name, str) or not name.strip():
        raise ValueError('Every course needs a nonempty name')
    if education_level not in {'high_school', 'university'}:
        raise ValueError('education_level must be high_school or university')
    start, end = parse_date(course.get('term_start'), 'term_start'), parse_date(course.get('term_end'), 'term_end')
    if end <= start or not start <= as_of < end:
        raise ValueError('Prediction date must be within an ongoing term with term_end after term_start')
    low, high = course.get('grade_min', 0), course.get('grade_max', 100)
    direction = course.get('higher_is_better', True)
    passing = normalize_grade(course.get('passing_grade'), low, high, direction)
    progress = (as_of - start).days / (end - start).days
    assessments = course.get('assessments', [])
    if not isinstance(assessments, list):
        raise ValueError('assessments must be a list')
    known, planned, submitted, overdue = [], [], [], []
    for record in assessments:
        if not isinstance(record, dict):
            raise ValueError('Every assessment must be an object')
        kind=record.get('type','assessment')
        if kind not in {'assessment','period','final_exam'}:
            raise ValueError('Assessment type must be assessment, period, or final_exam')
        if kind == 'final_exam':
            # The source model deliberately excludes final exams at training cutoffs.
            continue
        due = parse_date(record.get('due_date'), 'due_date')
        if not start <= due <= end:
            raise ValueError('Assessment due_date must belong to this term')
        weight = number(record.get('weight', 1), 'assessment weight', 0)
        planned.append((due, weight))
        submission = parse_date(record['submitted_on'], 'submitted_on') if record.get('submitted_on') else None
        if submission and submission < start:
            raise ValueError('submitted_on must not precede this term')
        if due <= as_of and (submission is None or submission > as_of):
            overdue.append((due, weight))
        if submission and submission <= as_of:
            submitted.append((due, submission, weight))
        if record.get('score') is not None:
            available = parse_date(record.get('available_on'), 'available_on')
            if available < start or submission and available < submission:
                raise ValueError('Score availability must follow term start and submission')
            if available <= as_of:
                score = normalize_grade(record['score'], record.get('grade_min', low), record.get('grade_max', high), record.get('higher_is_better', direction))
                known.append((available, score, weight))
    known.sort(key=lambda value: value[0])
    history = [item[1] for item in known]
    current = course.get('current_grade')
    if current is not None:
        available = parse_date(course.get('current_grade_available_on'), 'current_grade_available_on')
        if not start <= available <= as_of:
            raise ValueError('current_grade must have been available by the prediction date')
        current = normalize_grade(current, low, high, direction)
    elif known:
        weights = np.asarray([item[2] for item in known])
        current = float(np.average(history, weights=weights)) if weights.sum() > 0 else float(np.mean(history))
    else:
        return None, {'name': name.strip(), 'status': 'insufficient_data', 'reason': 'At least one observed grade is required', 'credits': number(course.get('credits', 1), 'credits', 0.000001)}
    # Completeness is only computable if caller explicitly supplied the entire schedule.
    complete_schedule = course.get('assessment_schedule_complete', False)
    if not isinstance(complete_schedule, bool):
        raise ValueError('assessment_schedule_complete must be true or false')
    graded_fraction = overdue_fraction = None
    if complete_schedule and planned:
        total_weight = sum(w for _, w in planned)
        graded_fraction = sum(w for _, _, w in known) / total_weight if total_weight > 0 else len(known) / len(planned)
        due_count = sum(due <= as_of for due, _ in planned)
        overdue_fraction = len(overdue) / due_count if due_count else 0.
    late_fraction = sum(submission > due for due, submission, _ in submitted) / len(submitted) if submitted else None
    previous = course.get('previous_failures')
    if previous is not None:
        previous = number(previous, 'previous_failures', 0, 10)
        if previous != int(previous):
            raise ValueError('previous_failures must be an integer')
        previous = min(previous, 4) / 4
    study = course.get('study_hours_per_week')
    if study is not None:
        study = number(study, 'study_hours_per_week', 0, 168)
        study = (1 if study < 2 else 2 if study < 5 else 3 if study <= 10 else 4) / 4
    activity = course.get('extracurricular_participation')
    if activity is not None and not isinstance(activity, bool):
        raise ValueError('extracurricular_participation must be true or false')
    features = snapshot_features(current, history, progress, passing,
        university=int(education_level == 'university'), graded_fraction=graded_fraction,
        overdue_fraction=overdue_fraction, late_fraction=late_fraction,
        previous_failures=previous, study_time=study,
        activities=float(activity) if activity is not None else None)
    details = {'name': name.strip(), 'status': 'predicted', 'credits': number(course.get('credits', 1), 'credits', 0.000001),
        'current_grade_percent': round(current * 100, 2), 'passing_grade_percent': round(passing * 100, 2),
        'term_progress': round(progress, 3), 'observed_assessments': len(known),
        'optional_fields_missing': [key for key, value in features.items() if np.isnan(value)],
        'focus': []}
    if current < passing:
        details['focus'].append({'observation': 'Current grade is below the passing threshold', 'action': 'Review the lowest-scoring work and the remaining assessment weights'})
    if complete_schedule and overdue:
        details['focus'].append({'observation': f'{len(overdue)} overdue assessments', 'action': 'Check which submissions can still receive credit and their deadlines'})
    if len(history) > 1 and history[-1] < history[-2]:
        details['focus'].append({'observation': 'The latest assessment score declined', 'action': 'Review the assessed topic and ask for clarification where needed'})
    if progress < 0.25 or progress > 0.75:
        details['coverage_note'] = 'This timing is outside the main assessment checkpoints used in evaluation'
    return features, details
