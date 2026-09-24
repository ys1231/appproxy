import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:appproxy/data/common.dart';
import 'package:appproxy/data/ebpf_config_generator.dart';
import 'package:appproxy/data/ebpf_proxy_data.dart';
import 'package:appproxy/data/proxy_config_data.dart';
import 'package:appproxy/events/app_events.dart';
import 'package:appproxy/events/restore/restore_cubit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../generated/l10n.dart';
import 'addproxy.dart';

class ProxyListHome extends StatefulWidget {
  const ProxyListHome({super.key});

  /// 创建 State
  @override
  State<ProxyListHome> createState() => _ProxyListHomeState();
}

class _ProxyListHomeState extends State<ProxyListHome> {
  // 配置文件操作类
  final ProxyConfigData _proxyConfigData = ProxyConfigData();

  // 配置文件数据
  List<Map<String, dynamic>> _dataLists = [];

  // 控制只初始化读取一次配置文件
  bool _iscalled = false;

  // 当前选中代理名称
  String _isSelectedProxyName = "";

  // 当前正在运行的引擎：'' | 'tun2socks' | 'ebpf'
  // 停止时按这个决定调哪个通道（原 vpn 通道 / eBPF 通道）
  String _runningEngine = "";

  // 本机 eBPF 检测结果缓存（列表徽标用，不跑 root 命令）
  EbpfSupportStatus _ebpfSupport = const EbpfSupportStatus();

  // 哪些配置走 eBPF（设置侧，按配置名；不随代理配置备份/恢复）
  Set<String> _ebpfProfiles = {};

  // 方法调用通道
  static const platform = MethodChannel("cn.ys1231/appproxy/vpn");

  // 当前需要启动的代理配置
  Map<String, dynamic> _currentProxyData = {};

  /// 初始化：加载代理配置 + eBPF 检测/运行状态；并处理原生发来的 stopVpn 通知
  @override
  void initState() {
    super.initState();
    debugPrint("---- ProxyListHome initState call ");
    initProxyConfig();
    _loadEbpfState();

    // 在Flutter端处理来自原生的调用
    platform.setMethodCallHandler((call) async {
      if (call.method == 'stopVpn') {
        // 执行Flutter逻辑
        setState(() {
          _stopProxy();
        });
      }
    });
  }

  /// 读取 eBPF 检测结果缓存 + 同步运行状态（用于列表徽标与开关回显）
  ///
  /// 顺带满足「App 启动即检测」：先渲染缓存（不闪白），再后台静默重测一次。
  /// 静默重测**不自动下载二进制**（避免冷启动拉 ~10MB），二进制缺失时只会得到 not_ready。
  Future<void> _loadEbpfState() async {
    try {
      final support = await EbpfProxyData.getSupportStatus();
      final profiles = await AppSetings.getEbpfProfiles();
      final run = await EbpfProxyData.status();
      if (!mounted) return;
      setState(() {
        _ebpfSupport = support;
        _ebpfProfiles = profiles;
        if (run.running && _runningEngine.isEmpty) {
          // 可能是上次会话/通知栏停止前的状态：标记为 eBPF 运行中
          _runningEngine = 'ebpf';
        }
      });
      // 后台重测（root 命令，结果由原生持久化到 support.json）
      final latest = await EbpfProxyData.checkEbpfSupport(autoDownload: false);
      if (!mounted) return;
      setState(() => _ebpfSupport = latest);
    } catch (e) {
      debugPrint("---- _loadEbpfState: $e");
    }
  }

  /// 读取 proxyConfig.json 填充列表（_iscalled 保证只自动加载一次）
  void initProxyConfig() {
    debugPrint("---- ProxyListHome initProxyConfig call ");
    if (_iscalled) {
      return;
    }
    _iscalled = true;
    try {
      // 初始化历史代理配置
      _proxyConfigData.readProxyConfig().then((value) async {
        final profiles = await AppSetings.getEbpfProfiles();
        if (!mounted) return;
        setState(() {
          _dataLists.clear();
          _dataLists = value ?? [];
          _ebpfProfiles = profiles;
        });
      });
    } catch (e) {
      debugPrint("---- ProxyListHome initProxyConfig error $e");
    }
  }

