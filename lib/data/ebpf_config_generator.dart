import 'dart:convert';

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
/// 3. **这个文件产出的就是 sing-box 的配置**（config.json），它由三部分组成：
///      log        —— 日志写哪、什么级别
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
///   outbounds[0].type          ← proxyType
///                                UI 下拉只有 http / socks5 两个值：
///                                `http`   → `"type":"http"`（HTTP 代理，支持 CONNECT 隧道）
///                                `socks5` → `"type":"socks"` + `"version":"5"`
///   outbounds[0].server        ← proxyHost
///   outbounds[0].server_port   ← proxyPort（UI 里是字符串，这里转成数字）
///   outbounds[0].username      ← proxyUser（为空则**整个字段省略**，不要写成空串）
///   outbounds[0].password      ← proxyPass（同上）
///   local.include_package      ← 分应用列表（**空列表则省略该字段 = 全部 app 都接管**）
///   local.exclude_package      ← 本应用包名（否则 appproxy 自己的请求也会被接管，可能成环）
///   local.data_plane           ← 设置页「兼容模式」：cgroup（默认）/ tc
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

  /// 生成 config.json 字符串
  ///
  /// [proxy]       代理配置项（proxyType/proxyHost/proxyPort/proxyUser/proxyPass）
  /// [packageList] 分应用包名列表（空 = 全部接管）
  /// [selfPackage] 本应用包名（写进 exclude_package）
  /// [dataPlane]   cgroup（默认）| tc —— 见下面 local.data_plane 的说明
  ///
  /// 其余 inbound 参数（udp_timeout / tc_priority / fakeip_icmp / dns_mode / ipv6 /
  /// bypass_private_address / 日志级别）沿用**已验证过的基线值**，直接写在模板里；
  /// 将来要开放成可调项，把它们从模板提到参数即可（默认值保持不变）。
  static String build({
    required Map<String, dynamic> proxy,
    required List<String> packageList,
    required String selfPackage,
    String dataPlane = 'cgroup',
  }) {
    final proxyType = (proxy['proxyType'] ?? 'socks5').toString().toLowerCase();
    final isHttp = proxyType == 'http';

    // ---- outbounds：唯一的出口：你填的那个代理 ----
    final outbound = <String, dynamic>{
      // 类型必须跟着 UI 选择变：http 代理和 socks 代理在协议上不同，填错就连不上
      'type': isHttp ? 'http' : 'socks',
      'tag': isHttp ? 'http-out' : 'socks-out',
      'server': (proxy['proxyHost'] ?? '').toString(),
      'server_port': int.tryParse((proxy['proxyPort'] ?? '').toString()) ?? 0,
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
      //   tc     —— 挂在当前默认网络接口上（少数机型 cgroup 挂不上时的退路）
      'data_plane': dataPlane,
      // DNS 处理策略：respect_policy = **先**按 UID/包名筛选，**再**接管 53 端口；
      // 于是只有被代理的 app 的 DNS 才会被接管（hijack 是无差别接管，off 是都不管）
      'dns_mode': 'respect_policy',
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

    // ---- 组装完整配置 ----
    final config = <String, dynamic>{
      // 日志：debug 级别便于排查（能看到 "eBPF inbound started" 与每条连接记录）
      // output 用相对路径，相对的是原生启动时 cd 到的运行目录（见类注释）
      'log': {'disabled': false, 'level': 'debug', 'output': 'box.log', 'timestamp': true},
      'inbounds': [
        {
          'type': 'ebpf', // 只有编译带 with_ebpf 的 sing-box 才认识这个类型
          'tag': 'ebpf-in', // 标签只用于日志/路由引用，起什么名字无所谓
          'network': ['tcp', 'udp'], // 同时接管 TCP 和 UDP
          'udp_timeout': '5m', // UDP 会话（如 DNS、QUIC）的空闲超时
          'tc_priority': 1, // 仅 tc 数据面用：TC 过滤器的优先级（数值越小越先执行）
          'fakeip_icmp': 'off', // 不响应发往 FakeIP 的 ICMP（FakeIP 没启用，保持关闭）
          'local': local,
        }
      ],
      'outbounds': [outbound],
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  /// 通知栏/日志里用的摘要文本，例如 `socks5 192.168.0.27:8080`
  static String summaryOf(Map<String, dynamic> proxy) {
    final type = (proxy['proxyType'] ?? '').toString();
    final host = (proxy['proxyHost'] ?? '').toString();
    final port = (proxy['proxyPort'] ?? '').toString();
    return '$type $host:$port';
  }
}
