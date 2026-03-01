import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'words.dart';

class _ActiveBuff {
  _ActiveBuff(this.type, this.remainingMs);
  final PowerupType type;
  double remainingMs;
}

class GameController extends ChangeNotifier {
  GameController({int? seed})
      : _rng = Random(seed ?? DateTime.now().millisecondsSinceEpoch) {
    resetGame();

    // Decorative enemies while paused (like the web version)
    for (int i = 0; i < 3; i++) {
      spawnEnemy();
    }
  }

  // -------- RNG / helpers
  final Random _rng;
  double _rand(double a, double b) => a + _rng.nextDouble() * (b - a);
  int _randi(int a, int b) => a + _rng.nextInt((b - a) + 1);

  // -------- Public state (read by painter / UI)
  bool running = true;
  bool gameOver = false;
  bool paused = true;

  int score = 0;
  int lives = 3;
  int wave = 1;

  double timeMs = 0;
  double spawnTimerMs = 0;
  double spawnEveryMs = 1600;

  double speedBase = 24; // px/s (base)
  int? targetId;

  final List<Enemy> enemies = [];
  final List<Projectile> projectiles = [];
  final List<Particle> particles = [];
  final List<Scribble> scribbles = [];

  // Layout from widget each frame
  double width = 1;
  double height = 1;

  // input mirror
  String inputText = "";

  // overlay strings
  String overlayTitle = "Typing Invaders";
  String overlayHtmlishText =
      "Enemies descend with words. Type a word to destroy it before it reaches the bottom.<br><br>"
      "Press <b>Enter</b> or tap to start.";

  // ============================================================
  // POWERUPS STATE
  // ============================================================
  final List<_ActiveBuff> _buffs = [];

  // Shield is charge-based.
  int shieldCharges = 0;

  // Optional: last activated powerup (UI toast)
  PowerupType? lastPowerup;
  double lastPowerupToastMs = 0;

  bool _has(PowerupType t) => _buffs.any((b) => b.type == t);

  double get timeScale => _has(PowerupType.slowTime) ? 0.55 : 1.0;
  double get scoreMultiplier => _has(PowerupType.doubleScore) ? 2.0 : 1.0;
  bool get chainLightningActive => _has(PowerupType.chainLightning);
  bool get autoCompleteActive => _has(PowerupType.autoComplete);
  bool get frenzyActive => _has(PowerupType.frenzy);

  double get autoCompleteRatio => autoCompleteActive ? 0.80 : 1.00;

  String get activePowerupsLabel {
    final parts = <String>[];
    if (_has(PowerupType.slowTime)) parts.add("⏳ slow");
    if (_has(PowerupType.doubleScore)) parts.add("💰 x2");
    if (_has(PowerupType.chainLightning)) parts.add("⚡ chain");
    if (_has(PowerupType.autoComplete)) parts.add("✨ auto");
    if (_has(PowerupType.frenzy)) parts.add("🔥 frenzy");
    if (shieldCharges > 0) parts.add("🛡 $shieldCharges");
    return parts.join("  ");
  }

  // ============================================================
  // POWERUP SPAWN PACING (NEW)
  // ============================================================
  double _sinceLastPowerupMs = 0;
  static const double _powerupPityMs = 12000; // guarantee one every 12s after wave 3
  static const double _powerupChanceMin = 0.10; // 10%
  static const double _powerupChanceMax = 0.18; // 18%

  // -------- Mechanics
  double bottomHudHeight() => min(110.0, max(88.0, height * 0.14));

  int maxEnemiesAllowed() => (6 + (wave * 0.6).floor()).clamp(6, 14);

  double spawnEveryForWave() {
    final base = max(520.0, 1600.0 - (wave - 1) * 110.0);
    return frenzyActive ? base * 0.65 : base;
  }

  double speedForWave() {
    final base = speedBase + (wave - 1) * 10.0;
    return base * timeScale;
  }

  double enemySpeed() => speedForWave();

