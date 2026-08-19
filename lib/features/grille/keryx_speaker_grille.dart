import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/grille/grille_motion.dart';

/// PT `.grille i` fill (`#0d0f10`). Theme has no slot-idle token.
const Color _slotIdle = Color(0xFF0D0F10);

/// PT `.grille.live i` fill (`#12211a`). Theme has no slot-live token.
const Color _slotLive = Color(0xFF12211A);

/// Recessed speaker grille whose slots tremble with injected RX amplitude.
///
/// This widget owns no radio or audio state. The host maps RX / MONITOR /
/// idle onto [amplitude] (0–1) and sets [live] for the RX tint. Reduced
/// motion freezes the slots at rest but keeps the stream subscription.
class KeryxSpeakerGrille extends StatefulWidget {
  const KeryxSpeakerGrille({
    super.key,
    required this.amplitude,
    this.live = false,
    this.reduceMotion,
    this.random,
  });

  /// Incoming RX amplitude in `[0, 1]`. Non-finite values are ignored.
  final Stream<double> amplitude;

  /// Live RX tint. Independent of [amplitude] so MONITOR can tremble
  /// without the live colour (prototype: `S.rx` vs `S.mon ? 0.25 : 0`).
  final bool live;

  /// When set, overrides [MediaQuery.disableAnimations]. `true` removes
  /// the tremble; haptics and sound are not owned here so they are
  /// unaffected.
  final bool? reduceMotion;

  /// Injected RNG for the per-bar jitter term. Production uses a fresh
  /// [math.Random] when this is null.
  final math.Random? random;

  @override
  State<KeryxSpeakerGrille> createState() => KeryxSpeakerGrilleState();
}

/// Public so widget tests can read the last accepted amplitude and scales.
class KeryxSpeakerGrilleState extends State<KeryxSpeakerGrille>
    with TickerProviderStateMixin {
  static const double _barHeight = 5;
  static const double _barGap = 5;
  static const double _barRadius = 3;
  static const double _padH = 18;
  static const double _padV = 14;

  late final AnimationController _level;
  late final Ticker _ticker;
  late final math.Random _random;
  StreamSubscription<double>? _subscription;

  final List<double> _scales = List<double>.filled(
    GrilleMotion.barCount,
    1,
    growable: false,
  );

  double _lastAmplitude = 0;

  /// Last finite amplitude accepted from the injected stream.
  @visibleForTesting
  double get lastAmplitude => _lastAmplitude;

  /// Current per-bar scaleY values (rest = 1).
  @visibleForTesting
  List<double> get barScales => List<double>.unmodifiable(_scales);

  bool get _motionOff {
    if (widget.reduceMotion != null) return widget.reduceMotion!;
    return MediaQuery.disableAnimationsOf(context);
  }

  @override
  void initState() {
    super.initState();
    _random = widget.random ?? math.Random();
    _level = AnimationController(
      vsync: this,
      duration: KeryxTheme.settleDuration,
      value: 0,
    );
    _ticker = createTicker(_onTick);
    _listen(widget.amplitude);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(KeryxSpeakerGrille oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amplitude != widget.amplitude) {
      _listen(widget.amplitude);
    }
    _syncTicker();
    if (_motionOff) {
      _freezeAtRest();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _ticker.dispose();
    _level.dispose();
    super.dispose();
  }

  void _listen(Stream<double> stream) {
    unawaited(_subscription?.cancel());
    _subscription = stream.listen(
      _onAmplitude,
      onError: (Object error, StackTrace stack) {
        developer.log(
          'Amplitude stream error: $error',
          name: 'keryx.grille',
          error: error,
          stackTrace: stack,
        );
      },
    );
  }

  void _onAmplitude(double raw) {
    if (!mounted) return;
    if (!raw.isFinite) {
      developer.log(
        'Ignoring non-finite amplitude $raw',
        name: 'keryx.grille',
      );
      return;
    }
    _lastAmplitude = GrilleMotion.clampAmplitude(raw);
    unawaited(
      _level.animateTo(
        _lastAmplitude,
        duration: KeryxTheme.settleDuration,
        curve: KeryxTheme.settleCurve,
      ),
    );
    _syncTicker();
  }

  void _syncTicker() {
    final needTick = !_motionOff &&
        (_level.isAnimating || _level.value > GrilleMotion.minAmplitude);
    if (needTick) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
      _freezeAtRest();
    }
  }

  void _freezeAtRest() {
    var changed = false;
    for (var i = 0; i < _scales.length; i++) {
      if (_scales[i] != 1) {
        _scales[i] = 1;
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    if (_motionOff) {
      _freezeAtRest();
      return;
    }
    final amp = _level.value;
    final elapsedMs = elapsed.inMicroseconds / 1000.0;
    final rng = widget.random ?? _random;
    for (var i = 0; i < GrilleMotion.barCount; i++) {
      _scales[i] = GrilleMotion.scaleY(
        amplitude: amp,
        barIndex: i,
        elapsedMs: elapsedMs,
        jitter: GrilleMotion.sampleJitter(rng),
      );
    }
    if (mounted) setState(() {});
    if (!_level.isAnimating && amp <= GrilleMotion.minAmplitude) {
      _syncTicker();
    }
  }

  @override
  Widget build(BuildContext context) {
    final slotColor = widget.live ? _slotLive : _slotIdle;
    return Semantics(
      container: true,
      label: widget.live ? 'Speaker grille, receiving' : 'Speaker grille',
      child: RepaintBoundary(
        child: DecoratedBox(
          key: const Key('keryx-grille-shell'),
          decoration: BoxDecoration(
            color: KeryxTheme.shell900,
            borderRadius: BorderRadius.circular(KeryxTheme.grid),
            boxShadow: <BoxShadow>[
              ...KeryxTheme.raisedMaterialEdges,
              const BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.6),
                offset: Offset(0, 6),
                blurRadius: 14,
                blurStyle: BlurStyle.inner,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _padH,
              vertical: _padV,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var i = 0; i < GrilleMotion.barCount; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: _barGap),
                  Transform.scale(
                    key: Key('keryx-grille-bar-$i'),
                    scaleY: _scales[i],
                    child: DecoratedBox(
                      key: Key('keryx-grille-slot-$i'),
                      decoration: BoxDecoration(
                        color: slotColor,
                        borderRadius: BorderRadius.circular(_barRadius),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color.fromRGBO(255, 255, 255, 0.045),
                            offset: Offset(0, 1),
                            blurRadius: 0,
                            blurStyle: BlurStyle.inner,
                          ),
                        ],
                      ),
                      child: const SizedBox(
                        height: _barHeight,
                        width: double.infinity,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
