enum Difficulty { easy, medium, hard }

enum GrowthStage { soak, germinate, grow, harvest }

class Plant {
  const Plant({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.difficulty,
    required this.seedGrams,
    this.soakHoursMin,
    this.soakHoursMax,
    required this.germinateHoursMin,
    required this.germinateHoursMax,
    this.pressKgMin,
    this.pressKgMax,
    this.growDaysMin,
    required this.growDays,
    required this.light,
    required this.temperature,
    required this.soil,
    required this.tips,
    required this.tags,
    this.feature,
  });

  final String id;
  final String name;
  final String description;
  final String icon;
  final Difficulty difficulty;

  /// Seed weight for a 13×18 tray, grams.
  final int seedGrams;

  /// Hours of soaking. Both null = no soak stage.
  final int? soakHoursMin;
  final int? soakHoursMax;

  /// Germination under lid in the dark (hours). 0 = skip dark stage.
  final int germinateHoursMin;
  final int germinateHoursMax;

  /// Optional tray press weight during germination (kg).
  final double? pressKgMin;
  final double? pressKgMax;

  /// Growing on light without lid (days). 0 = no light stage (dark-only).
  final int? growDaysMin;
  final int growDays;

  final String light;
  final String temperature;
  final String soil;
  final List<String> tips;
  final List<String> tags;

  /// Extra note from the cultivation table.
  final String? feature;

  bool get needsSoak => soakHoursMin != null;

  bool get needsPress => pressKgMin != null;

  bool get hasGerminateStage => germinateHoursMax > 0;

  bool get hasGrowStage => growDays > 0;

  int get growDaysLow => growDaysMin ?? growDays;

  int get germinateDaysMin => (germinateHoursForTiming / 24).floor();

  int get germinateDaysMax => (germinateHoursMax / 24).ceil();

  /// Earliest cycle length (lower bounds) — used for reminders.
  Duration get cycleDurationMin {
    final soak = soakHoursForTiming;
    return Duration(
      hours: soak + germinateHoursForTiming + growDaysLow * 24,
    );
  }

  /// Full cycle length (upper bounds) — used for progress bar.
  Duration get cycleDuration {
    final soak = soakHoursMaxTiming;
    return Duration(hours: soak + germinateHoursMax + growDays * 24);
  }

  int get daysToHarvest => germinateDaysMax + growDays;

  int get daysToHarvestMin => germinateDaysMin + growDaysLow;

  String get cycleDaysLabel {
    final min = daysToHarvestMin;
    final max = daysToHarvest;
    if (min <= 0 && max <= 0) return '—';
    if (min == max) return '$max дн.';
    return '$min–$max дн.';
  }

  /// Minimum hours for reminder timing (prefer catalog lower bound).
  int get soakHoursForTiming => soakHoursMin ?? soakHoursMax ?? 0;

  int get soakHoursMaxTiming => soakHoursMax ?? soakHoursMin ?? 0;

  /// Prefer min; if min is 0 but stage exists, fall back to max.
  int get germinateHoursForTiming =>
      germinateHoursMin > 0 ? germinateHoursMin : germinateHoursMax;

  int get germinateHoursMaxTiming => germinateHoursMax;

  String get difficultyLabel => switch (difficulty) {
        Difficulty.easy => 'Легко',
        Difficulty.medium => 'Средне',
        Difficulty.hard => 'Сложно',
      };

  String get soakLabel {
    if (!needsSoak) return 'Не нужно';
    final min = soakHoursMin!;
    final max = soakHoursMax ?? min;
    if (min == max) return _hoursLabel(min);
    if (min % 24 == 0 && max % 24 == 0 && min >= 24) {
      final dMin = min ~/ 24;
      final dMax = max ~/ 24;
      return '$dMin–$dMax ${_dayWord(dMax)}';
    }
    return '${_hoursLabel(min)}–${_hoursLabel(max)}';
  }

  String get germinateLabel {
    if (!hasGerminateStage) return 'Не нужно';
    final min = germinateHoursMin;
    final max = germinateHoursMax;
    if (min == max) return _hoursOrDaysLabel(min);
    if (min >= 24 && max >= 24 && min % 24 == 0 && max % 24 == 0) {
      final dMin = min ~/ 24;
      final dMax = max ~/ 24;
      return '$dMin–$dMax ${_dayWord(dMax)}';
    }
    if (min == 0 && max >= 24 && max % 24 == 0) {
      final dMax = max ~/ 24;
      return 'до $dMax ${_dayWord(dMax)}';
    }
    return '${_hoursOrDaysLabel(min)}–${_hoursOrDaysLabel(max)}';
  }

