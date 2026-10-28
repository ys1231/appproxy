import 'dart:io';

import 'package:appproxy/data/common.dart';
import 'package:appproxy/data/ebpf_proxy_data.dart';
import 'package:appproxy/events/debounce.dart';
import 'package:appproxy/generated/l10n.dart';
import 'package:flutter/material.dart';

class AddProxyWidget extends StatefulWidget {
  AddProxyWidget({super.key, required this.onDataFetched, required this.onData});

  // 定义一个回调，用于处理读取到的数据
  final Function(Map<String, dynamic>, {bool isAdd}) onDataFetched;
  Map<String, dynamic> onData = {};

  /// 创建 State
  @override
  State<AddProxyWidget> createState() => _AddProxyWidgetState();
}

// 定义全局函数用于校验Map中所有字符串类型的值
bool isNullOrEmpty(Map<String, String> map) {
  if (map.isEmpty) {
    return true;
  }
  for (var key in map.keys) {
    if (key == "proxyUser" || key == "proxyPass") {
      continue;
    }
    if (map[key] == null || map[key]!.isEmpty) {
      return true;
    }
  }

  return false;
}

class _AddProxyWidgetState extends State<AddProxyWidget> {
  var proxyConfig = <String, String>{};
  final TextEditingController _controller_proxyName = TextEditingController();
  final TextEditingController _controller_proxyType = TextEditingController();
  final TextEditingController _controller_proxyHost = TextEditingController();
  final TextEditingController _controller_proxyPort = TextEditingController();
  final TextEditingController _controller_proxyUser = TextEditingController();
  final TextEditingController _controller_proxyPass = TextEditingController();

  final Debounce _debounce = Debounce(const Duration(seconds: 1));

  // 默认title 添加代理配置 false 为修改
  var isDefaultTitle = true;

  // ---- eBPF 透明代理（root）----
  // 开关表示「本条配置是否走 sing-box(eBPF)」。开关状态**存在设置侧**（AppSetings.ebpfProfiles，
  // 按配置名记录），不写进 proxyConfig.json —— 这样备份/恢复代理配置不会把引擎标记带到别的设备。
  // 是否可点由本机检测结果（原生 support.json 缓存）决定：打开页面时读缓存，不跑 root 命令（秒开）。
  bool _ebpfEnabled = false;
  EbpfSupportStatus _ebpfSupport = const EbpfSupportStatus();
  bool _ebpfSupportLoaded = false;

  // ---- eBPF 可调项（仅影响 eBPF 引擎；**写进 proxyConfig.json，跟随备份/恢复**）----
  // ebpfDataPlane: 数据面 cgroup / socket_assign（旧值 tc 已废弃）。
  //                空字符串 = 未显式选择，按本机检测能力选默认（cgroup 优先）
  // ebpfNetwork:   all = TCP+UDP 都接管（默认）；tcp = 只接管 TCP；udp = 只接管 UDP
  String _ebpfDataPlane = '';

  // 空字符串 = 未显式选择（自动，默认 all）。**保存时保持空串**，不要写推导值，
  // 这样切换代理类型时仍能保持「自动」语义。
  String _ebpfNetwork = '';

