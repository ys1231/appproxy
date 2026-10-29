import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:appproxy/data/ebpf_options.dart' show EbpfAdvancedOptions;

/// sing-box config.json 生成器（Flutter 侧）。
///
/// ─────────────────────────────────────────────────────────────────────────
/// 【先弄懂这套东西在干什么】
///
/// 1. **目标**：让「指定 app」的网络流量**透明地**走代理 —— 也就是那些 app 自己
///    完全不知道有代理存在（不用连 Wi-Fi 手动设代理、也不用装 VPN），它们发出的连接
///    在手机内部就被拦下来，改由 sing-box 转发到我们配置的代理服务器。
///
/// 2. **谁在干活**：sing-box（本分支按 ABI 下载的可执行文件，编译带 `with_ebpf` 标签）。
///    app 只负责「生成配置 + 用 root 把它拉起来」，具体的拦截与转发全在 sing-box 里。
///
/// 3. **这个文件产出的是 sing-box 的配置骨架**（config.json），它由这几部分组成：
///      log        —— 日志写哪、什么级别
///      dns        —— 由 [EbpfAdvancedOptions] 驱动（默认：系统 DNS 应答，仅接管被监听 app）
///      route      —— 默认出口 + 由选项模型追加的规则（DNS 劫持/UDP 处理）
///      inbounds   —— 流量从哪进来（这里只有一种：ebpf 透明接管）
///      outbounds  —— 流量往哪出去（这里只有一种：你填的那个 http/socks 代理）
///    流量路径：目标 app 的连接 → [inbounds.ebpf 拦下] → [路由] → [outbounds 发给代理]
///
/// 4. **为什么由 Dart 生成**：生成所需的数据（代理地址、分应用列表、eBPF 选项）本来
///    就在 Flutter 侧；放在这边生成，UI 想「预览配置」时直接调同一个函数即可，
///    不需要额外从原生取一遍。原生只负责把字符串落盘（见 EbpfProxyManager.start）。
///
/// 注意：Kotlin 侧还有一份等价实现 `EbpfConfigBuilder.kt`，那是给 MCP 调用用的
///（MCP 不经过 Flutter，拿不到这份 Dart 函数）。**改映射规则时两边都要改**。
/// ─────────────────────────────────────────────────────────────────────────
///
/// 【字段映射总表】输入是 UI 里填的代理配置 + 分应用勾选，输出是 config.json
///
///   outbounds[0].type          ← proxyType（**只接受 http / socks5**，其它值直接报错）
///                                `http`   → `"type":"http"`（HTTP/1 CONNECT，不写 version）
///                                `socks5` → `"type":"socks"` + `"version":"5"`
///   outbounds[0].server        ← proxyHost（trim 后必须非空）
///   outbounds[0].server_port   ← proxyPort（必须是 1-65535 的整数）
///   outbounds[0].username      ← proxyUser（为空则**整个字段省略**，不要写成空串）
///   outbounds[0].password      ← proxyPass（同上）
///   local.include_package      ← 分应用列表（**空列表则省略该字段 = 全部 app 都接管**）
///   local.exclude_package      ← 本应用包名（否则 appproxy 自己的请求也会被接管，可能成环）
///   local.data_plane           ← ebpfDataPlane：空 → 按设备能力（cgroup 优先，其次
///                                socket_assign）；旧值 tc → socket_assign；其它值报错
///   local.dns_mode             ← ebpfDnsMode：空 → respect_policy（只接管被监听 app 的
///                                DNS）；hijack = 全机 DNS；off = 不接管
///   inbounds[0].network        ← ebpfNetwork：空/缺省 = all；合法值 all/tcp/udp，其它报错
///   dns / route / local 其余项 ← 由 [EbpfAdvancedOptions] 从 ebpf* 键解析后驱动
///                                （ebpfDnsServers/ebpfDnsStrategy/ebpfDnsRoute/ebpfIpv6/
///                                ebpfBypassPrivate/ebpfUdpTimeout/ebpfBypassPorts/
///                                ebpfHttpUdpAction/ebpfCustomJson）
///
/// 【贯穿原则：不写进配置 = sing-box 默认值生效】
/// 只写用户显式选择的值；sing-box 默认就合理的字段（ipv6=true、bypass_private=true、
/// udp_timeout=5m）一律不写，二进制升级改默认值时 app 不会被旧固化行为绑死。
///
/// 说明：以上 ebpf* 键由「编辑配置」页写入 proxyConfig.json（跟随备份/恢复）；
/// 旧配置没有这些键时全部回落默认值（空 = 自动），行为与旧版兼容（且 DNS 从
/// 旧版的"全局 hijack + 双 DoH"变为"仅被监听 app + 系统应答"，正是需求目标）。
///
/// 【包名 vs UID —— 为什么我们只填包名】
/// 内核里的 eBPF 程序只能按 UID 判断进程（`bpf_get_current_uid_gid`），而 Android 里
/// 「包名 → UID」是系统知识。这个换算**由 sing-box 自己做**：它启动时读
/// `/data/system/packages.xml`（root 才读得到）建映射，并监听该文件变化（装/卸应用自动生效）。
/// 所以这里只写包名，不需要（也不应该）在 app 里算 UID。
///
/// 【log.output 为什么用相对路径 `box.log`】
/// 原生启动 sing-box 前会先 `cd <运行目录>`（见 EbpfProxyManager.start 的步骤 4），
/// 相对路径自然落在运行目录里 —— 这样 Dart 侧完全不需要知道原生把目录选在了哪
///（那是原生"实测"决定的，可能是 app 私有目录，也可能回退 /data/local/tmp）。
class EbpfConfigGenerator {
  EbpfConfigGenerator._(); // 纯静态工具类，不实例化

