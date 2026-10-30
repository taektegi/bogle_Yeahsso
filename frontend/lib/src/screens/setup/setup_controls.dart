part of '../setup_friend_screen.dart';

// Setup's pieces: the question prompt, the rising and hopping entrances, the
// buttons, the record button and the answer cards.

/// Figma 584:2306 / 585:2379: the question in 36 pt 양진체 (#333, -3 %), and
/// above it a hint in 24 pt 양진체 grey (#AAA), each on a 40 pt line, all
/// times [scale].
class _Prompt extends StatelessWidget {
  const _Prompt({
    super.key,
    required this.lead,
    required this.title,
    this.scale = 1,
  });
  final String? lead;
  final String title;
  final double scale;

  static const height = 92.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.max(
      height * scale,
      (lead == null ? 40 : 85) *
          scale *
          MediaQuery.textScalerOf(context).scale(1),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (lead != null) ...[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              lead!,
              maxLines: 1,
              style: TextStyle(
                fontFamily: bogleQuestionFont,
                fontSize: 24 * scale,
                height: 40 / 24,
                letterSpacing: -0.72 * scale,
                color: const Color(0xFFAAAAAA),
              ),
            ),
          ),
          SizedBox(height: 5 * scale),
        ],
        Semantics(
          header: true,
          // One line; a long name shrinks it rather than wrapping.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              maxLines: 1,
              style: TextStyle(
                fontFamily: bogleQuestionFont,
                fontSize: 36 * scale,
                height: 40 / 36,
                letterSpacing: -1.08 * scale,
                color: BogleColors.text,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Figma motion note: "모든 버튼 아래서/옆에서 올라오기" — every button
/// rises in from below (or slides in from the side), one after another.
class _Rise extends StatefulWidget {
  const _Rise({
    required this.child,
    this.index = 0,
    this.from = const Offset(0, .8),
  });
  final Widget child;
  final int index;
  final Offset from;
  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  static const _step = 60, _run = 420;
  late final _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _run + widget.index * _step),
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.index * _step / (_run + widget.index * _step),
      1,
      curve: Curves.easeOutBack,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    builder: (context, child) => FractionalTranslation(
      translation: widget.from * (1 - _curve.value),
      child: Opacity(opacity: _curve.value.clamp(0.0, 1.0), child: child),
    ),
    child: widget.child,
  );
}

/// A small bounce each time the friend hears a new question.
class _Hop extends StatelessWidget {
  const _Hop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 700),
    builder: (context, t, child) => Transform.translate(
      offset: Offset(0, -math.sin(t * math.pi) * 18),
      child: child,
    ),
    child: child,
  );
}

/// The app's rounded buttons with an icon: the answer buttons and the
/// "친구가 되었어요!" farewell.
class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 360,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 88),
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: filled ? BogleColors.logo : Colors.white,
          foregroundColor: filled ? Colors.white : BogleColors.logo,
          elevation: 0,
          padding: MediaQuery.textScalerOf(context).scale(1) > 1.2
              ? const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: filled
                ? BorderSide.none
                : const BorderSide(color: BogleColors.blueSoft, width: 2),
          ),
          textStyle: const TextStyle(
            fontFamily: bogleDisplayFont,
            fontSize: 24,
          ),
        ),
        icon: Icon(icon, size: 28),
        label: Text(label, textAlign: TextAlign.center),
      ),
    ),
  );
}

/// Figma 584:2274's answer buttons: 402 × 88, corners 6, at 80 % (the
/// lettering stays solid), a soft 15 % shadow, 28 pt 양진체 — blue with
/// white lettering, or white with blue. Disabled, it fades back.
class _SettingButton extends StatelessWidget {
  const _SettingButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.scale = 1,
  });
  final String label;
  final bool filled;
  final VoidCallback? onTap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final corner = BorderRadius.circular(6 * scale);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: onTap == null ? .45 : 1,
      child: Container(
        width: 402 * scale,
        height: math.max(
          48,
          math.max(
            88 * scale,
            40 * scale * MediaQuery.textScalerOf(context).scale(1) + 20,
          ),
        ),
        decoration: BoxDecoration(borderRadius: corner, boxShadow: figmaShadow),
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: (filled ? BogleColors.logo : Colors.white)
                .withValues(alpha: .8),
            disabledBackgroundColor: (filled ? BogleColors.logo : Colors.white)
                .withValues(alpha: .8),
            foregroundColor: filled ? Colors.white : BogleColors.logo,
            disabledForegroundColor: filled ? Colors.white : BogleColors.logo,
            elevation: 0,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: corner),
            textStyle: TextStyle(
              fontFamily: bogleDisplayFont,
              fontSize: 28 * scale,
              height: 40 / 28,
              letterSpacing: -0.84 * scale,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
          ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatefulWidget {
  const _RecordButton({required this.listening, required this.onTap});
  final bool listening;
  final VoidCallback onTap;
  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didUpdateWidget(_RecordButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    if (widget.listening && !MediaQuery.disableAnimationsOf(context)) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        button: true,
        label: widget.listening ? '그만 듣기' : '말하기',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Container(
              width: 164,
              height: 164,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BogleColors.logo.withValues(
                  alpha: .35 + math.sin(_pulse.value * math.pi) * .2,
                ),
              ),
              child: Transform.scale(
                scale: 1 + math.sin(_pulse.value * math.pi) * .06,
                child: child,
              ),
            ),
            child: Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: BogleColors.logo,
              ),
              child: Icon(
                widget.listening ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 52,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        widget.listening ? '듣고 있어요. 다 말하면 눌러요' : '누르고 말해요',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: BogleColors.text,
        ),
      ),
    ],
  );
}