  /// 初始化：编辑态回填已有配置；读取本机检测缓存（决定 eBPF 开关能否点）
  @override
  void initState() {
    super.initState();

    if (widget.onData.isNotEmpty) {
      _controller_proxyName.text = widget.onData['proxyName'];
      _controller_proxyType.text = widget.onData['proxyType'];
      _controller_proxyHost.text = widget.onData['proxyHost'];
      _controller_proxyPort.text = widget.onData['proxyPort'];
      _controller_proxyUser.text = widget.onData['proxyUser'];
      _controller_proxyPass.text = widget.onData['proxyPass'];
      // 旧配置没有这些键时回落默认值：数据面空 = 按本机能力，网络空 = 自动(all)
      final savedPlane = (widget.onData['ebpfDataPlane'] ?? '').toString().trim().toLowerCase();
      final migratedPlane = savedPlane == 'tc' ? 'socket_assign' : savedPlane; // 旧配置兼容
      // 与 network 一致做白名单清洗：tc→socket_assign、空→空(自动)、仅接受
      // cgroup/socket_assign；其它非法值（手工编辑/异常备份）回落空串(自动)，
      // 避免作为 DropdownButton.value 触发断言、保存时又写回非法值
      _ebpfDataPlane =
          const {'cgroup', 'socket_assign'}.contains(migratedPlane) ? migratedPlane : '';
      final savedNetwork = (widget.onData['ebpfNetwork'] ?? '').toString().trim().toLowerCase();
      // 非法旧值按自动处理，避免下拉框拿到不存在的选项而断言失败
      _ebpfNetwork = const {'all', 'tcp', 'udp'}.contains(savedNetwork) ? savedNetwork : '';
      debugPrint('addproxy init: 回填 eBPF 可调项 dataPlane=$_ebpfDataPlane '
          'network=$_ebpfNetwork');
      isDefaultTitle = false;
    } else {
      isDefaultTitle = true;
    }
    _loadEbpfState();
  }

  /// 读「本机检测结果（缓存）」+「本条配置的引擎标记（设置侧）」
  Future<void> _loadEbpfState() async {
    try {
      final support = await EbpfProxyData.getSupportStatus();
      final profiles = await AppSetings.getEbpfProfiles();
      if (!mounted) return;
      setState(() {
        _ebpfSupport = support;
        _ebpfEnabled = profiles.contains(widget.onData['proxyName']);
        _ebpfSupportLoaded = true;
      });
    } catch (e) {
      debugPrint("_loadEbpfState: $e");
      if (mounted) {
        setState(() => _ebpfSupportLoaded = true);
      }
    }
  }

  /// 实际生效的接管网络：未显式选择时默认 all（http/socks5 相同）。
  /// 显式值原样使用；保存时写回的仍是 [_ebpfNetwork]（空 = 自动）。
  String get _effectiveNetwork => _ebpfNetwork.isEmpty ? 'all' : _ebpfNetwork;

  /// 实际生效的数据面：
  ///  - 未显式选择（空）→ 按本机检测能力，cgroup 优先，其次 socket_assign；
  ///  - 旧值 tc → socket_assign；
  ///  - 显式选择但本机不支持 → 切到另一个可用项（避免生成必然启动失败的配置）。
  String get _effectiveDataPlane {
    var plane = _ebpfDataPlane;
    if (plane == 'tc') plane = 'socket_assign'; // 兜底：init 已迁移
    if (plane.isEmpty) {
      if (_ebpfSupport.cgroup) return 'cgroup';
      if (_ebpfSupport.socketAssign) return 'socket_assign';
      // 未检测/未知时先展示 cgroup；真正启动前有检测拦截
      return 'cgroup';
    }
    if (!_ebpfSupportLoaded) return plane;
    if (plane == 'cgroup' && !_ebpfSupport.cgroup && _ebpfSupport.socketAssign) {
      return 'socket_assign';
    }
    if (plane == 'socket_assign' && !_ebpfSupport.socketAssign && _ebpfSupport.cgroup) {
      return 'cgroup';
    }
    return plane;
  }

  /// 释放：销毁输入防抖计时器
  @override
  void dispose() {
    super.dispose();
    _debounce.dispose();
  }

