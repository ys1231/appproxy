import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

/// eBPF 高级选项页：数据面/接管网络之外的所有可调项（接管、DNS、兼容、JSON 覆盖）。
///
/// ─────────────────────────────────────────────────────────────────────────
/// 【设计：三档可配置性】
///   第 1 档：什么都不配 → 全自动合理默认（升级后的旧配置即落此档）；
///   第 2 档：本页结构化选项 → 每个必要项都可改、带说明、内置推荐值；
///   第 3 档：自定义 JSON 覆盖 → 深度合并进最终 config.json，兼容性终极兜底。
///
/// 【贯穿原则：不写进配置 = sing-box 默认值生效】
/// 生成器只写用户显式选择的值；「空字符串 = 自动」的选项一律不落盘，
/// 这样二进制升级、默认值漂移都不会被 app 固化行为绑死（例如不写 ipv6 字段，
/// 就由 sing-box 自己决定默认 true，而不是我们替他写死）。
///
/// 【存储】所有键存进 proxyConfig.json（跟随备份/恢复），读取侧统一走
/// [EbpfAdvancedOptions.fromProxyConfig]：未知/非法值一律回落空串(自动)，
/// 手工编辑或异常备份不会把非法值带进生成器。
/// ─────────────────────────────────────────────────────────────────────────

class EbpfAdvancedOptions {
  /// 接管模式：'' = respect_policy（默认，先过包名筛选再接管 53 端口，
  /// 只有被监听 app 的 DNS 进 sing-box）；
  /// 'hijack' = 全机 DNS 都进 sing-box（包括未监听的 app）；
  /// 'off' = 不接管 53 端口（DNS 走内核直连，不进 sing-box）。
  String dnsMode;

  /// DNS 服务器列表。空 = 默认档「系统 DNS 应答」（生成 {"type":"local"}）。
  /// 每项 {'type': 'https'|'tls'|'quic'|'udp'|'local', 'server': '...',
  ///        'detour': 'proxy'|'direct'}，local 无 server。
  final List<EbpfDnsServer> dnsServers;

  /// DNS 策略：'' = 默认 / 'ipv4_only' / 'ipv6_only' / 'prefer_ipv4'
  String dnsStrategy;

  /// DNS 路由（sing-box 内部域名解析的出站）：'' = 直连 / 'proxy' = 经代理
  String dnsRoute;

  /// 接管 IPv6：'' = 默认(开) / 'off' = 关
  String ipv6;

  /// 绕过私有地址：'' = 默认(开) / 'off' = 关
  String bypassPrivate;

  /// UDP 会话超时：'' = 默认(5m) / '30s' / '1m' / '5m' / '10m'
  String udpTimeout;

  /// 绕过端口列表（这些目标端口的流量直连不接管），如 ['853', '9000-9010']
  final List<String> bypassPorts;

  /// HTTP 代理接管 UDP 时的处理：'' = 拒绝(快速失败) / 'masque' = 尝试 CONNECT-UDP
  String httpUdpAction;

  /// 自定义 JSON 覆盖（深度合并到最终 config.json），空 = 不覆盖
  String customJson;

  EbpfAdvancedOptions({
    this.dnsMode = '',
    List<EbpfDnsServer>? dnsServers,
    this.dnsStrategy = '',
    this.dnsRoute = '',
    this.ipv6 = '',
    this.bypassPrivate = '',
    this.udpTimeout = '',
    List<String>? bypassPorts,
    this.httpUdpAction = '',
    this.customJson = '',
  })  : dnsServers = dnsServers ?? [],
        bypassPorts = bypassPorts ?? [];

  static const Set<String> validDnsModes = {'respect_policy', 'hijack', 'off'};
  static const Set<String> validDnsStrategies = {'ipv4_only', 'ipv6_only', 'prefer_ipv4'};
  static const Set<String> validDnsRoutes = {'proxy'};
  static const Set<String> validToggles = {'off'}; // ipv6/bypassPrivate 只有"关"一个非默认值
  static const Set<String> validUdpTimeouts = {'30s', '1m', '5m', '10m'};
  static const Set<String> validHttpUdpActions = {'masque'};