  // 在这里处理从 AddProxyButton 返回的数据 添加代理配置到列表
  void handleConfigData(Map<String, dynamic> data, {bool isAdd = false}) {
    if (!isAdd && _dataLists.any((item) => item['proxyName'] == data['proxyName'])) {
      debugPrint("handleConfigData Data already exists in the list, skipping.");
      return;
    }
    if (isAdd) {
      for (var item in _dataLists) {
        if (item['proxyName'] == data['proxyName']) {
          item['proxyName'] = data['proxyName'];
          item['proxyType'] = data['proxyType'];
          item['proxyHost'] = data['proxyHost'];
          item['proxyPort'] = data['proxyPort'];
          item['proxyUser'] = data['proxyUser'];
          item['proxyPass'] = data['proxyPass'];
          break;
        }
      }
    } else {
      _dataLists.add(data);
    }
    _proxyConfigData.addProxyConfig(_dataLists).then((value) {});
    // 引擎标记存在设置侧：保存配置后重新读一次，否则列表徽标不会跟着变
    AppSetings.getEbpfProfiles().then((profiles) {
      if (!mounted) return;
      setState(() => _ebpfProfiles = profiles);
    });
    setState(() {
      debugPrint('Received data: $_dataLists _dataLists lenth:${_dataLists.length}');
    });
  }

  // 删除列表中的代理配置
  void deletetoProxyConfig(Map<String, dynamic> data) {
    _dataLists.removeWhere((item) => item['proxyName'] == data['proxyName']);
    _proxyConfigData.deleteProxyConfig(_dataLists);
    setState(() {
      debugPrint('delete data: $_dataLists _dataLists lenth:${_dataLists.length}');
    });
  }

  /// 判断是否 Android 10+（不同系统版本的 Wi-Fi 设置入口不同）
  Future<bool> isAndroidQOrAbove() async {
    if (!Platform.isAndroid) return false;
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    return androidInfo.version.sdkInt >= 29; // Q = 29
  }