class _RoundChoice extends StatelessWidget {
  const _RoundChoice({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(
            side: BorderSide(color: BogleColors.blueSoft, width: 2),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 124,
              height: 124,
              child: Icon(icon, color: BogleColors.logo, size: 44),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: BogleColors.text,
        ),
      ),
    ],
  );
}

/// Goes on once an answer is chosen: a lavender pill as tall as the answer
/// cards, in their 양진체, with an arrow. Until then it isn't there (its
/// room is kept, so nothing moves when it comes), rather than a greyed
/// block asking to be pressed.
class _NextPill extends StatelessWidget {
  const _NextPill({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.scale = 1,
  });
  final String label;
  final VoidCallback? onTap;

  /// Pressed, and waiting on the service: shown, but not pressable again.
  final bool busy;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final shown = onTap != null || busy;
    const motion = Duration(milliseconds: 200);
    return IgnorePointer(
      ignoring: !shown,
      child: ExcludeSemantics(
        excluding: !shown,
        child: AnimatedOpacity(
          duration: motion,
          opacity: shown ? 1 : 0,
          child: AnimatedScale(
            duration: motion,
            curve: Curves.easeOutBack,
            scale: shown ? 1 : .85,
            child: Container(
              height: math.max(
                48,
                math.max(
                  60 * scale,
                  46.154 * scale * MediaQuery.textScalerOf(context).scale(1) +
                      12,
                ),
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x26000000),
                    blurRadius: 4.615 * scale,
                    spreadRadius: 1.154 * scale,
                  ),
                ],
              ),
              child: FilledButton(
                onPressed: busy ? null : onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: BogleColors.logo,
                  disabledBackgroundColor: BogleColors.logo,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: Size(180 * scale, 60 * scale),
                  padding: EdgeInsets.symmetric(horizontal: 32 * scale),
                  shape: const StadiumBorder(),
                  textStyle: TextStyle(
                    fontFamily: bogleDisplayFont,
                    fontSize: 22 * scale,
                    height: 1.2,
                    letterSpacing: -0.66 * scale,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label),
                    if (!busy) ...[
                      SizedBox(width: 10 * scale),
                      Icon(Icons.arrow_forward_rounded, size: 24 * scale),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma 563:2033's answer card: 203 × 60 (or [width] wide), white with
/// a 1 pt #8BA2FF outline, 23 pt corners and a soft 15 % shadow, the
/// answer in 19.6 pt 양진체 (#333); all times [scale]. Chosen, it fills
/// lavender with white lettering; not [enabled] (no more answers allowed),
/// it fades.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.width = 203,
    this.scale = 1,
  });
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final double width;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final corner = BorderRadius.circular(23.077 * scale);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : .45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: width * scale,
          height: math.max(
            48,
            math.max(
              60 * scale,
              46.154 * scale * MediaQuery.textScalerOf(context).scale(1) + 12,
            ),
          ),
          decoration: BoxDecoration(
            color: selected ? BogleColors.logo : Colors.white,
            borderRadius: corner,
            border: Border.all(color: BogleColors.logo),
            boxShadow: [
              BoxShadow(
                color: const Color(0x26000000),
                blurRadius: 4.615 * scale,
                spreadRadius: 1.154 * scale,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: corner,
              onTap: enabled ? onTap : null,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: bogleDisplayFont,
                        fontSize: 19.615 * scale,
                        height: 46.154 / 19.615,
                        letterSpacing: -0.5885 * scale,
                        color: selected ? Colors.white : BogleColors.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma 489:2142의 모서리 빛 번짐. 말투 단계에만 적용한다.
class _SpeechBackdrop extends StatelessWidget {
  const _SpeechBackdrop({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final (center, color) in [
          (const Alignment(1.15, -1.1), BogleColors.pink),
          (const Alignment(-1.1, 1.05), BogleColors.blueSoft),
          (const Alignment(1.05, 1.1), BogleColors.mint),
        ])
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: center,
                radius: .7,
                colors: [
                  color.withValues(alpha: .42),
                  color.withValues(alpha: 0),
                ],
                stops: const [0, 1],
              ),
            ),
          ),
        child,
      ],
    );
  }
}