  String get pressLabel {
    if (!needsPress) return 'Без прижима (под плёнкой/крышкой)';
    final min = pressKgMin!;
    final max = pressKgMax ?? min;
    if (min == max) return '${_kg(min)} кг';
    return '${_kg(min)}–${_kg(max)} кг';
  }

  String get growLabel {
    if (!hasGrowStage) return 'Не нужно';
    final min = growDaysLow;
    if (min == growDays) return '$growDays ${_dayWord(growDays)}';
    return '$min–$growDays ${_dayWord(growDays)}';
  }

  /// Stages in the cultivation process (skips empty ones).
  List<GrowthStage> get processStages => [
        if (needsSoak) GrowthStage.soak,
        if (hasGerminateStage) GrowthStage.germinate,
        if (hasGrowStage) GrowthStage.grow,
        GrowthStage.harvest,
      ];

  /// Stages the user can pick when starting tracking mid-cycle.
  List<GrowthStage> get startableStages => [
        if (needsSoak) GrowthStage.soak,
        if (hasGerminateStage) GrowthStage.germinate,
        if (hasGrowStage) GrowthStage.grow,
      ];

  /// Elapsed time from a full cycle start until [stage] begins (upper bounds).
  Duration elapsedBeforeStage(GrowthStage stage) {
    return switch (stage) {
      GrowthStage.soak => Duration.zero,
      GrowthStage.germinate => Duration(hours: soakHoursMaxTiming),
      GrowthStage.grow || GrowthStage.harvest => Duration(
          hours: soakHoursMaxTiming + germinateHoursMaxTiming,
        ),
    };
  }

  /// Planned duration of [stage] in hours for progress (upper bound).
  int stageDurationHours(GrowthStage stage) => switch (stage) {
        GrowthStage.soak => soakHoursMaxTiming,
        GrowthStage.germinate => germinateHoursMaxTiming,
        GrowthStage.grow => growDays * 24,
        GrowthStage.harvest => 0,
      };

  /// Lower-bound duration of [stage] for reminder timing.
  int stageDurationHoursMin(GrowthStage stage) => switch (stage) {
        GrowthStage.soak => soakHoursForTiming,
        GrowthStage.germinate => germinateHoursForTiming,
        GrowthStage.grow => growDaysLow * 24,
        GrowthStage.harvest => 0,
      };

  /// Catalog range label for the current stage duration.
  String stageRangeLabel(GrowthStage stage) => switch (stage) {
        GrowthStage.soak => soakLabel,
        GrowthStage.germinate => germinateLabel,
        GrowthStage.grow => growLabel,
        GrowthStage.harvest => 'Готово',
      };

  String stageDurationLabel(GrowthStage stage) => switch (stage) {
        GrowthStage.soak => soakLabel,
        GrowthStage.germinate => germinateLabel,
        GrowthStage.grow => growLabel,
        GrowthStage.harvest => 'Готово',
      };

  String stageHint(GrowthStage stage) => switch (stage) {
        GrowthStage.soak => 'Семена ещё в воде',
        GrowthStage.germinate => needsPress
            ? 'В темноте под крышкой, с прижимом'
            : 'В темноте под плёнкой/крышкой',
        GrowthStage.grow => 'Уже на свету, без крышки',
        GrowthStage.harvest => 'Пора срезать',
      };

  static String _kg(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : v.toString();

  static String _hoursLabel(int hours) {
    if (hours % 24 == 0 && hours >= 24) {
      final d = hours ~/ 24;
      return '$d ${_dayWord(d)}';
    }
    return '$hours ${_hourWord(hours)}';
  }

  static String elapsedHoursLabel(int hours) {
    final n = hours < 0 ? 0 : hours;
    return '$n ${_hourWord(n)}';
  }

  static String _hoursOrDaysLabel(int hours) {
    if (hours >= 24 && hours % 24 == 0) {
      final d = hours ~/ 24;
      return '$d ${_dayWord(d)}';
    }
    if (hours >= 24) {
      final d = hours / 24;
      final text = d == d.roundToDouble() ? '${d.toInt()}' : d.toStringAsFixed(1);
      return '$text ${_dayWordApprox(d)}';
    }
    return '$hours ${_hourWord(hours)}';
  }

  static String _hourWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'часов';
    if (mod10 == 1) return 'час';
    if (mod10 >= 2 && mod10 <= 4) return 'часа';
    return 'часов';
  }

