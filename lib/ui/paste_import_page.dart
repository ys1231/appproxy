import 'package:appproxy/data/proxy_paste_profile.dart';
import 'package:appproxy/generated/l10n.dart';
import 'package:flutter/material.dart';

/// 粘贴导入页：选一套识别规则 → 粘贴代理文本 → 预览 → 应用到添加/修改代理表单。
///
/// 规则本身可管理（新增/编辑/删除），存在 SharedPreferences 里，
/// 默认预置 `@` / `#` / `|` 三套「名称@类型@地址@端口@用户名@密码」规则和一套完整 URL 规则。
class PasteImportPage extends StatefulWidget {
  const PasteImportPage({super.key});

  @override
  State<PasteImportPage> createState() => _PasteImportPageState();
}

class _PasteImportPageState extends State<PasteImportPage> {
  final TextEditingController _textController = TextEditingController();
  List<ProxyPasteProfile> _profiles = [];
  String _selectedId = '';
  Map<String, String> _preview = {};
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  ProxyPasteProfile? get _selected {
    for (final p in _profiles) {
      if (p.id == _selectedId) return p;
    }
    return _profiles.isEmpty ? null : _profiles.first;
  }

  Future<void> _load() async {
    final profiles = await ProxyPasteProfiles.load();
    final last = await ProxyPasteProfiles.lastProfileId();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _selectedId = profiles.any((p) => p.id == last)
          ? last
          : (profiles.isEmpty ? '' : profiles.first.id);
      _loading = false;
    });
    _parse();
  }

  void _parse() {
    final profile = _selected;
    final text = _textController.text;
    if (profile == null) {
      setState(() {
        _preview = {};
        _error = '';
      });
      return;
    }
    if (text.trim().isEmpty) {
      setState(() {
        _preview = {};
        _error = '';
      });
      return;
    }
    try {
      final parsed = profile.parse(text);
      setState(() {
        _preview = parsed;
        _error = '';
      });
    } on FormatException catch (e) {
      setState(() {
        _preview = {};
        _error = e.message;
      });
    }
  }

  Future<void> _apply() async {
    if (_preview.isEmpty || _error.isNotEmpty) return;
    await ProxyPasteProfiles.setLastProfileId(_selectedId);
    if (!mounted) return;
    Navigator.pop(context, _preview);
  }

  Future<void> _manageProfiles() async {
    final result = await showDialog<List<ProxyPasteProfile>>(
      context: context,
      builder: (ctx) => _ProfileManagerDialog(initial: _profiles),
    );
    if (result == null) return;
    await ProxyPasteProfiles.save(result);
    if (!mounted) return;
    setState(() {
      _profiles = result;
      if (!_profiles.any((p) => p.id == _selectedId)) {
        _selectedId = _profiles.isEmpty ? '' : _profiles.first.id;
      }
    });
    _parse();
  }

  String _fieldLabel(S s, String field) {
    switch (field) {
      case PasteField.name:
        return s.paste_field_name;
      case PasteField.type:
        return s.paste_field_type;
      case PasteField.host:
        return s.paste_field_host;
      case PasteField.port:
        return s.paste_field_port;
      case PasteField.user:
        return s.paste_field_user;
      case PasteField.pass:
        return s.paste_field_pass;
      case PasteField.hostPort:
        return s.paste_field_host_port;
      case PasteField.url:
        return s.paste_field_url;
      case PasteField.ignore:
        return s.paste_field_ignore;
      default:
        return field;
    }
  }

  String _summary(S s, ProxyPasteProfile p) {
    final sep = p.separator.isEmpty ? s.paste_whole_text : p.separator;
    return '$sep → ${p.fields.map((f) => _fieldLabel(s, f)).join(" / ")}';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final canApply = _preview.isNotEmpty && _error.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.paste_import_title),
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          IconButton(
            tooltip: s.paste_manage,
            icon: const Icon(Icons.tune),
            onPressed: _manageProfiles,
          ),
          IconButton(
            tooltip: s.paste_apply,
            icon: const Icon(Icons.check),
            onPressed: canApply ? _apply : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12.0),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 12.0),
                    child: _profiles.isEmpty
                        ? Row(
                            children: [
                              Expanded(child: Text(s.paste_no_profile)),
                              TextButton(
                                onPressed: _manageProfiles,
                                child: Text(s.paste_profile_add),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                key: ValueKey('paste_profile_$_selectedId'),
                                initialValue: _selectedId,
                                decoration: InputDecoration(labelText: s.paste_profile),
                                items: _profiles
                                    .map((p) => DropdownMenuItem(
                                          value: p.id,
                                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _selectedId = v);
                                  _parse();
                                },
                              ),
                              if (_selected != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    _summary(s, _selected!),
                                    style: const TextStyle(fontSize: 12.0, color: Colors.grey),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 8.0),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _textController,
                          minLines: 4,
                          maxLines: 8,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13.0),
                          decoration: InputDecoration(
                            labelText: s.paste_content_label,
                            hintText: s.paste_content_hint,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => _parse(),
                        ),
                        const SizedBox(height: 12.0),
                        Text(s.paste_preview,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6.0),
                        if (_error.isNotEmpty)
                          Text(_error, style: const TextStyle(fontSize: 12.0, color: Colors.orange))
                        else if (_preview.isEmpty)
                          Text(s.paste_preview_empty,
                              style: const TextStyle(fontSize: 12.0, color: Colors.grey))
                        else
                          ..._preview.entries.map((e) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 90.0,
                                      child: Text(_fieldLabel(s, e.key),
                                          style: const TextStyle(fontSize: 13.0)),
                                    ),
                                    Expanded(
                                      child: SelectableText(
                                        e.value,
                                        style: const TextStyle(
                                            fontSize: 13.0, fontFamily: 'monospace'),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12.0),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: canApply ? _apply : null,
                    child: Text(s.paste_apply),
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  s.paste_help,
                  style: const TextStyle(fontSize: 11.0, color: Colors.grey),
                ),
              ],
            ),
    );
  }
}

