import 'dart:ui';

enum PowerupType {
  slowTime,
  extraLife,
  shield,
  pushBack,
  doubleScore,
  chainLightning,
  autoComplete,
  frenzy,
}

class Enemy {
  Enemy({
    required this.id,
    required this.word,
    required this.x,
    required this.y,
    required this.vx,
    required this.r,
    required this.size,
    required this.wobble,
    required this.wobbleSpeed,
    this.hitsRemaining = 1,
    this.isPowerup = false,
    this.powerupType,
    this.powerupTint,
  });

  final int id;
  final String word;

  String typed = "";
  double x;
  double y;
  double vx;
  double r;
  double size;

  double wobble;
  double wobbleSpeed;

  bool alive = true;
  double hitFlashMs = 0;

  /// If > 1, enemy requires multiple correct full-word completions.
  int hitsRemaining;

  /// Powerup enemy metadata
  final bool isPowerup;
  final PowerupType? powerupType;

  /// Optional tint used by painter (different color from normal enemies)
  final Color? powerupTint;
}

class Projectile {
  Projectile({
    required this.x,
    required this.y,
    required this.tx,
    required this.ty,
    this.durMs = 180,
  });

  final double x;
  final double y;
  final double tx;
  final double ty;

  double tMs = 0;
  final double durMs;
  bool alive = true;
}

class Particle {
  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.lifeMs,
    required this.r,
  });

  double x;
  double y;
  double vx;
  double vy;

  double lifeMs;
  double ageMs = 0;
  double r;
}

enum ScribbleKind { circle, text }

class Scribble {
  Scribble.circle({
    required this.x,
    required this.y,
    required this.r,
    required this.lifeMs,
    required this.wob,
    required this.rot,
  })  : kind = ScribbleKind.circle,
        text = null;

  Scribble.text({
    required this.text,
    required this.x,
    required this.y,
    required this.lifeMs,
    required this.rot,
  })  : kind = ScribbleKind.text,
        r = null,
        wob = null;

  final ScribbleKind kind;
  final String? text;

  final double x;
  final double y;

  final double lifeMs;
  double ageMs = 0;

  // circle
  final double? r;
  final double? wob;
  final double rot;
}