  // Armored enemies:
  // - wave < 4: normal (1 hit)
  // - wave 4..11: some are 2-hit
  // - wave 12+: some are 3-hit
  int armorHitsForWave(String word) {
    if (wave < 4) return 1;

    final baseChance = (0.10 + (wave - 4) * 0.03).clamp(0.10, 0.45);
    final lengthBonus =
    (word.length >= 10) ? 0.12 : (word.length >= 8 ? 0.06 : 0.0);
    final p = (baseChance + lengthBonus).clamp(0.10, 0.55);

    if (_rng.nextDouble() >= p) return 1;
    return wave >= 12 ? 3 : 2;
  }

  // -------- Word selection (harder with wave; frenzy makes them shorter)
  String pickWord() {
    if (frenzyActive) {
      final minLen = (3 + (wave * 0.25)).floor().clamp(3, 7);
      final maxLen = (6 + (wave * 0.35)).floor().clamp(6, 10);
      final candidates =
      kWords.where((w) => w.length >= minLen && w.length <= maxLen).toList();
      final list = candidates.isNotEmpty ? candidates : kWords;
      return list[_randi(0, list.length - 1)];
    }

    final minLen = (3 + (wave * 0.55)).floor().clamp(3, 10);
    final maxLen = (6 + (wave * 0.75)).floor().clamp(6, 18);

    final candidates =
    kWords.where((w) => w.length >= minLen && w.length <= maxLen).toList();

    final list = candidates.isNotEmpty
        ? candidates
        : kWords.where((w) => w.length >= minLen).toList(growable: false);

    if (list.isEmpty) return kWords[_randi(0, kWords.length - 1)];
    return list[_randi(0, list.length - 1)];
  }

  void advanceWaveIfNeeded() {
    final targetWave = 1 + (score / 120).floor();
    if (targetWave > wave) {
      wave = targetWave;
      spawnEveryMs = spawnEveryForWave();
      addScribbleText("wave $wave");
    }
  }

  // -------- Targeting
  Enemy? getTargetEnemy() {
    if (targetId == null) return null;
    for (final e in enemies) {
      if (e.id == targetId && e.alive) return e;
    }
    return null;
  }

  void chooseTarget(Enemy? e) {
    targetId = e?.id;
    notifyListeners();
  }

  void cycleTarget() {
    final alive = enemies.where((e) => e.alive).toList();
    if (alive.isEmpty) {
      chooseTarget(null);
      return;
    }
    if (targetId == null) {
      chooseTarget(alive.first);
      return;
    }
    final idx = alive.indexWhere((e) => e.id == targetId);
    chooseTarget(alive[(idx + 1) % alive.length]);
  }

  void autoTargetFromInput(String str) {
    final s = str.toLowerCase();
    final alive = enemies.where((e) => e.alive).toList();
    if (alive.isEmpty) {
      chooseTarget(null);
      return;
    }

    if (s.isNotEmpty) {
      final matches = alive
          .where((e) => e.word.startsWith(s))
          .toList()
        ..sort((a, b) {
          final aa = (a.word.length - s.length);
          final bb = (b.word.length - s.length);
          if (aa != bb) return aa.compareTo(bb);
          return b.y.compareTo(a.y);
        });
      if (matches.isNotEmpty) {
        chooseTarget(matches.first);
        return;
      }
    }

    alive.sort((a, b) => b.y.compareTo(a.y));
    chooseTarget(alive.first);
  }

  // ============================================================
  // POWERUP ENEMIES
  // ============================================================
  bool get _powerupOnScreen => enemies.any((e) => e.alive && e.isPowerup);

  List<PowerupType> _powerupPoolForWave() {
    final pool = <PowerupType>[];
    if (wave >= 3) {
      pool.add(PowerupType.slowTime);
      pool.add(PowerupType.extraLife);
    }
    if (wave >= 5) {
      pool.add(PowerupType.shield);
      pool.add(PowerupType.pushBack);
      pool.add(PowerupType.doubleScore);
    }
    if (wave >= 8) {
      pool.add(PowerupType.chainLightning);
      pool.add(PowerupType.autoComplete);
    }
    if (wave >= 12) {
      pool.add(PowerupType.frenzy);
    }
    return pool;
  }