  static String _dayWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'дней';
    if (mod10 == 1) return 'день';
    if (mod10 >= 2 && mod10 <= 4) return 'дня';
    return 'дней';
  }

  static String _dayWordApprox(double d) {
    if (d == 1) return 'день';
    if (d > 1 && d < 5) return 'дня';
    return 'дней';
  }
}

class GardenPlant {
  GardenPlant({
    required this.id,
    required this.plantId,
    required this.startedAt,
    required this.lastWateredAt,
    required this.stage,
    DateTime? stageChangedAt,
    DateTime? createdAt,
    this.customName,
    this.seedGrams,
    this.notes = '',
  })  : stageChangedAt = stageChangedAt ?? startedAt,
        createdAt = createdAt ?? startedAt;

  final String id;
  final String plantId;
  final DateTime startedAt;
  DateTime lastWateredAt;
  GrowthStage stage;
  DateTime stageChangedAt;
  /// When the tray was added to the app. Differs from [startedAt] if dated back.
  final DateTime createdAt;
  String? customName;
  int? seedGrams;
  String notes;

  /// First stage when starting a new tray.
  static GrowthStage initialStageFor(Plant plant) =>
      plant.processStages.firstWhere(
        (s) => s != GrowthStage.harvest,
        orElse: () => GrowthStage.harvest,
      );

  Duration elapsed(DateTime now) => now.difference(startedAt);

  double elapsedHoursInStage(DateTime now) =>
      now.difference(stageChangedAt).inMinutes / 60.0;

  /// Hours left in the current stage (0 if already past the planned bound).
  double remainingHoursInCurrentStage(
    Plant plant,
    DateTime now, {
    required bool useMax,
  }) {
    final planned = useMax
        ? plant.stageDurationHours(stage).toDouble()
        : plant.stageDurationHoursMin(stage).toDouble();
    final left = planned - elapsedHoursInStage(now);
    return left > 0 ? left : 0;
  }

  /// Later stages after the current one (full planned durations).
  int hoursOfFollowingStages(Plant plant, {required bool useMax}) {
    final stages = processStages(plant);
    final index = stages.indexOf(stage);
    if (index < 0) return 0;
    var hours = 0;
    for (var i = index + 1; i < stages.length; i++) {
      final s = stages[i];
      if (s == GrowthStage.harvest) break;
      hours += useMax
          ? plant.stageDurationHours(s)
          : plant.stageDurationHoursMin(s);
    }
    return hours;
  }

  /// Catalog hours from entering the current stage until harvest.
  int plannedHoursUntilHarvest(Plant plant, {required bool useMax}) {
    if (stage == GrowthStage.harvest) return 0;
    final current = useMax
        ? plant.stageDurationHours(stage)
        : plant.stageDurationHoursMin(stage);
    return current + hoursOfFollowingStages(plant, useMax: useMax);
  }

  /// Remaining hours until harvest from [now].
  double remainingHoursToHarvest(
    Plant plant,
    DateTime now, {
    required bool useMax,
  }) {
    final at = useMax ? harvestAt(plant, now) : harvestAtMin(plant, now);
    final hours = at.difference(now).inMinutes / 60.0;
    return hours > 0 ? hours : 0;
  }

  /// Upper-bound harvest instant: [stageChangedAt] + max of this and later stages.
  DateTime harvestAt(Plant plant, [DateTime? now]) => stageChangedAt.add(
        Duration(hours: plannedHoursUntilHarvest(plant, useMax: true)),
      );

  /// Earliest harvest: [stageChangedAt] + min of this and later stages.
  DateTime harvestAtMin(Plant plant, [DateTime? now]) => stageChangedAt.add(
        Duration(hours: plannedHoursUntilHarvest(plant, useMax: false)),
      );

  /// Calendar days until harvest date (upper bound). <= 0 means today/overdue.
  int daysUntilHarvest(Plant plant, DateTime now) {
    final h = harvestAt(plant, now);
    final harvestDay = DateTime(h.year, h.month, h.day);
    final today = DateTime(now.year, now.month, now.day);
    return harvestDay.difference(today).inDays;
  }

  int daysUntilHarvestMin(Plant plant, DateTime now) {
    final h = harvestAtMin(plant, now);
    final harvestDay = DateTime(h.year, h.month, h.day);
    final today = DateTime(now.year, now.month, now.day);
    return harvestDay.difference(today).inDays;
  }

  /// Stored stage (manual). [now] kept for call-site compatibility.
  GrowthStage stageFor(Plant plant, DateTime now) => stage;

