import 'package:appproxy/ui/proxy_config_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:appproxy/ui/app_config_list.dart';

import 'ui/settings.dart';

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
      home: const iyueMainPage(),
    );
  }
}

class iyueMainPage extends StatefulWidget {
  const iyueMainPage({super.key});

  @override
  State<iyueMainPage> createState() => _iyueMainPageState();
}

class _iyueMainPageState extends State<iyueMainPage> {
  int _currentIndex = 0;
  late List<String> _appBarTitles;

  // 创建globalkey 方便调用子控件方法
  final GlobalKey<AppConfigState> _appConfigKey = GlobalKey<AppConfigState>();
  final GlobalKey<AppConfigListOptionCheckboxState> _appOptionKey =
      GlobalKey<AppConfigListOptionCheckboxState>();
  late List<Widget> _children;

  // 2. 新增菜单项支持选择用户app和系统app以及全选等动态避免刷新ui时始终不变
  bool _showUserAppisSelected = true;
  bool _showSystemAppSelected = false;
  bool _selectAll = false;

  /// initState函数是在State对象被创建并插入到Widget树中时调用的。
  @override
  void initState() {
    super.initState(); // 调用父类的initState方法
    // 初始化_children列表，包含首页、配置列表和设置页三个Widget
    _children = <Widget>[
      // 首页Widget
      const ProxyListHome(),
      // app配置列表
      AppConfigList(key: _appConfigKey),
      // 设置页面 TODO
      const AppSettings(), // 设置页Widget
    ];
    _appBarTitles = ['ProxyConfig', 'AppConfigList', 'Settings'];
  }

  // 调用子控件方法传递菜单项选择内容
  void _onChangedShowUserApp(bool? value) {
    _appConfigKey.currentState?.updateShowUserApp(value);
    _showUserAppisSelected = value!;
    _appOptionKey.currentState?.updateSelect(false);
    _selectAll = false;
  }

  void _onChangedShowSystemApp(bool? value) {
    _appConfigKey.currentState?.updateShowSystemApp(value);
    _showSystemAppSelected = value!;
    _appOptionKey.currentState?.updateSelect(false);
    _selectAll = false;
  }

  void _onChangedSelectAll(bool? value) {
    _appConfigKey.currentState?.updateSelectAll(value);
    _selectAll = value!;
  }

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
                        PopupMenuItem<String>(
                            value: 'showUserApp',
                            child: Row(
                              children: [
                                const Text('显示用户应用'),
                                const Spacer(),
                                AppConfigListOptionCheckbox(
                                    isSelected: _showUserAppisSelected,
                                    onChanged: _onChangedShowUserApp)
                              ],
                            )),
                        PopupMenuItem<String>(
                            value: 'showSystemApp',
                            child: Row(
                              children: [
                                const Text('显示系统应用'),
                                const Spacer(),
                                AppConfigListOptionCheckbox(
                                    isSelected: _showSystemAppSelected,
                                    onChanged: _onChangedShowSystemApp)
                              ],
                            )),
                        PopupMenuItem<String>(
                            value: 'selectAll',
                            child: Row(
                              children: [
                                const Text('全选'),
                                const Spacer(),
                                AppConfigListOptionCheckbox(
                                    key: _appOptionKey,
                                    isSelected: _selectAll,
                                    onChanged: _onChangedSelectAll)
                              ],
                            )),
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

class AppConfigListOptionCheckbox extends StatefulWidget {
  AppConfigListOptionCheckbox({super.key, required this.isSelected, required this.onChanged});

  final Function(bool? value) onChanged;
  bool? isSelected;

  @override
  State<AppConfigListOptionCheckbox> createState() => AppConfigListOptionCheckboxState();
}

class AppConfigListOptionCheckboxState extends State<AppConfigListOptionCheckbox> {
  // 更新appconfig 菜单项是否选中
  void updateSelect(bool? value) {
    setState(() {
      widget.isSelected = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Checkbox(
        value: widget.isSelected,
        onChanged: (bool? value) => {
              // 把ui刷新控制在内部
              setState(() {
                widget.onChanged(value);
                widget.isSelected = value;
              })
            });
  }
}
