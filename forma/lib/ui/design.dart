import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'palette.dart';
export 'palette.dart';

class SoftPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool inset;
  const SoftPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 26,
    this.inset = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Palette.of(context).canvas,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: inset
            ? Palette.of(context).line
            : Palette.of(context).light.withValues(alpha: .7),
        width: .7,
      ),
      gradient: inset
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(
                  Palette.of(context).canvas,
                  Palette.of(context).shadow,
                  .25,
                )!,
                Palette.of(context).canvas,
              ],
            )
          : null,
      boxShadow: inset
          ? []
          : [
              BoxShadow(
                color: Palette.of(context).shadow,
                offset: const Offset(7, 7),
                blurRadius: 18,
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Palette.of(context).light,
                offset: const Offset(-6, -6),
                blurRadius: 16,
              ),
            ],
    ),
    child: child,
  );
}

class SoftButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool filled;
  final String? label;
  final EdgeInsetsGeometry padding;
  const SoftButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.filled = false,
    this.label,
    this.padding = const EdgeInsets.all(14),
  });
  @override
  State<SoftButton> createState() => _SoftButtonState();
}

class _SoftButtonState extends State<SoftButton> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: widget.label,
    enabled: widget.onPressed != null,
    child: AnimatedScale(
      scale: pressed ? .96 : 1,
      duration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 130,
      ),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: widget.onPressed,
          onHighlightChanged: (value) => setState(() => pressed = value),
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: widget.padding,
            decoration: BoxDecoration(
              color: widget.filled
                  ? Palette.of(context).ink
                  : Palette.of(context).canvas,
              borderRadius: BorderRadius.circular(22),
              boxShadow: pressed
                  ? []
                  : [
                      BoxShadow(
                        color: Palette.of(context).shadow.withValues(alpha: .8),
                        offset: const Offset(4, 5),
                        blurRadius: 12,
                      ),
                      if (!widget.filled)
                        BoxShadow(
                          color: Palette.of(context).light,
                          offset: const Offset(-4, -4),
                          blurRadius: 10,
                        ),
                    ],
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: widget.filled
                    ? Palette.of(context).canvas
                    : Palette.of(context).ink,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              child: IconTheme(
                data: IconThemeData(
                  color: widget.filled
                      ? Palette.of(context).canvas
                      : Palette.of(context).ink,
                  size: 21,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

String riskText(double? score) => score == null
    ? '—'
    : score < 1
    ? '<1%'
    : '${score.round()}%';
String numeric(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

double? rawCurrentGrade(
  Map<String, dynamic> course,
  Map<String, dynamic> result,
) {
  if (course['current_grade'] is num) {
    return (course['current_grade'] as num).toDouble();
  }
  if (result['current_grade_percent'] is! num) return null;
  final quality = (result['current_grade_percent'] as num).toDouble() / 100;
  final low = ((course['grade_min'] ?? 0) as num).toDouble();
  final high = ((course['grade_max'] ?? 100) as num).toDouble();
  return low +
      (high - low) *
          (course['higher_is_better'] == false ? 1 - quality : quality);
}

class RiskDial extends StatelessWidget {
  final double? score;
  final bool alert;
  final double size;
  const RiskDial({super.key, this.score, this.alert = false, this.size = 240});
  @override
  Widget build(BuildContext context) => Semantics(
    label: score == null
        ? 'Risk unavailable'
        : 'Estimated risk ${score!.toStringAsFixed(1)} percent',
    child: ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: score ?? 0),
        duration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 950,
        ),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size - 36,
                height: size - 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Palette.of(context).canvas,
                  boxShadow: [
                    BoxShadow(
                      color: Palette.of(context).shadow,
                      offset: const Offset(8, 8),
                      blurRadius: 19,
                    ),
                    BoxShadow(
                      color: Palette.of(context).light,
                      offset: const Offset(-8, -8),
                      blurRadius: 19,
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _DialPainter(
                    value / 100,
                    alert,
                    Palette.of(context),
                  ),
                ),
              ),
              Text(
                score == null ? '—' : riskText(value),
                style: TextStyle(
                  fontSize: size * .245,
                  height: 1,
                  letterSpacing: -4,
                  fontVariations: const [FontVariation('wght', 350)],
                  color: Palette.of(context).ink,
                ),
              ),
              Positioned(
                bottom: size * .10,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: score == null
                        ? Palette.of(context).line
                        : Palette.of(context).sage,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DialPainter extends CustomPainter {
  final double fraction;
  final bool alert;
  final Palette palette;
  const _DialPainter(this.fraction, this.alert, this.palette);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 9;
    final start = math.pi * .75, sweep = math.pi * 1.5;
    for (var i = 0; i <= 48; i++) {
      final angle = start + sweep * i / 48;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * radius,
        center + direction * (radius - (i % 4 == 0 ? 7 : 4)),
        Paint()
          ..color = palette.muted.withValues(alpha: .32)
          ..strokeWidth = 1,
      );
    }
    final rect = Rect.fromCircle(center: center, radius: radius - 15);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, track..color = palette.line);
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        start,
        sweep * fraction.clamp(0, 1),
        false,
        track..color = alert ? palette.clay : palette.sage,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.alert != alert ||
      oldDelegate.palette != palette;
}

class PageHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const PageHeader({super.key, required this.title, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 26),
    child: Row(
      children: [
        SoftButton(
          label: 'Back',
          onPressed: () => Navigator.maybePop(context),
          child: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w600,
              letterSpacing: -.8,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

Route<T> softRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (context, animation, secondary) => page,
  transitionDuration: const Duration(milliseconds: 350),
  reverseTransitionDuration: const Duration(milliseconds: 250),
  transitionsBuilder: (context, animation, secondary, child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(.045, .015),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);