  /// 从 proxyConfig.json 的 map 解析（编辑配置页回填/列表页生成前）。
  /// 任何非法值都静默回落自动——生成器前还有一道严格校验，这里只负责"不让坏值进 UI"。
  factory EbpfAdvancedOptions.fromProxyConfig(Map<dynamic, dynamic> proxy) {
    String str(String key) => (proxy[key] ?? '').toString().trim();
    String clean(String key, Set<String> valid) {
      final v = str(key).toLowerCase();
      return valid.contains(v) ? v : '';
    }

    final servers = <EbpfDnsServer>[];
    final rawServers = str('ebpfDnsServers');
    if (rawServers.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawServers);
        if (decoded is List) {
          for (final item in decoded) {
            final s = EbpfDnsServer.fromJson(item);
            if (s != null) servers.add(s);
          }
        }
      } catch (e) {
        debugPrint('EbpfAdvancedOptions: ebpfDnsServers 解析失败，按默认处理: $e');
      }
    }

    final ports = <String>[];
    final rawPorts = str('ebpfBypassPorts');
    if (rawPorts.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPorts);
        if (decoded is List) {
          ports.addAll(decoded
              .map((e) => e.toString().trim())
              .where((e) => EbpfAdvancedOptions.isValidPortOrRange(e)));
        }
      } catch (e) {
        debugPrint('EbpfAdvancedOptions: ebpfBypassPorts 解析失败: $e');
      }
    }

    return EbpfAdvancedOptions(
      dnsMode: clean('ebpfDnsMode', validDnsModes),
      dnsServers: servers,
      dnsStrategy: clean('ebpfDnsStrategy', validDnsStrategies),
      dnsRoute: clean('ebpfDnsRoute', validDnsRoutes),
      ipv6: clean('ebpfIpv6', validToggles),
      bypassPrivate: clean('ebpfBypassPrivate', validToggles),
      udpTimeout: clean('ebpfUdpTimeout', validUdpTimeouts),
      bypassPorts: ports,
      httpUdpAction: clean('ebpfHttpUdpAction', validHttpUdpActions),
      customJson: str('ebpfCustomJson'),
    );
  }

  /// 写回 proxyConfig.json 的键值（只写有内容的；空 = 自动 = 不存该键，
  /// 保持配置最小化，也让"没配过"与"配了又清空"不可区分、都回落默认）。
  Map<String, String> toProxyConfigEntries() {
    final entries = <String, String>{};
    if (dnsMode.isNotEmpty) entries['ebpfDnsMode'] = dnsMode;
    if (dnsServers.isNotEmpty) {
      entries['ebpfDnsServers'] =
          jsonEncode(dnsServers.map((e) => e.toJson()).toList());
    }
    if (dnsStrategy.isNotEmpty) entries['ebpfDnsStrategy'] = dnsStrategy;
    if (dnsRoute.isNotEmpty) entries['ebpfDnsRoute'] = dnsRoute;
    if (ipv6.isNotEmpty) entries['ebpfIpv6'] = ipv6;
    if (bypassPrivate.isNotEmpty) entries['ebpfBypassPrivate'] = bypassPrivate;
    if (udpTimeout.isNotEmpty) entries['ebpfUdpTimeout'] = udpTimeout;
    if (bypassPorts.isNotEmpty) entries['ebpfBypassPorts'] = jsonEncode(bypassPorts);
    if (httpUdpAction.isNotEmpty) entries['ebpfHttpUdpAction'] = httpUdpAction;
    if (customJson.trim().isNotEmpty) entries['ebpfCustomJson'] = customJson.trim();
    return entries;
  }

  /// 本模型持有的全部 proxyConfig 键。
  ///
  /// 列表页编辑合并时用：先 removeWhere 清掉旧条目里的这些键，再 addAll 新表单数据，
  /// 保证「改成默认 = 不存该键」能真正删掉旧值（否则旧的 ebpfDnsMode 等会残留生效）。
  static const List<String> storageKeys = [
    'ebpfDnsMode',
    'ebpfDnsServers',
    'ebpfDnsStrategy',
    'ebpfDnsRoute',
    'ebpfIpv6',
    'ebpfBypassPrivate',
    'ebpfUdpTimeout',
    'ebpfBypassPorts',
    'ebpfHttpUdpAction',
    'ebpfCustomJson',
  ];

  /// 本组选项是否全部处于默认（用于入口行的摘要展示）
  bool get isAllDefault =>
      dnsMode.isEmpty &&
      dnsServers.isEmpty &&
      dnsStrategy.isEmpty &&
      dnsRoute.isEmpty &&
      ipv6.isEmpty &&
      bypassPrivate.isEmpty &&
      udpTimeout.isEmpty &&
      bypassPorts.isEmpty &&
      httpUdpAction.isEmpty &&
      customJson.trim().isEmpty;

  /// 端口或端口范围校验：'853' 或 '9000-9010'，端口 1-65535，范围起<=止
  static bool isValidPortOrRange(String s) {
    final single = RegExp(r'^\d{1,5}$');
    final range = RegExp(r'^(\d{1,5})-(\d{1,5})$');
    if (single.hasMatch(s)) {
      final p = int.parse(s);
      return p >= 1 && p <= 65535;
    }
    final m = range.firstMatch(s);
    if (m != null) {
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      return a >= 1 && b <= 65535 && a <= b;
    }
    return false;
  }

  /// ── 以下是 sing-box 配置片段生成（Dart 侧单一来源；Kotlin EbpfConfigBuilder 保持同规则）──

  /// local.dns_mode：空 → respect_policy（sing-box 默认，先包名筛选再接管 53）。
  String get effectiveDnsMode => dnsMode.isEmpty ? 'respect_policy' : dnsMode;

  /// 是否接管 53 端口（off = DNS 留在内核直连，不进 sing-box）
  bool get capturesDns => effectiveDnsMode != 'off';

  /// local 块的可选字段（不写 = sing-box 默认 true/5m，保持配置最小化）。
  /// 与 data_plane / dns_mode / include_package 等由生成器统一组装。
  Map<String, dynamic> buildLocalExtras() {
    final local = <String, dynamic>{};
    if (ipv6 == 'off') local['ipv6'] = false;
    if (bypassPrivate == 'off') local['bypass_private_address'] = false;
    if (bypassPorts.isNotEmpty) {
      final singles = <int>[];
      final ranges = <String>[];
      for (final p in bypassPorts) {
        if (p.contains('-')) {
          ranges.add(p);
        } else {
          singles.add(int.parse(p));
        }
      }
      if (singles.isNotEmpty) local['bypass_port'] = singles;
      if (ranges.isNotEmpty) local['bypass_port_range'] = ranges;
    }
    return local;
  }

  /// inbound 的可选字段：只有非默认的 udp_timeout 才写。
  Map<String, dynamic> buildInboundExtras() {
    if (udpTimeout.isNotEmpty) return {'udp_timeout': udpTimeout};
    return const {};
  }

  /// dns 段。
  ///
  /// [outboundTag] 上游出站标签（"经代理"的 detour 目标）。
  /// 返回 null = 不写 dns 段（dns_mode=off）：sing-box 兜底仍会自动创建 local 传输
  /// 供自身解析（见 box.go defaultTransportFallback），不需要我们写。
  ///
  /// 注意「dns-local 保证」：需要直连解析器兜底时（[needsLocalResolverBootstrap]），
  /// 若用户的自定义列表里没有 local 服务器，会自动补一台 —— 因为
  /// route.default_domain_resolver 恒引用 'dns-local'，列表里没有它解析器就是空标签。
  Map<String, dynamic>? buildDnsSection(String outboundTag) {
    if (!capturesDns) return null;
    final servers = <Map<String, dynamic>>[];
    // 默认档：系统 DNS 应答。不写 detour = 直连系统解析器（不经代理，
    // 对 http/socks5 代理都兼容，且启动零额外请求）。
    // 注意：标签固定用 dns-local（route.default_domain_resolver 引用它）
    if (dnsServers.isEmpty) {
      servers.add({'tag': 'dns-local', 'type': 'local'});
    } else {
      // 兜底：需要 local 解析器（dnsRoute=proxy 或经代理的 DoH/DoT/DoQ）但用户没选
      // local 时自动补一台，保证 default_domain_resolver 的 dns-local 引用有目标
      final effective = hasLocalResolver(dnsServers) || !needsLocalResolverBootstrap
          ? dnsServers
          : [...dnsServers, EbpfDnsServer(type: 'local', detour: 'direct')];
      final groupMembers = <String>[];
      for (var i = 0; i < effective.length; i++) {
        // local 类型的服务器同样用 dns-local 标签，保证 resolver 引用稳定
        final tag = effective[i].type == 'local' ? 'dns-local' : 'dns-$i';
        servers.add(effective[i].toServerJson(tag, outboundTag));
        groupMembers.add(tag);
      }
      if (servers.length > 1) {
        servers.add({
          'tag': 'dns-group',
          'type': 'group',
          'servers': groupMembers,
        });
      }
      return {
        'servers': servers,
        'final': effective.length > 1 ? 'dns-group' : servers.first['tag'],
        if (dnsStrategy.isNotEmpty) 'strategy': dnsStrategy,
      };
    }
    return {
      'servers': servers,
      'final': 'dns-local',
      if (dnsStrategy.isNotEmpty) 'strategy': dnsStrategy,
    };
  }

  /// route 段中由本模型决定的部分：DNS 劫持规则（仅 hijack）与
  /// http+UDP 的 reject/masque 规则（off 模式下豁免 53，不接管就不误杀直连 DNS）。
  ///
  /// [isHttp] 上游是否 http 代理；[capturesUdp] 是否接管 UDP；
  /// [outboundTag] 上游出站标签（masque 动作的 route 目标）；
  /// 返回需要**追加**到 route.rules 的规则（可能为空列表）。
  List<Map<String, dynamic>> buildRouteRules(
      {required bool isHttp, required bool capturesUdp, required String outboundTag}) {
    final rules = <Map<String, dynamic>>[];
    if (effectiveDnsMode == 'hijack') {
      // hijack = 全机 53 进 sing-box：内核已在筛选前定向，路由层补一条交给 DNS 模块
      rules.add({
        'port': 53,
        'action': 'hijack-dns',
      });
    }
    if (isHttp && capturesUdp) {
      // http 出站没有原生 UDP：默认 reject 让 UDP 快速失败（避免 MASQUE 404 风暴）；
      // masque = 显式路由给上游出站，让 sing-box 尝试 CONNECT-UDP（上游不支持会 404，
      // 用户显式选择即接受该风险）。
      // dns_mode=off 时 DNS 是内核直连流量（也走 eBPF UDP），必须豁免 53，
      // 否则"不接管 DNS"反而把被监听 app 的直连 DNS 杀了。
      if (httpUdpAction == 'masque') {
        rules.add({
          'network': ['udp'],
          'action': 'route',
          'outbound': outboundTag,
          if (!capturesDns) 'port_range': ['54:65535', '1:52'],
        });
      } else {
        rules.add({
          'network': ['udp'],
          'action': 'reject',
          if (!capturesDns) 'port_range': ['54:65535', '1:52'],
        });
      }
    }
    return rules;
  }

  /// route.default_domain_resolver：sing-box 自身需要解析域名时（经代理的 DoH 服务器
  /// 域名、"经代理"的 DNS 路由）用哪台 DNS、走哪个出站。
  ///
  /// 需要直连解析器兜底时（经代理的域名型 DNS / dnsRoute=proxy），default_domain_resolver
  /// 必须有 server：调用方负责保证 dns 段里一定有 local 服务器（默认档有；自定义档用户
  /// 没选 local 时自动补一台），所以这里恒写 'dns-local'。
  Map<String, dynamic> buildRouteExtras(String outboundTag) {
    final needsBootstrap = dnsRoute == 'proxy' || hasProxiedDomainServer(dnsServers);
    if (!needsBootstrap) return const {};
    final resolver = <String, dynamic>{'server': 'dns-local'};
    if (dnsRoute == 'proxy') {
      // DNS 路由=经代理：sing-box 内部解析（含 DoH 服务器域名）都走代理
      resolver['detour'] = outboundTag;
    }
    return {'default_domain_resolver': resolver};
  }

  /// 是否需要保证 dns 段里有 local 服务器（buildRouteExtras 会引用 dns-local）：
  /// dnsRoute=proxy，或有经代理的域名型 DNS 服务器（DoH/DoT/DoQ 域名要直连解析）。
  bool get needsLocalResolverBootstrap =>
      capturesDns && (dnsRoute == 'proxy' || hasProxiedDomainServer(dnsServers));

  /// 是否存在需要直连解析器兜底的"经代理域名型 DNS 服务器"（DoH/DoT/DoQ + 经代理）
  static bool hasProxiedDomainServer(List<EbpfDnsServer> servers) => servers.any(
      (e) => e.detour == 'proxy' && (e.type == 'https' || e.type == 'tls' || e.type == 'quic'));

  /// 默认档（servers 为空）或用户选了 local 时，dns 段里有 dns-local 解析器标签
  static bool hasLocalResolver(List<EbpfDnsServer> servers) =>
      servers.isEmpty || servers.any((e) => e.type == 'local');

  /// 自定义 JSON 覆盖：解析并校验必须是 JSON 对象；非法抛 [FormatException]
  /// （由生成器包成 ArgumentError 给用户看，不静默吞掉一份"以为生效了"的覆盖）。
  Map<String, dynamic>? parseCustomOverride() {
    final raw = customJson.trim();
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('自定义 JSON 覆盖必须是对象（{...}）');
    }
    return decoded;
  }

  /// 深度合并：override 的 Map 递归合并，其余类型（含数组、标量）直接覆盖。
  /// 数组不可合并 —— 用户写 `"servers": [...]` 就是要整个替换服务器列表。
  static Map<String, dynamic> deepMerge(
      Map<String, dynamic> base, Map<String, dynamic> override) {
    final out = Map<String, dynamic>.from(base);
    override.forEach((key, value) {
      final old = out[key];
      if (old is Map<String, dynamic> && value is Map<String, dynamic>) {
        out[key] = deepMerge(old, value);
      } else if (old is Map && value is Map) {
        out[key] = deepMerge(Map<String, dynamic>.from(old), Map<String, dynamic>.from(value));
      } else {
        out[key] = value;
      }
    });
    return out;
  }
}