  // 检测网络类型
  Future<bool> _checkWifiState() async {
    final List<ConnectivityResult> connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.wifi)) {
      debugPrint('Wi-Fi connected');
      return true;
    } else {
      if (await isAndroidQOrAbove()) {
        AppSettings.openAppSettingsPanel(AppSettingsPanelType.wifi);
      } else {
        AppSettings.openAppSettings(type: AppSettingsType.wifi);
      }
      return false;
    }
  }

  // 显示提示是否删除代理
  Future<void> _showDeleteDialog(BuildContext context, Map<String, dynamic> data) async {
    bool isDelete = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(S.of(context).text_tips),
            content: Text(S.of(context).text_delete_proxy_tips),
            actions: [
              TextButton(
                child: Text(S.current.text_cancel),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: Text(S.of(context).text_confirm),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        });
    if (isDelete) {
      deletetoProxyConfig(data);
    }
  }

  /// 启动代理：按设置侧记录的引擎分流
  ///  - `ebpf`      → 新通道（sing-box，root 透明代理）
  ///  - 其它/缺省    → 原 `startVpn`（tun2socks），逻辑保持不变
  void _startProxy(data) async {
    if (await AppSetings.getCheckWifi()) {
      bool isWifi = await _checkWifiState();
      if (!isWifi) {
        return;
      }
    }
    final engine = _ebpfProfiles.contains(data["proxyName"]) ? "ebpf" : "tun2socks";
    if (engine == "ebpf") {
      await _startEbpfProxy(data);
      return;
    }
    // 互斥：eBPF 正在跑就先停掉
    await _stopOtherEngine("tun2socks");
    _isSelectedProxyName = data["proxyName"];
    _currentProxyData = data;
    _currentProxyData['appProxyPackageList'] = appProxyPackageList.getListString();
    try {
      bool result = await platform.invokeMethod('startVpn', _currentProxyData);
      if (result) {
        debugPrint("---- ProxyListHome startVpn: $_currentProxyData success");
        setState(() {
          _runningEngine = "tun2socks";
        });
      } else {
        debugPrint("---- ProxyListHome startVpn: $_currentProxyData fail");
        _isSelectedProxyName = "";
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to start proxy: '${e.message}'.");
    }
  }

  /// 启动 eBPF(sing-box) 透明代理。
  ///
  /// 流程（每步失败都给明确提示，不静默降级）：
  ///   1. 前置校验      — 读本机检测缓存，未通过就提示去设置页检测
  ///   2. 互斥          — 若 tun2socks(VPN) 正在跑，先停掉（两条链路不能同时接管流量）
  ///   3. 生成 config.json — outbounds 完全跟随本条配置；分应用列表 → include_package；自身包名 → exclude_package
  ///   4. 交给原生启动   — 原生负责部署二进制、root 起进程、看门狗；失败会把日志尾部原样弹出来
  Future<void> _startEbpfProxy(Map<String, dynamic> data) async {
    // 1) 前置校验：本机检测必须通过（读缓存，不跑命令）
    final support = await EbpfProxyData.getSupportStatus();
    if (!support.supported) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.of(context).ebpf_check_first)));
      return;
    }

    // 2) 互斥：VPN(tun2socks) 正在跑就先停掉（两条链路不能同时接管流量）
    await _stopOtherEngine("ebpf");

    // 3) 生成 config.json：outbounds 完全跟随本条配置（type/host/port/user/pass）
    final selfPackage = (await PackageInfo.fromPlatform()).packageName;
    final configJson = EbpfConfigGenerator.build(
      proxy: data,
      packageList: appProxyPackageList.getList(),
      selfPackage: selfPackage,
      dataPlane: await AppSetings.getEbpfDataPlane(),
    );

    // 4) 启动（原生会部署二进制 + 写 config + root 起进程 + 看门狗）
    try {
      await EbpfProxyData.start(
        configJson: configJson,
        summary: EbpfConfigGenerator.summaryOf(data),
      );
      if (!mounted) return;
      setState(() {
        _isSelectedProxyName = data["proxyName"];
        _runningEngine = "ebpf";
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to start ebpf proxy: '${e.message}'");
      if (!mounted) return;
      // 启动失败时原样弹出原生日志（内核能力不足、附着失败等都在里面）
      showDialog(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(S.of(ctx).ebpf_start_failed),
          content: SingleChildScrollView(child: Text(e.message ?? "")),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(S.of(ctx).text_confirm),
            ),
          ],
        ),
      );
      setState(() {
        _isSelectedProxyName = "";
        _runningEngine = "";
      });
    }
  }

  /// 关闭代理：按当前运行的引擎调对应通道
  void _stopProxy() async {
    try {
      // 控制关闭代理
      _isSelectedProxyName = "";
      bool result;
      if (_runningEngine == "ebpf") {
        result = await EbpfProxyData.stop();
      } else {
        result = await platform.invokeMethod('stopVpn');
      }
      if (result) {
        debugPrint("---- ProxyListHome stopProxy success ($_runningEngine)");
        _runningEngine = "";
      } else {
        debugPrint("---- ProxyListHome stopProxy fail");
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to stop proxy: '${e.message}'.");
    }
  }

  /// 互斥：要启动 [engine] 前，先把另一个正在运行的引擎停掉
  Future<void> _stopOtherEngine(String engine) async {
    if (_runningEngine.isEmpty || _runningEngine == engine) return;
    if (_runningEngine == "ebpf") {
      await EbpfProxyData.stop();
    } else {
      await platform.invokeMethod('stopVpn');
    }
    _runningEngine = "";
    debugPrint("---- _stopOtherEngine: stopped $_runningEngine before $engine");
  }

  /// 引擎徽标：VPN(tun2socks) / eBPF(sing-box)。
  /// 标记了 eBPF 但本机检测不支持时加 ⚠（提醒这条配置在本机跑不起来，而不是悄悄降级）
  Widget _engineBadge(BuildContext context, Map<String, dynamic> data) {
    final isEbpf = _ebpfProfiles.contains(data["proxyName"]);
    final unsupported = isEbpf && !_ebpfSupport.supported;
    final label = isEbpf ? S.of(context).ebpf_badge_ebpf : S.of(context).ebpf_badge_vpn;
    final color = isEbpf ? (unsupported ? Colors.orange : Colors.deepPurple) : Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        unsupported ? '⚠ $label' : label,
        style: TextStyle(fontSize: 11.0, color: color),
      ),
    );
  }

  /// 构建代理列表（每行：名称 + 引擎徽标 + 开关；长按删除、双击编辑）
  @override
  Widget build(BuildContext context) {
    // debugPrint("---- ProxyListHome build call: $_dataLists");
    return Scaffold(
      appBar: AppBar(
        title: Text('Server ${S.of(context).text_server_config}'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: BlocConsumer<RestoreCubit, int>(listener: (BuildContext context, int state) {
        _iscalled = false;
        initProxyConfig();
      }, builder: (context, state) {
        return ListView.separated(
          // 创建从边缘反弹的滚动物理效果
          physics: const BouncingScrollPhysics(),
          // 设置底部内边距 解决底部按钮遮挡问题
          padding: const EdgeInsets.only(bottom: 70.0),
          // 配置列表个数
          itemCount: _dataLists.length,
          // 设置分隔符零尺寸
          separatorBuilder: (BuildContext context, int index) {
            return const SizedBox.shrink();
          },
          itemBuilder: (BuildContext context, int c_index) {
            Map<String, dynamic> c_data = _dataLists[c_index];
            return Card(
              // 设置 margin 为水平方向 8.0，垂直方向 4.0
              margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: GestureDetector(
                  child: SwitchListTile(
                    // 设置选中状态
                    value: _isSelectedProxyName == c_data["proxyName"] ? true : false,
                    // 设置标题和副标题
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${c_data["proxyName"]}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6.0),
                        _engineBadge(context, c_data),
                      ],
                    ),
                    subtitle: Text(
                        '${c_data["proxyType"]} ${c_data["proxyHost"]}:${c_data["proxyPort"]}'),
                    // 设置switch的onChanged事件
                    onChanged: (bool value) {
                      setState(() {
                        if (value) {
                          _startProxy(c_data);
                        } else {
                          _stopProxy();
                        }
                        debugPrint("current index:$c_index select: $_isSelectedProxyName");
                      });
                    },
                  ),
                  // 设置长按事件 主要触发删除操作
                  onLongPress: () {
                    debugPrint("long press delete:${c_data["proxyName"]}");
                    _showDeleteDialog(context, c_data);
                  },
                  // 设置双击事件
                  onDoubleTap: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (BuildContext context) {
                      return AddProxyWidget(onDataFetched: handleConfigData, onData: c_data);
                    }));
                    // 从表单返回后同步一次引擎标记（保存逻辑里也会刷新，这里兜底）
                    if (!mounted) return;
                    final profiles = await AppSetings.getEbpfProfiles();
                    if (!mounted) return;
                    setState(() => _ebpfProfiles = profiles);
                  }),
            );
          },
        );
      }),
      floatingActionButton: AddProxyButton(onDataFetched: handleConfigData),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// 添加代理按钮
