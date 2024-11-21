import 'package:appproxy/ui/app_config_list.dart';
import 'package:appproxy/ui/proxy_config_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'generated/l10n.dart';
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
      title: "appproxy",
      // 在调试模式下打开一个小“DEBUG”横幅，以指示应用程序处于调试模式。默认情况下（在调试模式下）处于打开状态，要将其关闭，请将构造函数参数设置为 false。在发布模式下这没有任何效果
      debugShowCheckedModeBanner: true,
      localeResolutionCallback: (Locale? locale, Iterable<Locale> supportedLocales) {
        var result =
            supportedLocales.where((element) => element.languageCode == locale?.languageCode);
        if (result.isNotEmpty) {
          debugPrint(locale?.languageCode);
          if (locale.toString().contains("zh")) {
            return const Locale('zh', 'CN');
          } else {
            return const Locale('en', 'US');
          }
        }
        return const Locale('zh', 'CN');
        // return _initLocale;
      },
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      theme: ThemeData(
          // 使用深紫色作为主题颜色方案的种子颜色
          colorScheme: ColorScheme.fromSeed(
            primary: const Color.fromRGBO(149, 0, 255, 1.0),
            seedColor: const Color.fromRGBO(149, 0, 255, 1.0),
            secondary: Colors.transparent, // 可选：设置次要颜色为透明，避免产生额外的颜色
            error: Colors.transparent, // 可选：设置错误颜色为透明，避免产生额外的颜色
            // 其他颜色也可以根据需要设置为透明或自定义颜色
          ),
          appBarTheme: const AppBarTheme(centerTitle: true)),
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

  late List<Widget> _children;

  // initState函数是在State对象被创建并插入到Widget树中时调用的。
  @override
  void initState() {
    super.initState(); // 调用父类的initState方法
    // 初始化_children列表，包含首页、配置列表和设置页三个Widget
    _children = <Widget>[
      // 首页Widget
      const ProxyListHome(),
      // app配置列表
      FutureBuilder(
          // 先启动后加载
          future: Future.delayed(const Duration(milliseconds: 100)),
          builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
            // 当计算状态为等待时，显示加载动画
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                // 显示一个加载动画
                child: CircularProgressIndicator(),
              );
            } else if (snapshot.hasError) {
              // 当 future 出现错误时，显示错误信息
              return Center(
                child: Text('Error: ${snapshot.error}'),
              );
            } else {
              // 当计算完成时，显示app配置列表
              return const AppConfigList();
            }
          }),
      // const AppConfigList(),
      // 设置页面
      const AppSettings(), // 设置页Widget
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: S.current.text_proxy,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: S.of(context).text_configure,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings),
            label: S.of(context).text_settings,
          ),
        ],
      ),
    );
  }
}
