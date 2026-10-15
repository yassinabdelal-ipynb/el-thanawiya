import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/student_store.dart';
import 'design.dart';
import 'night_button.dart';
import 'splash_page.dart';

class ProfilePage extends StatefulWidget {
  final StudentStore store;
  const ProfilePage({super.key, required this.store});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(),
      grade = TextEditingController(),
      age = TextEditingController();
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    grade.dispose();
    age.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final profile = StudentProfile.fromJson({
        'name': name.text,
        'grade': grade.text,
        'age': int.tryParse(age.text.trim()),
      });
      await widget.store.saveProfile(profile);
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
          error = 'Could not save your details. Try again.';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(26, 24, 26, 32),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: NightButton(store: widget.store),
                ),
                const SizedBox(height: 76),
                const Center(child: BrandWordmark()),
                const SizedBox(height: 48),
                SoftPanel(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      TextFormField(
                        key: const ValueKey('profile_name'),
                        controller: name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          counterText: '',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        key: const ValueKey('profile_grade'),
                        controller: grade,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        maxLength: 40,
                        decoration: const InputDecoration(
                          labelText: 'School grade',
                          hintText: 'Grade 11',
                          counterText: '',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your school grade'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        key: const ValueKey('profile_age'),
                        controller: age,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        maxLength: 3,
                        decoration: const InputDecoration(
                          labelText: 'Age',
                          counterText: '',
                        ),
                        onFieldSubmitted: (_) {
                          if (!saving) _continue();
                        },
                        validator: (value) {
                          final parsed = int.tryParse(value ?? '');
                          return parsed == null || parsed < 1 || parsed > 120
                              ? 'Enter a valid age'
                              : null;
                        },
                      ),
                    ],
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: TextStyle(color: Palette.of(context).clay),
                      ),
                    ),
                  ),
                const SizedBox(height: 34),
                SoftButton(
                  key: const ValueKey('profile_continue'),
                  filled: true,
                  onPressed: saving ? null : _continue,
                  padding: const EdgeInsets.symmetric(vertical: 19),
                  child: Center(child: Text(saving ? 'Saving…' : 'Continue')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
