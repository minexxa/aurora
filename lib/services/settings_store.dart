import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aurora/models/virt_key_def.dart';

enum AppThemeMode { system, light, dark }

/// 应用设置。
class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  static const _themeKey = 'theme_mode';
  static const _fontSizeKey = 'font_size';
  static const _virtKeysKey = 'virt_keys';
  static const _virtKeyIdsKey = 'virt_key_ids';
  static const _virtKeyRowsKey = 'virt_key_per_row';
  static const _virtKeyAutoOffKey = 'virt_key_auto_off';
  static const _localTerminalKey = 'enable_local_terminal';
  static const _exitConfirmKey = 'terminal_exit_confirm';

  AppThemeMode themeMode = AppThemeMode.system;
  double fontSize = 14;
  bool showVirtKeys = true;

  /// 修饰键（Ctrl/Alt/Shift）组合生效一次后自动取消亮起。
  bool virtKeyAutoOff = true;

  /// 是否在首页显示「本机终端」入口。
  bool enableLocalTerminal = false;

  /// SSH 终端退出时是否弹出断开确认（默认开启；本机终端始终不弹）。
  bool confirmExitTerminal = true;

  /// 当前启用的虚拟按键 id（有序）。
  List<String> virtKeyIds = List.of(VirtKeyDef.defaultIds);

  /// 每行最多几个键。
  int virtKeysPerRow = 7;

  final List<void Function()> _listeners = [];

  void addListener(void Function() fn) => _listeners.add(fn);
  void removeListener(void Function() fn) => _listeners.remove(fn);
  void _notify() {
    for (final fn in List.of(_listeners)) {
      fn();
    }
  }

  ThemeMode get materialThemeMode => switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  List<VirtKeyDef> get enabledVirtKeys {
    final keys = [
      for (final id in virtKeyIds)
        if (VirtKeyDef.byId(id) case final k?) k,
    ];
    // 旧设置里可能只剩下已移除的按键 id，此时回退默认布局。
    if (keys.isEmpty) {
      return [
        for (final id in VirtKeyDef.defaultIds)
          if (VirtKeyDef.byId(id) case final k?) k,
      ];
    }
    return keys;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_themeKey);
    themeMode = switch (t) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
    fontSize = prefs.getDouble(_fontSizeKey) ?? 14;
    showVirtKeys = prefs.getBool(_virtKeysKey) ?? true;
    virtKeyAutoOff = prefs.getBool(_virtKeyAutoOffKey) ?? true;
    enableLocalTerminal = prefs.getBool(_localTerminalKey) ?? false;
    confirmExitTerminal = prefs.getBool(_exitConfirmKey) ?? true;
    virtKeysPerRow = (prefs.getInt(_virtKeyRowsKey) ?? 7).clamp(4, 10);

    final raw = prefs.getString(_virtKeyIdsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).cast<String>();
        if (list.isNotEmpty) {
          virtKeyIds = list;
        }
      } catch (_) {
        virtKeyIds = List.of(VirtKeyDef.defaultIds);
      }
    }
    _notify();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _themeKey,
      switch (mode) {
        AppThemeMode.system => 'system',
        AppThemeMode.light => 'light',
        AppThemeMode.dark => 'dark',
      },
    );
    _notify();
  }

  Future<void> setFontSize(double size) async {
    fontSize = size.clamp(10, 24);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, fontSize);
    _notify();
  }

  Future<void> setShowVirtKeys(bool value) async {
    showVirtKeys = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_virtKeysKey, value);
    _notify();
  }

  Future<void> setVirtKeyAutoOff(bool value) async {
    virtKeyAutoOff = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_virtKeyAutoOffKey, value);
    _notify();
  }

  Future<void> setEnableLocalTerminal(bool value) async {
    enableLocalTerminal = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localTerminalKey, value);
    _notify();
  }

  Future<void> setConfirmExitTerminal(bool value) async {
    confirmExitTerminal = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_exitConfirmKey, value);
    _notify();
  }

  Future<void> setVirtKeyIds(List<String> ids) async {
    virtKeyIds = List.of(ids);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_virtKeyIdsKey, jsonEncode(virtKeyIds));
    _notify();
  }

  Future<void> setVirtKeysPerRow(int n) async {
    virtKeysPerRow = n.clamp(4, 10);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_virtKeyRowsKey, virtKeysPerRow);
    _notify();
  }

  Future<void> applyVirtKeyPreset(List<String> ids) => setVirtKeyIds(ids);
}