  List<GrowthStage> processStages(Plant plant) => plant.processStages;

  /// Readiness from elapsed time since [startedAt], same clock as harvest dates.
  double progressFor(Plant plant, DateTime now) {
    if (stage == GrowthStage.harvest) return 1;

    final totalHours = plant.cycleDuration.inHours.toDouble();
    if (totalHours <= 0) return 1;

    final elapsedH = now.difference(startedAt).inMinutes / 60.0;
    return (elapsedH / totalHours).clamp(0.0, 1.0);
  }

  bool needsWater(Plant plant, DateTime now) {
    if (stage != GrowthStage.grow) return false;
    final last = DateTime(
      lastWateredAt.year,
      lastWateredAt.month,
      lastWateredAt.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    return today.isAfter(last);
  }

  /// Next process stage, or null when already at harvest.
  GrowthStage? nextStage(Plant plant) {
    final stages = processStages(plant);
    final index = stages.indexOf(stage);
    if (index < 0 || index >= stages.length - 1) return null;
    return stages[index + 1];
  }

  /// Planned due moment for leaving the current stage (catalog minimum).
  DateTime currentStageDueAtMin(Plant plant) {
    if (stage == GrowthStage.soak) return soakReminderAt(plant);
    return stageChangedAt.add(
      Duration(hours: plant.stageDurationHoursMin(stage)),
    );
  }

  /// `15 авг` — only the catalog minimum for this stage.
  String currentStageWhenPhrase(Plant plant, DateTime now) =>
      whenPhrase(_calendarDaysUntil(currentStageDueAtMin(plant), now), now);

  /// e.g. `Рост 15 авг`
  String nextPhaseLine(Plant plant, DateTime now) {
    final next = nextStage(plant);
    if (next == null) return 'Собрать';
    return '${stageLabel(next)} ${currentStageWhenPhrase(plant, now)}';
  }

  /// Status under the title:
  /// `Прошло 4ч - посеять сегодня с 16:00` /
  /// `посеять` when the sow time is already past /
  /// `Прорастает. На свет 16 авг` /
  /// `Растет. Собрать 15 авг. Проверить воду`
  String statusLine(Plant plant, DateTime now) {
    if (stage == GrowthStage.soak) return soakActionLabel(plant, now);
    final verb = stageVerb(plant, now);
    if (stage == GrowthStage.harvest) return verb;

    if (stage == GrowthStage.grow) {
      final when = whenPhrase(daysUntilHarvestMin(plant, now), now);
      var line = '$verb. Собрать $when';
      if (needsWater(plant, now)) {
        line = '$line. Проверить воду';
      }
      return line;
    }

    return '$verb. ${nextActionLabel(plant)} ${currentStageWhenPhrase(plant, now)}';
  }

  /// Harvest keeps a min–max range window.
  String harvestLine(Plant plant, DateTime now) {
    final minDays = daysUntilHarvestMin(plant, now);
    final maxDays = daysUntilHarvest(plant, now);
    return 'Урожай ${daysRangePhrase(minDays, maxDays, now)}';
  }

  /// Label for the primary action button on the current stage.
  String nextActionLabel(Plant plant) {
    if (completesNext(plant)) return 'Собрать';
    final stages = processStages(plant);
    final index = stages.indexOf(stage);
    final next = stages[index + 1];
    return switch (next) {
      GrowthStage.germinate => 'Посеять',
      GrowthStage.grow =>
        stage == GrowthStage.soak ? 'Посеять' : 'Раскрыть',
      GrowthStage.harvest => 'Собрать',
      GrowthStage.soak => 'Посеять',
    };
  }

  /// True when the next action finishes the tray (remove from active).
  bool completesNext(Plant plant) {
    final stages = processStages(plant);
    final index = stages.indexOf(stage);
    if (index < 0) return true;
    return index >= stages.length - 2;
  }

  /// True when the date shown in [statusLine] is today or overdue.
  bool isStatusActionDueToday(Plant plant, DateTime now) {
    if (stage == GrowthStage.harvest) return true;
    if (stage == GrowthStage.grow) {
      return daysUntilHarvestMin(plant, now) <= 0;
    }
    return _calendarDaysUntil(currentStageDueAtMin(plant), now) <= 0;
  }

  /// Advance to the next process stage. No-op at harvest.
  void advanceStage([Plant? plant]) {
    if (plant != null) {
      final stages = processStages(plant);
      final index = stages.indexOf(stage);
      if (index >= 0 && index < stages.length - 1) {
        stage = stages[index + 1];
      } else {
        stage = GrowthStage.harvest;
      }
    } else {
      stage = switch (stage) {
        GrowthStage.soak => GrowthStage.germinate,
        GrowthStage.germinate => GrowthStage.grow,
        GrowthStage.grow => GrowthStage.harvest,
        GrowthStage.harvest => GrowthStage.harvest,
      };
    }
    stageChangedAt = DateTime.now();
  }

  int _calendarDaysUntil(DateTime event, DateTime now) {
    final e = DateTime(event.year, event.month, event.day);
    final t = DateTime(now.year, now.month, now.day);
    return e.difference(t).inDays;
  }

  String displayName(Plant plant) {
    final custom = customName?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return plant.name;
  }

  String titleWithDate(Plant plant) {
    final date = formatStartDate(startedAt).replaceAll('.', '');
    return '${displayName(plant)} от $date';
  }

  /// Compact title for notifications: `Горох от 8авг.`
  String titleCompact(Plant plant) =>
      '${displayName(plant)} от ${formatStartDateCompact(startedAt)}';

  /// Next full hour at or after [t]. 7:33 → 8:00, 8:00 stays 8:00.
  static DateTime ceilToHour(DateTime t) {
    final hourStart = DateTime(t.year, t.month, t.day, t.hour);
    if (!t.isAfter(hourStart)) return hourStart;
    return hourStart.add(const Duration(hours: 1));
  }

  /// Reminder for the next manual step — fires at the catalog minimum.
  List<DueAction> dueActions(Plant plant) {
    final (kind, at) = switch (stage) {
      GrowthStage.soak => (DueActionKind.sow, soakReminderAt(plant)),
      GrowthStage.germinate => (
          DueActionKind.toLight,
          stageChangedAt
              .add(Duration(hours: plant.germinateHoursForTiming)),
        ),
      GrowthStage.grow || GrowthStage.harvest => (
          DueActionKind.harvest,
          harvestAtMin(plant),
        ),
    };
    return [DueAction(kind: kind, at: at)];
  }

  /// Home reminder: title, then lowercase action on the next line.
  String reminderLine(Plant plant, DueAction action) =>
      '${titleWithDate(plant)}\n${action.message}';

  /// Push text matches the home reminder.
  String pushLine(Plant plant, DueAction action) =>
      reminderLine(plant, action);

  /// Reminder text if [action] falls on calendar day of [now], else null.
  String? notificationIfDueToday(Plant plant, DueAction action, DateTime now) {
    if (_calendarDaysUntil(action.at, now) != 0) return null;
    return pushLine(plant, action);
  }

  /// Reveal/to-light push: catalog minimum hours after germinate start.
  DateTime germinateReminderAt(Plant plant) =>
      stageChangedAt.add(Duration(hours: plant.germinateHoursForTiming));

  /// Sow push: catalog min hours after soak start, rounded up to a full hour.
  DateTime soakReminderAt(Plant plant) => ceilToHour(stageChangedAt)
      .add(Duration(hours: plant.soakHoursForTiming));

  /// `Прошло 4ч - посеять сегодня с 16:00`. If sow time is already past: `посеять`.
  String soakActionLabel(Plant plant, DateTime now) {
    final due = soakReminderAt(plant);
    if (due.isBefore(now)) return 'посеять';
    final when = soakSowWhenLabel(plant, now);
    final elapsed =
        now.difference(stageChangedAt).inHours.clamp(0, 9999);
    if (elapsed <= 0) return when;
    return 'Прошло ${elapsed}ч - $when';
  }

  /// `посеять сегодня с 16:00`
  String soakSowWhenLabel(Plant plant, DateTime now) {
    final due = soakReminderAt(plant);
    final days = _calendarDaysUntil(due, now);
    final dayPart = days == 0
        ? 'сегодня'
        : days == 1
            ? 'завтра'
            : formatStartDate(DateTime(due.year, due.month, due.day))
                .replaceAll('.', '');
    return 'посеять $dayPart с ${due.hour}:00';
  }

  bool get isInGrowStage => stage == GrowthStage.grow;

  bool get isInGerminateStage => stage == GrowthStage.germinate;

  bool get isReadyToHarvestStage =>
      stage == GrowthStage.grow || stage == GrowthStage.harvest;

  /// Short live stage: Замачивается / Прорастает / Растет.
  String stageVerb(Plant plant, DateTime now) {
    return switch (stage) {
      GrowthStage.soak => 'Замачивается',
      GrowthStage.germinate => 'Прорастает',
      GrowthStage.grow => 'Растет',
      GrowthStage.harvest => 'Собрать',
    };
  }

  /// Relative day label: `19 авг`.
  static String whenPhrase(int days, [DateTime? now]) {
    final base = now ?? DateTime.now();
    final offset = days < 0 ? 0 : days;
    if (offset == 0) return 'сегодня';
    if (offset == 1) return 'завтра';

    final day = DateTime(base.year, base.month, base.day)
        .add(Duration(days: offset));
    return formatStartDate(day).replaceAll('.', '');
  }

  /// Range of dates: `16 авг–19 авг`.
  static String daysRangePhrase(int minDays, int maxDays, [DateTime? now]) {
    final at = now ?? DateTime.now();
    final min = minDays < maxDays ? minDays : maxDays;
    final max = minDays < maxDays ? maxDays : minDays;
    final a = whenPhrase(min, at);
    final b = whenPhrase(max, at);
    if (a == b) return a;
    return '$a–$b';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'plantId': plantId,
        'startedAt': startedAt.toIso8601String(),
        'lastWateredAt': lastWateredAt.toIso8601String(),
        'stage': stage.name,
        'stageChangedAt': stageChangedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        if (customName != null) 'customName': customName,
        if (seedGrams != null) 'seedGrams': seedGrams,
        'notes': notes,
      };

  factory GardenPlant.fromJson(Map<String, dynamic> json) {
    final started = DateTime.parse(
      json['startedAt'] as String? ??
          json['plantedAt'] as String? ??
          DateTime.now().toIso8601String(),
    );
    final stageName = json['stage'] as String?;
    final stage = stageName != null
        ? GrowthStage.values.byName(stageName)
        : GrowthStage.germinate;
    final stageChangedRaw = json['stageChangedAt'] as String?;
    final createdRaw = json['createdAt'] as String?;
    return GardenPlant(
      id: json['id'] as String,
      plantId: json['plantId'] as String,
      startedAt: started,
      lastWateredAt: DateTime.parse(json['lastWateredAt'] as String),
      stage: stage,
      stageChangedAt:
          stageChangedRaw != null ? DateTime.parse(stageChangedRaw) : started,
      createdAt: createdRaw != null ? DateTime.parse(createdRaw) : started,
      customName: json['customName'] as String?,
      seedGrams: json['seedGrams'] as int?,
      notes: json['notes'] as String? ?? '',
    );
  }

  /// Time-based stage for trays saved before manual progression.
  static GrowthStage legacyStageFor(
    Plant plant,
    DateTime startedAt,
    DateTime now,
  ) {
    final hours = now.difference(startedAt).inHours;
    final soakEnd = plant.soakHoursMaxTiming;
    final germEnd = soakEnd + plant.germinateHoursMaxTiming;
    final growEnd = germEnd + plant.growDays * 24;

    if (plant.needsSoak && hours < soakEnd) return GrowthStage.soak;
    if (hours < germEnd) return GrowthStage.germinate;
    if (hours < growEnd) return GrowthStage.grow;
    return GrowthStage.harvest;
  }
}

String stageLabel(GrowthStage stage) => switch (stage) {
      GrowthStage.soak => 'Замачивание',
      GrowthStage.germinate => 'Проращивание',
      GrowthStage.grow => 'Рост',
      GrowthStage.harvest => 'Собрать',
    };

enum DueActionKind { sow, toLight, harvest, water }

class DueAction {
  const DueAction({required this.kind, required this.at});

  final DueActionKind kind;
  final DateTime at;

  String get message => switch (kind) {
        DueActionKind.sow => 'посеять',
        DueActionKind.toLight => 'раскрыть',
        DueActionKind.harvest => 'собрать',
        DueActionKind.water => 'проверить воду',
      };
}

String formatStartDate(DateTime d) {
  const months = [
    'янв.',
    'фев.',
    'мар.',
    'апр.',
    'мая',
    'июн.',
    'июл.',
    'авг.',
    'сен.',
    'окт.',
    'ноя.',
    'дек.',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

/// Compact date for notifications: `4авг.`
String formatStartDateCompact(DateTime d) {
  const months = [
    'янв.',
    'фев.',
    'мар.',
    'апр.',
    'мая',
    'июн.',
    'июл.',
    'авг.',
    'сен.',
    'окт.',
    'ноя.',
    'дек.',
  ];
  return '${d.day}${months[d.month - 1]}';
}
