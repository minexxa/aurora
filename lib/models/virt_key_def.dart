import 'package:xterm/xterm.dart';

enum VirtKeyKind {
  /// 可切换的修饰键（Ctrl / Alt / Shift），点亮后与输入法键盘的
  /// 字母等按键组合使用（逻辑与 server_box 一致）。
  modifier,
  /// 发送 TerminalKey
  terminalKey,
  /// 发送原始字符
  char,
  /// 功能键（如切换手机输入法）
  func,
}

/// 一枚可配置的虚拟按键。
class VirtKeyDef {
  const VirtKeyDef({
    required this.id,
    required this.label,
    required this.kind,
    this.terminalKey,
    this.char,
    this.icon,
  });

  final String id;
  final String label;
  final VirtKeyKind kind;
  final TerminalKey? terminalKey;
  final String? char;

  /// func 类按键的图标名（如 IME 切换键）。
  final String? icon;

  static const catalog = <VirtKeyDef>[
    VirtKeyDef(id: 'ctrl', label: 'Ctrl', kind: VirtKeyKind.modifier),
    VirtKeyDef(id: 'alt', label: 'Alt', kind: VirtKeyKind.modifier),
    VirtKeyDef(id: 'shift', label: 'Shift', kind: VirtKeyKind.modifier),
    VirtKeyDef(
      id: 'ime',
      label: '键盘',
      kind: VirtKeyKind.func,
      icon: 'keyboard',
    ),
    VirtKeyDef(
      id: 'esc',
      label: 'Esc',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.escape,
    ),
    VirtKeyDef(
      id: 'tab',
      label: 'Tab',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.tab,
    ),
    VirtKeyDef(id: 'dash', label: '—', kind: VirtKeyKind.char, char: '-'),
    VirtKeyDef(id: 'slash', label: '/', kind: VirtKeyKind.char, char: '/'),
    VirtKeyDef(id: 'pipe', label: '|', kind: VirtKeyKind.char, char: '|'),
    VirtKeyDef(id: 'tilde', label: '~', kind: VirtKeyKind.char, char: '~'),
    VirtKeyDef(id: 'dollar', label: '\$', kind: VirtKeyKind.char, char: '\$'),
    VirtKeyDef(id: 'star', label: '*', kind: VirtKeyKind.char, char: '*'),
    VirtKeyDef(id: 'amp', label: '&', kind: VirtKeyKind.char, char: '&'),
    VirtKeyDef(id: 'semi', label: ';', kind: VirtKeyKind.char, char: ';'),
    VirtKeyDef(id: 'gt', label: '>', kind: VirtKeyKind.char, char: '>'),
    VirtKeyDef(id: 'lt', label: '<', kind: VirtKeyKind.char, char: '<'),
    VirtKeyDef(
      id: 'up',
      label: '↑',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.arrowUp,
    ),
    VirtKeyDef(
      id: 'down',
      label: '↓',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.arrowDown,
    ),
    VirtKeyDef(
      id: 'left',
      label: '←',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.arrowLeft,
    ),
    VirtKeyDef(
      id: 'right',
      label: '→',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.arrowRight,
    ),
    VirtKeyDef(
      id: 'home',
      label: 'Home',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.home,
    ),
    VirtKeyDef(
      id: 'end',
      label: 'End',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.end,
    ),
    VirtKeyDef(
      id: 'pgup',
      label: 'PgUp',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.pageUp,
    ),
    VirtKeyDef(
      id: 'pgdn',
      label: 'PgDn',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.pageDown,
    ),
    VirtKeyDef(
      id: 'backspace',
      label: '⌫',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.backspace,
    ),
    VirtKeyDef(
      id: 'delete',
      label: 'Del',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.delete,
    ),
    VirtKeyDef(
      id: 'enter',
      label: 'Enter',
      kind: VirtKeyKind.terminalKey,
      terminalKey: TerminalKey.enter,
    ),
  ];

  static VirtKeyDef? byId(String id) {
    for (final k in catalog) {
      if (k.id == id) return k;
    }
    return null;
  }

  /// 默认布局。
  static const defaultIds = <String>[
    'ctrl',
    'alt',
    'shift',
    'ime',
    'esc',
    'tab',
    'dash',
    'slash',
    'pipe',
    'up',
    'down',
    'left',
    'right',
    'home',
    'end',
    'backspace',
    'enter',
  ];

  /// 精简布局。
  static const compactIds = <String>[
    'ctrl',
    'esc',
    'tab',
    'ime',
    'up',
    'down',
    'left',
    'right',
    'enter',
  ];
}
