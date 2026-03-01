import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'models.dart';
import 'sketch.dart';

class GamePainter extends CustomPainter {
  GamePainter({
    required this.controller,
    required this.sketch,
  }) : super(repaint: controller);

  final GameController controller;
  final Sketch sketch;

  final Paint _ink = Paint()
    ..color = const Color(0xFF111111)
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    controller.setViewport(size.width, size.height);

    // --- Paper base
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFBFBF7),
    );

    // --- Paper lighting (subtle radial “whiteness” blooms like your HTML background)
    _drawPaperBlooms(canvas, size);

    // --- Ruled sheet (repeating horizontal lines)
    _drawRuledPaper(canvas, size);

    // --- Paper specks
    _drawSpecks(canvas, size);

    // --- Inset frame border (like .frame::before) + tiny “blur”
    _drawInsetFrameBorder(canvas, size);

    // --- Game layers
    _drawGround(canvas, size);
    _drawPlayer(canvas, size);

    for (final e in controller.enemies) {
      if (e.alive) _drawEnemy(canvas, size, e);
    }
    _drawProjectiles(canvas, size);

    _drawParticles(canvas);
    _drawScribbles(canvas);

    // --- Vignette
    _drawVignette(canvas, size);

    if (controller.paused) {
      _drawPausedLabel(canvas, size);
    }
  }

  // ============================================================
  // VISUAL PASS 1: subtle radial paper blooms (white-ish spots)
  // ============================================================
  void _drawPaperBlooms(Canvas canvas, Size size) {
    final g1 = RadialGradient(
      colors: [
        const Color(0xFFFFFFFF).withOpacity(0.55),
        const Color(0xFFFFFFFF).withOpacity(0.0),
      ],
      stops: const [0.0, 1.0],
    ).createShader(
      Rect.fromCircle(
        center: Offset(size.width * 0.30, size.height * 0.20),
        radius: min(size.width, size.height) * 0.60,
      ),
    );

    final g2 = RadialGradient(
      colors: [
        const Color(0xFFFFFFFF).withOpacity(0.45),
        const Color(0xFFFFFFFF).withOpacity(0.0),
      ],
      stops: const [0.0, 1.0],
    ).createShader(
      Rect.fromCircle(
        center: Offset(size.width * 0.70, size.height * 0.30),
        radius: min(size.width, size.height) * 0.55,
      ),
    );

    canvas.drawRect(Offset.zero & size, Paint()..shader = g1);
    canvas.drawRect(Offset.zero & size, Paint()..shader = g2);
  }

  // ============================================================
  // VISUAL PASS 2: repeating horizontal rules like sketch sheet
  // ============================================================
  void _drawRuledPaper(Canvas canvas, Size size) {
    final spacing = 28.0;
    final topOffset = 0.0;

    final rulePaint = Paint()
      ..color = const Color(0xFF000000).withOpacity(0.045)
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    for (double y = topOffset; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rulePaint);
    }
  }

  // ============================================================
  // VISUAL PASS 3: inset border + slight blur (fake blur)
  // ============================================================
  void _drawInsetFrameBorder(Canvas canvas, Size size) {
    final inset = 10.0;
    final rect = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));

    final borderPaint = Paint()
      ..color = const Color(0xFF000000).withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..isAntiAlias = true;

    canvas.drawRRect(rrect, borderPaint);

    for (int i = 1; i <= 3; i++) {
      final inflated = rect.inflate(i * 0.6);
      final rr = RRect.fromRectAndRadius(inflated, const Radius.circular(14));
      final p = Paint()
        ..color = const Color(0xFF000000).withOpacity(0.06 / i)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..isAntiAlias = true;
      canvas.drawRRect(rr, p);
    }
  }

  void _drawSpecks(Canvas canvas, Size size) {
    final speckPaint = Paint()
      ..color = const Color(0xFF000000).withOpacity(0.10)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    const specks = 80;
    for (int i = 0; i < specks; i++) {
      final x = ((i * 37) % size.width) + sketch.rand(-6, 6);
      final y = ((i * 91) % size.height) + sketch.rand(-6, 6);
      final r = sketch.rand(0.4, 1.0);
      canvas.drawCircle(Offset(x, y), r, speckPaint);
    }
  }

  void _drawGround(Canvas canvas, Size size) {
    final y = size.height - controller.bottomHudHeight() - 10;
    final p = Paint()
      ..color = const Color(0xFF111111).withOpacity(0.22)
      ..isAntiAlias = true;
    sketch.sketchLine(canvas, p, Offset(22, y), Offset(size.width - 22, y), jitter: 0.6);
  }

  void _drawPlayer(Canvas canvas, Size size) {
    final px = size.width * 0.5;
    final py = size.height - controller.bottomHudHeight() + 6;

    canvas.save();
    canvas.translate(px, py);
    canvas.rotate(-0.03);

    final stroke = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final ship = Path()
      ..moveTo(-28, 8)
      ..lineTo(-16, -10)
      ..lineTo(16, -10)
      ..lineTo(28, 8)
      ..close();
    canvas.drawPath(ship, stroke);

    final fin = Path()
      ..moveTo(-8, -10)
      ..lineTo(-2, -18)
      ..lineTo(10, -14);
    canvas.drawPath(fin, stroke);

    sketch.sketchLine(canvas, stroke, const Offset(-28, 8), const Offset(-40, 14), jitter: 0.8);
    sketch.sketchLine(canvas, stroke, const Offset(28, 8), const Offset(40, 14), jitter: 0.8);

    final fill = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(sketch.rand(-6, 6), 14 + i * 4),
        sketch.rand(0.8, 1.6),
        fill..color = fill.color.withOpacity(0.65),
      );
    }

    canvas.restore();
  }

  void _drawEnemy(Canvas canvas, Size size, Enemy e) {
    canvas.save();
    canvas.translate(e.x, e.y);
    final rot = sin((controller.timeMs * 0.001) * e.wobbleSpeed + e.wobble) * 0.08;
    canvas.rotate(rot);

    // shadow
    final shadow = Paint()
      ..color = const Color(0xFF000000).withOpacity(0.12)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(4, 10), width: e.r * 1.5, height: e.r * 0.56),
      shadow,
    );

    // body circle
    final stroke = Paint()
      ..color = const Color(0xFF111111)
      ..isAntiAlias = true;
    sketch.sketchCircle(canvas, stroke, Offset.zero, e.r);

    // eyes-ish lines
    final soft = Paint()
      ..color = const Color(0xFF111111).withOpacity(0.85)
      ..isAntiAlias = true;
    sketch.sketchLine(
      canvas,
      soft,
      Offset(-e.r * 0.35, -e.r * 0.05),
      Offset(-e.r * 0.1, e.r * 0.15),
      jitter: 0.6,
    );
    sketch.sketchLine(
      canvas,
      soft,
      Offset(e.r * 0.35, -e.r * 0.05),
      Offset(e.r * 0.1, e.r * 0.15),
      jitter: 0.6,
    );

    // hit flash fill
    if (e.hitFlashMs > 0) {
      final flash = Paint()
        ..color = const Color(0xFFB00020).withOpacity(0.18)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawCircle(Offset.zero, e.r * 0.92, flash);
    }

    // word rendering
    final word = e.word;
    final typed = e.typed;

    final baseStyle = TextStyle(
      color: const Color(0xFF111111),
      fontWeight: FontWeight.w900,
      fontSize: e.size,
      fontFamily: 'monospace',
    );

    // shadow word
    _paintTextCentered(
      canvas,
      word,
      const Offset(0, -2),
      baseStyle.copyWith(color: const Color(0xFF111111).withOpacity(0.35)),
    );

    // typed overlay
    if (typed.isNotEmpty) {
      _paintTextCentered(
        canvas,
        typed,
        const Offset(0, -2),
        baseStyle.copyWith(color: const Color(0xFF111111).withOpacity(0.95)),
      );

      // underline for typed width
      final fullW = _measureTextWidth(word, baseStyle);
      final typedW = _measureTextWidth(typed, baseStyle);
      final startX = -fullW / 2;
      final y = e.size * 0.62;
      sketch.sketchLine(
        canvas,
        Paint()..color = const Color(0xFF111111).withOpacity(0.8),
        Offset(startX, y),
        Offset(startX + typedW, y),
        jitter: 0.4,
      );
    }

    // ✅ ARMOR / HIT COUNT INDICATOR (×2 / ×3)
    if (e.hitsRemaining > 1) {
      final badgeStyle = TextStyle(
        color: const Color(0xFF111111).withOpacity(0.75),
        fontWeight: FontWeight.w900,
        fontSize: 12,
        fontFamily: 'monospace',
      );

      // place it on upper-right of the bubble
      _paintTextCentered(
        canvas,
        "×${e.hitsRemaining}",
        Offset(e.r * 0.55, -e.r * 0.65),
        badgeStyle,
      );

      // add a tiny scribble ring behind the badge for clarity
      final ringPaint = Paint()
        ..color = const Color(0xFF111111).withOpacity(0.22)
        ..isAntiAlias = true;
      sketch.sketchCircle(canvas, ringPaint, Offset(e.r * 0.55, -e.r * 0.65), 10);
    }

    // target burst
    if (controller.targetId == e.id) {
      final burstPaint = Paint()
        ..color = const Color(0xFF111111).withOpacity(0.9)
        ..isAntiAlias = true;
      sketch.sketchBurst(canvas, burstPaint, Offset(0, -e.r - 10), 10);
    }

    canvas.restore();
  }

  void _drawProjectiles(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF111111)
      ..isAntiAlias = true;

    for (final pr in controller.projectiles) {
      if (!pr.alive) continue;
      final tt = (pr.tMs / pr.durMs).clamp(0.0, 1.0);
      final ease = 1 - pow(1 - tt, 3).toDouble();

      final x = pr.x + (pr.tx - pr.x) * ease;
      final y = pr.y + (pr.ty - pr.y) * ease;

      p.color = const Color(0xFF111111).withOpacity(0.9);
      sketch.sketchLine(canvas, p, Offset(pr.x, pr.y), Offset(x, y), jitter: 1.1);

      final dot = Paint()
        ..color = const Color(0xFF111111)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawCircle(Offset(x, y), 2.2, dot);
    }
  }

  void _drawParticles(Canvas canvas) {
    final p = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final s in controller.particles) {
      final t = s.ageMs / s.lifeMs;
      if (t >= 1) continue;
      p.color = const Color(0xFF111111).withOpacity(0.7 * (1 - t));
      canvas.drawCircle(Offset(s.x, s.y), s.r, p);
    }
  }

  void _drawScribbles(Canvas canvas) {
    for (final s in controller.scribbles) {
      final t = s.ageMs / s.lifeMs;
      if (t >= 1) continue;

      if (s.kind == ScribbleKind.circle) {
        final paint = Paint()
          ..color = const Color(0xFF111111).withOpacity(0.35 * (1 - t))
          ..isAntiAlias = true;

        canvas.save();
        canvas.translate(s.x, s.y);
        canvas.rotate(s.rot + sin(controller.timeMs * 0.003) * 0.08);

        final r = (s.r ?? 10) + sin(controller.timeMs * 0.004) * 2 * (s.wob ?? 1);
        sketch.sketchCircle(canvas, paint, Offset.zero, r);
        canvas.restore();
      } else {
        final style = TextStyle(
          color: const Color(0xFF111111).withOpacity(0.22 * (1 - t)),
          fontWeight: FontWeight.w900,
          fontSize: 24,
          fontFamily: 'monospace',
        );

        canvas.save();
        canvas.translate(s.x, s.y);
        canvas.rotate(s.rot);
        _paintTextCentered(canvas, s.text ?? "", Offset.zero, style);
        canvas.restore();
      }
    }
  }

  void _drawVignette(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.45);
    final outer = max(size.width, size.height) * 0.75;

    final shader = RadialGradient(
      colors: [
        const Color(0x00000000),
        const Color(0x14000000),
      ],
      stops: const [0.0, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: outer));

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  void _drawPausedLabel(Canvas canvas, Size size) {
    final status = controller.gameOver ? "game over" : "paused";
    const style = TextStyle(
      color: Color(0xFF111111),
      fontWeight: FontWeight.w900,
      fontSize: 12,
      fontFamily: 'monospace',
    );

    _paintTextCentered(canvas, status, Offset(size.width * 0.5, 10), style, alignTop: true);
  }

  // ---- text helpers
  void _paintTextCentered(
      Canvas canvas,
      String text,
      Offset c,
      TextStyle style, {
        bool alignTop = false,
      }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = Offset(
      c.dx - tp.width / 2,
      alignTop ? c.dy : (c.dy - tp.height / 2),
    );
    tp.paint(canvas, offset);
  }

  double _measureTextWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}