  /// ebpfNetwork 的合法值：all = TCP+UDP / tcp = 仅 TCP / udp = 仅 UDP
  static const Set<String> _validNetworks = {'all', 'tcp', 'udp'};

  /// ebpfDataPlane 的合法值（tc 是旧值，生成前迁移成 socket_assign）
  static const Set<String> _validDataPlanes = {'cgroup', 'socket_assign'};

  /// 生成 config.json 字符串
  ///
  /// [proxy]       代理配置项（proxyType/proxyHost/proxyPort/proxyUser/proxyPass，
  ///               以及 eBPF 可调项 ebpfNetwork/ebpfDataPlane 与高级选项 ebpf* 键）
  /// [packageList] 分应用包名列表（空 = 全部接管）
  /// [selfPackage] 本应用包名（写进 exclude_package）
  /// [cgroupSupported]        本机 cgroup 数据面是否可用（决定 ebpfDataPlane 为空时的默认值）
  /// [socketAssignSupported]  本机 socket_assign 数据面是否可用（同上）
  ///
  /// 输入非法（proxyType/host/port/ebpfNetwork/ebpfDataPlane/高级选项）时抛
  /// [ArgumentError] —— 不静默生成一份跑不起来的配置。数据面为空且设备两种能力
  /// 都未知时回落 cgroup（与 Kotlin 侧 EbpfConfigBuilder 保持一致）。
  static String build({
    required Map<String, dynamic> proxy,
    required List<String> packageList,
    required String selfPackage,
    bool cgroupSupported = true,
    bool socketAssignSupported = true,
  }) {
    // ---- 代理类型：只认 http / socks5，非法值直接报错（不做静默映射）----
    final proxyType = (proxy['proxyType'] ?? '').toString().trim().toLowerCase();
    if (proxyType != 'http' && proxyType != 'socks5') {
      throw ArgumentError.value(
          proxy['proxyType'], 'proxyType', '仅支持 http 或 socks5，收到 "$proxyType"');
    }
    final isHttp = proxyType == 'http';

    // ---- 地址 / 端口：交给 sing-box 前先校验，坏的配置直接报错而不是启动失败 ----
    final host = (proxy['proxyHost'] ?? '').toString().trim();
    if (host.isEmpty) {
      throw ArgumentError.value(proxy['proxyHost'], 'proxyHost', '代理地址不能为空');
    }
    final port = _parsePort(proxy['proxyPort']);

    // ---- 接管网络：空/缺省 = all；仅接受 all / tcp / udp ----
    final savedNetwork = (proxy['ebpfNetwork'] ?? '').toString().trim().toLowerCase();
    final networkMode = savedNetwork.isEmpty ? 'all' : savedNetwork;
    if (!_validNetworks.contains(networkMode)) {
      throw ArgumentError.value(
          proxy['ebpfNetwork'], 'ebpfNetwork', '仅支持 all/tcp/udp，收到 "$savedNetwork"');
    }
    final capturesUdp = networkMode != 'tcp';

    // ---- 数据面：空值 = 按本机能力选；tc → socket_assign（sing-box 1.15 起移除别名）----
    final savedPlane = (proxy['ebpfDataPlane'] ?? '').toString().trim().toLowerCase();
    var dataPlane = savedPlane;
    if (dataPlane == 'tc') {
      debugPrint('EbpfConfigGenerator: 旧数据面 tc 已废弃，自动改用 socket_assign');
      dataPlane = 'socket_assign';
    }
    if (dataPlane.isEmpty) {
      if (cgroupSupported) {
        dataPlane = 'cgroup';
      } else if (socketAssignSupported) {
        dataPlane = 'socket_assign';
      } else {
        // 检测缓存缺失/两者都不可用时回落 cgroup（与 Kotlin 生成器一致）；
        // 真正启动前代理列表页会先校验 support.supported，不会把必失败配置拉起来
        dataPlane = 'cgroup';
      }
    } else if (!_validDataPlanes.contains(dataPlane)) {
      throw ArgumentError.value(
          proxy['ebpfDataPlane'], 'ebpfDataPlane', '仅支持 cgroup/socket_assign，收到 "$savedPlane"');
    }

    // ---- 高级选项：统一从 ebpf* 键解析（非法值已在这里回落默认）----
    final opts = EbpfAdvancedOptions.fromProxyConfig(proxy);
    // 自定义 JSON 覆盖在这里先解析一次：非法 JSON 直接报错，不生成"以为生效了"的配置
    final Map<String, dynamic>? customOverride;
    try {
      customOverride = opts.parseCustomOverride();
    } on FormatException catch (e) {
      throw ArgumentError.value(opts.customJson, 'ebpfCustomJson', '自定义 JSON 非法: ${e.message}');
    }

    debugPrint('EbpfConfigGenerator.build: type=$proxyType network=$networkMode '
        'dataPlane=$dataPlane dnsMode=${opts.effectiveDnsMode} '
        'dnsServers=${opts.dnsServers.length} customOverride=${customOverride != null}');

    // ---- outbounds：唯一的出口：你填的那个代理 ----
    final outboundTag = isHttp ? 'http-out' : 'socks-out';
    final outbound = <String, dynamic>{
      // 类型必须跟着 UI 选择变：http 代理和 socks 代理在协议上不同，填错就连不上。
      // HTTP 出站不带 version：没有 TLS 时就是 HTTP/1 CONNECT，不需要额外字段。
      'type': isHttp ? 'http' : 'socks',
      'tag': outboundTag,
      'server': host,
      'server_port': port,
    };
    if (!isHttp) {
      // sing-box 的 socks 出站必须显式声明版本（不写会被当成 socks4 或直接报错）
      outbound['version'] = '5';
    }
    final user = (proxy['proxyUser'] ?? '').toString();
    final pass = (proxy['proxyPass'] ?? '').toString();
    if (user.isNotEmpty) outbound['username'] = user;
    if (pass.isNotEmpty) outbound['password'] = pass;

    // ---- inbounds[0].local：eBPF 的「本机接管」参数 ----
    // data_plane / dns_mode 必填（dns_mode 不写也是 respect_policy，显式写出便于排查）；
    // ipv6/bypass_private/端口绕过等可选字段由选项模型提供（不写 = sing-box 默认）。
    final local = <String, dynamic>{
      'enabled': true,
      // 数据面 = 内核钩子挂在哪（两种效果相同，只是依赖的内核能力不同）：
      //   cgroup —— 挂在 cgroup v2 层级上，不跟网络接口绑定（切 Wi-Fi/流量更稳），默认
      //   socket_assign —— 当前默认接口的 socket assignment 路径（仅在检测支持时使用）
      'data_plane': dataPlane,
      // DNS 接管策略（见 EbpfAdvancedOptions.dnsMode）：默认 respect_policy =
      // 先过包名筛选，只有被监听 app 的 53 端口查询进 sing-box，不影响其它 app
      'dns_mode': opts.effectiveDnsMode,
      ...opts.buildLocalExtras(),
    };
    if (packageList.isNotEmpty) {
      // 注意：**不写** include_package = 全部 app 都接管；写了就只接管列表里的
      local['include_package'] = packageList;
    }
    if (selfPackage.isNotEmpty) {
      // 排除自己：否则本 app 自己的网络请求（如 MCP 服务、检查更新）也会被绕进代理
      local['exclude_package'] = [selfPackage];
    }

    // ---- route / dns：由选项模型驱动 ----
    // route.rules 只保留模型需要的规则（hijack-dns / http+UDP 处理），
    // 不再有全局 IPv6 reject（接管 IPv6 的开关在选项里，默认跟随 sing-box）。
    final dnsSection = opts.buildDnsSection(outboundTag);
    final routeSection = <String, dynamic>{
      // dns-local 标签由 buildDnsSection 保证存在（需要时自动补 local），
      // 这里直接把解析器引用交给模型即可
      ...opts.buildRouteExtras(outboundTag),
      'rules': opts.buildRouteRules(
          isHttp: isHttp, capturesUdp: capturesUdp, outboundTag: outboundTag),
      'final': outboundTag,
    };

    // ---- 组装完整配置（dns 段在 off 模式下整个省略）----
    var config = <String, dynamic>{
      // 日志：debug 级别便于排查（能看到 inbound_start 事件与每条连接记录）
      // output 用相对路径，相对的是原生启动时 cd 到的运行目录（见类注释）
      'log': {'disabled': false, 'level': 'debug', 'output': 'box.log', 'timestamp': true},
      if (dnsSection != null) 'dns': dnsSection,
      'route': routeSection,
      'inbounds': [
        {
          'type': 'ebpf', // 只有编译带 with_ebpf 的 sing-box 才认识这个类型
          'tag': 'ebpf-in', // 标签只用于日志/路由引用，起什么名字无所谓
          // 可调项：all = tcp+udp / tcp / udp
          'network': networkMode == 'tcp'
              ? ['tcp']
              : networkMode == 'udp'
                  ? ['udp']
                  : ['tcp', 'udp'],
          ...opts.buildInboundExtras(), // 非默认 udp_timeout 才写
          'local': local,
        }
      ],
      'outbounds': [outbound],
    };

    // ---- 自定义 JSON 覆盖（最后一步，深度合并；用户显式写的字段优先级最高）----
    if (customOverride != null) {
      config = EbpfAdvancedOptions.deepMerge(config, customOverride);
      debugPrint('EbpfConfigGenerator.build: 已合并自定义 JSON 覆盖 '
          '(${customOverride.keys.join(", ")})');
    }

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  /// 端口校验：接受整数或纯数字字符串，必须落在 1-65535
  static int _parsePort(dynamic raw) {
    int? port;
    if (raw is int) {
      port = raw;
    } else if (raw is double && raw == raw.truncateToDouble()) {
      port = raw.toInt();
    } else if (raw != null) {
      port = int.tryParse(raw.toString().trim());
    }
    if (port == null || port < 1 || port > 65535) {
      throw ArgumentError.value(raw, 'proxyPort', '端口必须是 1-65535 的整数');
    }
    return port;
  }

  /// 通知栏/日志里用的摘要文本，例如 `socks5 192.168.0.27:8080`
  static String summaryOf(Map<String, dynamic> proxy) {
    final type = (proxy['proxyType'] ?? '').toString();
    final host = (proxy['proxyHost'] ?? '').toString().trim();
    final port = (proxy['proxyPort'] ?? '').toString().trim();
    return '$type $host:$port';
  }
}
