import 'package:appproxy/proxypage/proxylisthome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromRGBO(142, 0, 244, 1.0)),
        // 启用Material Design 3主题
        useMaterial3: true,
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
  static const List<Widget> _children = <Widget>[
    ProxyListHome(),
    Text('Profile', style: TextStyle(color: Colors.lightGreenAccent)),
    Text('Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
    ));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        title: const Text(
          'IyueProxy',
        ),
      ),
      body: _children[_currentIndex],
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