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

  int get germinateDaysMin => (germinateHoursMin / 24).floor();

  int get germinateDaysMax => (germinateHoursMax / 24).ceil();

  /// Conservative cycle length (upper bounds) for harvest ETA.
  Duration get cycleDuration {
    final soak = soakHoursMax ?? soakHoursMin ?? 0;
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

  int get soakHoursForTiming => soakHoursMax ?? soakHoursMin ?? 0;

  int get germinateHoursForTiming => germinateHoursMax;

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
    return '${_hoursLabel(min)}–${_hoursLabel(max)}';
  }

  String get germinateLabel {
    if (!hasGerminateStage) return 'Не нужно';
    final min = germinateHoursMin;
    final max = germinateHoursMax;
    if (min == max) return _hoursOrDaysLabel(min);
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

  /// Elapsed time from a full cycle start until [stage] begins.
  Duration elapsedBeforeStage(GrowthStage stage) {
    return switch (stage) {
      GrowthStage.soak => Duration.zero,
      GrowthStage.germinate => Duration(hours: soakHoursForTiming),
      GrowthStage.grow || GrowthStage.harvest => Duration(
          hours: soakHoursForTiming + germinateHoursForTiming,
        ),
    };
  }

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
    this.notes = '',
  }) : stageChangedAt = stageChangedAt ?? startedAt;

  final String id;
  final String plantId;
  final DateTime startedAt;
  DateTime lastWateredAt;
  GrowthStage stage;
  DateTime stageChangedAt;
  String notes;

  /// First stage when starting a new tray.
  static GrowthStage initialStageFor(Plant plant) =>
      plant.processStages.firstWhere(
        (s) => s != GrowthStage.harvest,
        orElse: () => GrowthStage.harvest,
      );

  Duration elapsed(DateTime now) => now.difference(startedAt);

  DateTime harvestAt(Plant plant) => startedAt.add(plant.cycleDuration);

  /// Calendar days until harvest date. <= 0 means harvest today (or overdue).
  int daysUntilHarvest(Plant plant, DateTime now) {
    final h = harvestAt(plant);
    final harvestDay = DateTime(h.year, h.month, h.day);
    final today = DateTime(now.year, now.month, now.day);
    return harvestDay.difference(today).inDays;
  }

  /// Stored stage (manual). [now] kept for call-site compatibility.
  GrowthStage stageFor(Plant plant, DateTime now) => stage;

  List<GrowthStage> processStages(Plant plant) => plant.processStages;

  double progressFor(Plant plant, DateTime now) {
    final stages = processStages(plant);
    if (stages.isEmpty) return 1;
    final index = stages.indexOf(stage);
    if (index < 0) return 0;
    return ((index + 1) / stages.length).clamp(0.0, 1.0);
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

  /// Label for the primary action button on the current stage.
  String nextActionLabel(Plant plant) {
    if (completesNext(plant)) return 'Собрать';
    final stages = processStages(plant);
    final index = stages.indexOf(stage);
    final next = stages[index + 1];
    return switch (next) {
      GrowthStage.germinate => 'Посадить',
      GrowthStage.grow =>
        stage == GrowthStage.soak ? 'Посадить' : 'На свет',
      GrowthStage.harvest => 'Собрать',
      GrowthStage.soak => 'Посадить',
    };
  }

  /// True when the next action finishes the tray (remove from active).
  bool completesNext(Plant plant) {
    final stages = processStages(plant);
    final index = stages.indexOf(stage);
    if (index < 0) return true;
    return index >= stages.length - 2;
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

  String titleWithDate(Plant plant) {
    final date = formatStartDate(startedAt).replaceAll('.', '');
    return '${plant.name} от $date';
  }

  /// Compact title for notifications: `Горох от 8авг.`
  String titleCompact(Plant plant) =>
      '${plant.name} от ${formatStartDateCompact(startedAt)}';

  /// Reminder for the next manual step, based on time spent in current stage.
  List<DueAction> dueActions(Plant plant) {
    final (kind, at) = switch (stage) {
      GrowthStage.soak => (
          DueActionKind.sow,
          stageChangedAt.add(Duration(hours: plant.soakHoursForTiming)),
        ),
      GrowthStage.germinate => (
          DueActionKind.toLight,
          stageChangedAt
              .add(Duration(hours: plant.germinateHoursForTiming)),
        ),
      GrowthStage.grow || GrowthStage.harvest => (
          DueActionKind.harvest,
          stageChangedAt.add(Duration(days: plant.growDays)),
        ),
    };
    return [DueAction(kind: kind, at: at)];
  }

  /// Reminder text if [action] falls on calendar day of [now], else null.
  String? notificationIfDueToday(Plant plant, DueAction action, DateTime now) {
    if (_calendarDaysUntil(action.at, now) != 0) return null;
    return '${titleCompact(plant)} ${action.message}';
  }

  /// Absolute soak push time from culture soak duration after stage start.
  DateTime soakReminderAt(Plant plant) =>
      stageChangedAt.add(Duration(hours: plant.soakHoursForTiming));

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
      GrowthStage.harvest => 'К срезке',
    };
  }

  /// Relative time: сегодня / завтра / через N дней.
  static String whenPhrase(int days) {
    if (days <= 0) return 'сегодня';
    if (days == 1) return 'завтра';
    return 'через $days ${Plant._dayWord(days)}';
  }

  /// Status under the title — current stage only (no auto time jumps).
  String statusLine(Plant plant, DateTime now) {
    final verb = stageVerb(plant, now);
    return switch (stage) {
      GrowthStage.soak => '$verb. Дальше — посадка',
      GrowthStage.germinate => '$verb. Дальше — на свет',
      GrowthStage.grow => '$verb. Проверить воду',
      GrowthStage.harvest => '$verb. Можно собирать',
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'plantId': plantId,
        'startedAt': startedAt.toIso8601String(),
        'lastWateredAt': lastWateredAt.toIso8601String(),
        'stage': stage.name,
        'stageChangedAt': stageChangedAt.toIso8601String(),
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
    return GardenPlant(
      id: json['id'] as String,
      plantId: json['plantId'] as String,
      startedAt: started,
      lastWateredAt: DateTime.parse(json['lastWateredAt'] as String),
      stage: stage,
      stageChangedAt:
          stageChangedRaw != null ? DateTime.parse(stageChangedRaw) : started,
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
    final soakEnd = plant.soakHoursForTiming;
    final germEnd = soakEnd + plant.germinateHoursForTiming;
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
      GrowthStage.grow => 'Выращивание',
      GrowthStage.harvest => 'К срезке',
    };

enum DueActionKind { sow, toLight, harvest }

class DueAction {
  const DueAction({required this.kind, required this.at});

  final DueActionKind kind;
  final DateTime at;

  String get message => switch (kind) {
        DueActionKind.sow => 'Пора посеять.',
        DueActionKind.toLight => 'Пора на свет.',
        DueActionKind.harvest => 'Время собирать урожай!',
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