  String _powerupWord(PowerupType t) {
    switch (t) {
      case PowerupType.slowTime:
        return "slow";
      case PowerupType.extraLife:
        return "life";
      case PowerupType.shield:
        return "shield";
      case PowerupType.pushBack:
        return "push";
      case PowerupType.doubleScore:
        return "x2";
      case PowerupType.chainLightning:
        return "chain";
      case PowerupType.autoComplete:
        return "auto";
      case PowerupType.frenzy:
        return "frenzy";
    }
  }

  Color _powerupTint(PowerupType t) {
    switch (t) {
      case PowerupType.slowTime:
        return const Color(0xFF2E7DFF);
      case PowerupType.extraLife:
        return const Color(0xFFE53935);
      case PowerupType.shield:
        return const Color(0xFF00A884);
      case PowerupType.pushBack:
        return const Color(0xFF8E24AA);
      case PowerupType.doubleScore:
        return const Color(0xFFF9A825);
      case PowerupType.chainLightning:
        return const Color(0xFF1565C0);
      case PowerupType.autoComplete:
        return const Color(0xFF00897B);
      case PowerupType.frenzy:
        return const Color(0xFFFF6D00);
    }
  }

  PowerupType? _rollPowerupEnemySpawn() {
    if (wave < 3) return null;
    if (_powerupOnScreen) return null;

    final pool = _powerupPoolForWave();
    if (pool.isEmpty) return null;

    // PITY: guarantee a powerup if too long since last one.
    final pityReady = _sinceLastPowerupMs >= _powerupPityMs;

    // Otherwise: higher chance that scales with wave.
    final chance = (_powerupChanceMin + wave * 0.004)
        .clamp(_powerupChanceMin, _powerupChanceMax);

    final shouldSpawn = pityReady || (_rng.nextDouble() < chance);
    if (!shouldSpawn) return null;

    // Weighting so life/frenzy are rarer.
    double w(PowerupType t) {
      switch (t) {
        case PowerupType.extraLife:
          return 0.55;
        case PowerupType.frenzy:
          return 0.65;
        default:
          return 1.0;
      }
    }

    final weights = pool.map(w).toList();
    final total = weights.fold<double>(0, (a, b) => a + b);

    double r = _rng.nextDouble() * total;
    for (int i = 0; i < pool.length; i++) {
      r -= weights[i];
      if (r <= 0) return pool[i];
    }
    return pool.last;
  }

  // -------- Spawning
  int _nextId = 1;

  void spawnEnemy() {
    // Sometimes spawn a powerup enemy (word activates the powerup).
    final p = _rollPowerupEnemySpawn();
    if (p != null) {
      _spawnPowerupEnemy(p);
      return;
    }

    // Otherwise, normal enemy
    final w = pickWord();
    final hits = armorHitsForWave(w);

    final pad = max(54.0, min(70.0, width * 0.12));
    final x = _rand(pad, width - pad);
    final y = _rand(58.0, 108.0);
    final drift = _rand(-18.0, 18.0);
    final size =
    (13.0 + w.length * 0.55).clamp(13.0, width < 420 ? 16.0 : 18.0);

    enemies.add(Enemy(
      id: _nextId++,
      word: w,
      x: x,
      y: y,
      vx: drift,
      r: 22.0 + w.length * 2.2,
      size: size,
      wobble: _rand(0.0, pi * 2),
      wobbleSpeed: _rand(0.8, 1.6),
      hitsRemaining: hits,
      isPowerup: false,
      powerupType: null,
      powerupTint: null,
    ));

    if (getTargetEnemy() == null) autoTargetFromInput(inputText);
  }

