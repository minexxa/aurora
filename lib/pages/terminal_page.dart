import 'dart:ui' show View;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aurora/models/server.dart';
import 'package:aurora/pages/sftp_page.dart';
import 'package:aurora/services/settings_store.dart';
import 'package:aurora/services/ssh_session.dart';
import 'package:aurora/services/virt_key_input_handler.dart';
import 'package:aurora/widgets/virt_keys.dart';
import 'package:xterm/xterm.dart';

/// 完整 SSH 终端页：连接、渲染、虚拟按键、重连。
///
/// 与 server_box 对齐的交互：
/// - 长按终端：有选区则复制，无选区则粘贴；
/// - 虚拟按键条随手机输入法键盘一同显示/消失（输入法弹出时位于其上方）；
/// - Ctrl / Alt / Shift 点亮后与输入法键盘的字母等按键组合。
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.server});

  final Server server;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver {
  late final SshSession _session;
  final _terminalKey = GlobalKey<TerminalViewState>();
  final _focusNode = FocusNode();

  /// 修饰键状态机，同时挂载到 [Terminal.inputHandler]。
  late final VirtKeyInputHandler _inputHandler = VirtKeyInputHandler();

  /// 手机输入法键盘当前是否弹出。虚拟按键条随之显示/消失。
  ///
  /// 显示取 insets 上升沿，隐藏取焦点边沿（即时，不等 insets 动画
  /// 逐帧归零，保证虚拟条与键盘同步消失）。
  bool _imeVisible = false;

  final _settings = SettingsStore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_onFocusChange);
    _session = SshSession(server: widget.server);
    // 修饰键经 inputHandler 生效：输入法键盘/物理键盘的按键都会带上。
    _session.terminal.inputHandler = _inputHandler;
    _session.stateNotifier.addListener(_onState);
    _settings.addListener(_onSettings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _session.connect();
      _focusWithoutKeyboard();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_onFocusChange);
    _session.stateNotifier.removeListener(_onState);
    _settings.removeListener(_onSettings);
    _session.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 输入法弹出/收起会改变底部 viewInsets。
    final visible = View.of(context).viewInsets.bottom > 0;
    if (visible != _imeVisible && mounted) {
      setState(() => _imeVisible = visible);
    }
  }

  /// 焦点失去即键盘收起，立即同步隐藏虚拟按键条。
  void _onFocusChange() {
    if (!_focusNode.hasFocus && _imeVisible && mounted) {
      setState(() => _imeVisible = false);
    }
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  /// 聚焦终端但不唤起输入法键盘（server_box 的 `keyboard: false` 行为）。
  void _focusWithoutKeyboard() {
    _focusNode.requestFocus();
    // 聚焦会顺势打开输入连接，延迟一帧后收起键盘。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  /// 切换手机输入法键盘（server_box 的 IME 键）。
  void _toggleIme() {
    if (_imeVisible) {
      _focusNode.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } else {
      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

  Future<void> _reconnect() async {
    await _session.reconnect();
    _focusWithoutKeyboard();
  }

  void _openSftp() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SftpPage(server: widget.server),
      ),
    );
  }

  /// 长按终端：有选区复制，无选区粘贴（server_box 同款逻辑）。
  Future<void> _onClipboardAction() async {
    final selection = _session.controller.selection;
    if (selection != null) {
      final text = _selectedText(selection);
      if (text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制到剪贴板'),
            duration: Duration(seconds: 1),
          ),
        );
        _session.controller.clearSelection();
      }
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _session.terminal.paste(text);
    _session.controller.clearSelection();
  }

  /// 从 buffer 中提取选区文本（server_box `renderTerminal.selectedText` 等价逻辑）。
  String _selectedText(BufferRange range) {
    final r = range.normalized;
    final lines = _session.terminal.buffer.lines;
    final sb = StringBuffer();
    for (var y = r.begin.y; y <= r.end.y; y++) {
      if (y < 0 || y >= lines.length) break;
      final from = y == r.begin.y ? r.begin.x : 0;
      final to = y == r.end.y ? r.end.x : null;
      if (sb.isNotEmpty) sb.write('\n');
      sb.write(lines[y].getText(from, to));
    }
    return sb.toString();
  }

  Future<bool> _onWillPop() async {
    if (_session.state == SshSessionState.connected) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('断开连接？'),
          content: const Text('当前会话仍在连接中，确定退出吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('断开并退出'),
            ),
          ],
        ),
      );
      return ok ?? false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fontSize = _settings.fontSize;

    final termTheme = isDark ? _darkTheme : _lightTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _onWillPop()) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: termTheme.background,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.server.name,
                style: const TextStyle(fontSize: 16),
              ),
              Text(
                '${widget.server.username}@${widget.server.displayAddr}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          actions: [
            // SFTP 在连接状态左侧
            IconButton(
              tooltip: 'SFTP 文件',
              icon: const Icon(Icons.folder_outlined),
              onPressed: _openSftp,
            ),
            _StatusChip(state: _session.state),
            IconButton(
              tooltip: '重连',
              icon: const Icon(Icons.refresh),
              onPressed: _session.state == SshSessionState.connecting
                  ? null
                  : _reconnect,
            ),
            IconButton(
              tooltip: '断开',
              icon: const Icon(Icons.link_off),
              onPressed: _session.state == SshSessionState.connected
                  ? () async {
                      await _session.close();
                    }
                  : null,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_session.state == SshSessionState.connecting)
              const LinearProgressIndicator(minHeight: 2),
            if (_session.state == SshSessionState.failed)
              MaterialBanner(
                content: Text(
                  _session.errorMessage ?? '连接失败',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                leading: const Icon(Icons.error_outline),
                actions: [
                  TextButton(
                    onPressed: _reconnect,
                    child: const Text('重试'),
                  ),
                ],
              ),
            Expanded(
              child: TerminalView(
                _session.terminal,
                key: _terminalKey,
                controller: _session.controller,
                focusNode: _focusNode,
                autofocus: false,
                // 输入法键盘的输入类型（默认 emailAddress 不合适）。
                keyboardType: TextInputType.text,
                textStyle: TerminalStyle(
                  fontSize: fontSize,
                  fontFamily: 'monospace',
                ),
                theme: termTheme,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                hardwareKeyboardOnly: false,
                // 长按：有选区复制，无选区粘贴。
                onSecondaryTapUp: (details, offset) => _onClipboardAction(),
              ),
            ),
            // 虚拟按键条随手机输入法键盘一同显示/消失（输入法弹出时
            // 位于其上方，与 server_box 的 AnimatedPadding(viewInsets) 一致）。
            if (_settings.showVirtKeys && _imeVisible)
              VirtKeysBar(
                inputHandler: _inputHandler,
                onInput: (data) => _session.terminal.textInput(data),
                onKey: (key) => _session.terminal.keyInput(key),
                onToggleIme: _toggleIme,
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});
  final SshSessionState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      SshSessionState.idle => ('空闲', Colors.grey),
      SshSessionState.connecting => ('连接中', Colors.orange),
      SshSessionState.connected => ('已连接', Colors.green),
      SshSessionState.disconnected => ('已断开', Colors.grey),
      SshSessionState.failed => ('失败', Colors.red),
    };

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Chip(
        visualDensity: VisualDensity.compact,
        label: Text(label, style: const TextStyle(fontSize: 11)),
        avatar: CircleAvatar(backgroundColor: color, radius: 5),
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.only(right: 8),
      ),
    );
  }
}

