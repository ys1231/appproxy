import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/proxy_config_data.dart';
import 'addproxy.dart';

class ProxyListHome extends StatefulWidget {
  const ProxyListHome({super.key});

  @override
  State<ProxyListHome> createState() => _ProxyListHomeState();
}

class _ProxyListHomeState extends State<ProxyListHome> {
  final ProxyConfigData _proxyConfigData = ProxyConfigData();

  int _itemCount = 0;
  List<Map<String, dynamic>> _dataLists = [];
  bool _iscalled = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      print("---- ProxyListHome initState call ");
    }
    initProxyConfig();
  }

  void initProxyConfig() {
    if (kDebugMode) {
      print("---- ProxyListHome initProxyConfig call ");
    }
    if (_iscalled) {
      return;
    }
    _iscalled = true;
    try {
      _proxyConfigData.readProxyConfig().then((value) {
        setState(() {
          _dataLists = value ?? [];
          _itemCount = _dataLists.length;
        });
      });
    } catch (e) {
      if (kDebugMode) {
        print("---- ProxyListHome initProxyConfig error $e");
      }
    }

    return;
  }

  void handleConfigData(Map<String, dynamic> data) {
    // 在这里处理从 AddProxyButton 返回的数据
    _proxyConfigData.addProxyConfig(data).then((value) {
      setState(() {
        _dataLists.add(data);
        if (kDebugMode) print('Received data: $data _dataLists lenth:${_dataLists.length}');
        // 可能还会根据数据更新state，触发UI重建等
        _itemCount = _dataLists.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      print("---- ProxyListHome build call $_itemCount $_dataLists");
    }
    return Scaffold(
      body: ListView.separated(
        // 创建从边缘反弹的滚动物理效果
        physics: const BouncingScrollPhysics(),
        // 设置底部内边距 解决底部按钮遮挡问题
        padding: const EdgeInsets.only(bottom: 70.0),
        // 配置列表个数
        itemCount: _itemCount,
        // 设置分隔符零尺寸
        separatorBuilder: (BuildContext context, int index) {
          return const SizedBox.shrink();
        },
        itemBuilder: (BuildContext context, int c_index) {
          if (kDebugMode) {
            print("---- ProxyListHome c_index: $c_index ");
          }
          Map<String, dynamic> c_data = _dataLists[c_index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            key: ValueKey(c_index),
            child: ListTile(
              title: Text('${c_data["proxyName"]}'),
              subtitle: Text(
                  '${c_data["proxyType"]} ${c_data["proxyHost"]}:${c_data["proxyPort"]}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () {
                  if (kDebugMode) {
                    print("delete item:$c_data");
                  }
                  setState(() {
                    _dataLists.removeAt(c_index);
                    _itemCount = _dataLists.length;
                    _proxyConfigData.deleteProxyConfig(c_data);
                  });
                },
              ),
              onTap: () {
                if (kDebugMode) {
                  print("---- ProxyListHome onTap ${c_data}");
                }
              },
            ),
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
  final Function(Map<String, dynamic>) onDataFetched;

  @override
  Widget build(BuildContext context) {
    // proxyConfigData.readProxyConfig();
    return InkWell(
        // 点击事件处理函数
        onTap: () {
          // 使用Navigator.push 实现页面路由跳转，传入当前上下文context和MaterialPageRoute构建器
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddProxyWidget()),
          ).then((value) {
            if (kDebugMode) {
              print("onDataFetched:$value");
            }
            if (value != null) {
              onDataFetched(value);
            }
          });
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

                /// 阴影的扩展半径，0.0表示没有扩展
                spreadRadius: 0.0,

                /// 阴影的模糊半径，1.0表示轻微模糊
                blurRadius: 1.0,

                /// 阴影的偏移量，这里设置为水平0像素，垂直2像素的偏移
                offset: const Offset(0, 3),
              ),
            ],
          ),

          // 在UI中创建一个带内边距的子组件，用于显示“添加代理”按钮
          child: const Padding(
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
                    Icon(Icons.add, color: Colors.white),
                    // 在图标和文本之间添加一个宽度为10.0的空白间隔
                    SizedBox(width: 5.0),
                    // 添加文本组件，显示“添加代理”文本
                    Text(
                      "添加代理",
                      style: TextStyle(fontSize: 16.0, color: Colors.white),
                    ),
                    SizedBox(width: 5.0),
                  ],
                ),
              )),
        ));
  }
}
