part of 'language_bloc.dart';

@immutable
sealed class LanguageEvent {}
class SetLanguageEvent extends LanguageEvent {
  final Locale locale;
  SetLanguageEvent(this.locale);
}
