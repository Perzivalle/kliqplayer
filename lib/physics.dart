import 'dart:math' as math;

/// Ressort amorti, intégré pas à pas (comme les animations « spring » d'iOS).
///
/// [damping] est le taux d'amortissement : 1 = critique (pas de rebond),
/// < 1 = léger rebond, > 1 = lent et mou.
class Spring {
  Spring(this.value, {this.stiffness = 170, this.damping = 0.85});

  double value;
  double velocity = 0;
  double stiffness;
  double damping;
  double _target = 0;

  void step(double target, double dt) {
    _target = target;
    final c = 2 * damping * math.sqrt(stiffness);
    var remaining = dt;
    // Petits pas pour rester stable même avec un ressort raide.
    while (remaining > 0) {
      final h = math.min(remaining, 1 / 480);
      final accel = -stiffness * (value - target) - c * velocity;
      velocity += accel * h;
      value += velocity * h;
      remaining -= h;
    }
  }

  bool get isSettled => (value - _target).abs() < 1e-4 && velocity.abs() < 1e-3;
}
