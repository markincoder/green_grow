import 'package:flutter/material.dart';

import '../data/plants_data.dart';
import '../services/harvest_stats.dart';
import '../services/tray_history_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/stage_icons.dart';

class HarvestStatsButton extends StatelessWidget {
  const HarvestStatsButton({super.key, this.size = 58});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Выращено',
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const HarvestStatsScreen(),
                ),
              );
            },
            customBorder: const CircleBorder(),
            child: Center(
              child: HarvestGlyph(size: size),
            ),
          ),
        ),
      ),
    );
  }
}

const _periodChips = <HarvestStatsPeriod>[
  HarvestStatsPeriod.all,
  HarvestStatsPeriod.custom,
];

class HarvestStatsScreen extends StatefulWidget {
  const HarvestStatsScreen({super.key});

  @override
  State<HarvestStatsScreen> createState() => _HarvestStatsScreenState();
}

class _HarvestStatsScreenState extends State<HarvestStatsScreen> {
  HarvestStatsPeriod _period = HarvestStatsPeriod.all;
  DateTime? _customFrom;
  DateTime? _customTo;
  DateTime? _firstHarvest;
  Future<List<HarvestStatRow>>? _future;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final records = await TrayHistoryStore.instance.allRecords();
    final savedPeriod = await HarvestStatsPrefs.loadPeriod();
    final savedRange = await HarvestStatsPrefs.loadCustomRange();
    final today = harvestStatsDay(DateTime.now());
    final first = firstHarvestDay(records) ?? today;
    var from = savedRange.$1 ?? first;
    var to = savedRange.$2 ?? today;
    if (from.isBefore(first)) from = first;
    if (from.isAfter(to)) from = to;
    if (to.isAfter(today)) to = today;
    if (!mounted) return;
    setState(() {
      _period = savedPeriod;
      _firstHarvest = first;
      _customFrom = from;
      _customTo = to;
      _ready = true;
      _reload();
    });
  }

  void _reload() {
    _future = _load();
  }

  Future<List<HarvestStatRow>> _load() async {
    final records = await TrayHistoryStore.instance.allRecords();
    return aggregateHarvestStats(
      records: records,
      range: harvestStatsRange(
        period: _period,
        now: DateTime.now(),
        customFrom: _customFrom,
        customTo: _customTo,
      ),
      nameOf: (id, fallback) => plantById(id)?.name ?? fallback,
      canonicalId: (id) => plantById(id)?.id ?? id,
    );
  }

  Future<void> _selectPeriod(HarvestStatsPeriod period) async {
    if (_period == period && period != HarvestStatsPeriod.custom) return;
    setState(() {
      _period = period;
      if (period == HarvestStatsPeriod.custom) {
        final today = harvestStatsDay(DateTime.now());
        _customFrom ??= _firstHarvest ?? today;
        _customTo ??= today;
      }
      _reload();
    });
    await HarvestStatsPrefs.savePeriod(period);
    if (period == HarvestStatsPeriod.custom &&
        _customFrom != null &&
        _customTo != null) {
      await HarvestStatsPrefs.saveCustomRange(_customFrom!, _customTo!);
    }
  }

  Future<void> _pickBound({required bool isFrom}) async {
    final today = harvestStatsDay(DateTime.now());
    final first = _firstHarvest ?? today;
    var from = harvestStatsDay(_customFrom ?? first);
    var to = harvestStatsDay(_customTo ?? today);
    final picked = await showAppDateWheel(
      context: context,
      title: isFrom ? 'От' : 'До',
      initialDate: isFrom ? from : to,
      minimumDate: first,
      maximumDate: today,
    );
    if (picked == null || !mounted) return;
    final day = harvestStatsDay(picked);
    if (isFrom) {
      from = day;
      if (from.isAfter(to)) to = from;
    } else {
      to = day;
      if (to.isBefore(from)) from = to;
    }
    await _applyRange(from, to);
  }

  Future<void> _jumpFromToStart() async {
    final today = harvestStatsDay(DateTime.now());
    final first = _firstHarvest ?? today;
    var to = harvestStatsDay(_customTo ?? today);
    if (first.isAfter(to)) to = first;
    await _applyRange(first, to);
  }

  Future<void> _jumpToToToday() async {
    final today = harvestStatsDay(DateTime.now());
    final first = _firstHarvest ?? today;
    var from = harvestStatsDay(_customFrom ?? first);
    if (from.isAfter(today)) from = today;
    await _applyRange(from, today);
  }

  Future<void> _applyRange(DateTime from, DateTime to) async {
    setState(() {
      _customFrom = from;
      _customTo = to;
      _reload();
    });
    await HarvestStatsPrefs.saveCustomRange(from, to);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Выращено'),
      ),
      body: !_ready
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.meadow),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _periodChips.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final period = _periodChips[index];
                        final selected = period == _period;
                        return FilterChip(
                          label: Text(harvestStatsPeriodLabel(period)),
                          selected: selected,
                          onSelected: (_) => _selectPeriod(period),
                          showCheckmark: false,
                          selectedColor: AppColors.leaf.withValues(alpha: 0.18),
                          labelStyle: TextStyle(
                            color: selected ? AppColors.forest : AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                          side: BorderSide(
                            color: selected
                                ? AppColors.leaf.withValues(alpha: 0.45)
                                : AppColors.mist,
                          ),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (_period == HarvestStatsPeriod.custom) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _DateBoundButton(
                            label: 'От',
                            shortcutLabel: 'начало',
                            onShortcut: _jumpFromToStart,
                            value: formatHarvestFilterDate(
                              _customFrom ?? _firstHarvest ?? DateTime.now(),
                            ),
                            onTap: () => _pickBound(isFrom: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DateBoundButton(
                            label: 'До',
                            shortcutLabel: 'сегодня',
                            onShortcut: _jumpToToToday,
                            value: formatHarvestFilterDate(
                              _customTo ?? DateTime.now(),
                            ),
                            onTap: () => _pickBound(isFrom: false),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<HarvestStatRow>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.meadow,
                          ),
                        );
                      }
                      final rows = snapshot.data ?? const <HarvestStatRow>[];
                      if (rows.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          child: SoftPanel(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              _period == HarvestStatsPeriod.all
                                  ? 'Пока нет собранных лотков.\nНажмите «Собрать» на Моей грядке.'
                                  : 'За этот период ничего не собрано.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        );
                      }
                      final total = harvestStatsTotal(rows);
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        children: [
                          Text(
                            harvestStatsTotalLabel(total),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          _HarvestBarChart(rows: rows),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _DateBoundButton extends StatelessWidget {
  const _DateBoundButton({
    required this.label,
    required this.value,
    required this.onTap,
    required this.shortcutLabel,
    required this.onShortcut,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final String shortcutLabel;
  final VoidCallback onShortcut;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.muted,
                      ),
                ),
              ),
              TextButton(
                onPressed: onShortcut,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.leaf,
                ),
                child: Text(shortcutLabel),
              ),
            ],
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HarvestBarChart extends StatelessWidget {
  const _HarvestBarChart({required this.rows});

  final List<HarvestStatRow> rows;

  @override
  Widget build(BuildContext context) {
    final maxCount = rows.fold<int>(
      0,
      (m, row) => row.trayCount > m ? row.trayCount : m,
    );

    return SoftPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _HarvestBarRow(
              row: rows[i],
              maxCount: maxCount,
              color: harvestStatsBarColor(i),
            ),
            if (i < rows.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _HarvestBarRow extends StatelessWidget {
  const _HarvestBarRow({
    required this.row,
    required this.maxCount,
    required this.color,
  });

  final HarvestStatRow row;
  final int maxCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = harvestStatsBarFraction(row.trayCount, maxCount);

    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            row.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '${row.trayCount}',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.forest,
                ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final fill = (maxW * fraction).clamp(10.0, maxW);
              return SizedBox(
                height: 22,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.mist.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const SizedBox.expand(),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        width: fill,
                        height: 22,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
