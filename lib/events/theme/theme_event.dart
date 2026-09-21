part of 'theme_bloc.dart';

@immutable
sealed class ThemeEvent {}

class SetThemeEvent extends ThemeEvent {
  final ThemeMode themeMode;

  SetThemeEvent(this.themeMode);
}
