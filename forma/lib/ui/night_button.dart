import 'package:flutter/material.dart';
import '../data/student_store.dart';
import 'design.dart';

class NightButton extends StatelessWidget {
  final StudentStore store;
  const NightButton({super.key, required this.store});
  @override
  Widget build(BuildContext context) => SoftButton(
    key: const ValueKey('night_mode'),
    label: store.darkMode ? 'Use light mode' : 'Use night mode',
    onPressed: () async {
      try {
        await store.toggleNightMode();
      } on FormatException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save the appearance. Try again.'),
            ),
          );
        }
      }
    },
    child: Icon(
      store.darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
    ),
  );
}
