import 'package:flutter/material.dart';

@immutable
class Palette extends ThemeExtension<Palette> {
  final Color canvas, ink, muted, sage, clay, shadow, light, line;
  const Palette({
    required this.canvas,
    required this.ink,
    required this.muted,
    required this.sage,
    required this.clay,
    required this.shadow,
    required this.light,
    required this.line,
  });
  static const day = Palette(
    canvas: Color(0xFFECEDE6),
    ink: Color(0xFF29322C),
    muted: Color(0xFF626B64),
    sage: Color(0xFF5C6E5F),
    clay: Color(0xFF99553B),
    shadow: Color(0xFFC8CDC2),
    light: Color(0xFFFDFEF8),
    line: Color(0xFFD7DCD1),
  );
  static const night = Palette(
    canvas: Color(0xFF232B26),
    ink: Color(0xFFEDF0E6),
    muted: Color(0xFFBAC4B5),
    sage: Color(0xFFAABD9E),
    clay: Color(0xFFE5AC8A),
    shadow: Color(0xFF141C17),
    light: Color(0xFF364339),
    line: Color(0xFF405044),
  );
  static Palette of(BuildContext context) =>
      Theme.of(context).extension<Palette>() ?? day;
  @override
  Palette copyWith({
    Color? canvas,
    Color? ink,
    Color? muted,
    Color? sage,
    Color? clay,
    Color? shadow,
    Color? light,
    Color? line,
  }) => Palette(
    canvas: canvas ?? this.canvas,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    sage: sage ?? this.sage,
    clay: clay ?? this.clay,
    shadow: shadow ?? this.shadow,
    light: light ?? this.light,
    line: line ?? this.line,
  );
  @override
  Palette lerp(covariant Palette? other, double t) => other == null
      ? this
      : Palette(
          canvas: Color.lerp(canvas, other.canvas, t)!,
          ink: Color.lerp(ink, other.ink, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          sage: Color.lerp(sage, other.sage, t)!,
          clay: Color.lerp(clay, other.clay, t)!,
          shadow: Color.lerp(shadow, other.shadow, t)!,
          light: Color.lerp(light, other.light, t)!,
          line: Color.lerp(line, other.line, t)!,
        );
}

ThemeData appTheme({bool dark = false}) {
  final palette = dark ? Palette.night : Palette.day;
  final brightness = dark ? Brightness.dark : Brightness.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: palette.canvas,
    extensions: [palette],
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: palette.ink,
      onPrimary: palette.canvas,
      secondary: palette.sage,
      onSecondary: palette.canvas,
      surface: palette.canvas,
      onSurface: palette.ink,
      error: palette.clay,
      onError: palette.canvas,
      outline: palette.line,
    ),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      fontFamily: 'Manrope',
      bodyColor: palette.ink,
      displayColor: palette.ink,
    ),
    splashFactory: NoSplash.splashFactory,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.light.withValues(alpha: dark ? .3 : .35),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: TextStyle(color: palette.muted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide(color: palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide(color: palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide(color: palette.sage, width: 1.5),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.canvas,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.canvas,
      surfaceTintColor: Colors.transparent,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: palette.canvas,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
