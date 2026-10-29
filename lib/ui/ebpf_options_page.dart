import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:appproxy/data/ebpf_options.dart';
import 'package:appproxy/generated/l10n.dart';


/// eBPF 高级选项页（从添加/修改配置页进入）。
///
/// 只负责编辑 [EbpfAdvancedOptions] 并原样返回（pop 时回传），
/// 不直接写 proxyConfig.json —— 保存动作仍在添加/修改页的「保存」按钮上，
/// 这样"进了高级页又反悔不保存"的语义与表单其他字段一致。
class EbpfAdvancedOptionsPage extends StatefulWidget {
  final EbpfAdvancedOptions initial;

  /// 上游代理类型（http / socks5）：决定「HTTP 代理接管 UDP」项是否显示、
  /// 以及 udp 类型 DNS 服务器能否选"经代理"。
  final String proxyType;

  const EbpfAdvancedOptionsPage({
    super.key,
    required this.initial,
    required this.proxyType,
  });

  @override
  State<EbpfAdvancedOptionsPage> createState() => _EbpfAdvancedOptionsPageState();
}

class _EbpfAdvancedOptionsPageState extends State<EbpfAdvancedOptionsPage> {
  late EbpfAdvancedOptions _o;
  late final TextEditingController _customJsonController;

  bool get _isHttp => widget.proxyType.trim().toLowerCase() == 'http';

  @override
  void initState() {
    super.initState();
    // 深拷贝一份再编辑：编辑过程不污染调用方手里的那份（只有 pop 回传时才生效）
    final src = widget.initial;
    _o = EbpfAdvancedOptions(
      dnsMode: src.dnsMode,
      dnsServers: src.dnsServers
          .map((e) => EbpfDnsServer(type: e.type, server: e.server, detour: e.detour))
          .toList(),
      dnsStrategy: src.dnsStrategy,
      dnsRoute: src.dnsRoute,
      ipv6: src.ipv6,
      bypassPrivate: src.bypassPrivate,
      udpTimeout: src.udpTimeout,
      bypassPorts: List.of(src.bypassPorts),
      httpUdpAction: src.httpUdpAction,
      customJson: src.customJson,
    );
    _customJsonController = TextEditingController(text: _o.customJson);
  }

