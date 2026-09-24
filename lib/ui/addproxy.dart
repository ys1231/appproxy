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
      isDefaultTitle = false;
    }else{
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
          title: Text(isDefaultTitle?S.of(context).text_add_proxy: S.of(context).text_modify_config),
          // backgroundColor: const Color.fromRGBO(142, 0, 244, 1.0),
          backgroundColor: Theme.of(context).primaryColor,
          actions: [
            IconButton(
              padding: const EdgeInsets.only(right: 20.0),
              icon: const Icon(Icons.save),
              onPressed: () async {
                proxyConfig['proxyName'] = _controller_proxyName.text;
                proxyConfig['proxyType'] = _controller_proxyType.text;
                proxyConfig['proxyHost'] = _controller_proxyHost.text;
                proxyConfig['proxyPort'] = _controller_proxyPort.text;
                if (isNullOrEmpty(proxyConfig)) {
                  debugPrint("proxyConfig:$proxyConfig");
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(S.of(context).text_check_parameters),
                      backgroundColor: Colors.purple.withValues(alpha: 0.4)));
                  return;
                }
                // 这俩可以为空
                proxyConfig['proxyUser'] = _controller_proxyUser.text;
                proxyConfig['proxyPass'] = _controller_proxyPass.text;
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
      status = '${s.ebpf_status_supported} (${_ebpfSupport.cgroup ? "cgroup" : "tc"})';
    } else {
      final reasons = _ebpfSupport.reasons.take(2).join('; ');
      status = reasons.isEmpty ? s.ebpf_status_unsupported : '${s.ebpf_status_unsupported}: $reasons';
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
  String defaultValue = 'socks5';
  proxyItem? selectedItem;

  /// 下拉选择回调（值本身由 controller 提供，这里只需要触发重建）
  void onChanged(String? newValue) {
    setState(() {
      defaultValue = newValue!;
    });
  }

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
      // 选择项时的回调
      onSelected: (proxyItem? item) {
        setState(() {
          selectedItem = item;
        });
      },
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
