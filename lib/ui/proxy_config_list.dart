import 'dart:async';

import 'package:appproxy/data/proxy_config_data.dart';
import 'package:appproxy/events/app_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../generated/l10n.dart';
import 'addproxy.dart';

class ProxyListHome extends StatefulWidget {
  const ProxyListHome({super.key});

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

  // 方法调用通道
  static const platform = MethodChannel("cn.ys1231/appproxy/vpn");

  // 当前需要启动的代理配置
  Map<String, dynamic> _currentData = {};

  @override
  void initState() {
    super.initState();
    debugPrint("---- ProxyListHome initState call ");
    initProxyConfig();
  }

  void initProxyConfig() {
    debugPrint("---- ProxyListHome initProxyConfig call ");
    if (_iscalled) {
      return;
    }
    _iscalled = true;
    try {
      // 初始化历史代理配置
      _proxyConfigData.readProxyConfig().then((value) {
        setState(() {
          _dataLists.clear();
          _dataLists = value ?? [];
        });
      });
    } catch (e) {
      debugPrint("---- ProxyListHome initProxyConfig error $e");
    }
  }

  // 在这里处理从 AddProxyButton 返回的数据 添加代理配置到列表
  void handleConfigData(Map<String, dynamic> data, {bool isAdd = false}) {
    if (!isAdd &&
        _dataLists.any((item) => item['proxyName'] == data['proxyName'])) {
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
    setState(() {
      debugPrint(
          'Received data: $_dataLists _dataLists lenth:${_dataLists.length}');
    });
  }

  // 删除列表中的代理配置
  void deletetoProxyConfig(Map<String, dynamic> data) {
    _dataLists.removeWhere((item) => item['proxyName'] == data['proxyName']);
    _proxyConfigData.deleteProxyConfig(_dataLists);
    setState(() {
      debugPrint(
          'delete data: $_dataLists _dataLists lenth:${_dataLists.length}');
    });
  }

  // 显示提示是否删除代理
  Future<void> _showDeleteDialog(
      BuildContext context, Map<String, dynamic> data) async {
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

  // 启动VPN
  void _startProxy() async {
    _currentData['appProxyPackageList'] = appProxyPackageList.getListString();
    try {
      bool result = await platform.invokeMethod('startVpn', _currentData);
      if (result) {
        debugPrint("---- ProxyListHome startVpn: $_currentData success");
      } else {
        debugPrint("---- ProxyListHome startVpn: $_currentData fail");
        _isSelectedProxyName = "";
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to start proxy: '${e.message}'.");
    }
  }

  // 关闭VPN
  void _stopProxy() async {
    try {
      bool result = await platform.invokeMethod('stopVpn');
      if (result) {
        debugPrint("---- ProxyListHome stopVpn success");
      } else {
        debugPrint("---- ProxyListHome stopVpn fail");
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to stop proxy: '${e.message}'.");
    }
  }

  @override
  Widget build(BuildContext context) {
    // debugPrint("---- ProxyListHome build call: $_dataLists");
    return Scaffold(
      appBar: AppBar(
        title: Text('Server ${S.of(context).text_server_config}'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: ListView.separated(
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
                  value: _isSelectedProxyName == c_data["proxyName"]
                      ? true
                      : false,
                  // 设置标题和副标题
                  title: Text('${c_data["proxyName"]}'),
                  subtitle: Text(
                      '${c_data["proxyType"]} ${c_data["proxyHost"]}:${c_data["proxyPort"]}'),
                  // 设置switch的onChanged事件
                  onChanged: (bool value) {
                    setState(() {
                      if (value) {
                        _isSelectedProxyName = c_data["proxyName"];
                        _currentData = c_data;
                        _startProxy();
                      } else {
                        _stopProxy();
                        _isSelectedProxyName = "";
                      }
                      debugPrint(
                          "current index:$c_index select: $_isSelectedProxyName");
                    });
                  },
                ),
                // 设置长按事件 主要触发删除操作
                onLongPress: () {
                  debugPrint("long press delete:${c_data["proxyName"]}");
                  _showDeleteDialog(context, c_data);
                },
                // 设置双击事件
                onDoubleTap: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (BuildContext context) {
                    return AddProxyWidget(
                        onDataFetched: handleConfigData, onData: c_data);
                  }));
                }),
          );
        },
      ),
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
                builder: (context) => AddProxyWidget(
                    onDataFetched: onDataFetched, onData: const {})),
          );
        },
        child: Container(
          height: 50.0,
          // 构建一个BoxDecoration对象，用于设置容器的装饰效果
          decoration: BoxDecoration(
            // 设置背景颜色为紫色
            color: Colors.purple.withOpacity(0.9),
            // 设置边框圆角为24.0
            borderRadius: BorderRadius.circular(15.0),
            boxShadow: [
              /// 创建一个紫色的阴影效果
              BoxShadow(
                /// 阴影颜色，这里设置为淡紫色
                color: Colors.purple.withOpacity(0.2),
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
                      style:
                          const TextStyle(fontSize: 16.0, color: Colors.white),
                    ),
                    const SizedBox(width: 5.0),
                  ],
                ),
              )),
        ));
  }
}