  void _spawnPowerupEnemy(PowerupType type) {
    _sinceLastPowerupMs = 0;

    final w = _powerupWord(type);

    final pad = max(54.0, min(70.0, width * 0.12));
    final x = _rand(pad, width - pad);
    final y = _rand(58.0, 108.0);
    final drift = _rand(-14.0, 14.0);

    // Make powerup enemies slightly easier to read/catch:
    final size = (15.0 + w.length * 0.75)
        .clamp(15.0, width < 420 ? 17.0 : 19.0);
    final rr = 26.0 + w.length * 2.8;

    enemies.add(Enemy(
      id: _nextId++,
      word: w,
      x: x,
      y: y,
      vx: drift,
      r: rr,
      size: size,
      wobble: _rand(0.0, pi * 2),
      wobbleSpeed: _rand(0.9, 1.7),
      hitsRemaining: 1, // always 1-hit: typing activates instantly
      isPowerup: true,
      powerupType: type,
      powerupTint: _powerupTint(type),
    ));

    addScribbleText(w);
    if (getTargetEnemy() == null) autoTargetFromInput(inputText);
  }

  // -------- Combat
  void fireAt(Enemy e) {
    final px = width * 0.5;
    final py = height - bottomHudHeight() - 14.0;
    projectiles.add(Projectile(
      x: px,
      y: py,
      tx: e.x,
      ty: e.y,
      durMs: 180,
    ));
  }

  void explode(Enemy e) {
    for (int i = 0; i < 18; i++) {
      particles.add(Particle(
        x: e.x + _rand(-8.0, 8.0),
        y: e.y + _rand(-6.0, 6.0),
        vx: _rand(-110.0, 110.0),
        vy: _rand(-140.0, 40.0),
        lifeMs: _rand(360.0, 700.0),
        r: _rand(0.8, 2.2),
      ));
    }
    addScribbleCircle(e.x, e.y, e.r + _rand(8.0, 16.0));
  }

  void addScribbleCircle(double x, double y, double r) {
    scribbles.add(Scribble.circle(
      x: x,
      y: y,
      r: r,
      lifeMs: 900,
      wob: _rand(0.8, 1.6),
      rot: _rand(0.0, pi * 2),
    ));
  }

  void addScribbleText(String text) {
    scribbles.add(Scribble.text(
      text: text,
      x: width * 0.5,
      y: height * 0.22,
      lifeMs: 1200,
      rot: _rand(-0.12, 0.12),
    ));
  }

  void _addBuff(PowerupType type, double durationMs) {
    final existing = _buffs.where((b) => b.type == type).toList();
    if (existing.isNotEmpty) {
      existing.first.remainingMs = max(existing.first.remainingMs, durationMs);
      return;
    }
    _buffs.add(_ActiveBuff(type, durationMs));
  }

  void _applyPowerup(PowerupType p) {
    lastPowerup = p;
    lastPowerupToastMs = 1600;

    switch (p) {
      case PowerupType.slowTime:
        _addBuff(PowerupType.slowTime, 6000);
        addScribbleText("slow");
        break;

      case PowerupType.extraLife:
        lives = min(9, lives + 1);
        addScribbleText("+1");
        break;

      case PowerupType.shield:
        shieldCharges += 3;
        addScribbleText("shield");
        break;

      case PowerupType.pushBack:
        for (final e in enemies) {
          if (!e.alive) continue;
          e.y = max(40.0, e.y - 110.0);
        }
        addScribbleText("push");
        break;

      case PowerupType.doubleScore:
        _addBuff(PowerupType.doubleScore, 8000);
        addScribbleText("x2");
        break;

      case PowerupType.chainLightning:
        _addBuff(PowerupType.chainLightning, 8000);
        addScribbleText("chain");
        break;

      case PowerupType.autoComplete:
        _addBuff(PowerupType.autoComplete, 7000);
        addScribbleText("auto");
        break;

      case PowerupType.frenzy:
        _addBuff(PowerupType.frenzy, 10000);
        addScribbleText("frenzy");
        break;
    }
  }

  void _chainKillFrom(double x, double y, {required int count}) {
    final alive = enemies.where((en) => en.alive && !en.isPowerup).toList();
    if (alive.isEmpty) return;

    alive.sort((a, b) {
      final da = (a.x - x) * (a.x - x) + (a.y - y) * (a.y - y);
      final db = (b.x - x) * (b.x - x) + (b.y - y) * (b.y - y);
      return da.compareTo(db);
    });

    final n = min(count, alive.length);
    for (int i = 0; i < n; i++) {
      final e = alive[i];
      fireAt(e);
      _killEnemyInternal(e, allowChain: false);
    }
  }

