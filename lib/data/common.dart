import 'package:shared_preferences/shared_preferences.dart';

class AppSetings {
  static const String _isCnOrEn = "isCnOrEn";
  static const String _enableDarkMode = "isEnableDarkMode";
  static const String _isMcpServer = "isMcpServer";
  static const String _checkUpdate = "isUpdate";
  static const String _checkWifi = "isCheckWifi";
  static const String _iMcpPort = "iMcpPort";
  static const String _sAuthToken = "sAuthToken";
  // ---- eBPF(sing-box) 引擎相关（设置页「eBPF 透明代理」分区）----
  // 注意：这些属于「设置侧」数据，**不参与备份/恢复**（备份只含 proxyConfig.json）
  static const String _ebpfDataPlane = "ebpfDataPlane"; // cgroup | tc
  static const String _ebpfDownloadBase = "ebpfDownloadBase"; // 自定义下载源，留空用官方
  static const String _ebpfProfiles = "ebpfProfiles"; // 哪些代理配置走 eBPF（按配置名）

  /// 语言：true=中文 / false=英文
  static Future<bool> getCnOrEn() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isCnOrEn) ?? true;
  }

  /// 设置语言
  static Future<bool> setCnOrEn(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_isCnOrEn, value);
  }

  /// 深色模式开关
  static Future<bool> getEnableDarkMode() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enableDarkMode) ?? false;
  }

  /// 设置深色模式
  static Future<bool> setEnableDarkMode(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_enableDarkMode, value);
  }

  /// MCP 服务开关（App 启动时据此决定要不要拉起）
  static Future<bool> getMcpServer() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isMcpServer) ?? false;
  }

  /// 设置 MCP 服务开关
  static Future<bool> setMcpServer(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_isMcpServer, value);
  }

  /// 启动时是否检查 App 更新
  static Future<bool> getCheckUpdate() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_checkUpdate) ?? true;
  }

  /// 设置"检查更新"开关
  static Future<bool> setCheckUpdate(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_checkUpdate, value);
  }

  /// 启动代理前是否要求连 Wi-Fi（外网代理常只在 Wi-Fi 下可用）
  static Future<bool> getCheckWifi() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_checkWifi) ?? true;
  }

  /// 设置"Wi-Fi 检查"开关
  static Future<bool> setCheckWifi(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_checkWifi, value);
  }

  /// MCP 监听端口（默认 12345）
  static Future<int> getMcpPort() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_iMcpPort) ?? 12345;
  }

  /// 设置 MCP 端口
  static Future<bool> setMcpPort(int value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setInt(_iMcpPort, value);
  }

  /// MCP 的 Bearer 鉴权 token（默认 appproxy）
  static Future<String> getAuthToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sAuthToken) ?? "appproxy";
  }

  /// 设置 MCP 鉴权 token
  static Future<bool> setAuthToken(String value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setString(_sAuthToken, value);
  }

  /// eBPF 数据面：cgroup（默认，已实测）| tc（部分厂家 netd 冲突时的退路）
  static Future<String> getEbpfDataPlane() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ebpfDataPlane) ?? "cgroup";
  }

  /// 设置 eBPF 数据面
  static Future<bool> setEbpfDataPlane(String value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setString(_ebpfDataPlane, value);
  }

  /// 二进制自定义下载源（留空 = 用官方 pfile 地址）
  static Future<String> getEbpfDownloadBase() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ebpfDownloadBase) ?? "";
  }

  /// 设置自定义下载源
  static Future<bool> setEbpfDownloadBase(String value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setString(_ebpfDownloadBase, value);
  }

  /// 哪些代理配置走 eBPF（存配置名集合）。
  ///
  /// 为什么存设置侧而不是写进 proxyConfig.json：代理配置支持**备份/恢复**，
  /// 而「本机能不能用 eBPF」只由本机检测结果决定 —— 标记放设置侧，
  /// 换机/恢复后不会带着别的设备的引擎标记过来（与检测结果的处理一致）。
  ///
  /// 写法上刻意避免「读-改-写」竞态：内存里保留一份权威集合，写入只从它出发，
  /// 且全应用只有这里写这个 key（否则并发保存会互相覆盖，实测出现过开关状态反复）。
  static Set<String>? _ebpfProfilesCache;

  static Future<Set<String>> getEbpfProfiles() async {
    final cache = await _ebpfProfileSet();
    return {...cache}; // 返回副本，避免调用方直接改到缓存
  }

  static Future<Set<String>> _ebpfProfileSet() async {
    if (_ebpfProfilesCache != null) return _ebpfProfilesCache!;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _ebpfProfilesCache = (prefs.getStringList(_ebpfProfiles) ?? const <String>[]).toSet();
    return _ebpfProfilesCache!;
  }

  static Future<bool> setEbpfProfiles(Set<String> names) async {
    _ebpfProfilesCache = {...names};
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setStringList(_ebpfProfiles, _ebpfProfilesCache!.toList());
  }

  /// 单条配置的引擎开关（唯一写入口）
  static Future<void> setEbpfProfile(String name, bool enabled) async {
    if (name.isEmpty) return;
    final profiles = await _ebpfProfileSet();
    if (enabled) {
      profiles.add(name);
    } else {
      profiles.remove(name);
    }
    await setEbpfProfiles(profiles);
  }
}
