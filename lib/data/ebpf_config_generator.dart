import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

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
/// 3. **这个文件产出的就是 sing-box 的配置**（config.json），它由这几部分组成：
///      log        —— 日志写哪、什么级别
///      dns        —— 启动 DNS + 经代理的 DoH
///      route      —— 53 端口劫持、IPv6/HTTP-UDP 拒绝、默认出口
///      inbounds   —— 流量从哪进来（这里只有一种：ebpf 透明接管）
///      outbounds  —— 流量往哪出去（这里只有一种：你填的那个 http/socks 代理）
///    流量路径：目标 app 的连接 → [inbounds.ebpf 拦下] → [路由] → [outbounds 发给代理]
///
/// 4. **为什么由 Dart 生成**：生成所需的数据（代理地址、分应用列表、数据面选项）本来
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
///   inbounds[0].network        ← ebpfNetwork：空/缺省 = all；合法值 all/tcp/udp，其它报错
///   local.dns_mode             ← 固定 hijack（53 端口由 route 的 hijack-dns 接管）
///   dns/route                  ← 固定策略：启动 DNS(直连 UDP) + 双 DoH group(经代理)，
///                                53 → hijack-dns，拒绝 IPv6；HTTP + 接管 UDP 时拒绝 UDP
///
/// 说明：以上 ebpf* 键由「编辑配置」页写入 proxyConfig.json（跟随备份/恢复）；
/// 旧配置没有这些键时全部回落默认值（空 = 自动），行为与旧版兼容。
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

  /// HTTP 出站接管 UDP 时的路由动作。
  ///
  /// 目前固定为 `reject`：HTTP 代理没有原生 UDP，UDP/QUIC 会被封装成 MASQUE，
  /// 上游不支持即 404 风暴，所以在路由层快速失败。
  /// 如需回退为直连，把这里改成 `'direct'` 即可（socks5 永远不加这条规则）。
  static const String httpUdpRouteAction = 'reject';

  /// 生成 config.json 字符串
  ///
  /// [proxy]       代理配置项（proxyType/proxyHost/proxyPort/proxyUser/proxyPass，
  ///               以及 eBPF 可调项 ebpfNetwork/ebpfDataPlane）
  /// [packageList] 分应用包名列表（空 = 全部接管）
  /// [selfPackage] 本应用包名（写进 exclude_package）
  /// [cgroupSupported]        本机 cgroup 数据面是否可用（决定 ebpfDataPlane 为空时的默认值）
  /// [socketAssignSupported]  本机 socket_assign 数据面是否可用（同上）
  ///
  /// 输入非法（proxyType/host/port/ebpfNetwork/ebpfDataPlane）时抛 [ArgumentError] ——
  /// 不静默生成一份跑不起来的配置。数据面为空且设备两种能力都未知时回落 cgroup
  /// （与 Kotlin 侧 EbpfConfigBuilder 保持一致）。
  ///
  /// 其余 inbound 参数（udp_timeout / tc_priority / fakeip_icmp / ipv6 /
  /// bypass_private_address / 日志级别）沿用**已验证过的基线值**，直接写在模板里。
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
    //   两种代理默认都是 all（不再按类型给 tcp 默认）：
    //     socks5 → UDP 走 SOCKS5 UDP ASSOCIATE，可完整代理；
    //     http   → 没有原生 UDP，生成时会追加「拒绝 UDP」路由规则（见下），
    //              避免 UDP/QUIC 被封装成 MASQUE 后因上游不支持而 404。
    final savedNetwork = (proxy['ebpfNetwork'] ?? '').toString().trim().toLowerCase();
    final networkMode = savedNetwork.isEmpty ? 'all' : savedNetwork;
    if (!_validNetworks.contains(networkMode)) {
      throw ArgumentError.value(
          proxy['ebpfNetwork'], 'ebpfNetwork', '仅支持 all/tcp/udp，收到 "$savedNetwork"');
    }
    final capturesUdp = networkMode != 'tcp';

    // ---- 数据面 ----
    //   cgroup（默认）/ socket_assign（兼容路径；旧配置里的 tc 已废弃，
    //   sing-box 1.15 起「旧配置中的 local tc 必须改为 socket_assign，不保留别名」）
    //   空值 = 未显式选择 → 按本机能力选：cgroup 优先，其次 socket_assign。
    final savedPlane = (proxy['ebpfDataPlane'] ?? '').toString().trim().toLowerCase();
    var dataPlane = savedPlane;
    if (dataPlane == 'tc') {
      // 兼容旧配置：tc → socket_assign（新版二进制不再接受 tc，会 FATAL 退出）
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
    debugPrint('EbpfConfigGenerator.build: type=$proxyType network=$networkMode '
        'dataPlane=$dataPlane '
        '(network来源=${savedNetwork.isEmpty ? "自动" : "用户显式"}, '
        'dataPlane来源=${savedPlane.isEmpty ? "按设备能力" : "用户显式"})');

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
    // 这一整块是内核态行为，字段名都来自 sing-box 的 ebpf 入站文档
    final local = <String, dynamic>{
      'enabled': true,
      // 数据面 = 内核钩子挂在哪（两种效果相同，只是依赖的内核能力不同）：
      //   cgroup —— 挂在 cgroup v2 层级上，不跟网络接口绑定（切 Wi-Fi/流量更稳），默认
      //   socket_assign —— 当前默认接口的 socket assignment 路径（仅在检测支持时使用）
      'data_plane': dataPlane,
      // DNS 处理策略：hijack = 53 端口统一交给 sing-box 的 DNS 模块应答
      //（配合 route.rules 的 hijack-dns，避免 netd 代发导致直连泄漏）
      'dns_mode': 'hijack',
      'ipv6': true,
      // 目标地址是私网/特殊地址时不接管（局域网设备、路由器后台、组播等）
      'bypass_private_address': true,
    };
    if (packageList.isNotEmpty) {
      // 注意：**不写** include_package = 全部 app 都接管；写了就只接管列表里的
      local['include_package'] = packageList;
    }
    if (selfPackage.isNotEmpty) {
      // 排除自己：否则本 app 自己的网络请求（如 MCP 服务、检查更新）也会被绕进代理
      local['exclude_package'] = [selfPackage];
    }

    // ---- dns + route：DNS 由 sing-box 统一处理（**不作为用户选项**）----
    //   1) eBPF 入站把目标端口 53 的查询送进路由（dns_mode=hijack）；
    //   2) route 规则「端口 53 → hijack-dns」交给 DNS 模块本地应答；
    //   3) dns-boot（明文 UDP，直连）只用于解析 DoH 服务器域名，避免解析 DoH 域名时
    //      又绕回代理形成循环；dns-ali / dns-dnspod 两个 DoH 带 detour 走代理；
    //   4) dns-group 把两个 DoH 组成 group，dns.final 指向 group（不要简化成单个 DoH）；
    //   5) strategy=ipv4_only：经代理转发时 IPv6 常不可达（实测 socks5 出现
    //      [2001::1]:443 EOF），只返回 IPv4；
    //   6) route.rules 里拒绝全部 IPv6（::/0），避免 IPv6 目标经代理 EOF；
    //   7) http 代理没有原生 UDP：实际 network 含 udp 时追加拒绝 UDP 的路由规则，
    //      避免 UDP/QUIC 被封装成 MASQUE 后因上游不支持而 404（socks5 有 UDP ASSOCIATE，
    //      不加这条规则）。动作见 [httpUdpRouteAction]。
    final dnsSection = <String, dynamic>{
      'servers': [
        // 启动解析器：直连 UDP，仅用于解析 DoH 域名
        {'tag': 'dns-boot', 'type': 'udp', 'server': '223.5.5.5'},
        _dohServer('dns-ali', 'dns.alidns.com', outboundTag),
        _dohServer('dns-dnspod', 'doh.pub', outboundTag),
        // 双 DoH 组成 group：final 指向它，避免只依赖单个 DoH
        {
          'tag': 'dns-group',
          'type': 'group',
          'servers': ['dns-ali', 'dns-dnspod'],
        },
      ],
      'final': 'dns-group',
      'strategy': 'ipv4_only',
    };
    // 规则顺序固定：先 hijack-dns（53 端口），再 IPv6 reject，最后 HTTP+UDP reject
    final routeRules = <Map<String, dynamic>>[
      // 端口 53（被接管的 TCP/UDP DNS）交给 DNS 模块应答；必须排在 UDP 拒绝规则之前
      {'port': 53, 'action': 'hijack-dns'},
      // IPv6 目标经代理常不可达（EOF），直接拒绝，让应用回落 IPv4
      {'ip_cidr': ['::/0'], 'action': 'reject'},
    ];
    if (isHttp && capturesUdp) {
      routeRules.add({'network': ['udp'], 'action': httpUdpRouteAction});
    }
    final routeSection = <String, dynamic>{
      // 未显式指定 resolver 的域名（含 DoH 服务器域名）用直连的 dns-boot 解析
      'default_domain_resolver': 'dns-boot',
      'rules': routeRules,
      'final': outboundTag,
    };

    // ---- 组装完整配置 ----
    final config = <String, dynamic>{
      // 日志：debug 级别便于排查（能看到 inbound_start 事件与每条连接记录）
      // output 用相对路径，相对的是原生启动时 cd 到的运行目录（见类注释）
      'log': {'disabled': false, 'level': 'debug', 'output': 'box.log', 'timestamp': true},
      'dns': dnsSection,
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
          'udp_timeout': '5m', // UDP 会话（如 DNS、QUIC）的空闲超时
          'tc_priority': 1, // 仅 TC 路径用：TC 过滤器的优先级（数值越小越先执行）
          'fakeip_icmp': 'off', // 不响应发往 FakeIP 的 ICMP（FakeIP 没启用，保持关闭）
          'local': local,
        }
      ],
      'outbounds': [outbound],
    };
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

  /// 单个 DoH 服务器（sing-box 1.12+ 新格式：type + server，旧 address 写法已移除）
  /// detour 指向上游 outbound：DoH 是 TCP/TLS，http 与 socks 出站都能承载。
  static Map<String, dynamic> _dohServer(String tag, String host, String detour) => {
        'tag': tag,
        'type': 'https',
        'server': host,
        'detour': detour,
      };

  /// 通知栏/日志里用的摘要文本，例如 `socks5 192.168.0.27:8080`
  static String summaryOf(Map<String, dynamic> proxy) {
    final type = (proxy['proxyType'] ?? '').toString();
    final host = (proxy['proxyHost'] ?? '').toString().trim();
    final port = (proxy['proxyPort'] ?? '').toString().trim();
    return '$type $host:$port';
  }
}
