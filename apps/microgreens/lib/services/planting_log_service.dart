import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plant.dart';

/// Append-only planting log as a plain text file.
///
/// Primary working copy (always updated):
/// - Android: `Android/data/.../files/лог_посадок.txt` (USB)
/// - iOS: Documents / `лог_посадок.txt` (Files app)
/// - Desktop: Downloads
/// - Web: SharedPreferences (`planting_log_v1`)
///
/// On Android also mirrors the full file into public **Download/лог_посадок.txt**
/// so it can be opened/copied from the system Files app.
class PlantingLogService {
  PlantingLogService._();
  static final PlantingLogService instance = PlantingLogService._();

  static const fileName = 'лог_посадок.txt';
  static const _webPrefsKey = 'planting_log_v1';
  static const _channel = MethodChannel('com.agronizer.greengrow/device');
  static final _stamp = DateFormat('dd.MM.yyyy HH:mm');

  /// Optional override for tests.
  Directory? directoryOverride;

  Future<Directory?> _resolveDirectory() async {
    if (directoryOverride != null) return directoryOverride;
    if (kIsWeb) return null;
    try {
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectory();
        if (external != null) return external;
      }
      if (Platform.isIOS) {
        return getApplicationDocumentsDirectory();
      }
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
      return getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }

  Future<File?> logFile() async {
    final dir = await _resolveDirectory();
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  Future<String?> logFilePath() async {
    final file = await logFile();
    return file?.path;
  }

  /// Full log text (file or web prefs). Empty string if nothing stored.
  Future<String> readAllText() async {
    if (directoryOverride == null && kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_webPrefsKey) ?? '';
    }
    final file = await logFile();
    if (file == null || !await file.exists()) return '';
    try {
      await _migrateLegacyIfNeeded(file);
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  /// Move legacy internal `plantings_log.txt` into the visible file once.
  Future<void> _migrateLegacyIfNeeded(File target) async {
    if (await target.exists() && await target.length() > 0) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final legacy = File(
        '${docs.path}${Platform.pathSeparator}plantings_log.txt',
      );
      if (!await legacy.exists()) return;
      final text = await legacy.readAsString();
      if (text.isEmpty) return;
      await target.writeAsString(text, flush: true);
    } catch (_) {}
  }

  /// One CSV-like row:
  /// `11.08.2026 12:40;Горох от 11 авг (1 шт);старт;замачивание`
  Future<void> append({
    required String cycleName,
    required String action,
    required String stageOrComment,
    DateTime? at,
  }) async {
    final line =
        '${_stamp.format(at ?? DateTime.now())};$cycleName;$action;$stageOrComment\n';
    if (directoryOverride == null && kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final prev = prefs.getString(_webPrefsKey) ?? '';
        await prefs.setString(_webPrefsKey, prev + line);
      } catch (_) {}
      return;
    }
    final file = await logFile();
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await _migrateLegacyIfNeeded(file);
      await file.writeAsString(line, mode: FileMode.append, flush: true);
      await _mirrorToPublicDownloads(file);
    } catch (_) {
      // Best-effort log — never break garden actions.
    }
  }

  Future<void> _mirrorToPublicDownloads(File source) async {
    if (directoryOverride != null || kIsWeb || !Platform.isAndroid) return;
    try {
      final content = await source.readAsString();
      await _channel.invokeMethod<String>('writeDownloadsTextFile', {
        'name': fileName,
        'content': content,
      });
    } catch (_) {
      // MediaStore / permissions may fail on some devices.
    }
  }

  static String stageField(GrowthStage stage) => switch (stage) {
        GrowthStage.soak => 'замачивание',
        GrowthStage.germinate => 'проращивание',
        GrowthStage.grow => 'рост',
        GrowthStage.harvest => 'собрать',
      };
}
