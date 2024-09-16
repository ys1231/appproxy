// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'intl/messages_all.dart';

// **************************************************************************
// Generator: Flutter Intl IDE plugin
// Made by Localizely
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars
// ignore_for_file: join_return_with_assignment, prefer_final_in_for_each
// ignore_for_file: avoid_redundant_argument_values, avoid_escaping_inner_quotes

class S {
  S();

  static S? _current;

  static S get current {
    assert(_current != null,
        'No instance of S was loaded. Try to initialize the S delegate before accessing S.current.');
    return _current!;
  }

  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  static Future<S> load(Locale locale) {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode
        : locale.toString();
    final localeName = Intl.canonicalizedLocale(name);
    return initializeMessages(localeName).then((_) {
      Intl.defaultLocale = localeName;
      final instance = S();
      S._current = instance;

      return instance;
    });
  }

  static S of(BuildContext context) {
    final instance = S.maybeOf(context);
    assert(instance != null,
        'No instance of S present in the widget tree. Did you add S.delegate in localizationsDelegates?');
    return instance!;
  }

  static S? maybeOf(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  /// `Proxy`
  String get text_proxy {
    return Intl.message(
      'Proxy',
      name: 'text_proxy',
      desc: '',
      args: [],
    );
  }

  /// `Configure`
  String get text_configure {
    return Intl.message(
      'Configure',
      name: 'text_configure',
      desc: '',
      args: [],
    );
  }

  /// `Settings`
  String get text_settings {
    return Intl.message(
      'Settings',
      name: 'text_settings',
      desc: '',
      args: [],
    );
  }

  /// `Add Proxy`
  String get text_add_proxy {
    return Intl.message(
      'Add Proxy',
      name: 'text_add_proxy',
      desc: '',
      args: [],
    );
  }

  /// `Please fill in all parameters!`
  String get text_check_parameters {
    return Intl.message(
      'Please fill in all parameters!',
      name: 'text_check_parameters',
      desc: '',
      args: [],
    );
  }

  /// `Configuration Name`
  String get text_config_name {
    return Intl.message(
      'Configuration Name',
      name: 'text_config_name',
      desc: '',
      args: [],
    );
  }

  /// `Configuration name cannot be modified!`
  String get text_config_cannot_be_modified {
    return Intl.message(
      'Configuration name cannot be modified!',
      name: 'text_config_cannot_be_modified',
      desc: '',
      args: [],
    );
  }

  /// `Proxy Address`
  String get text_proxy_addr {
    return Intl.message(
      'Proxy Address',
      name: 'text_proxy_addr',
      desc: '',
      args: [],
    );
  }

  /// `Proxy Port`
  String get text_proxy_port {
    return Intl.message(
      'Proxy Port',
      name: 'text_proxy_port',
      desc: '',
      args: [],
    );
  }

  /// `Username`
  String get text_proxy_username {
    return Intl.message(
      'Username',
      name: 'text_proxy_username',
      desc: '',
      args: [],
    );
  }

  /// `Password`
  String get text_proxy_passworld {
    return Intl.message(
      'Password',
      name: 'text_proxy_passworld',
      desc: '',
      args: [],
    );
  }

  /// `Proxy Type`
  String get text_proxy_type {
    return Intl.message(
      'Proxy Type',
      name: 'text_proxy_type',
      desc: '',
      args: [],
    );
  }

  /// `Configuration List`
  String get text_app_config_list {
    return Intl.message(
      'Configuration List',
      name: 'text_app_config_list',
      desc: '',
      args: [],
    );
  }

  /// `Search Applications`
  String get text_search_app {
    return Intl.message(
      'Search Applications',
      name: 'text_search_app',
      desc: '',
      args: [],
    );
  }

  /// `Select All`
  String get text_select_all {
    return Intl.message(
      'Select All',
      name: 'text_select_all',
      desc: '',
      args: [],
    );
  }

  /// `Show User Applications`
  String get text_show_user_app {
    return Intl.message(
      'Show User Applications',
      name: 'text_show_user_app',
      desc: '',
      args: [],
    );
  }

  /// `Show System Applications`
  String get text_show_system_app {
    return Intl.message(
      'Show System Applications',
      name: 'text_show_system_app',
      desc: '',
      args: [],
    );
  }

  /// `Update Tips`
  String get text_update_tips {
    return Intl.message(
      'Update Tips',
      name: 'text_update_tips',
      desc: '',
      args: [],
    );
  }

  /// `Current Version`
  String get text_current_version {
    return Intl.message(
      'Current Version',
      name: 'text_current_version',
      desc: '',
      args: [],
    );
  }

  /// `Latest Version`
  String get text_latest_version {
    return Intl.message(
      'Latest Version',
      name: 'text_latest_version',
      desc: '',
      args: [],
    );
  }

  /// `Update Content:`
  String get text_update_content {
    return Intl.message(
      'Update Content:',
      name: 'text_update_content',
      desc: '',
      args: [],
    );
  }

  /// `Cancel`
  String get text_cancel {
    return Intl.message(
      'Cancel',
      name: 'text_cancel',
      desc: '',
      args: [],
    );
  }

  /// `Download`
  String get text_download {
    return Intl.message(
      'Download',
      name: 'text_download',
      desc: '',
      args: [],
    );
  }

  /// `Tips`
  String get text_tips {
    return Intl.message(
      'Tips',
      name: 'text_tips',
      desc: '',
      args: [],
    );
  }

  /// `Are you sure you want to delete this proxy configuration?`
  String get text_delete_proxy_tips {
    return Intl.message(
      'Are you sure you want to delete this proxy configuration?',
      name: 'text_delete_proxy_tips',
      desc: '',
      args: [],
    );
  }

  /// `Confirm`
  String get text_confirm {
    return Intl.message(
      'Confirm',
      name: 'text_confirm',
      desc: '',
      args: [],
    );
  }

  /// `Configuration List`
  String get text_server_config {
    return Intl.message(
      'Configuration List',
      name: 'text_server_config',
      desc: '',
      args: [],
    );
  }

  /// `Version Update`
  String get text_version_update {
    return Intl.message(
      'Version Update',
      name: 'text_version_update',
      desc: '',
      args: [],
    );
  }

  /// `Enable Update Check`
  String get text_is_open_check_update {
    return Intl.message(
      'Enable Update Check',
      name: 'text_is_open_check_update',
      desc: '',
      args: [],
    );
  }

  /// `Check for Updates`
  String get text_check_update {
    return Intl.message(
      'Check for Updates',
      name: 'text_check_update',
      desc: '',
      args: [],
    );
  }

  /// `About`
  String get text_about {
    return Intl.message(
      'About',
      name: 'text_about',
      desc: '',
      args: [],
    );
  }

  /// `appproxy is a lightweight VPN proxy tool that supports HTTP and SOCKS5 protocols.`
  String get text_describe {
    return Intl.message(
      'appproxy is a lightweight VPN proxy tool that supports HTTP and SOCKS5 protocols.',
      name: 'text_describe',
      desc: '',
      args: [],
    );
  }

  /// `Author: @iyue`
  String get text_author {
    return Intl.message(
      'Author: @iyue',
      name: 'text_author',
      desc: '',
      args: [],
    );
  }

  /// `Update Time`
  String get text_update_time {
    return Intl.message(
      'Update Time',
      name: 'text_update_time',
      desc: '',
      args: [],
    );
  }

  /// `Failed to get version information, please use domestic update channels!`
  String get text_get_version_info_fail {
    return Intl.message(
      'Failed to get version information, please use domestic update channels!',
      name: 'text_get_version_info_fail',
      desc: '',
      args: [],
    );
  }

  /// `Failed to get version information, please check your network!`
  String get text_get_version_info_check_networ {
    return Intl.message(
      'Failed to get version information, please check your network!',
      name: 'text_get_version_info_check_networ',
      desc: '',
      args: [],
    );
  }

  /// `You are on the latest version`
  String get text_current_latest {
    return Intl.message(
      'You are on the latest version',
      name: 'text_current_latest',
      desc: '',
      args: [],
    );
  }

  /// `Language`
  String get text_language {
    return Intl.message(
      'Language',
      name: 'text_language',
      desc: '',
      args: [],
    );
  }

  /// `Switch the language`
  String get text_switch_language {
    return Intl.message(
      'Switch the language',
      name: 'text_switch_language',
      desc: '',
      args: [],
    );
  }
}

class AppLocalizationDelegate extends LocalizationsDelegate<S> {
  const AppLocalizationDelegate();

  List<Locale> get supportedLocales {
    return const <Locale>[
      Locale.fromSubtags(languageCode: 'en'),
      Locale.fromSubtags(languageCode: 'en', countryCode: 'US'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
    ];
  }

  @override
  bool isSupported(Locale locale) => _isSupported(locale);
  @override
  Future<S> load(Locale locale) => S.load(locale);
  @override
  bool shouldReload(AppLocalizationDelegate old) => false;

  bool _isSupported(Locale locale) {
    for (var supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return true;
      }
    }
    return false;
  }
}