  /// 构建表单：名称 → 类型 → 地址 → 端口 → 账号/密码 → eBPF 开关
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(
              isDefaultTitle ? S.of(context).text_add_proxy : S.of(context).text_modify_config),
          // backgroundColor: const Color.fromRGBO(142, 0, 244, 1.0),
          backgroundColor: Theme.of(context).primaryColor,
          actions: [
            IconButton(
              padding: const EdgeInsets.only(right: 20.0),
              icon: const Icon(Icons.save),
              onPressed: () async {
                // 名称不做 trim：编辑态用它匹配原配置，改掉首尾空格会导致匹配不到
                proxyConfig['proxyName'] = _controller_proxyName.text;
                proxyConfig['proxyType'] = _controller_proxyType.text.trim().toLowerCase();
                proxyConfig['proxyHost'] = _controller_proxyHost.text.trim();
                proxyConfig['proxyPort'] = _controller_proxyPort.text.trim();
                if (isNullOrEmpty(proxyConfig)) {
                  debugPrint("proxyConfig:$proxyConfig");
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(S.of(context).text_check_parameters),
                      backgroundColor: Colors.purple.withValues(alpha: 0.4)));
                  return;
                }
                // 类型/端口严格校验：只接受 http / socks5，端口必须是 1-65535 的整数
                //（生成器还会再校验一次；这里提前拦，避免保存一份启动必失败的配置）
                final port = int.tryParse(proxyConfig['proxyPort']!);
                final typeOk =
                    proxyConfig['proxyType'] == 'http' || proxyConfig['proxyType'] == 'socks5';
                if (!typeOk || port == null || port < 1 || port > 65535) {
                  debugPrint('addproxy save invalid: '
                      'type=${proxyConfig['proxyType']} port=${proxyConfig['proxyPort']}');
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(S.of(context).text_check_parameters),
                      backgroundColor: Colors.purple.withValues(alpha: 0.4)));
                  return;
                }
                // 这俩可以为空
                proxyConfig['proxyUser'] = _controller_proxyUser.text;
                proxyConfig['proxyPass'] = _controller_proxyPass.text;
                // eBPF 可调项（流量策略，**跟随备份/恢复**，所以写进 proxyConfig.json；
                // 只有「这条配置是否走 eBPF」的开关标记存设置侧，见上面注释）
                // 数据面：保存实际生效值（空值已按本机能力解析）
                proxyConfig['ebpfDataPlane'] = _effectiveDataPlane;
                // 网络：未手动选择时保存空串（自动），不要写按类型推导的显式值
                proxyConfig['ebpfNetwork'] = _ebpfNetwork;
                debugPrint('addproxy save: name=${_controller_proxyName.text} '
                    'type=${_controller_proxyType.text} ebpfEnabled=$_ebpfEnabled '
                    'dataPlane=$_effectiveDataPlane '
                    'network=${_ebpfNetwork.isEmpty ? "auto($_effectiveNetwork)" : _ebpfNetwork}');
                // 引擎标记存设置侧（不写入 proxyConfig.json，避免跟随备份/恢复）。
                // 必须 await：列表页返回后会立刻读这个值刷新徽标，不 await 会读到旧值（竞态）。
                await AppSetings.setEbpfProfile(_controller_proxyName.text, _ebpfEnabled);
                if (!mounted) return;
                if (widget.onData.isNotEmpty) {
                  widget.onDataFetched(proxyConfig, isAdd: true);
                } else {
                  widget.onDataFetched(proxyConfig);
                }
                Navigator.pop(context);
              },
            )
          ],
        ),
        body: Container(
            color: Theme.of(context).canvasColor,
            // 获取当前设备的屏幕高度,解决Column没有充满屏幕出现白色问题
            height: MediaQuery.of(context).size.height,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                // 设置UI布局中子元素的主轴线对齐方式
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextField(
                      readOnly: widget.onData.isNotEmpty,
                      controller: _controller_proxyName,
                      decoration: InputDecoration(
                        labelText: S.of(context).text_config_name,
                        border: const OutlineInputBorder(),
                      ),
                      onTap: () {
                        if (widget.onData.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(S.of(context).text_config_cannot_be_modified),
                              backgroundColor: Colors.purple.withOpacity(0.4)));
                        }
                      }),
                  const SizedBox(height: 20.0),
                  ProxyType(
                    controller: _controller_proxyType,
                  ),
                  const SizedBox(height: 20.0),
                  TextField(
                    controller: _controller_proxyHost,
                    decoration: InputDecoration(
                      labelText: S.of(context).text_proxy_addr,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      // 校验只能输入ip地址
                      // if (value.isNotEmpty &&
                      //     !RegExp(r'^[0-9.]+$').hasMatch(value)) {
                      //   _controller_proxyHost.text =
                      //       value.substring(0, value.length - 1);
                      // }
                      _debounce.call(context, checkConnect);
                    },
                  ),
                  const SizedBox(height: 20.0),
                  TextField(
                    controller: _controller_proxyPort,
                    decoration: InputDecoration(
                      labelText: S.of(context).text_proxy_port,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      // 校验只能输入数字
                      if (value.isNotEmpty && !RegExp(r'^[0-9]+$').hasMatch(value)) {
                        _controller_proxyPort.text = value.substring(0, value.length - 1);
                      }
                      _debounce.call(context, checkConnect);
                    },
                  ),
                  const SizedBox(height: 20.0),
                  TextField(
                    controller: _controller_proxyUser,
                    decoration: InputDecoration(
                      labelText: S.of(context).text_proxy_username,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20.0),
                  TextField(
                    // 设置密码输入框的配置
                    // 控制器，用于管理输入框的文本状态
                    controller: _controller_proxyPass,
                    // 是否隐藏密码字符
                    obscureText: true,
                    // 用于隐藏密码的字符，默认为"*"
                    obscuringCharacter: "*",
                    decoration: InputDecoration(
                      // 输入框的标签文本
                      labelText: S.of(context).text_proxy_passworld,
                      // 输入框的边框样式
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20.0),
                  _buildEbpfSwitch(context),
                ],
              ),
            )));
  }

  /// eBPF 透明代理开关（root）。
  ///
  /// 行为约定：
  ///  - 开关是否可点**只由本机检测结果**决定（原生 support.json 缓存，打开页面时读取，秒开）；
  ///  - 开关状态存设置侧（AppSetings.ebpfProfiles，按配置名），不写进 proxyConfig.json，
  ///    因此不会跟着代理配置的备份/恢复跑到别的设备上；
  ///  - 检测按钮在「设置 → eBPF 透明代理」，这里只显示状态与原因。
  Widget _buildEbpfSwitch(BuildContext context) {
    final s = S.of(context);
    final supported = _ebpfSupport.supported;
    String status;
    if (!_ebpfSupportLoaded) {
      status = s.ebpf_status_loading;
    } else if (!_ebpfSupport.root) {
      status = s.ebpf_status_no_root;
    } else if (_ebpfSupport.neverChecked) {
      status = s.ebpf_status_never_checked;
    } else if (supported) {
      status = '${s.ebpf_status_supported} (${_ebpfSupport.cgroup ? "cgroup" : "socket_assign"})';
    } else {
      final reasons = _ebpfSupport.reasons.take(2).join('; ');
      status =
          reasons.isEmpty ? s.ebpf_status_unsupported : '${s.ebpf_status_unsupported}: $reasons';
    }
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 50.0,
            padding: const EdgeInsets.only(left: 10.0, right: 10.0),
            child: Row(
              children: [
                Expanded(child: Text(s.ebpf_engine_title)),
                Switch(
                  value: _ebpfEnabled,
                  // 只有检测通过才可点；不支持时置灰
                  onChanged: supported
                      ? (bool value) {
                          setState(() {
                            _ebpfEnabled = value;
                          });
                        }
                      : null,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10.0, right: 10.0, bottom: 10.0),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12.0,
                color: supported ? Colors.green : Colors.orange,
              ),
            ),
          ),
          // 开启 eBPF 后才显示可调项：数据面 / 接管网络 / DNS 解析。
          // 目的是兼容性兜底 —— 不同机型内核能力、不同上游代理对 UDP 的支持都不同，
          // 出问题时可切换组合（如 http 代理 + 仅 TCP、或换 DoH）直到可用
          if (_ebpfEnabled && supported) ...[
            _ebpfOptionRow(
              label: S.of(context).ebpf_opt_data_plane,
              // 显示实际生效值：未显式选择时按本机能力给默认（cgroup 优先）
              value: _effectiveDataPlane,
              items: {
                'cgroup': _ebpfSupport.cgroup
                    ? S.of(context).ebpf_opt_data_plane_cgroup
                    : '${S.of(context).ebpf_opt_data_plane_cgroup} (${S.of(context).ebpf_opt_unsupported})',
                // 新版二进制已移除 tc，改名 socket_assign
                'socket_assign': _ebpfSupport.socketAssign
                    ? S.of(context).ebpf_opt_data_plane_socket_assign
                    : '${S.of(context).ebpf_opt_data_plane_socket_assign} (${S.of(context).ebpf_opt_unsupported})',
              },
              // 本机检测不支持的数据面置灰
              disabledValues: {
                if (!_ebpfSupport.cgroup) 'cgroup',
                if (!_ebpfSupport.socketAssign) 'socket_assign',
              },
              onChanged: (v) => setState(() => _ebpfDataPlane = v),
            ),
            _ebpfOptionRow(
              label: S.of(context).ebpf_opt_network,
              value: _effectiveNetwork,
              items: {
                'all': S.of(context).ebpf_opt_network_all,
                'tcp': S.of(context).ebpf_opt_network_tcp,
                'udp': S.of(context).ebpf_opt_network_udp,
              },
              onChanged: (v) => setState(() => _ebpfNetwork = v),
            ),
          ],
        ],
      ),
    );
  }

  /// eBPF 可调项行：左标签 + 右下拉（表单内联，风格与现有行一致）
  ///
  /// [disabledValues] 里的选项不可选（例如探测明确不支持的数据面）。
  Widget _ebpfOptionRow({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
    Set<String> disabledValues = const {},
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10.0, 0, 10.0, 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.0))),
          DropdownButton<String>(
            value: value,
            underline: const SizedBox.shrink(),
            items: items.entries
                .map((e) => DropdownMenuItem<String>(
                      value: e.key,
                      enabled: !disabledValues.contains(e.key),
                      child: Text(
                        e.value,
                        style: TextStyle(
                          fontSize: 13.0,
                          color: disabledValues.contains(e.key) ? Colors.grey : null,
                        ),
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                debugPrint('addproxy: $label -> $v');
                onChanged(v);
              }
            },
          ),
        ],
      ),
    );
  }

  /// 地址/端口变更后（防抖 1s）做一次 TCP 连通性探测，把结果弹给用户；不影响保存
  void checkConnect(context) async {
    final ip = _controller_proxyHost.text;
    final port = _controller_proxyPort.text;

    if (ip.isEmpty || port.isEmpty) {
      return;
    }
    debugPrint("checkConnect:$ip:$port");
    try {
      final socket = await Socket.connect(ip, int.parse(port), timeout: const Duration(seconds: 1));
      socket.close();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('connect success'), backgroundColor: Colors.greenAccent));
    } catch (e) {
      debugPrint(e.toString());
    }
  }
}

