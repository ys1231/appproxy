import 'package:appproxy/ui/proxy_config_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/app_config_list.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    /**
     * 构建并返回一个MaterialApp实例。
     * 这个函数不接受任何参数。
     *
     * @return 返回一个配置了特定主题和起始页面的MaterialApp实例。
     */
    return MaterialApp(
      // 应用标题
      title: 'iyue Flutter',
      // 在调试模式下打开一个小“DEBUG”横幅，以指示应用程序处于调试模式。默认情况下（在调试模式下）处于打开状态，要将其关闭，请将构造函数参数设置为 false。在发布模式下这没有任何效果
      debugShowCheckedModeBanner: true,
      theme: ThemeData(
        // 使用深紫色作为主题颜色方案的种子颜色
        colorScheme: ColorScheme.fromSeed(
          primary: const Color.fromRGBO(149, 0, 255, 1.0),
          seedColor: const Color.fromRGBO(149, 0, 255, 1.0),
          secondary: Colors.transparent, // 可选：设置次要颜色为透明，避免产生额外的颜色
          error: Colors.transparent, // 可选：设置错误颜色为透明，避免产生额外的颜色
          // 其他颜色也可以根据需要设置为透明或自定义颜色
        ),
      ),
      // 设置底部导航菜单作为应用的起始页面
      home: const BottomMenuPage(),
    );
  }
}

class BottomMenuPage extends StatefulWidget {
  const BottomMenuPage({super.key});

  @override
  State<BottomMenuPage> createState() => _BottomMenuPageState();
}

class _BottomMenuPageState extends State<BottomMenuPage> {
  int _currentIndex = 0;
  late List<String> _appBarTitles;

  /// initState函数是在State对象被创建并插入到Widget树中时调用的。
  /// 这个函数不接受任何参数，并且没有返回值。
  /// 在这个函数中，我们可以进行一些初始化操作，比如设置状态栏颜色、初始化数据等。
  @override
  void initState() {
    super.initState(); // 调用父类的initState方法
    // 初始化_children列表，包含首页、配置列表和设置页三个Widget
    _children = <Widget>[
      const ProxyListHome(), // 首页Widget
      const AppConfigList(), // 配置列表Widget，标题变化时更新AppBar标题
      const Text('Settings'), // 设置页Widget
    ];
    _appBarTitles = ['ProxyConfig', 'AppConfigList', 'Settings'];
  }

  late List<Widget> _children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          backgroundColor: Theme.of(context).primaryColor,
          title: Text(_appBarTitles[_currentIndex]),
          actions: _appBarTitles[_currentIndex] == "AppConfigList"
              ? <Widget>[
                  PopupMenuButton<String>(
                    // 设置弹出菜单的图标
                    icon: const Icon(Icons.more_vert),
                    // 定义菜单项
                    itemBuilder: (BuildContext context) {
                      return [
                        const PopupMenuItem<String>(
                            value: 'Option_1', child: Text('Option 1')),
                        const PopupMenuItem<String>(
                            value: 'Option_2', child: Text('Option 2')),
                        const PopupMenuItem<String>(
                            value: 'Option_3', child: Text('Option 3')),
                      ];
                    },
                    // 当选择一个菜单项时触发的回调
                    onSelected: (String value) {
                      print('Selected option: $value');
                    },
                  )
                ]
              : []),
      body: IndexedStack(
        index: _currentIndex,
        children: _children,
      ), //_children[_currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '代理',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: '配置',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