class AddProxyButton extends StatelessWidget {
  const AddProxyButton({super.key, required this.onDataFetched});

  // 定义一个回调，用于处理读取到的数据
  final Function(Map<String, dynamic>, {bool isAdd}) onDataFetched;

  /// 构建代理列表（每行：名称 + 引擎徽标 + 开关；长按删除、双击编辑）
  @override
  Widget build(BuildContext context) {
    // proxyConfigData.readProxyConfig();
    return InkWell(
        // 点击事件处理函数
        onTap: () {
          // 使用Navigator.push 实现页面路由跳转，传入当前上下文context和MaterialPageRoute构建器
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    AddProxyWidget(onDataFetched: onDataFetched, onData: const {})),
          );
        },
        child: Container(
          height: 50.0,
          // 构建一个BoxDecoration对象，用于设置容器的装饰效果
          decoration: BoxDecoration(
            // 设置背景颜色为紫色
            color: Colors.purple.withAlpha(230),
            // 设置边框圆角为24.0
            borderRadius: BorderRadius.circular(15.0),
            boxShadow: [
              /// 创建一个紫色的阴影效果
              BoxShadow(
                /// 阴影颜色，这里设置为淡紫色
                color: Colors.purple.withAlpha(50),
                // 阴影的扩展半径，0.0表示没有扩展
                spreadRadius: 0.0,
                // 阴影的模糊半径，1.0表示轻微模糊
                blurRadius: 1.0,
                // 阴影的偏移量，这里设置为水平0像素，垂直2像素的偏移
                offset: const Offset(0, 3),
              ),
            ],
          ),

          // 在UI中创建一个带内边距的子组件，用于显示“添加代理”按钮
          child: Padding(
              // 设置四周的内边距为8.0
              padding: EdgeInsets.all(8.0),
              // 使用IntrinsicWidth组件来确定其子组件的自然宽度
              child: IntrinsicWidth(
                // 添加水平布局组件
                child: Row(
                  // 设置子组件在父容器中的水平排列方式为居中
                  mainAxisAlignment: MainAxisAlignment.center,
                  // 设置交叉轴对齐方式为居中
                  crossAxisAlignment: CrossAxisAlignment.center,
                  // 子组件数组，包括一个图标和一个文本
                  children: [
                    // 添加图标组件
                    const Icon(Icons.add, color: Colors.white),
                    // 在图标和文本之间添加一个宽度为10.0的空白间隔
                    const SizedBox(width: 5.0),
                    // 添加文本组件，显示“添加代理”文本
                    Text(
                      S.of(context).text_add_proxy,
                      style: const TextStyle(fontSize: 16.0, color: Colors.white),
                    ),
                    const SizedBox(width: 5.0),
                  ],
                ),
              )),
        ));
  }
}