class ProxyType extends StatefulWidget {
  const ProxyType({super.key, required this.controller});

  final TextEditingController controller;

  /// 创建 State
  @override
  State<ProxyType> createState() => _ProxyTypeState();
}

enum proxyItem {
  http('http'),
  socks5('socks5');

  const proxyItem(this.label);

  final String label;
}

class _ProxyTypeState extends State<ProxyType> {
  final String defaultValue = 'socks5';

  /// 构建表单：名称 → 类型 → 地址 → 端口 → 账号/密码 → eBPF 开关
  @override
  Widget build(BuildContext context) {
    return DropdownMenu<proxyItem>(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStateProperty.all(Colors.purple[100]),
      ),
      // 设置DropdownMenu的宽度将与其父级的宽度相同
      expandedInsets: EdgeInsets.zero,
      // 设置初始选中项为_http
      initialSelection: widget.controller.text == defaultValue ? proxyItem.socks5 : proxyItem.http,
      // 关联的控制器
      controller: widget.controller,
      // 点击时不自动获取焦点
      requestFocusOnTap: false,
      // 禁用搜索功能
      enableSearch: false,
      // 菜单标签
      label: Text(S.of(context).text_proxy_type),
      // 生成下拉菜单项的列表
      dropdownMenuEntries: proxyItem.values.map<DropdownMenuEntry<proxyItem>>((proxyItem item) {
        // 为每个proxyItem生成一个DropdownMenuEntry
        return DropdownMenuEntry<proxyItem>(
          value: item, // 设置菜单项的值
          label: item.label, // 设置菜单项的显示文本
        );
      }).toList(),
    );
  }
}
