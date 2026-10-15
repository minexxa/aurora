import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aurora/models/server.dart';
import 'package:aurora/services/sysinfo_session.dart';

/// 服务器信息采集页：底部导航切换分类，进入某一页时才执行对应命令。
class SysInfoPage extends StatefulWidget {
  const SysInfoPage({super.key, required this.server});

  final Server server;

  @override
  State<SysInfoPage> createState() => _SysInfoPageState();
}

class _SysInfoPageState extends State<SysInfoPage> {
  late final SysInfoSession _session;
  SysInfoTab _tab = SysInfoTab.basic;
  bool _connecting = true;
  String? _pageError;

  static const _tabs = SysInfoTab.values;

  static IconData _icon(SysInfoTab t) => switch (t) {
        SysInfoTab.basic => Icons.info_outline,
        SysInfoTab.process => Icons.memory,
        SysInfoTab.service => Icons.settings_applications_outlined,
        SysInfoTab.firewall => Icons.security_outlined,
        SysInfoTab.power => Icons.power_settings_new,
        SysInfoTab.users => Icons.people_outline,
        SysInfoTab.cron => Icons.schedule,
        SysInfoTab.docker => Icons.view_in_ar_outlined,
      };

  @override
  void initState() {
    super.initState();
    _session = SysInfoSession(server: widget.server);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _connecting = true;
      _pageError = null;
    });
    try {
      await _session.connect();
      if (!mounted) return;
      setState(() => _connecting = false);
      await _loadTab(_tab);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _pageError = e.toString();
      });
    }
  }

  Future<void> _loadTab(SysInfoTab tab, {bool force = false}) async {
    if (!_session.connected) {
      await _bootstrap();
      return;
    }
    setState(() {}); // 触发 loading 指示
    try {
      await _session.fetch(tab, force: force);
    } catch (_) {
      // 错误已写入 session.errors
    }
    if (mounted) setState(() {});
  }

  void _onTabSelected(int index) {
    final tab = _tabs[index];
    if (tab == _tab) return;
    setState(() => _tab = tab);
    // 首次进入该 Tab 才采集
    if (!_session.cache.containsKey(tab)) {
      _loadTab(tab);
    }
  }

  Future<void> _copyContent() async {
    final text = _session.cache[_tab] ?? '';
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.server.name, style: const TextStyle(fontSize: 16)),
            Text(
              '${widget.server.username}@${widget.server.displayAddr} · ${_tab.label}',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '复制',
            onPressed: (_session.cache[_tab]?.isNotEmpty ?? false)
                ? _copyContent
                : null,
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _connecting || _session.loading.contains(_tab)
                ? null
                : () => _loadTab(_tab, force: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(scheme),
      bottomNavigationBar: Material(
        elevation: 3,
        color: scheme.surfaceContainer,
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _tabs.length,
              itemBuilder: (context, i) {
                final t = _tabs[i];
                final selected = t == _tab;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _onTabSelected(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.secondaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _icon(t),
                            size: 22,
                            color: selected
                                ? scheme.onSecondaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.normal,
                              color: selected
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_connecting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pageError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 56, color: scheme.error),
              const SizedBox(height: 12),
              Text(_pageError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _bootstrap,
                icon: const Icon(Icons.refresh),
                label: const Text('重试连接'),
              ),
            ],
          ),
        ),
      );
    }

    final loading = _session.loading.contains(_tab);
    final err = _session.errors[_tab];
    final text = _session.cache[_tab];

    if (loading && text == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (err != null && (text == null || text.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('采集失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(err, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _loadTab(_tab, force: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: SelectableText(
                text ?? '',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.35,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