final _darkTheme = TerminalTheme(
  cursor: const Color(0xFFAEAFAD),
  selection: const Color(0x40FFFFFF),
  foreground: const Color(0xFFCCCCCC),
  background: const Color(0xFF1E1E1E),
  black: const Color(0xFF000000),
  red: const Color(0xFFCD3131),
  green: const Color(0xFF0DBC79),
  yellow: const Color(0xFFE5E510),
  blue: const Color(0xFF2472C8),
  magenta: const Color(0xFFBC3FBC),
  cyan: const Color(0xFF11A8CD),
  white: const Color(0xFFE5E5E5),
  brightBlack: const Color(0xFF666666),
  brightRed: const Color(0xFFF14C4C),
  brightGreen: const Color(0xFF23D18B),
  brightYellow: const Color(0xFFF5F543),
  brightBlue: const Color(0xFF3B8EEA),
  brightMagenta: const Color(0xFFD670D6),
  brightCyan: const Color(0xFF29B8DB),
  brightWhite: const Color(0xFFE5E5E5),
  searchHitBackground: const Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: const Color(0xFF31FF26),
  searchHitForeground: const Color(0xFF000000),
);

final _lightTheme = TerminalTheme(
  cursor: const Color(0xFF000000),
  selection: const Color(0x40000000),
  foreground: const Color(0xFF333333),
  background: const Color(0xFFFAFAFA),
  black: const Color(0xFF000000),
  red: const Color(0xFFCD3131),
  green: const Color(0xFF00BC00),
  yellow: const Color(0xFF949800),
  blue: const Color(0xFF0451A5),
  magenta: const Color(0xFFBC05BC),
  cyan: const Color(0xFF0598BC),
  white: const Color(0xFF555555),
  brightBlack: const Color(0xFF666666),
  brightRed: const Color(0xFFCD3131),
  brightGreen: const Color(0xFF14CE14),
  brightYellow: const Color(0xFFB5B00),
  brightBlue: const Color(0xFF0451A5),
  brightMagenta: const Color(0xFFBC05BC),
  brightCyan: const Color(0xFF0598BC),
  brightWhite: const Color(0xFFA5A5A5),
  searchHitBackground: const Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: const Color(0xFF31FF26),
  searchHitForeground: const Color(0xFF000000),
);
