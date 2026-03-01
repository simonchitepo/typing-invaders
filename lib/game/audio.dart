import 'package:audioplayers/audioplayers.dart';

class GameAudio {
  GameAudio._();

  static final GameAudio instance = GameAudio._();

  final AudioPlayer _bgm = AudioPlayer();
  bool _initialized = false;
  bool muted = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Lower latency, better looping behavior on mobile.
    await _bgm.setReleaseMode(ReleaseMode.loop);

    // Optional: set a pleasant default volume
    await _bgm.setVolume(0.55);
  }

  Future<void> playBgm() async {
    if (muted) return;
    await init();

    // AssetSource path is relative to /assets in pubspec
    await _bgm.play(AssetSource('audio/bg.mp3'));
  }

  Future<void> stopBgm() async {
    if (!_initialized) return;
    await _bgm.stop();
  }

  Future<void> pauseBgm() async {
    if (!_initialized) return;
    await _bgm.pause();
  }

  Future<void> resumeBgm() async {
    if (muted) return;
    if (!_initialized) return;
    await _bgm.resume();
  }

  Future<void> setMuted(bool value) async {
    muted = value;
    if (muted) {
      await pauseBgm();
    } else {
      await resumeBgm();
    }
  }

  Future<void> dispose() async {
    await _bgm.dispose();
  }
}