  void _killEnemyInternal(Enemy e, {required bool allowChain}) {
    if (!e.alive) return;

    e.alive = false;
    explode(e);

    final gained = (10 + min(10, e.word.length)) * scoreMultiplier;
    score += gained.round();

    advanceWaveIfNeeded();
    autoTargetFromInput(inputText);

    if (allowChain && chainLightningActive && !e.isPowerup) {
      _chainKillFrom(e.x, e.y, count: 2);
    }
  }

  void killEnemy(Enemy e) => _killEnemyInternal(e, allowChain: true);

  // -------- Input hooks (POWERUP ACTIVATION HAPPENS HERE)
  void onTextChanged(String value) {
    inputText = value;
    final str = value.toLowerCase();

    autoTargetFromInput(str);

    final t = getTargetEnemy();
    if (t == null) {
      notifyListeners();
      return;
    }

    if (t.word.startsWith(str)) {
      t.typed = str;
    } else {
      t.hitFlashMs = 140;
      t.typed = "";
    }

    final needed = (t.word.length * autoCompleteRatio).ceil();
    final completed = str.isNotEmpty && str.length >= needed && t.word.startsWith(str);

    if (completed) {
      fireAt(t);

      // If this is a powerup enemy, activate powerup on completion.
      if (t.isPowerup && t.powerupType != null) {
        _applyPowerup(t.powerupType!);
        t.hitsRemaining = 0;
        killEnemy(t);
        inputText = "";
        notifyListeners();
        return;
      }

      // Normal armored behavior
      t.hitsRemaining -= 1;
      if (t.hitsRemaining <= 0) {
        killEnemy(t);
      } else {
        t.hitFlashMs = 160;
        addScribbleCircle(t.x, t.y, t.r + 8.0);
        chooseTarget(t);
      }

      inputText = "";
    }

    notifyListeners();
  }

  void clearInput() {
    inputText = "";
    onTextChanged("");
  }

  void togglePause() {
    if (!running) return;

    if (gameOver) {
      resetGame();
      return;
    }

    paused = !paused;
    if (!paused) {
      overlayTitle = "";
      overlayHtmlishText = "";
    } else {
      overlayTitle = "Paused";
      overlayHtmlishText =
      "Press <b>Enter</b> to resume.<br><br>"
          "On mobile: tap anywhere to resume.";
    }
    notifyListeners();
  }

  // -------- Game loop tick
  void setViewport(double w, double h) {
    width = max(1.0, w);
    height = max(1.0, h);
  }

