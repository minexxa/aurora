import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import 'package:aurora/services/ssh_session.dart' show SshSessionState;

/// 本机 shell 会话：通过 Process 启动 /system/bin/sh（或 sh），
/// 与 xterm Terminal 双向绑定。
///
/// 注意：Android 无完整 PTY 时，shell 判定 stdin 非 tty，通常不会打印 PS1。
/// 因此启动后会写入欢迎信息，并尽量用 -i / ENV 改善交互。
class LocalSession {
  LocalSession();

  final terminal = Terminal(maxLines: 10000);
  final controller = TerminalController();

  Process? _process;
  SshSessionState _state = SshSessionState.idle;
  SshSessionState get state => _state;

  String? errorMessage;

  final ValueNotifier<SshSessionState> stateNotifier =
      ValueNotifier(SshSessionState.idle);

  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  void _setState(SshSessionState s) {
    _state = s;
    stateNotifier.value = s;
  }

  Future<void> connect() async {
    if (_state == SshSessionState.connecting ||
        _state == SshSessionState.connected) {
      return;
    }

    _setState(SshSessionState.connecting);
    errorMessage = null;
    terminal.write('\r\n\x1b[36mStarting local shell...\x1b[0m\r\n');

    try {
      final shell = await _resolveShell();
      // -i：尽量以交互模式启动；无 PTY 时仍可能不回显提示符
      _process = await Process.start(
        shell,
        const ['-i'],
        runInShell: false,
        environment: {
          ...Platform.environment,
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
          'PS1': r'$ ',
          'HOME': Platform.environment['HOME'] ?? '/data/local/tmp',
        },
      );

      terminal.onOutput = (data) {
        _process?.stdin.add(utf8.encode(data));
      };

      // 本机 Process 无法真正 resize PTY，仅保持接口一致。
      terminal.onResize = (width, height, pixelWidth, pixelHeight) {};

      _stdoutSub = _process!.stdout.listen(
        (data) {
          terminal.write(utf8.decode(data, allowMalformed: true));
        },
        onDone: _onProcessDone,
        onError: (e) {
          terminal.write('\r\n\x1b[31mstdout error: $e\x1b[0m\r\n');
        },
      );

      _stderrSub = _process!.stderr.listen(
        (data) {
          terminal.write(utf8.decode(data, allowMalformed: true));
        },
      );

      _process!.exitCode.then((_) => _onProcessDone());

      // 不清空 buffer：保留启动信息；并主动写欢迎语
      // （无 PTY 时 sh 往往不打印任何提示符，否则用户会看到空白屏）
      terminal.write(
        '\x1b[32mLocal shell ready\x1b[0m ($shell)\r\n'
        '\x1b[90mNote: no PTY — prompt may be missing; type a command and Enter.\x1b[0m\r\n'
        r'$ ',
      );

      // 触发一次输出，减少完全静默的情况
      try {
        _process!.stdin.writeln('echo ""; pwd');
        await _process!.stdin.flush();
      } catch (_) {}

      _setState(SshSessionState.connected);
    } catch (e, st) {
      debugPrint('Local shell failed: $e\n$st');
      errorMessage = e.toString();
      terminal.write('\r\n\x1b[31mLocal shell failed: $e\x1b[0m\r\n');
      _setState(SshSessionState.failed);
      await close();
    }
  }

  Future<String> _resolveShell() async {
    const candidates = [
      '/system/bin/sh',
      '/bin/sh',
      'sh',
    ];
    for (final path in candidates) {
      try {
        if (path.contains('/')) {
          final f = File(path);
          if (await f.exists()) return path;
        } else {
          return path;
        }
      } catch (_) {}
    }
    return 'sh';
  }

  void _onProcessDone() {
    if (_state == SshSessionState.disconnected) return;
    terminal.write('\r\n\x1b[33m[Session closed]\x1b[0m\r\n');
    _setState(SshSessionState.disconnected);
  }

  Future<void> close() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;

    try {
      _process?.kill(ProcessSignal.sigkill);
    } catch (_) {
      try {
        _process?.kill();
      } catch (_) {}
    }
    try {
      await _process?.stdin.close();
    } catch (_) {}
    _process = null;

    if (_state != SshSessionState.failed) {
      _setState(SshSessionState.disconnected);
    }
  }

  Future<void> reconnect() async {
    await close();
    await connect();
  }

  void dispose() {
    close();
    stateNotifier.dispose();
  }
}
