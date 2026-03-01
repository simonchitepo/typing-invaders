import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'game_controller.dart';
import 'models.dart';
import 'painter.dart';
import 'sketch.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  late final GameController controller;
  late final Sketch sketch;

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  final FocusNode _rawFocus = FocusNode(debugLabel: 'raw_keys');
  final FocusNode _textFocus = FocusNode(debugLabel: 'type_input');
  final TextEditingController _textController = TextEditingController();

  bool _bgmWasPlaying = false;

  @override
  void initState() {
    super.initState();

    controller = GameController();
    sketch = Sketch(Random(controller.hashCode));

    // Start BGM immediately; we'll pause/resume based on game state in _onTick().
    GameAudio.instance.playBgm();

    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = (_last == Duration.zero)
        ? 0.0
        : (elapsed - _last).inMicroseconds / 1000.0;
    _last = elapsed;

    final clamped = dt.clamp(0.0, 50.0);
    controller.tick(clamped);

    // ---- Sync background music with game state (robust even with keyboard pause)
    final shouldPlay = !controller.paused && !controller.gameOver;
    if (shouldPlay != _bgmWasPlaying) {
      _bgmWasPlaying = shouldPlay;
      if (shouldPlay) {
        GameAudio.instance.resumeBgm();
      } else {
        GameAudio.instance.pauseBgm();
      }
    }
  }

  void _focusInput() {
    if (!_textFocus.hasFocus) {
      FocusScope.of(context).requestFocus(_textFocus);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    controller.dispose();
    _rawFocus.dispose();
    _textFocus.dispose();
    _textController.dispose();

    GameAudio.instance.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paper = const Color(0xFFFBFBF7);

    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 700),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isSmall = MediaQuery.of(context).size.width < 520;

                return RawKeyboardListener(
                  focusNode: _rawFocus,
                  autofocus: true,
                  onKey: (event) {
                    // let controller handle keys
                    controller.handleKey(event);

                    // keep typing focus when gameplay is active
                    if (event is RawKeyDownEvent &&
                        !controller.paused &&
                        !controller.gameOver) {
                      _focusInput();
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) {
                      if (!controller.paused && !controller.gameOver) _focusInput();
                    },
                    child: Stack(
                      children: [
                        // Frame + canvas
                        Container(
                          decoration: BoxDecoration(
                            color: paper,
                            borderRadius: BorderRadius.circular(isSmall ? 0 : 18),
                            boxShadow: isSmall
                                ? null
                                : const [
                              BoxShadow(
                                blurRadius: 50,
                                offset: Offset(0, 18),
                                color: Color(0x20000000),
                              ),
                            ],
                            border: Border.all(
                              color: const Color(0x14000000),
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(isSmall ? 0 : 18),
                            child: CustomPaint(
                              painter: GamePainter(controller: controller, sketch: sketch),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),

                        // HUD (top)
                        Positioned(
                          top: 10,
                          left: 10,
                          right: 10,
                          child: AnimatedBuilder(
                            animation: controller,
                            builder: (_, __) {
                              final hide = !controller.paused && !controller.gameOver;
                              final buffs = controller.activePowerupsLabel;

                              return AnimatedOpacity(
                                duration: const Duration(milliseconds: 180),
                                opacity: hide ? 0 : 1,
                                child: AnimatedSlide(
                                  duration: const Duration(milliseconds: 180),
                                  offset: hide ? const Offset(0, -0.1) : Offset.zero,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _pill(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _stat("Score: ${controller.score}"),
                                            _sep(),
                                            _stat("Lives: ${controller.lives}"),
                                            _sep(),
                                            _stat("Wave: ${controller.wave}"),
                                            if (buffs.isNotEmpty) ...[
                                              _sep(),
                                              _stat(buffs),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (!isSmall) _pill(child: _stat("Type to shoot")),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Powerup toast (top-center)
                        Positioned(
                          top: 58,
                          left: 0,
                          right: 0,
                          child: AnimatedBuilder(
                            animation: controller,
                            builder: (_, __) {
                              final p = controller.lastPowerup;
                              final show = p != null && controller.lastPowerupToastMs > 0;
                              if (!show) return const SizedBox.shrink();

                              final label = _powerupLabel(p!);

                              return IgnorePointer(
                                child: Center(
                                  child: _pill(
                                    radius: 999,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Input bar (bottom)
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: AnimatedBuilder(
                            animation: controller,
                            builder: (_, __) {
                              final target = controller.getTargetEnemy();
                              final targetName = target?.word ?? "—";

                              // keep controller input + TextEditingController in sync
                              if (_textController.text != controller.inputText) {
                                _textController.value = TextEditingValue(
                                  text: controller.inputText,
                                  selection: TextSelection.collapsed(offset: controller.inputText.length),
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(
                                    child: _pill(
                                      radius: 16,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      child: Row(
                                        children: [
                                          if (!isSmall)
                                            const Padding(
                                              padding: EdgeInsets.only(right: 10),
                                              child: Text(
                                                "Type:",
                                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                                              ),
                                            ),
                                          Expanded(
                                            child: TextField(
                                              focusNode: _textFocus,
                                              controller: _textController,
                                              onChanged: (v) {
                                                controller.onTextChanged(v);
                                                if (_textController.text != controller.inputText) {
                                                  _textController.value = TextEditingValue(
                                                    text: controller.inputText,
                                                    selection: TextSelection.collapsed(offset: controller.inputText.length),
                                                  );
                                                }
                                              },
                                              autocorrect: false,
                                              enableSuggestions: false,
                                              textInputAction: TextInputAction.done,
                                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: InputBorder.none,
                                                hintText: "type word…",
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          _chip("🎯 $targetName"),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      elevation: 0,
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        side: const BorderSide(color: Color(0x20000000)),
                                      ),
                                    ),
                                    onPressed: () {
                                      controller.resetGame();
                                      _textController.clear();
                                      _focusInput();
                                    },
                                    child: const Text("Restart", style: TextStyle(fontWeight: FontWeight.w900)),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        // Overlay
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: controller,
                            builder: (_, __) {
                              final show = controller.paused;
                              return IgnorePointer(
                                ignoring: !show,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: show ? 1 : 0,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      if (controller.paused) {
                                        controller.togglePause();
                                        _focusInput();
                                      }
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        gradient: RadialGradient(
                                          center: Alignment(0, -0.2),
                                          radius: 1.2,
                                          colors: [
                                            Color(0xD8FFFFFF),
                                            Color(0x7AFFFFFF),
                                            Color(0x00FFFFFF),
                                          ],
                                          stops: [0.0, 0.55, 1.0],
                                        ),
                                      ),
                                      child: _overlayCard(
                                        title: controller.overlayTitle.isEmpty
                                            ? "Typing Invaders"
                                            : controller.overlayTitle,
                                        htmlish: controller.overlayHtmlishText,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ---- UI helpers
  Widget _stat(String s) => Text(
    s,
    style: const TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: 12,
      letterSpacing: 0.2,
    ),
  );

  Widget _sep() => Container(
    width: 1,
    height: 14,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: const Color(0x18000000),
  );

  Widget _pill({
    required Widget child,
    double radius = 999,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xC8FFFFFF),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x18000000)),
        boxShadow: const [
          BoxShadow(blurRadius: 24, offset: Offset(0, 8), color: Color(0x12000000)),
        ],
      ),
      child: child,
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x18000000)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }

  // Powerup toast label mapping
  String _powerupLabel(PowerupType p) {
    switch (p) {
      case PowerupType.slowTime:
        return "⏳ Slow Time";
      case PowerupType.extraLife:
        return "❤️ Extra Life";
      case PowerupType.shield:
        return "🛡 Shield";
      case PowerupType.pushBack:
        return "🧲 Push Back";
      case PowerupType.doubleScore:
        return "💰 Double Score";
      case PowerupType.chainLightning:
        return "⚡ Chain Lightning";
      case PowerupType.autoComplete:
        return "✨ Auto-Complete";
      case PowerupType.frenzy:
        return "🔥 Frenzy Mode";
    }
  }

  // ---- Overlay
  Widget _overlayCard({required String title, required String htmlish}) {
    final spans = _parseHtmlish(htmlish);

    return Container(
      width: 560,
      constraints: const BoxConstraints(maxWidth: 560),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xEEFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x22000000)),
        boxShadow: const [
          BoxShadow(blurRadius: 60, offset: Offset(0, 18), color: Color(0x24000000)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Color(0xFF333333),
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.35,
                fontFamily: 'monospace',
              ),
              children: spans,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _Hint(kbd: "Enter", text: "start / pause"),
              _Hint(kbd: "Tab", text: "switch target"),
              _Hint(kbd: "Esc", text: "clear"),
              _Hint(icon: "📱", text: "Tap anywhere to start"),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "Ink-on-paper canvas style.",
            style: TextStyle(fontSize: 12, color: Color(0x66000000), fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _parseHtmlish(String s) {
    // supports: <br> and <b>...</b>
    final out = <InlineSpan>[];
    int i = 0;
    const bold = TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF111111));

    while (i < s.length) {
      final br = s.indexOf("<br>", i);
      final b0 = s.indexOf("<b>", i);

      int next = s.length;
      if (br >= 0) next = min(next, br);
      if (b0 >= 0) next = min(next, b0);

      if (next > i) {
        out.add(TextSpan(text: s.substring(i, next)));
        i = next;
      } else if (br == i) {
        out.add(const TextSpan(text: "\n\n"));
        i += 4;
      } else if (b0 == i) {
        final b1 = s.indexOf("</b>", i + 3);
        if (b1 > i) {
          out.add(TextSpan(text: s.substring(i + 3, b1), style: bold));
          i = b1 + 4;
        } else {
          out.add(TextSpan(text: s.substring(i)));
          break;
        }
      } else {
        out.add(TextSpan(text: s.substring(i)));
        break;
      }
    }
    return out;
  }
}

class _Hint extends StatelessWidget {
  const _Hint({this.kbd, this.icon, required this.text});

  final String? kbd;
  final String? icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x18000000)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kbd != null) _kbd(kbd!),
          if (icon != null) Text(icon!, style: const TextStyle(fontSize: 12)),
          if (kbd != null || icon != null) const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _kbd(String k) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x20000000)),
      ),
      child: Text(k, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}