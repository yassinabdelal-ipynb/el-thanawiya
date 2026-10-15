"""Build shared checkpoint data without relabeling or inventing courses."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import numpy as np
import pandas as pd

from download_data import ROOT, ensure_sources, sha256
from features import snapshot_features
from model import FEATURES

MATCH_KEYS = ['school','sex','age','address','famsize','Pstatus','Medu','Fedu','Mjob','Fjob','reason','nursery','internet']


def school_rows(directory: Path):
    rows, audits = [], {}
    for subject, filename in [('Mathematics','student-mat.csv'), ('Portuguese','student-por.csv')]:
        path = directory / filename
        frame = pd.read_csv(path, sep=';')
        if frame.isna().any().any() or not frame[['G1','G2','G3']].apply(lambda s: s.between(0,20)).all().all():
            raise ValueError(f'Invalid school CSV: {path}')
        if frame.duplicated().any():
            raise ValueError('Duplicate school rows need manual investigation')
        audits[filename] = {'rows': len(frame), 'sha256': sha256(path), 'ambiguous_identity_rows': int(frame.duplicated(MATCH_KEYS, keep=False).sum())}
        for index, row in frame.iterrows():
            identity = json.dumps([str(row[key]) for key in MATCH_KEYS], separators=(',', ':'))
            group = 'school:' + hashlib.sha256(identity.encode()).hexdigest()[:24]
            for checkpoint, grades in [('first', [row.G1/20]), ('second', [row.G1/20,row.G2/20])]:
                values = snapshot_features(grades[-1], grades, 1/3 if checkpoint=='first' else 2/3, 0.5,
                    previous_failures=min(float(row.failures),4)/4, study_time=float(row.studytime)/4,
                    activities=float(row.activities=='yes'))
                rows.append({**values, 'group': group, 'source': 'school', 'subject': subject,
                    'course_record': f'{filename}:{index}', 'checkpoint': checkpoint,
                    'target': int(row.G3 < 10), 'cutoff_day': np.nan, 'max_score_available_day': np.nan})
    return rows, audits


def university_rows(raw: Path, score_lag_days=14):
    directory = raw / 'oulad'
    info = pd.read_csv(directory/'studentInfo.csv', na_values=['?'])
    courses = pd.read_csv(directory/'courses.csv', na_values=['?'])
    assessments = pd.read_csv(directory/'assessments.csv', na_values=['?'])
    records = pd.read_csv(directory/'studentAssessment.csv', na_values=['?'])
    for col in ['date_submitted','score','is_banked']:
        records[col] = pd.to_numeric(records[col], errors='coerce')
    assessments['date'] = pd.to_numeric(assessments['date'], errors='coerce')
    assessments['weight'] = pd.to_numeric(assessments['weight'], errors='coerce')
    scheduled = assessments[(assessments.assessment_type != 'Exam') & assessments.date.notna()].copy()
    submitted = records[(records.is_banked == 0) & records.date_submitted.notna()].merge(scheduled, on='id_assessment', validate='many_to_one')
    valid = submitted[submitted.score.between(0,100)].copy()
    valid['available_day'] = valid.date_submitted + score_lag_days
    keys = ['code_module','code_presentation']
    score_groups = {key: group.sort_values('available_day') for key, group in valid.groupby(keys+['id_student'])}
    submission_groups = {key: group for key, group in submitted.groupby(keys+['id_student'])}
    schedule_groups = {key: group for key, group in scheduled.groupby(keys)}
    info = info.merge(courses, on=keys, validate='many_to_one')
    graded = info[info.final_result.isin(['Fail','Pass','Distinction'])]
    rows, skipped_no_grade = [], 0
    for student in graded.itertuples(index=False):
        key = (student.code_module, student.code_presentation, student.id_student)
        schedule = schedule_groups.get(key[:2])
        scores = score_groups.get(key)
        submissions = submission_groups.get(key)
        if schedule is None:
            continue
        for fraction in [0.25,0.50,0.75]:
            cutoff = int(np.floor(student.module_presentation_length * fraction))
            known = scores[scores.available_day <= cutoff] if scores is not None else None
            if known is None or known.empty:
                skipped_no_grade += 1
                continue
            history = (known.score.to_numpy()/100).tolist()
            weights = known.weight.fillna(0).to_numpy()
            current = float(np.average(history,weights=weights)) if weights.sum()>0 else float(np.mean(history))
            total_weight = float(schedule.weight.fillna(0).sum())
            coverage = float(weights.sum()/total_weight) if total_weight>0 else len(known)/len(schedule)
            observed_submissions = submissions[submissions.date_submitted <= cutoff]
            due = schedule[schedule.date <= cutoff]
            completed_ids = set(observed_submissions.id_assessment)
            overdue = float((~due.id_assessment.isin(completed_ids)).mean()) if len(due) else 0.
            late = float((observed_submissions.date_submitted > observed_submissions.date).mean()) if len(observed_submissions) else None
            values = snapshot_features(current,history,fraction,0.4,university=1,
                graded_fraction=coverage,overdue_fraction=overdue,late_fraction=late)
            rows.append({**values,'group':f'oulad:{student.id_student}','source':'oulad',
                'subject':student.code_module,'course_record':f'{student.code_module}:{student.code_presentation}:{student.id_student}',
                'checkpoint':f'{fraction:.2f}', 'target':int(student.final_result=='Fail'),
                'cutoff_day':cutoff,'max_score_available_day':float(known.available_day.max())})
    return rows, {'enrollments_total':len(info),'graded_enrollments':len(graded),
        'withdrawn_excluded':int((info.final_result=='Withdrawn').sum()),
        'snapshots_without_grade_excluded':skipped_no_grade,'score_availability_lag_days':score_lag_days,
        'score_timing_assumption':'No actual grade-release dates exist. Submission+14 days is an explicit assumption, not verified availability.',
        'final_exams_excluded':True,'banked_assessments_excluded':True,
        'target':'Recorded Fail versus Pass/Distinction, among graded course completers; withdrawal is not modeled.'}


def main():
    raw = ensure_sources()
    school, school_audit = school_rows(raw/'school')
    university, university_audit = university_rows(raw)
    frame = pd.DataFrame(school+university)
    if not np.isfinite(frame[['current_grade','passing_grade','progress','university']].to_numpy()).all():
        raise ValueError('Required numerical features are invalid')
    if not frame.current_grade.between(0,1).all():
        raise ValueError('Normalized grades outside expected range')
    if not (frame.loc[frame.source=='oulad','max_score_available_day'] <= frame.loc[frame.source=='oulad','cutoff_day']).all():
        raise ValueError('A future assessment entered a snapshot')
    processed = ROOT/'data'/'processed'
    processed.mkdir(exist_ok=True)
    temporary=processed/'snapshots.csv.part'
    frame.to_csv(temporary,index=False)
    temporary.replace(processed/'snapshots.csv')
    extra = pd.read_csv(raw/'halabja-grades.csv')
    audit = {'features':FEATURES,'snapshot_rows':len(frame),'group_counts':frame.groupby('source').group.nunique().to_dict(),
        'by_source':frame.groupby('source').agg(rows=('target','size'),fail_rate=('target','mean')).to_dict(),
        'school':school_audit,'oulad':university_audit,
        'halabja':{'rows_observed':len(extra),'duplicate_student_year_rows':int(extra.duplicated(['Serial No','Years']).sum()),
            'used_for_training':False,'reason':'Annual end grades; absent within-term history; reuse policy and passing rules unverified.'},
        'school_timing':'G1/G2 are grading-period checkpoints. 1/3 and 2/3 are coarse progress proxies, not actual event dates.',
        'identity':'Conservative grouping on supplied matching keys may combine ambiguous school students; OULAD uses student IDs.',
        'sources':json.loads((raw/'sources.json').read_text()),
        'unsupported_features':['dated school absences','extracurricular hours','topic mastery','overall term failure']}
    (processed/'audit.json').write_text(json.dumps(audit,indent=2),encoding='utf-8')
    print(json.dumps({'rows':len(frame),'groups':audit['group_counts'],'sources':audit['by_source']},indent=2))


if __name__ == '__main__':
    main()
