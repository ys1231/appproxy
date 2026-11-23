import 'package:appproxy/generated/l10n.dart';
import 'package:appproxy/ui/addproxy.dart';
import 'package:appproxy/ui/paste_import_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget home) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.delegate.supportedLocales,
    home: home,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('编辑配置时名称可修改，保存回传 oldName 用于迁移 eBPF 标记', (tester) async {
    Map<String, dynamic>? saved;
    bool? savedIsAdd;
    String? savedOldName;

    await tester.pumpWidget(_app(AddProxyWidget(
      onDataFetched: (data, {bool isAdd = false, String? oldName}) {
        saved = data;
        savedIsAdd = isAdd;
        savedOldName = oldName;
      },
      onData: {
        'proxyName': 'old',
        'proxyType': 'http',
        'proxyHost': '1.1.1.1',
        'proxyPort': '8080',
        'proxyUser': '',
        'proxyPass': '',
      },
      existingNames: const ['other'],
    )));
    await tester.pumpAndSettle();

    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.readOnly, isFalse, reason: '配置名应可编辑');

    await tester.enterText(find.byType(TextField).first, 'new');
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!['proxyName'], 'new');
    expect(savedIsAdd, isTrue);
    expect(savedOldName, 'old');
  });

  testWidgets('粘贴识别页默认加载规则，解析后应用到表单', (tester) async {
    Map<String, String>? captured;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await Navigator.push<Map<String, String>>(
                  context,
                  MaterialPageRoute(builder: (_) => const PasteImportPage()),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 默认选中「识别配置1」(@ 分隔)
    expect(find.text('识别配置1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '节点@http@1.2.3.4@8080@u@p');
    await tester.pumpAndSettle();
    expect(find.text('1.2.3.4'), findsOneWidget);

    await tester.tap(find.text('应用到表单'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!['proxyName'], '节点');
    expect(captured!['proxyType'], 'http');
    expect(captured!['proxyHost'], '1.2.3.4');
    expect(captured!['proxyPort'], '8080');
    expect(captured!['proxyUser'], 'u');
    expect(captured!['proxyPass'], 'p');
  });
}
