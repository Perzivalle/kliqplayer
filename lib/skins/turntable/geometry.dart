import 'dart:math' as math;
import 'dart:ui';

/// Dimensions de la platine, dans un repère fixe de 1320 × 1000 unités
/// (la scène est ensuite mise à l'échelle de la fenêtre).
class TurntableGeometry {
  static const double width = 1320;
  static const double height = 1000;
  static const double margin = 30;

  static const Rect plinth = Rect.fromLTWH(margin, margin, width - 2 * margin, height - 2 * margin);
  static const double plinthRadius = 35;

  static const Offset center = Offset(490, 500);
  static const double platterR = 410;
  static const double recordR = 385;
  static const double labelR = 130;

  static const Offset pivot = Offset(1120, 200);
  static final double pivotDist = (center - pivot).distance;
  static final double armLength = pivotDist - 150;

  /// Rayons du premier et du dernier sillon.
  static const double grooveStart = 372;
  static const double grooveEnd = 160;

  /// Bras sur son repose-bras.
  static const double armRest = math.pi / 2 + 0.25;
  static const double headLength = 85;
  static const double headOffset = 0.38;

  static const Rect startButton = Rect.fromLTWH(70, 878, 170, 52);
  static const Rect speed33 = Rect.fromLTWH(905, 888, 70, 42);
  static const Rect speed45 = Rect.fromLTWH(990, 888, 70, 42);

  static const Offset knob = Offset(1180, 860);
  static const double knobR = 55;

  static final Offset lamp = center + Offset.fromDirection(3 * math.pi / 4, platterR + 38);
  static const double lampR = 17;

  static const double pitchX = 1240;
  static const double pitchTop = 420;
  static const double pitchBottom = 650;
  static const double pitchRange = 0.08; // ±8 %

  /// Position de la pointe pour un angle de bras.
  static Offset stylus(double angle) => pivot + Offset.fromDirection(angle, armLength);

  /// Angle du bras qui pose la pointe à [dist] du centre du disque.
  static double armAngleFor(double dist) {
    final d = pivotDist;
    final l = armLength;
    final cosPhi = ((d * d + l * l - dist * dist) / (2 * d * l)).clamp(-1.0, 1.0);
    final toCenter = center - pivot;
    return math.atan2(toCenter.dy, toCenter.dx) - math.acos(cosPhi);
  }

  static double armAngleForProgress(double p) =>
      armAngleFor(grooveStart - (grooveStart - grooveEnd) * p.clamp(0.0, 1.0));

  static double stylusRadius(double angle) => (stylus(angle) - center).distance;

  /// Avancement correspondant à un angle de bras (0 à 1), ou null si la
  /// pointe n'est pas sur la zone gravée du disque.
  static double? progressForAngle(double angle) {
    final r = stylusRadius(angle);
    if (r > grooveStart + 12 || r < grooveEnd - 12) return null;
    return ((grooveStart - r) / (grooveStart - grooveEnd)).clamp(0.0, 1.0);
  }

  static final double innerAngle = armAngleFor(grooveEnd);

  /// Le bras ne peut aller que du repose-bras au dernier sillon.
  static double clampArm(double a) => a.clamp(math.min(armRest, innerAngle), math.max(armRest, innerAngle));

  /// Distance d'un point au bras (pour savoir si on l'attrape).
  static bool hitsArm(Offset p, double angle) {
    final s = stylus(angle);
    final ab = s - pivot;
    final t = (((p - pivot).dx * ab.dx + (p - pivot).dy * ab.dy) / (ab.distanceSquared)).clamp(0.0, 1.0);
    final closest = pivot + ab * t;
    return (p - closest).distance < 40 || (p - s).distance < 80;
  }
}