  void tick(double dtMs) {
    timeMs += dtMs;

    _updateParticles(dtMs);
    _updateScribbles(dtMs);
    _updateBuffs(dtMs);

    // track pity timer only during active play
    if (!paused && !gameOver) {
      _sinceLastPowerupMs += dtMs;
    }

    if (paused || gameOver) {
      notifyListeners();
      return;
    }

    spawnEveryMs = spawnEveryForWave();

    // Catch-up spawning: can spawn multiple times per tick.
    // Powerups may spawn even when normal cap is reached.
    spawnTimerMs += dtMs;
    while (spawnTimerMs >= spawnEveryMs) {
      spawnTimerMs -= spawnEveryMs;

      final aliveCount = enemies.where((e) => e.alive).length;
      final canSpawnNormal = aliveCount < maxEnemiesAllowed();
      final canSpawnPowerup = (wave >= 3) && !_powerupOnScreen;

      if (!canSpawnNormal && !canSpawnPowerup) break;

      // If cap reached, try to spawn a powerup (at most +1)
      if (!canSpawnNormal && canSpawnPowerup) {
        final p = _rollPowerupEnemySpawn();
        if (p != null) {
          _spawnPowerupEnemy(p);
        }
        break;
      }

      spawnEnemy();
    }

    final spd = enemySpeed();
    final floorY = height - bottomHudHeight() - 10.0;

    for (final e in enemies) {
      if (!e.alive) continue;

      e.wobble += (dtMs / 1000.0) * e.wobbleSpeed;
      final drift = sin(e.wobble) * 10.0;
      e.x += (e.vx + drift) * (dtMs / 1000.0);
      e.y += spd * (dtMs / 1000.0);

      final sidePad = max(46.0, min(70.0, width * 0.12));
      if (e.x < sidePad) {
        e.x = sidePad;
        e.vx = e.vx.abs();
      }
      if (e.x > width - sidePad) {
        e.x = width - sidePad;
        e.vx = -e.vx.abs();
      }

      e.hitFlashMs = max(0.0, e.hitFlashMs - dtMs);

      if (e.y + e.r >= floorY) {
        e.alive = false;

        // Shield absorbs ground hits.
        if (shieldCharges > 0) {
          shieldCharges -= 1;
          addScribbleText("🛡");
        } else {
          lives -= 1;
          addScribbleText("oops");
        }

        if (lives <= 0) {
          gameOver = true;
          paused = true;
          overlayTitle = "Game Over";
          overlayHtmlishText =
          "Final score: <b>$score</b><br><br>"
              "Press <b>Enter</b> or tap to restart.";
        } else {
          autoTargetFromInput(inputText);
        }
      }
    }

    for (final p in projectiles) {
      if (!p.alive) continue;
      p.tMs += dtMs;
      if (p.tMs >= p.durMs) p.alive = false;
    }

    projectiles.removeWhere((p) => !p.alive);
    enemies.removeWhere((e) => !e.alive);

    if (getTargetEnemy() == null) autoTargetFromInput(inputText);

    notifyListeners();
  }

  void _updateParticles(double dtMs) {
    for (final s in particles) {
      s.ageMs += dtMs;
      final t = s.ageMs / s.lifeMs;
      if (t >= 1) continue;

      s.vy += 220.0 * (dtMs / 1000.0);
      s.x += s.vx * (dtMs / 1000.0);
      s.y += s.vy * (dtMs / 1000.0);
    }
    particles.removeWhere((p) => p.ageMs >= p.lifeMs);
  }

  void _updateScribbles(double dtMs) {
    for (final s in scribbles) {
      s.ageMs += dtMs;
    }
    scribbles.removeWhere((s) => s.ageMs >= s.lifeMs);
  }

  void _updateBuffs(double dtMs) {
    if (lastPowerupToastMs > 0) {
      lastPowerupToastMs = max(0.0, lastPowerupToastMs - dtMs);
      if (lastPowerupToastMs == 0) lastPowerup = null;
    }

    for (final b in _buffs) {
      b.remainingMs -= dtMs;
    }
    _buffs.removeWhere((b) => b.remainingMs <= 0);
  }

  // -------- Reset
  void resetGame() {
    running = true;
    gameOver = false;
    paused = true;

    score = 0;
    lives = 3;
    wave = 1;

    timeMs = 0;
    spawnTimerMs = 0;
    spawnEveryMs = spawnEveryForWave();

    enemies.clear();
    projectiles.clear();
    particles.clear();
    scribbles.clear();

    targetId = null;
    inputText = "";

    _buffs.clear();
    shieldCharges = 0;
    lastPowerup = null;
    lastPowerupToastMs = 0;

    _sinceLastPowerupMs = 0;

    overlayTitle = "Typing Invaders";
    overlayHtmlishText =
    "Enemies descend with words. Type a word to destroy it before it reaches the bottom.<br><br>"
        "Press <b>Enter</b> or tap to start.";

    notifyListeners();
  }

  // -------- Keyboard mapping (UI calls this)
  void handleKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter) {
      togglePause();
      return;
    }
    if (key == LogicalKeyboardKey.tab) {
      cycleTarget();
      return;
    }
    if (key == LogicalKeyboardKey.escape) {
      clearInput();
      return;
    }
  }
}