import 'package:appproxy/events/language/language_bloc.dart';
import 'package:appproxy/events/restore/restore_cubit.dart';
import 'package:appproxy/ui/app_config_list.dart';
import 'package:appproxy/ui/proxy_config_list.dart';
import 'package:appproxy/ui/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'events/theme/theme_bloc.dart';
import 'generated/l10n.dart';


void main() {
  runApp(MultiBlocProvider(providers: [
    BlocProvider<ThemeBloc>(
      create: (context) => ThemeBloc(),
    ),
    BlocProvider<LanguageBloc>(
      create: (context) => LanguageBloc(),
    ),
    BlocProvider<RestoreCubit>(create: (context) => RestoreCubit())
  ], child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  /// 构建界面
  @override
  Widget build(BuildContext context) {
    /**
     * 构建并返回一个MaterialApp实例。
     * 这个函数不接受任何参数。
     *
     * @return 返回一个配置了特定主题和起始页面的MaterialApp实例。
     */
    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<LanguageBloc, LanguageState>(
          builder: (context, langState) {
            return MaterialApp(
              // 应用标题
              title: "appproxy",
              // 在调试模式下打开一个小“DEBUG”横幅，以指示应用程序处于调试模式。默认情况下（在调试模式下）处于打开状态，要将其关闭，请将构造函数参数设置为 false。在发布模式下这没有任何效果
              debugShowCheckedModeBanner: true,
              locale: langState.locale,
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
                    // 设置主颜色，使用RGBA格式定义颜色
                    // RGBA(149, 0, 255, 1.0) 表示红色为149，绿色为0，蓝色为255，透明度为1.0（完全不透明）
                    primary: const Color.fromRGBO(149, 0, 255, 1.0),
                    // 设置种子颜色，使用RGBA格式定义颜色
                    // RGBA(149, 0, 255, 1.0) 表示红色为149，绿色为0，蓝色为255，透明度为1.0（完全不透明）
                    seedColor: const Color.fromRGBO(149, 0, 255, 1.0),
                    secondary: Colors.transparent, // 可选：设置次要颜色为透明，避免产生额外的颜色
                    error: Colors.transparent, // 可选：设置错误颜色为透明，避免产生额外的颜色
                    // 其他颜色也可以根据需要设置为透明或自定义颜色
                  ),
                  appBarTheme: const AppBarTheme(centerTitle: true)),
              darkTheme: ThemeData.dark(useMaterial3: true).copyWith( appBarTheme: const AppBarTheme(centerTitle: true)),
              themeMode: themeState.themeMode,
              // 设置底部导航菜单作为应用的起始页面
              home: const iyueMainPage(),
            );
          },
        );
      },
    );
  }
}

class iyueMainPage extends StatefulWidget {
  const iyueMainPage({super.key});

  /// 创建 State（Flutter 生命周期样板）
  @override
  State<iyueMainPage> createState() => _iyueMainPageState();
}

class _iyueMainPageState extends State<iyueMainPage> {
  int _currentIndex = 0;

  late List<Widget> _children;

  // initState函数是在State对象被创建并插入到Widget树中时调用的。
  /// 初始化：读取数据 / 装配回调（只执行一次）
  @override
  void initState() {
    super.initState(); // 调用父类的initState方法
    // 初始化_children列表，包含首页、配置列表和设置页三个Widget
    _children = <Widget>[
      // 首页Widget
      const ProxyListHome(),
      // app配置列表
      const AppConfigList(),
      // 设置页面
      const AppSettings(), // 设置页Widget
    ];
  }

  /// 构建界面
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
            label: S
                .of(context)
                .text_configure,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings),
            label: S
                .of(context)
                .text_settings,
          ),
        ],
      ),
    );
  }
}
