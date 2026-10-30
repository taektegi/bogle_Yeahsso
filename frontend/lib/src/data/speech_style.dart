import 'korean.dart';
import 'speech_catalog.dart';

enum SpeechManner { plain, bouncy, story, robot }

enum SpeechSample { play, snack, comfort }

extension SpeechMannerDetails on SpeechManner {
  Map<String, dynamic> get catalog =>
      (speechCatalog['manners'] as Map)[name] as Map<String, dynamic>;
  String get label => catalog['label'] as String;
  String get description => catalog['description'] as String;
}

/// 말하는 방식과 높임을 분리하되 기존 speechStyle 문자열 계약으로 보관한다.
class SpeechProfile {
  const SpeechProfile(this.manner, {this.polite = false});
  final SpeechManner manner;
  final bool polite;
  String get value => '${manner.name}_${polite ? 'polite' : 'casual'}';
  String get endingLabel => polite ? '공손한 말' : '편한 말';
  String get label => '${manner.label} · $endingLabel';

  static SpeechProfile? tryParse(String value) {
    for (final manner in SpeechManner.values) {
      for (final polite in [false, true]) {
        final profile = SpeechProfile(manner, polite: polite);
        if (profile.value == value) return profile;
      }
    }
    return null;
  }

  List<String> lines(String topic) => [
    for (final pair
        in (manner.catalog['lines'] as Map)[topic] as List? ?? const [])
      (pair as List)[polite ? 1 : 0] as String,
  ];

  String preview(SpeechSample sample) =>
      koreanTemplate(lines(sample.name).first, {'f': '사과'});

  String introduction(String name) => koreanTemplate(
    (manner.catalog['intro'] as List)[polite ? 1 : 0] as String,
    {'n': name},
  );
}
