import 'package:shared_preferences/shared_preferences.dart';

class AppSetings {
  static const String _CheckUpdate = "isUpdate";

  static Future<bool> getCheckUpdate() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_CheckUpdate) ?? true;
  }

  static Future<bool> setCheckUpdate(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_CheckUpdate, value);
  }
}