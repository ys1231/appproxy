import 'package:shared_preferences/shared_preferences.dart';

class AppSetings {
  static const String _CheckUpdate = "isUpdate";
  static const String _CheckWifi = "isCheckWifi";
  static const String _enableDarkMode = "isEnableDarkMode";
  static const String _TransparentProxy = "isTransparentProxy";

  static Future<bool> getCheckUpdate() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_CheckUpdate) ?? true;
  }

  static Future<bool> setCheckUpdate(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_CheckUpdate, value);
  }

  static Future<bool> getCheckWifi() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_CheckWifi) ?? true;
  }

  static Future<bool> setCheckWifi(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_CheckWifi, value);
  }

  static Future<bool> getEnableDarkMode() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enableDarkMode) ?? false;
  }

  static Future<bool> setEnableDarkMode(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_enableDarkMode, value);
  }

  static Future<bool> getTransparentProxy() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_TransparentProxy) ?? false;
  }

  static Future<bool> setTransparentProxy(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_TransparentProxy, value);
  }
}
