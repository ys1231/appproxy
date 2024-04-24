import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ProxyListHome extends StatefulWidget {
  const ProxyListHome({Key? key}) : super(key: key);

  @override
  State<ProxyListHome> createState() => _ProxyListHomeState();
}

class _ProxyListHomeState extends State<ProxyListHome> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text("代理页面"),
      // ),
      body: const Text("ProxyListHome"),
      floatingActionButton: InkWell(
          // 点击事件处理函数
          onTap: () {
            // 使用Navigator.push实现页面路由跳转，传入当前上下文context和MaterialPageRoute构建器
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const AddProxyConfig()
                )
            );
          },
          child: Container(
            height: 50.0,
            // 构建一个BoxDecoration对象，用于设置容器的装饰效果
            decoration: BoxDecoration(
              // 设置背景颜色为紫色
              color: Colors.purple,
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
                      Icon(
                        Icons.add,
                        color: Colors.white,
                      ),
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
          )),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class AddProxyConfig extends StatefulWidget {
  const AddProxyConfig({super.key});

  @override
  State<AddProxyConfig> createState() => _AddProxyConfigState();
}

class _AddProxyConfigState extends State<AddProxyConfig> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("添加代理"),
          backgroundColor: const Color.fromRGBO(142, 0, 244, 1.0),
        ),
        body: Container(
            color: Colors.purple.withOpacity(0.1),
            child: const SingleChildScrollView(
              padding: EdgeInsets.all(20.0),
              child: Column(
                // 设置UI布局中子元素的主轴线对齐方式
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      labelText: '配置名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 20.0),
                  ProxyType(),
                  SizedBox(height: 20.0),
                  TextField(
                    decoration: InputDecoration(
                      labelText: '代理类型',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 20.0),
                  TextField(
                    decoration: InputDecoration(
                      labelText: '代理地址',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 20.0),
                  TextField(
                    decoration: InputDecoration(
                      labelText: '代理端口',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 20.0),
                  TextField(
                    decoration: InputDecoration(
                      labelText: '名户名',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 20.0),
                  TextField(
                    decoration: InputDecoration(
                      labelText: '密码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 100.0),
                ],
              ),
            )));
  }
}

class ProxyType extends StatefulWidget {
  const ProxyType({Key? key}) : super(key: key);

  @override
  State<ProxyType> createState() => _ProxyTypeState();
}

enum proxyItem {
  http('Http'),
  socks5('Socks5');

  const proxyItem(this.label);

  final String label;
}

class _ProxyTypeState extends State<ProxyType> {
  String defaultValue = 'http';
  final controller = TextEditingController();

  proxyItem? selectedColor;

  void onChanged(String? newValue) {
    setState(() {
      defaultValue = newValue!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<proxyItem>(
      // 设置菜单宽度为屏幕宽度的90%
      width: MediaQuery.of(context).size.width * 0.9,
      // 设置初始选中项为_http
      initialSelection: proxyItem.http,
      // 关联的控制器
      controller: controller,
      // 点击时不自动获取焦点
      requestFocusOnTap: false,
      // 禁用搜索功能
      enableSearch: false,
      // 菜单标签
      label: const Text('代理类型'),
      // 选择项时的回调
      onSelected: (proxyItem? item) {
        setState(() {
          selectedColor = item;
        });
      },
      // 生成下拉菜单项的列表
      dropdownMenuEntries:
          proxyItem.values.map<DropdownMenuEntry<proxyItem>>((proxyItem item) {
        // 为每个proxyItem生成一个DropdownMenuEntry
        return DropdownMenuEntry<proxyItem>(
          value: item, // 设置菜单项的值
          label: item.label, // 设置菜单项的显示文本
        );
      }).toList(),
    );
  }
}
