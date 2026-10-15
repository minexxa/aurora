import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:aurora/models/server.dart';

/// 系统信息分类（底部导航）。
enum SysInfoTab {
  basic,
  process,
  service,
  firewall,
  power,
  users,
  cron,
  docker,
}

extension SysInfoTabX on SysInfoTab {
  String get label => switch (this) {
        SysInfoTab.basic => '基础',
        SysInfoTab.process => '进程',
        SysInfoTab.service => '服务',
        SysInfoTab.firewall => '防火墙',
        SysInfoTab.power => '电源',
        SysInfoTab.users => '用户',
        SysInfoTab.cron => '计划',
        SysInfoTab.docker => 'Docker',
      };

  /// 在目标机上执行的 shell（按显示时采集，非实时轮询）。
  String get command => switch (this) {
        SysInfoTab.basic => r'''
echo "=== 主机 / 内核 ==="
hostname 2>/dev/null; uname -a 2>/dev/null
echo
echo "=== 系统发行版 ==="
cat /etc/os-release 2>/dev/null || cat /etc/openwrt_release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || true
echo
echo "=== 运行时间 / 负载 ==="
uptime 2>/dev/null; cat /proc/loadavg 2>/dev/null
echo
echo "=== CPU ==="
(grep -E 'model name|Hardware|processor|cpu cores|BogoMIPS' /proc/cpuinfo 2>/dev/null | sort -u | head -20) || true
nproc 2>/dev/null && echo "逻辑核心: $(nproc)"
echo
echo "=== 内存 ==="
free -h 2>/dev/null || (head -5 /proc/meminfo 2>/dev/null)
echo
echo "=== 磁盘 ==="
df -h 2>/dev/null || df 2>/dev/null
echo
echo "=== 网络接口 ==="
ip -br addr 2>/dev/null || ifconfig 2>/dev/null || cat /proc/net/dev 2>/dev/null
''',
        SysInfoTab.process => r'''
echo "=== 进程列表 (最多 120 行) ==="
ps aux 2>/dev/null | head -120 || ps w 2>/dev/null | head -120 || ps 2>/dev/null | head -120
echo
echo "=== 按内存 Top ==="
ps aux --sort=-%mem 2>/dev/null | head -16 || true
echo
echo "=== 按 CPU Top ==="
ps aux --sort=-%cpu 2>/dev/null | head -16 || true
''',
        SysInfoTab.service => r'''
echo "=== systemd 服务 (running) ==="
systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -80 || true
echo
echo "=== systemd 失败单元 ==="
systemctl --failed --no-pager 2>/dev/null | head -40 || true
echo
echo "=== SysV / init.d ==="
ls -la /etc/init.d/ 2>/dev/null | head -60 || true
echo
echo "=== OpenWrt / procd (若有) ==="
ls /etc/init.d/ 2>/dev/null | head -40
service 2>/dev/null | head -5 || true
''',
        SysInfoTab.firewall => r'''
echo "=== iptables (filter) ==="
iptables -L -n -v 2>/dev/null | head -120 || echo "(无 iptables 或无权限)"
echo
echo "=== nftables ==="
nft list ruleset 2>/dev/null | head -120 || true
echo
echo "=== ufw ==="
ufw status verbose 2>/dev/null || true
echo
echo "=== firewalld ==="
firewall-cmd --state 2>/dev/null; firewall-cmd --list-all 2>/dev/null | head -80 || true
''',
        SysInfoTab.power => r'''
echo "=== 运行时间 ==="
uptime 2>/dev/null
echo
echo "=== 启动时间 ==="
who -b 2>/dev/null || last reboot 2>/dev/null | head -5 || true
echo
echo "=== 电源 / 电池 ==="
for d in /sys/class/power_supply/*; do
  [ -d "$d" ] || continue
  echo "-- $(basename "$d") --"
  cat "$d/type" 2>/dev/null
  cat "$d/status" 2>/dev/null
  cat "$d/capacity" 2>/dev/null
  echo
done
echo "=== 温度 (若有) ==="
cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -10 || true
vcgencmd measure_temp 2>/dev/null || true
echo
echo "=== 最近电源相关日志 ==="
last -x 2>/dev/null | head -25 || true
''',
        SysInfoTab.users => r'''
echo "=== 当前登录 ==="
who 2>/dev/null || w 2>/dev/null || true
echo
echo "=== /etc/passwd (系统用户) ==="
cat /etc/passwd 2>/dev/null
echo
echo "=== 最近登录 ==="
last -n 25 2>/dev/null || last | head -25 || true
echo
echo "=== 组 ==="
cat /etc/group 2>/dev/null | head -40 || true
''',
        SysInfoTab.cron => r'''
echo "=== 当前用户 crontab ==="
crontab -l 2>/dev/null || echo "(无 crontab 或无权限)"
echo
echo "=== /etc/crontab ==="
cat /etc/crontab 2>/dev/null || true
echo
echo "=== /etc/cron.* ==="
ls -la /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly 2>/dev/null || true
echo
echo "=== cron.d 内容摘要 ==="
for f in /etc/cron.d/*; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  cat "$f" 2>/dev/null
  echo
done
echo "=== OpenWrt scheduled tasks (若有) ==="
cat /etc/crontabs/root 2>/dev/null || true
''',
        SysInfoTab.docker => r'''
echo "=== Docker 版本 ==="
docker version 2>/dev/null | head -30 || echo "docker 不可用或不在 PATH"
echo
echo "=== 容器 ==="
docker ps -a 2>/dev/null || true
echo
echo "=== 镜像 ==="
docker images 2>/dev/null || true
echo
echo "=== 资源占用 ==="
docker stats --no-stream 2>/dev/null | head -40 || true
echo
echo "=== podman (若有) ==="
podman ps -a 2>/dev/null | head -30 || true
''',
      };
}

