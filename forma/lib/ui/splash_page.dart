import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'design.dart';

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key});
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      'El-Thanawiya',
      style: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 36,
        letterSpacing: -1.7,
        fontVariations: const [FontVariation('wght', 450)],
        color: Palette.of(context).ink,
      ),
    ),
  );
}

class SplashPage extends StatefulWidget {
  final bool animate;
  const SplashPage({super.key, this.animate = true});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      if (!rotation.isAnimating) rotation.repeat();
    } else {
      rotation.stop();
    }
  }

  @override
  void dispose() {
    rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: SoftPanel(
                  radius: 55,
                  padding: const EdgeInsets.all(17),
                  child: Semantics(
                    label: 'Loading El-Thanawiya',
                    liveRegion: true,
                    child: ExcludeSemantics(
                      child: AnimatedBuilder(
                        animation: rotation,
                        builder: (context, _) => Transform.rotate(
                          key: const ValueKey('loading_rotation'),
                          angle: rotation.value * math.pi * 2,
                          child: CustomPaint(
                            painter: _LoadingRing(Palette.of(context)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 42),
              const BrandWordmark(),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LoadingRing extends CustomPainter {
  final Palette palette;
  const _LoadingRing(this.palette);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width - 10,
      height: size.height - 10,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(rect, paint..color = palette.line);
    canvas.drawArc(rect, -.8, 1.7, false, paint..color = palette.sage);
  }

  @override
  bool shouldRepaint(_LoadingRing oldDelegate) =>
      oldDelegate.palette != palette;
}