/// 一台自定义 DNS 服务器（内置池与用户手动添加共用此模型）
class EbpfDnsServer {
  /// https(DoH) / tls(DoT) / quic(DoQ) / udp(明文) / local(系统)
  String type;

  /// 服务器地址：DoH/DoT/DoQ 填域名（如 dns.alidns.com），udp 填 IP。local 为空。
  String server;

  /// 'proxy' = 经代理 / 'direct' = 直连（udp 类型选 proxy 时 http 代理下不可用）
  String detour;

  EbpfDnsServer({required this.type, this.server = '', this.detour = 'direct'});

  static const Set<String> validTypes = {'https', 'tls', 'quic', 'udp', 'local'};

  static EbpfDnsServer? fromJson(dynamic item) {
    if (item is! Map) return null;
    final type = (item['type'] ?? '').toString().trim().toLowerCase();
    if (!validTypes.contains(type)) return null;
    final server = (item['server'] ?? '').toString().trim();
    if (type != 'local' && server.isEmpty) return null;
    final detour = (item['detour'] ?? '').toString().trim().toLowerCase();
    return EbpfDnsServer(
      type: type,
      server: server,
      detour: detour == 'proxy' ? 'proxy' : 'direct',
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (type != 'local') 'server': server,
        'detour': detour,
      };

  /// sing-box dns.servers[] 条目（sing-box 1.12+ 新格式：type + server）
  Map<String, dynamic> toServerJson(String tag, String outboundTag) => {
        'tag': tag,
        'type': type,
        if (type != 'local') 'server': server,
        if (detour == 'proxy') 'detour': outboundTag,
      };

  /// 内置池用的显示名（服务器地址本身）
  String get displayName => type == 'local' ? 'local' : server;
}

/// 内置 DNS 服务器池（UI 多选列表的数据源；用户也可手动添加池外服务器）。
/// detour 是默认值，用户可在列表里切换。
class EbpfDnsPreset {
  final String type;
  final String server;
  final String detour;
  final bool recommended;

  const EbpfDnsPreset(this.type, this.server, this.detour, {this.recommended = false});

  EbpfDnsServer toServer() =>
      EbpfDnsServer(type: type, server: server, detour: detour);

  static const List<EbpfDnsPreset> all = [
    // 经代理的 DoH：域名本身需要解析，生成器用 route.default_domain_resolver 直连兜底
    EbpfDnsPreset('https', 'dns.alidns.com', 'proxy', recommended: true),
    EbpfDnsPreset('https', 'doh.pub', 'proxy', recommended: true),
    EbpfDnsPreset('https', 'cloudflare-dns.com', 'proxy'),
    EbpfDnsPreset('https', 'dns.google', 'proxy'),
    EbpfDnsPreset('tls', 'dot.pub', 'proxy'),
    // 明文 UDP：直连才有意义（IP 形式不需要再解析）
    EbpfDnsPreset('udp', '223.5.5.5', 'direct'),
    EbpfDnsPreset('udp', '119.29.29.29', 'direct'),
    EbpfDnsPreset('udp', '114.114.114.114', 'direct'),
    // 系统解析器
    EbpfDnsPreset('local', '', 'direct'),
  ];
}
