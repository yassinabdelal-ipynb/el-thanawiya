import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class StudentProfile {
  final String name, grade;
  final int age;
  const StudentProfile({
    required this.name,
    required this.grade,
    required this.age,
  });
  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    final name = json['name'], grade = json['grade'], age = json['age'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > 60 ||
        grade is! String ||
        grade.trim().isEmpty ||
        grade.length > 40 ||
        age is! int ||
        age < 1 ||
        age > 120) {
      throw const FormatException(
        'Enter a name, school grade, and a valid age.',
      );
    }
    return StudentProfile(
      name: name.trim().replaceAll(RegExp(r'\s+'), ' '),
      grade: grade.trim(),
      age: age,
    );
  }
  Map<String, dynamic> toJson() => {'name': name, 'grade': grade, 'age': age};
}

class StudentStore extends ChangeNotifier {
  final SharedPreferences? _preferences;
  List<Map<String, dynamic>> _courses;
  final bool demo;
  StudentProfile? _profile;
  bool _darkMode;
  bool _appearanceSaving = false;
  StudentStore._(
    this._preferences,
    this._courses, {
    this.demo = false,
    StudentProfile? profile,
    bool darkMode = false,
  }) : _profile = profile,
       _darkMode = darkMode;
  factory StudentStore.memory({
    List<Map<String, dynamic>> courses = const [],
    bool demo = false,
    StudentProfile? profile,
    bool darkMode = false,
  }) => StudentStore._(
    null,
    List.of(courses),
    demo: demo,
    profile: profile,
    darkMode: darkMode,
  );
  static Future<StudentStore> open() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('courses_v1');
    final courses = saved == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(saved) as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
    final savedProfile = preferences.getString('profile_v1');
    final profile = savedProfile == null
        ? null
        : StudentProfile.fromJson(
            Map<String, dynamic>.from(jsonDecode(savedProfile) as Map),
          );
    return StudentStore._(
      preferences,
      courses,
      profile: profile,
      darkMode: preferences.getBool('dark_mode_v1') ?? false,
    );
  }

  StudentProfile? get profile => _profile;
  bool get darkMode => _darkMode;
  Future<void> saveProfile(StudentProfile value) async {
    final validated = StudentProfile.fromJson(value.toJson());
    if (_preferences != null &&
        !await _preferences.setString(
          'profile_v1',
          jsonEncode(validated.toJson()),
        )) {
      throw const FormatException(
        'Your details could not be saved. Try again.',
      );
    }
    _profile = validated;
    notifyListeners();
  }

  Future<void> toggleNightMode() async {
    if (_appearanceSaving) return;
    _appearanceSaving = true;
    try {
      final next = !_darkMode;
      if (_preferences != null &&
          !await _preferences.setBool('dark_mode_v1', next)) {
        throw const FormatException(
          'The appearance could not be saved. Try again.',
        );
      }
      _darkMode = next;
      notifyListeners();
    } finally {
      _appearanceSaving = false;
    }
  }

  List<Map<String, dynamic>> get courses => List.unmodifiable(_courses);
  Future<void> _commit(List<Map<String, dynamic>> next) async {
    if (_preferences != null &&
        !await _preferences.setString('courses_v1', jsonEncode(next))) {
      throw const FormatException('The changes could not be saved. Try again.');
    }
    _courses = next;
    notifyListeners();
  }

  Future<void> save(Map<String, dynamic> course) async {
    final next = _courses.where((c) => c['id'] != course['id']).toList();
    final index = _courses.indexWhere((c) => c['id'] == course['id']);
    if (index < 0) {
      next.add(course);
    } else {
      next.insert(index, course);
    }
    await _commit(next);
  }

  Future<void> remove(String id) =>
      _commit(_courses.where((course) => course['id'] != id).toList());
}