  @override
  void dispose() {
    _customJsonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // 各字段编辑时已 setState 写进 [_o]；✓ 按钮把 [_o] 带回给调用方，
    // 系统返回键/手势 = 放弃修改（不回传，调用方手里的那份保持原值）
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.ebpf_adv_title),
          backgroundColor: Theme.of(context).primaryColor,
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () {
                _o.customJson = _customJsonController.text;
                Navigator.pop(context, _o);
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(12.0),
          children: [
            _sectionHeader(s.ebpf_adv_sec_capture),
            _optionTile(
              label: s.ebpf_adv_ipv6,
              value: _o.ipv6,
              items: {'': s.ebpf_value_default_on, 'off': s.ebpf_value_off},
              help: s.ebpf_adv_ipv6_help,
              onChanged: (v) => setState(() => _o.ipv6 = v),
            ),
            _optionTile(
              label: s.ebpf_adv_bypass_private,
              value: _o.bypassPrivate,
              items: {'': s.ebpf_value_default_on, 'off': s.ebpf_value_off},
              help: s.ebpf_adv_bypass_private_help,
              onChanged: (v) => setState(() => _o.bypassPrivate = v),
            ),
            _optionTile(
              label: s.ebpf_adv_udp_timeout,
              value: _o.udpTimeout,
              items: {
                '': s.ebpf_value_default,
                '30s': '30s',
                '1m': '1m',
                '5m': '5m',
                '10m': '10m',
              },
              help: s.ebpf_adv_udp_timeout_help,
              onChanged: (v) => setState(() => _o.udpTimeout = v),
            ),
            _bypassPortsTile(s),
            _sectionHeader(s.ebpf_adv_sec_dns),
            _optionTile(
              label: s.ebpf_adv_dns_mode,
              value: _o.dnsMode,
              items: {
                '': '${s.ebpf_adv_dns_mode_respect} (${s.ebpf_value_default})',
                'respect_policy': s.ebpf_adv_dns_mode_respect,
                'hijack': s.ebpf_adv_dns_mode_hijack,
                'off': s.ebpf_adv_dns_mode_off,
              },
              help: s.ebpf_adv_dns_mode_help,
              onChanged: (v) => setState(() => _o.dnsMode = v),
            ),
            if (_o.dnsMode != 'off') ...[
              _dnsServersTile(s),
              _optionTile(
                label: s.ebpf_adv_dns_strategy,
                value: _o.dnsStrategy,
                items: {
                  '': s.ebpf_value_default,
                  'ipv4_only': s.ebpf_adv_dns_strategy_v4only,
                  'prefer_ipv4': s.ebpf_adv_dns_strategy_preferv4,
                  'ipv6_only': s.ebpf_adv_dns_strategy_v6only,
                },
                help: s.ebpf_adv_dns_strategy_help,
                onChanged: (v) => setState(() => _o.dnsStrategy = v),
              ),
              _optionTile(
                label: s.ebpf_adv_dns_route,
                value: _o.dnsRoute,
                items: {
                  '': '${s.ebpf_adv_dns_route_direct} (${s.ebpf_value_default})',
                  'proxy': s.ebpf_adv_dns_route_proxy,
                },
                help: s.ebpf_adv_dns_route_help,
                onChanged: (v) => setState(() => _o.dnsRoute = v),
              ),
            ],
            _sectionHeader(s.ebpf_adv_sec_compat),
            if (_isHttp)
              _optionTile(
                label: s.ebpf_adv_http_udp,
                value: _o.httpUdpAction,
                items: {
                  '': '${s.ebpf_adv_http_udp_reject} (${s.ebpf_value_default})',
                  'masque': s.ebpf_adv_http_udp_masque,
                },
                help: s.ebpf_adv_http_udp_help,
                onChanged: (v) => setState(() => _o.httpUdpAction = v),
              ),
            _customJsonTile(s),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4.0, 16.0, 4.0, 4.0),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13.0,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
          ),
        ),
      );

  /// 单选下拉项 + 说明文字（每项的含义直接写在卡片里，用户不需要猜）
  Widget _optionTile({
    required String label,
    required String value,
    required Map<String, String> items,
    required String help,
    required ValueChanged<String> onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 14.0))),
                DropdownButton<String>(
                  value: value,
                  underline: const SizedBox.shrink(),
                  items: items.entries
                      .map((e) => DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value, style: const TextStyle(fontSize: 13.0)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onChanged(v);
                  },
                ),
              ],
            ),
            Text(
              help,
              style: const TextStyle(fontSize: 12.0, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// 绕过端口：chip 列表 + 添加对话框（校验 1-65535 或 a-b 范围）
  Widget _bypassPortsTile(S s) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(s.ebpf_adv_bypass_port, style: const TextStyle(fontSize: 14.0))),
                IconButton(
                  icon: const Icon(Icons.add, size: 20.0),
                  onPressed: () => _addBypassPort(s),
                ),
              ],
            ),
            if (_o.bypassPorts.isEmpty)
              Text(s.ebpf_adv_bypass_port_empty,
                  style: const TextStyle(fontSize: 12.0, color: Colors.grey))
            else
              Wrap(
                spacing: 6.0,
                children: _o.bypassPorts
                    .map((p) => Chip(
                          label: Text(p, style: const TextStyle(fontSize: 12.0)),
                          onDeleted: () => setState(() => _o.bypassPorts.remove(p)),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            Text(s.ebpf_adv_bypass_port_help,
                style: const TextStyle(fontSize: 12.0, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Future<void> _addBypassPort(S s) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.ebpf_adv_bypass_port_add),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(hintText: s.ebpf_adv_bypass_port_hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(s.text_cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(s.text_confirm),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    if (!EbpfAdvancedOptions.isValidPortOrRange(result)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.ebpf_adv_bypass_port_invalid)));
      }
      return;
    }
    setState(() {
      if (!_o.bypassPorts.contains(result)) _o.bypassPorts.add(result);
    });
  }

  /// DNS 服务器：空 = 系统应答（默认档）；否则显示已选列表 + 内置池选择 + 手动添加
  Widget _dnsServersTile(S s) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Text(s.ebpf_adv_dns_servers,
                        style: const TextStyle(fontSize: 14.0))),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _showPresetPicker(s),
                      child: Text(s.ebpf_adv_dns_add_preset,
                          style: const TextStyle(fontSize: 12.0)),
                    ),
                    TextButton(
                      onPressed: () => _addCustomServer(s),
                      child: Text(s.ebpf_adv_dns_add_custom,
                          style: const TextStyle(fontSize: 12.0)),
                    ),
                  ],
                ),
              ],
            ),
            if (_o.dnsServers.isEmpty)
              Text(s.ebpf_adv_dns_servers_empty,
                  style: const TextStyle(fontSize: 12.0, color: Colors.grey))
            else
              ..._o.dnsServers.asMap().entries.map((entry) {
                final i = entry.key;
                final srv = entry.value;
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${srv.type} ${srv.displayName}',
                        style: const TextStyle(fontSize: 13.0),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownButton<String>(
                      value: srv.detour,
                      underline: const SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(
                            value: 'direct',
                            child: Text(s.ebpf_adv_dns_detour_direct,
                                style: const TextStyle(fontSize: 12.0))),
                        DropdownMenuItem(
                          value: 'proxy',
                          enabled: !(_isHttp && srv.type == 'udp'),
                          child: Text(
                            s.ebpf_adv_dns_route_proxy,
                            style: TextStyle(
                                fontSize: 12.0,
                                color: (_isHttp && srv.type == 'udp')
                                    ? Colors.grey
                                    : null),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => srv.detour = v);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18.0),
                      onPressed: () => setState(() => _o.dnsServers.removeAt(i)),
                    ),
                  ],
                );
              }),
            Text(s.ebpf_adv_dns_servers_help,
                style: const TextStyle(fontSize: 12.0, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  /// 内置池多选：勾中的加入列表（已存在同名服务器则跳过/移除）
  Future<void> _showPresetPicker(S s) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          bool selected(EbpfDnsPreset p) => _o.dnsServers
              .any((e) => e.type == p.type && e.server == p.server);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(s.ebpf_adv_dns_add_preset,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                ...EbpfDnsPreset.all.map((p) {
                  final label = p.type == 'local'
                      ? s.ebpf_adv_dns_preset_local
                      : '${p.type}  ${p.server}';
                  final sub = p.detour == 'proxy'
                      ? s.ebpf_adv_dns_route_proxy
                      : s.ebpf_adv_dns_detour_direct;
                  final disabled = _isHttp && p.type == 'udp' && p.detour == 'proxy';
                  return CheckboxListTile(
                    value: selected(p),
                    enabled: !disabled,
                    dense: true,
                    title: Text(label, style: const TextStyle(fontSize: 13.0)),
                    subtitle: Text(
                      p.recommended ? '$sub · ${s.ebpf_adv_dns_recommended}' : sub,
                      style: const TextStyle(fontSize: 11.0),
                    ),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          if (!selected(p)) _o.dnsServers.add(p.toServer());
                        } else {
                          _o.dnsServers.removeWhere(
                              (e) => e.type == p.type && e.server == p.server);
                        }
                      });
                      setSheetState(() {});
                    },
                  );
                }),
              ],
            ),
          );
        });
      },
    );
  }

  /// 手动添加服务器：类型 + 地址 + 经代理/直连
  Future<void> _addCustomServer(S s) async {
    final serverController = TextEditingController();
    String type = 'https';
    String detour = 'direct';
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        final isLocal = type == 'local';
        return AlertDialog(
          title: Text(s.ebpf_adv_dns_add_custom),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(labelText: s.ebpf_adv_dns_type),
                items: const [
                  DropdownMenuItem(value: 'https', child: Text('https (DoH)')),
                  DropdownMenuItem(value: 'tls', child: Text('tls (DoT)')),
                  DropdownMenuItem(value: 'quic', child: Text('quic (DoQ)')),
                  DropdownMenuItem(value: 'udp', child: Text('udp')),
                  DropdownMenuItem(value: 'local', child: Text('local (系统)')),
                ],
                onChanged: (v) => setDialogState(() {
                  type = v ?? 'https';
                  // http 代理下 udp 类型不能选经代理（http 出站没有 UDP），强制回直连
                  if (_isHttp && type == 'udp') detour = 'direct';
                }),
              ),
              if (!isLocal)
                TextField(
                  controller: serverController,
                  decoration: InputDecoration(
                    labelText: s.ebpf_adv_dns_server_addr,
                    hintText: type == 'udp' ? '223.5.5.5' : 'dns.alidns.com',
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: detour,
                decoration: InputDecoration(labelText: s.ebpf_adv_dns_detour),
                items: [
                  DropdownMenuItem(
                      value: 'direct', child: Text(s.ebpf_adv_dns_detour_direct)),
                  DropdownMenuItem(
                    value: 'proxy',
                    enabled: !(_isHttp && type == 'udp'),
                    child: Text(s.ebpf_adv_dns_route_proxy),
                  ),
                ],
                onChanged: (v) => setDialogState(() => detour = v ?? 'direct'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.text_cancel)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.text_confirm)),
          ],
        );
      }),
    );
    if (added != true) return;
    final server = serverController.text.trim();
    if (type != 'local' && server.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.ebpf_adv_dns_server_invalid)));
      }
      return;
    }
    if (_isHttp && type == 'udp' && detour == 'proxy') detour = 'direct';
    setState(() {
      final exists = _o.dnsServers.any((e) => e.type == type && e.server == server);
      if (!exists) {
        _o.dnsServers.add(EbpfDnsServer(type: type, server: server, detour: detour));
      }
    });
  }

  /// 自定义 JSON 覆盖（多行编辑；保存时校验合法性，非法则红字提示但不强拦——
  /// 生成器启动前会再校验一次并给出明确报错，这里只做即时反馈）
  Widget _customJsonTile(S s) {
    String? error;
    final raw = _customJsonController.text.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) error = s.ebpf_adv_json_not_object;
      } catch (_) {
        error = s.ebpf_adv_json_invalid;
      }
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.ebpf_adv_json_override, style: const TextStyle(fontSize: 14.0)),
            const SizedBox(height: 6.0),
            TextField(
              controller: _customJsonController,
              maxLines: 5,
              style: const TextStyle(fontSize: 12.0, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: '{"dns": {"strategy": "ipv4_only"}}',
                border: const OutlineInputBorder(),
                errorText: error,
              ),
              onChanged: (v) {
                _o.customJson = v;
                setState(() {}); // 触发即时校验
              },
            ),
            Text(s.ebpf_adv_json_help,
                style: const TextStyle(fontSize: 12.0, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

