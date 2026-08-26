import 'dart:math' as math;
import 'dart:async' as async;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../models/plant.dart';
import '../services/reminder_service.dart';
import '../state/access_store.dart';
import '../state/garden_store.dart';
import '../state/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/common_widgets.dart';
import '../widgets/stage_icons.dart';
import '../widgets/trial_access_card.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.settings,
    required this.access,
    required this.onAddPlant,
  });

  final GardenStore store;
  final SettingsStore settings;
  final AccessStore access;
  final VoidCallback onAddPlant;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  OverlayEntry? _celebrateEntry;
  var _celebrating = false;

  @override
  void dispose() {
    _celebrateEntry?.remove();
    _celebrateEntry = null;
    super.dispose();
  }

  List<TodayReminderItem> get _reminders {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return ReminderService.buildTodayReminders(
      plants: widget.store.plants,
      day: day,
      dismissedKeys: widget.settings.dismissedReminderKeys,
      now: now,
    );
  }

  Future<void> _markDone(TodayReminderItem item) async {
    if (item.done) return;
    try {
      if (item.kind == DueActionKind.harvest) {
        _showCelebrate();
      }
      final undo = await widget.store.completeReminderAction(
        kind: item.kind,
        gardenId: item.gardenId,
      );
      await widget.settings.dismissReminder(item.key);
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      final controller = messenger.showSnackBar(
        SnackBar(
          content: Text(item.title),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          dismissDirection: DismissDirection.down,
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () async {
              await widget.settings.restoreReminder(item.key);
              if (undo != null) {
                await widget.store.undoReminderAction(undo);
              }
            },
          ),
        ),
      );
      // Accessibility / some platforms ignore SnackBar.duration when an
      // action is present — force close after 3s.
      async.unawaited(
        Future<void>.delayed(const Duration(seconds: 3), () {
          controller.close();
        }),
      );
    } catch (e, st) {
      if (!mounted) return;
      debugPrint('HomeScreen: mark reminder failed: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось обновить напоминание.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showCelebrate() {
    setState(() => _celebrating = true);
    _celebrateEntry?.remove();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: IgnorePointer(
          child: _CelebrateBurst(
            onFinished: () {
              if (_celebrateEntry == entry) {
                _celebrateEntry = null;
                entry.remove();
              }
              if (mounted) setState(() => _celebrating = false);
            },
          ),
        ),
      ),
    );
    _celebrateEntry = entry;
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          widget.store,
          widget.settings,
          widget.access,
        ]),
        builder: (context, _) {
          final reminders = _reminders;
          final showAccess = widget.access.trialEndsAt != null ||
              widget.access.paidExpiresAt != null;
          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      children: [
                        const BrandLogo(),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.leaf,
                              foregroundColor: Colors.white,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            onPressed: widget.onAddPlant,
                            icon: const Icon(Icons.add_rounded, size: 26),
                            label: const Text('Выращивать'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Выберите вид микрозелени и дату старта',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 18),
                        SoftPanel(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SettingsScreen(
                                  settings: widget.settings,
                                ),
                              ),
                            );
                          },
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                widget.settings.enabled
                                    ? Icons.notifications_active_rounded
                                    : Icons.notifications_off_outlined,
                                color: widget.settings.enabled
                                    ? AppColors.meadow
                                    : AppColors.muted,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Настройки уведомлений',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Text(
                                      widget.settings.enabled
                                          ? 'Ежедневно в ${widget.settings.reminderTimeLabel}'
                                          : 'Выключены · нажмите, чтобы настроить',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.forest,
                              ),
                            ],
                          ),
                        ),
                        if (reminders.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(
                            'Напоминания на сегодня',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          for (final item in reminders)
                            _ReminderTile(
                              item: item,
                              onMarkDone: item.done
                                  ? null
                                  : () => async.unawaited(_markDone(item)),
                            ),
                        ],
                      ],
                    ),
                    if (_celebrating && _celebrateEntry == null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _CelebrateBurst(
                            onFinished: () {
                              if (mounted) {
                                setState(() => _celebrating = false);
                              }
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (showAccess)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: TrialAccessCard(
                    key: const ValueKey('trial-access'),
                    access: widget.access,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.item,
    this.onMarkDone,
  });

  final TodayReminderItem item;
  final VoidCallback? onMarkDone;

  @override
  Widget build(BuildContext context) {
    final done = item.done;
    final titleStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: done ? AppColors.muted : AppColors.ink,
          height: 1.35,
          decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
        );
    final actionStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: done ? AppColors.muted : AppColors.forest,
          height: 1.3,
          decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: StageGlyph(
              kind: reminderGlyphKind(item.kind),
              color: done ? AppColors.muted : AppColors.meadow,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: titleStyle),
                Text(item.actionLabel, style: actionStyle),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: done ? 'Выполнено' : 'Отметить выполненным',
            child: InkWell(
              onTap: onMarkDone,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: _ReminderCheck(done: done),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderCheck extends StatelessWidget {
  const _ReminderCheck({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.meadow : Colors.transparent,
        border: Border.all(
          color: done ? AppColors.meadow : AppColors.muted,
          width: 2,
        ),
      ),
      child: done
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }
}

class _CelebrateBurst extends StatefulWidget {
  const _CelebrateBurst({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_CelebrateBurst> createState() => _CelebrateBurstState();
}

class _CelebrateBurstState extends State<_CelebrateBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiPiece> _pieces;
  var _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      })
      ..forward();
    _pieces = _ConfettiPiece.burst(DateTime.now().microsecondsSinceEpoch);
    Future<void>.delayed(const Duration(milliseconds: 2400), _finish);
  }

  @override
  void dispose() {
    _finished = true;
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    if (!mounted || _finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _ConfettiPainter(
                  pieces: _pieces,
                  t: Curves.easeOut.transform(_controller.value),
                ),
                size: Size.infinite,
              ),
              Lottie.asset(
                'assets/celebrate.json',
                repeat: false,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    const SizedBox.shrink(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConfettiPiece {
  const _ConfettiPiece({
    required this.x,
    required this.drift,
    required this.size,
    required this.color,
    required this.spin,
    required this.kind,
    required this.delay,
  });

  final double x;
  final double drift;
  final double size;
  final Color color;
  final double spin;
  final int kind;
  final double delay;

  static const _colors = [
    AppColors.sun,
    AppColors.meadow,
    AppColors.sprout,
    AppColors.leaf,
    AppColors.water,
    Color(0xFFE76F51),
    Color(0xFFF4A261),
  ];

  static List<_ConfettiPiece> burst(int seed) {
    final rng = _Lcg(seed);
    return List.generate(56, (i) {
      return _ConfettiPiece(
        x: rng.next(),
        drift: (rng.next() - 0.5) * 0.35,
        size: 7 + rng.next() * 11,
        color: _colors[rng.nextInt(_colors.length)],
        spin: (rng.next() - 0.5) * 8,
        kind: rng.nextInt(3),
        delay: rng.next() * 0.22,
      );
    });
  }
}

class _Lcg {
  _Lcg(int seed) : _state = seed & 0x7fffffff;
  int _state;
  double next() {
    _state = (1103515245 * _state + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }

  int nextInt(int max) => (next() * max).floor().clamp(0, max - 1);
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.pieces, required this.t});

  final List<_ConfettiPiece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final local = ((t - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final fall = Curves.easeIn.transform(local);
      final x = (piece.x + piece.drift * local) * size.width;
      final y = -24 + fall * (size.height + 48);
      final opacity = (1 - local * 0.35).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = piece.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(piece.spin * local);
      if (piece.kind == 0) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: piece.size,
            height: piece.size * 0.55,
          ),
          paint,
        );
      } else if (piece.kind == 1) {
        canvas.drawCircle(Offset.zero, piece.size * 0.42, paint);
      } else {
        _drawStar(canvas, piece.size * 0.55, paint);
      }
      canvas.restore();
    }
  }

  void _drawStar(Canvas canvas, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final a = -1.5708 + i * 1.2566;
      final p = Offset(r * math.cos(a), r * math.sin(a));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      final b = a + 0.6283;
      path.lineTo(r * 0.45 * math.cos(b), r * 0.45 * math.sin(b));
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.t != t;
}
