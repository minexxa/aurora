import 'package:flutter/material.dart';
import 'package:aurora/models/virt_key_def.dart';
import 'package:aurora/services/settings_store.dart';

/// 自定义虚拟按键：开关、排序、预设。
class VirtKeysSettingsPage extends StatefulWidget {
  const VirtKeysSettingsPage({super.key});

  @override
  State<VirtKeysSettingsPage> createState() => _VirtKeysSettingsPageState();
}

class _VirtKeysSettingsPageState extends State<VirtKeysSettingsPage> {
  final _settings = SettingsStore.instance;
  late List<String> _ids;

  @override
  void initState() {
    super.initState();
    _ids = List.of(_settings.virtKeyIds);
  }

  Future<void> _save() async {
    await _settings.setVirtKeyIds(_ids);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _applyPreset(List<String> ids) async {
    setState(() => _ids = List.of(ids));
    await _settings.setVirtKeyIds(_ids);
  }

  void _toggle(String id) {
    setState(() {
      if (_ids.contains(id)) {
        _ids.remove(id);
      } else {
        // 按 catalog 顺序插入，保持相对顺序
        final order = [for (final k in VirtKeyDef.catalog) k.id];
        _ids.add(id);
        _ids.sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
      }
    });
  }

  void _move(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _ids.length) return;
    setState(() {
      final item = _ids.removeAt(index);
      _ids.insert(next, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('虚拟按键'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '预设',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('完整'),
                  onPressed: () => _applyPreset(VirtKeyDef.defaultIds),
                ),
                ActionChip(
                  label: const Text('精简'),
                  onPressed: () => _applyPreset(VirtKeyDef.compactIds),
                ),
                ActionChip(
                  label: const Text('恢复默认'),
                  onPressed: () => _applyPreset(VirtKeyDef.defaultIds),
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('每行键数'),
            subtitle: Text('${_settings.virtKeysPerRow}'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: _settings.virtKeysPerRow.toDouble(),
                min: 4,
                max: 10,
                divisions: 6,
                label: '${_settings.virtKeysPerRow}',
                onChanged: (v) async {
                  await _settings.setVirtKeysPerRow(v.round());
                  setState(() {});
                },
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '已启用（可排序）',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (_ids.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('尚未选择任何按键'),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ids.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _ids.removeAt(oldIndex);
                  _ids.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final id = _ids[index];
                final def = VirtKeyDef.byId(id);
                return ListTile(
                  key: ValueKey(id),
                  leading: const Icon(Icons.drag_handle),
                  title: Text(def?.label ?? id),
                  subtitle: Text(id),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _toggle(id),
                  ),
                  onLongPress: () => _move(index, -1),
                );
              },
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '全部按键',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          for (final def in VirtKeyDef.catalog)
            CheckboxListTile(
              value: _ids.contains(def.id),
              onChanged: (_) => _toggle(def.id),
              title: Text(def.label),
              subtitle: Text(def.id),
              secondary: Icon(switch (def.kind) {
                VirtKeyKind.modifier => Icons.keyboard_option_key,
                VirtKeyKind.terminalKey => Icons.keyboard,
                VirtKeyKind.char => Icons.text_fields,
                VirtKeyKind.func => Icons.touch_app_outlined,
              }),
            ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存布局'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
