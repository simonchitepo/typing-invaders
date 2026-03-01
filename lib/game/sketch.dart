import 'dart:math';
import 'dart:ui';

class Sketch {
  Sketch(this.rng);

  final Random rng;

  double rand(double a, double b) => a + rng.nextDouble() * (b - a);
  int randi(int a, int b) => a + rng.nextInt((b - a) + 1);
  double clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);

  double inkStroke() => rand(1.2, 2.2);

  void sketchLine(Canvas canvas, Paint paint, Offset p1, Offset p2, {double jitter = 0.8}) {
    final w = inkStroke();
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final x1 = p1.dx + rand(-jitter, jitter);
    final y1 = p1.dy + rand(-jitter, jitter);
    final x2 = p2.dx + rand(-jitter, jitter);
    final y2 = p2.dy + rand(-jitter, jitter);

    final midx = (x1 + x2) / 2 + rand(-4, 4);
    final midy = (y1 + y2) / 2 + rand(-4, 4);

    path.moveTo(x1, y1);
    path.quadraticBezierTo(midx, midy, x2, y2);
    canvas.drawPath(path, paint);
  }

  void sketchCircle(Canvas canvas, Paint paint, Offset c, double r) {
    final w = inkStroke();
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;

    final start = rand(0, pi * 2);
    const steps = 16;
    final path = Path();

    for (int i = 0; i <= steps; i++) {
      final a = start + (i / steps) * pi * 2;
      final rr = r + rand(-1.2, 1.2);
      final px = c.dx + cos(a) * rr;
      final py = c.dy + sin(a) * rr;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(path, paint);
  }

  void sketchBurst(Canvas canvas, Paint paint, Offset c, double r) {
    final rays = randi(7, 11);
    for (int i = 0; i < rays; i++) {
      final a = (i / rays) * pi * 2 + rand(-0.15, 0.15);
      final len = r * rand(0.65, 1.2);
      sketchLine(
        canvas,
        paint,
        c,
        Offset(c.dx + cos(a) * len, c.dy + sin(a) * len),
        jitter: 1.1,
      );
    }
  }
}