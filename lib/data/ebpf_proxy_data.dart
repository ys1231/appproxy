import 'package:flutter/services.dart';

/// eBPF(sing-box) 引擎的 Flutter 侧通道封装。
///
/// ─────────────────────────────────────────────────────────────────────────
/// 【这一层存在的意义：把"平台差异"挡在 UI 之外】
/// 原生返回的是 `Map<dynamic, dynamic>`（MethodChannel 只能传基本类型），
/// 直接让 UI 去 `map['cgroup'] as bool?` 会很脆。所以这里做两件事：
///   1. **类型化**：把 Map 解析成 SupportStatus / BinaryStatus / ... 这些只读模型，
///      UI 用 `status.supported` 这种字段访问，写错会编译报错，而不是运行期空指针。
///   2. **统一入口**：所有方法都是静态的，UI 不需要关心通道名、方法名、参数格式。
///
/// 【异步与回调怎么配合】
/// 向前调（Dart → 原生）：每个方法都是 `Future`，完成后拿到模型。
/// 向后调（原生 → Dart）：耗时操作（下载、启动）会通过 `onEbpfProgress` 上报阶段/百分比；
///   这个通道的 handler 只装一次（_ensureHandler），页面把 `onProgress` 换成本页的回调即可
///   （页面 dispose 时置回 null，避免回调打到已销毁的 State 上）。
///
/// 【线程/耗时提醒】
/// `getSupportStatus` 只读原生缓存（毫秒级，适合在页面 initState 里调）；
/// 其余方法都可能执行 root 命令（几百毫秒~数秒），**不要放在 build() 里**。
/// ─────────────────────────────────────────────────────────────────────────
class EbpfProxyData {
  EbpfProxyData._();

  static const MethodChannel _channel = MethodChannel("cn.ys1231/appproxy/ebpf");

  /// 原生进度/阶段回调：phase = download | starting | started
  static void Function(String phase, int? percent)? onProgress;

  static bool _handlerInstalled = false;

  /// 安装来自原生的回调（幂等，首次调用任意方法时自动安装）
  static void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onEbpfProgress') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        onProgress?.call(
          args['phase'] as String? ?? '',
          args['percent'] as int?,
        );
      }
      return null;
    });
  }

  /// 读缓存的检测结果（不执行命令）。用于「添加/修改代理配置」页决定开关是否可点。
  static Future<EbpfSupportStatus> getSupportStatus() async {
    _ensureHandler();
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getSupportStatus');
    return EbpfSupportStatus.fromMap(raw);
  }

  /// 完整检测（root + 二进制 + 运行目录 + cgroup/tc 两种数据面），结果持久化到原生 support.json。
  /// [autoDownload] 为 true 时，二进制缺失会先自动下载再检测（设置页「检测」按钮用）。
  static Future<EbpfSupportStatus> checkEbpfSupport({bool autoDownload = true}) async {
    _ensureHandler();
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('checkEbpfSupport', {
      'autoDownload': autoDownload,
    });
    return EbpfSupportStatus.fromMap(raw);
  }

  /// 二进制现状（是否已下载 / 大小 / 版本 / 未下完的分片）
  static Future<EbpfBinaryStatus> getBinaryStatus() async {
    _ensureHandler();
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getBinaryStatus');
    return EbpfBinaryStatus.fromMap(raw);
  }

  /// 检查版本清单（`{下载源}/update.json`）：拿到最新版本号与拼好的下载地址。
  /// 失败时返回带 [EbpfBinaryUpdateInfo.error] 的结果，不抛异常。
  static Future<EbpfBinaryUpdateInfo> checkBinaryUpdate() async {
    _ensureHandler();
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('checkBinaryUpdate');
    return EbpfBinaryUpdateInfo.fromMap(raw);
  }

  /// 按 ABI 重新下载二进制（设置页「下载/重新下载」）
  static Future<EbpfBinaryStatus> downloadBinary() async {
    _ensureHandler();
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('downloadBinary');
    return EbpfBinaryStatus.fromMap(raw);
  }

  /// 启动 eBPF 代理。[configJson] 由 [EbpfConfigGenerator] 生成；[summary] 用于通知栏。
  static Future<EbpfRunStatus> start({required String configJson, required String summary}) async {
    _ensureHandler();
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('start', {
      'configJson': configJson,
      'summary': summary,
    });
    return EbpfRunStatus.fromMap(raw);
  }

  /// 停止 eBPF 引擎
  static Future<bool> stop() async {
    _ensureHandler();
    return await _channel.invokeMethod<bool>('stop') ?? false;
  }

  /// 当前运行状态（是否在跑 + pid + 运行目录）
  static Future<EbpfRunStatus> status() async {
    _ensureHandler();
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('status');
    return EbpfRunStatus.fromMap(raw);
  }

  /// 读取运行日志（box.log + sing-box.log 拼接，经 root 读取）
  static Future<String> readLog({int maxBytes = 32 * 1024}) async {
    _ensureHandler();
    return await _channel.invokeMethod<String>('readLog', {'maxBytes': maxBytes}) ?? '';
  }

  /// 清理运行目录（sing-box 副本/config/日志/pid），保留已下载的二进制
  static Future<bool> cleanupRuntimeDir() async {
    _ensureHandler();
    return await _channel.invokeMethod<bool>('cleanupRuntimeDir') ?? false;
  }
}