/// 规则管理弹窗：列表 + 新增/编辑/删除；点「保存」把整份规则回传。
class _ProfileManagerDialog extends StatefulWidget {
  const _ProfileManagerDialog({required this.initial});

  final List<ProxyPasteProfile> initial;

  @override
  State<_ProfileManagerDialog> createState() => _ProfileManagerDialogState();
}

class _ProfileManagerDialogState extends State<_ProfileManagerDialog> {
  late List<ProxyPasteProfile> _list;

  @override
  void initState() {
    super.initState();
    _list = List<ProxyPasteProfile>.from(widget.initial);
  }

  Future<void> _edit([ProxyPasteProfile? profile]) async {
    final result = await showDialog<ProxyPasteProfile>(
      context: context,
      builder: (ctx) => _ProfileEditDialog(initial: profile),
    );
    if (result == null || !mounted) return;
    setState(() {
      final idx = _list.indexWhere((p) => p.id == result.id);
      if (idx >= 0) {
        _list[idx] = result;
      } else {
        _list.add(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.paste_manage),
      content: SizedBox(
        width: 480.0,
        height: 380.0,
        child: Column(
          children: [
            Expanded(
              child: _list.isEmpty
                  ? Center(
                      child: Text(s.paste_no_profile,
                          style: const TextStyle(fontSize: 12.0, color: Colors.grey)),
                    )
                  : ListView.separated(
                      itemCount: _list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final p = _list[i];
                        return ListTile(
                          dense: true,
                          title: Text(p.name),
                          subtitle: Text(
                            '${p.separator.isEmpty ? s.paste_whole_text : p.separator} → '
                            '${p.fields.join(" / ")}',
                            style: const TextStyle(fontSize: 11.0),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18.0),
                                tooltip: s.paste_profile_edit,
                                onPressed: () => _edit(p),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18.0),
                                tooltip: s.paste_profile_delete,
                                onPressed: () => setState(() => _list.removeAt(i)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: Text(s.paste_profile_add),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.text_cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _list),
          child: Text(s.paste_save),
        ),
      ],
    );
  }
}

/// 单条规则编辑：名称 + 分隔符 + 字段顺序（上移/下移/删除/追加）。
class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({this.initial});

  final ProxyPasteProfile? initial;

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _separator;
  late List<String> _fields;
  String? _hint;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _separator = TextEditingController(text: initial?.separator ?? '');
    _fields = initial == null
        ? [
            PasteField.name,
            PasteField.type,
            PasteField.host,
            PasteField.port,
            PasteField.user,
            PasteField.pass,
          ]
        : List<String>.from(initial.fields);
  }

  @override
  void dispose() {
    _name.dispose();
    _separator.dispose();
    super.dispose();
  }

  String _label(S s, String field) {
    switch (field) {
      case PasteField.name:
        return s.paste_field_name;
      case PasteField.type:
        return s.paste_field_type;
      case PasteField.host:
        return s.paste_field_host;
      case PasteField.port:
        return s.paste_field_port;
      case PasteField.user:
        return s.paste_field_user;
      case PasteField.pass:
        return s.paste_field_pass;
      case PasteField.hostPort:
        return s.paste_field_host_port;
      case PasteField.url:
        return s.paste_field_url;
      case PasteField.ignore:
        return s.paste_field_ignore;
      default:
        return field;
    }
  }

  void _save(S s) {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _hint = s.paste_profile_need_name);
      return;
    }
    if (_fields.isEmpty) {
      setState(() => _hint = s.paste_profile_need_field);
      return;
    }
    final profile = ProxyPasteProfile(
      id: widget.initial?.id ?? ProxyPasteProfiles.newId(),
      name: name,
      separator: _separator.text,
      fields: List<String>.from(_fields),
      fixedType: widget.initial?.fixedType ?? '',
    );
    Navigator.pop(context, profile);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final unused = PasteField.all.where((f) => !_fields.contains(f)).toList();
    return AlertDialog(
      title: Text(widget.initial == null ? s.paste_profile_add : s.paste_profile_edit),
      content: SizedBox(
        width: 460.0,
        height: 430.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: s.paste_profile_name,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10.0),
            TextField(
              controller: _separator,
              decoration: InputDecoration(
                labelText: s.paste_separator,
                hintText: s.paste_separator_hint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10.0),
            Row(
              children: [
                Expanded(
                    child: Text(s.paste_profile_fields,
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                PopupMenuButton<String>(
                  enabled: unused.isNotEmpty,
                  tooltip: s.paste_profile_fields_add,
                  icon: const Icon(Icons.add, size: 20.0),
                  onSelected: (v) => setState(() => _fields.add(v)),
                  itemBuilder: (ctx) => unused
                      .map((f) => PopupMenuItem(
                            value: f,
                            child: Text(_label(s, f)),
                          ))
                      .toList(),
                ),
              ],
            ),
            Expanded(
              child: _fields.isEmpty
                  ? Center(
                      child: Text(s.paste_profile_need_field,
                          style: const TextStyle(fontSize: 12.0, color: Colors.grey)),
                    )
                  : ListView.builder(
                      itemCount: _fields.length,
                      itemBuilder: (ctx, i) {
                        final f = _fields[i];
                        return Row(
                          children: [
                            SizedBox(
                              width: 24.0,
                              child: Text('${i + 1}', style: const TextStyle(fontSize: 12.0)),
                            ),
                            Expanded(
                                child: Text(_label(s, f),
                                    style: const TextStyle(fontSize: 13.0))),
                            IconButton(
                              icon: const Icon(Icons.arrow_upward, size: 16.0),
                              onPressed: i == 0
                                  ? null
                                  : () => setState(() {
                                        final v = _fields.removeAt(i);
                                        _fields.insert(i - 1, v);
                                      }),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_downward, size: 16.0),
                              onPressed: i == _fields.length - 1
                                  ? null
                                  : () => setState(() {
                                        final v = _fields.removeAt(i);
                                        _fields.insert(i + 1, v);
                                      }),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16.0),
                              onPressed: () => setState(() => _fields.removeAt(i)),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (_hint != null)
              Text(_hint!, style: const TextStyle(fontSize: 12.0, color: Colors.orange)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.text_cancel),
        ),
        TextButton(
          onPressed: () => _save(s),
          child: Text(s.paste_save),
        ),
      ],
    );
  }
}