/// 按需采集的系统信息会话（进入某一 Tab 时才执行对应命令）。
class SysInfoSession {
  SysInfoSession({required this.server});

  final Server server;

  SSHClient? _client;
  bool connected = false;
  String? connectError;

  /// 各 Tab 缓存的纯文本结果。
  final Map<SysInfoTab, String> cache = {};
  final Map<SysInfoTab, String?> errors = {};
  final Set<SysInfoTab> loading = {};

  Future<void> connect() async {
    if (connected && _client != null) return;
    connectError = null;
    try {
      final socket = await SSHSocket.connect(
        server.host,
        server.port,
        timeout: const Duration(seconds: 15),
      );

      List<SSHKeyPair> identities = const [];
      if (server.privateKey != null && server.privateKey!.trim().isNotEmpty) {
        identities = SSHKeyPair.fromPem(
          server.privateKey!,
          server.passphrase,
        );
      }

      _client = SSHClient(
        socket,
        username: server.username,
        onPasswordRequest: (server.password != null &&
                server.password!.isNotEmpty)
            ? () => server.password!
            : null,
        identities: identities,
      );
      await _client!.authenticated;
      connected = true;
    } catch (e, st) {
      debugPrint('SysInfo connect failed: $e\n$st');
      connectError = e.toString();
      connected = false;
      await close();
      rethrow;
    }
  }

  /// 仅在尚未缓存或 [force] 时采集。
  Future<String> fetch(SysInfoTab tab, {bool force = false}) async {
    if (!force && cache.containsKey(tab) && (errors[tab] == null)) {
      return cache[tab]!;
    }
    if (_client == null || !connected) {
      await connect();
    }
    loading.add(tab);
    try {
      final raw = await _client!.run(tab.command);
      final text = utf8.decode(raw, allowMalformed: true).trim();
      final result = text.isEmpty ? '(无输出)' : text;
      cache[tab] = result;
      errors[tab] = null;
      return result;
    } catch (e, st) {
      debugPrint('SysInfo fetch $tab failed: $e\n$st');
      final msg = e.toString();
      errors[tab] = msg;
      cache[tab] = '';
      rethrow;
    } finally {
      loading.remove(tab);
    }
  }

  Future<void> close() async {
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    connected = false;
  }

  void dispose() {
    close();
    cache.clear();
    errors.clear();
    loading.clear();
  }
}