/// 检测结果（对应原生 SupportStatus）
class EbpfSupportStatus {
  final bool root;
  final bool binaryReady;
  final bool supported;
  final bool cgroup;
  final bool tc;
  final String runtimeDir;
  final String kernelRelease;
  final String binaryVersion;
  final int checkedAt;
  final String result; // not_ready | no_root | preflight_passed | unsupported | inconclusive
  final List<String> cgroupReasons;
  final List<String> tcReasons;

  const EbpfSupportStatus({
    this.root = false,
    this.binaryReady = false,
    this.supported = false,
    this.cgroup = false,
    this.tc = false,
    this.runtimeDir = '',
    this.kernelRelease = '',
    this.binaryVersion = '',
    this.checkedAt = 0,
    this.result = 'not_ready',
    this.cgroupReasons = const [],
    this.tcReasons = const [],
  });

  factory EbpfSupportStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const EbpfSupportStatus();
    /// 把 JSON 数组字段安全地解析成 List<String>（字段缺失/类型不对都返回空表）
    List<String> strList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const <String>[];
    return EbpfSupportStatus(
      root: map['root'] as bool? ?? false,
      binaryReady: map['binaryReady'] as bool? ?? false,
      supported: map['supported'] as bool? ?? false,
      cgroup: map['cgroup'] as bool? ?? false,
      tc: map['tc'] as bool? ?? false,
      runtimeDir: map['runtimeDir'] as String? ?? '',
      kernelRelease: map['kernelRelease'] as String? ?? '',
      binaryVersion: map['binaryVersion'] as String? ?? '',
      checkedAt: map['checkedAt'] as int? ?? 0,
      result: map['result'] as String? ?? 'not_ready',
      cgroupReasons: strList(map['cgroupReasons']),
      tcReasons: strList(map['tcReasons']),
    );
  }

  /// 是否从未检测过
  bool get neverChecked => checkedAt == 0 && !supported;

  /// 检测时间（本地时间）
  DateTime? get checkedTime =>
      checkedAt > 0 ? DateTime.fromMillisecondsSinceEpoch(checkedAt) : null;

  /// 失败原因（优先 cgroup，其次 tc）
  List<String> get reasons => cgroupReasons.isNotEmpty ? cgroupReasons : tcReasons;
}

/// 二进制信息（对应原生 BinaryStatus）
class EbpfBinaryStatus {
  final String abi;
  final String fileName;
  final bool exists;
  final int size;
  final String version; // sing-box 自身版本（`<bin> version`）
  final String packageVersion; // 下载来源的版本目录，如 v0.0.1
  final int updatedAt;
  final int pendingBytes; // 未下完的临时文件大小（>0 表示可续传）

  const EbpfBinaryStatus({
    this.abi = '',
    this.fileName = '',
    this.exists = false,
    this.size = 0,
    this.version = '',
    this.packageVersion = '',
    this.updatedAt = 0,
    this.pendingBytes = 0,
  });

  factory EbpfBinaryStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const EbpfBinaryStatus();
    return EbpfBinaryStatus(
      abi: map['abi'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      exists: map['exists'] as bool? ?? false,
      size: map['size'] as int? ?? 0,
      version: map['version'] as String? ?? '',
      packageVersion: map['packageVersion'] as String? ?? '',
      updatedAt: map['updatedAt'] as int? ?? 0,
      pendingBytes: map['pendingBytes'] as int? ?? 0,
    );
  }

  String get sizeText => size <= 0 ? '-' : '${(size / 1024 / 1024).toStringAsFixed(2)} MB';

  String get pendingText =>
      pendingBytes <= 0 ? '' : '${(pendingBytes / 1024 / 1024).toStringAsFixed(2)} MB';
}

/// 版本清单（update.json）
class EbpfBinaryUpdateInfo {
  final String latestVersion; // 最新版本号，如 v0.0.1
  final int versionCode;
  final String downloadUrl; // 已按当前 ABI 拼好
  final String changelogUrl;
  final String error; // 非空表示检查失败

  const EbpfBinaryUpdateInfo({
    this.latestVersion = '',
    this.versionCode = 0,
    this.downloadUrl = '',
    this.changelogUrl = '',
    this.error = '',
  });

  factory EbpfBinaryUpdateInfo.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const EbpfBinaryUpdateInfo();
    return EbpfBinaryUpdateInfo(
      latestVersion: map['latestVersion'] as String? ?? '',
      versionCode: map['versionCode'] as int? ?? 0,
      downloadUrl: map['downloadUrl'] as String? ?? '',
      changelogUrl: map['changelogUrl'] as String? ?? '',
      error: map['error'] as String? ?? '',
    );
  }

  bool get ok => error.isEmpty && latestVersion.isNotEmpty;
}

/// 运行状态（对应原生 RunStatus）
class EbpfRunStatus {
  final bool running;
  final int pid;
  final String runDir;

  const EbpfRunStatus({this.running = false, this.pid = -1, this.runDir = ''});

  factory EbpfRunStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const EbpfRunStatus();
    return EbpfRunStatus(
      running: map['running'] as bool? ?? false,
      pid: (map['pid'] as num?)?.toInt() ?? -1,
      runDir: map['runDir'] as String? ?? '',
    );
  }
}
