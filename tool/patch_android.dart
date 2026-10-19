// Run once after `flutter create`:
//   dart run tool/patch_android.dart
//
// Adds what the app needs to android/app/src/main/AndroidManifest.xml:
//   * INTERNET permission (one-time language pack download; release builds
//     don't get it by default)
//   * <queries> entry for TTS_SERVICE (Android 11+ hides TTS engines otherwise)
//
// Safe to run more than once.
import 'dart:io';

const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _internet =
    '    <uses-permission android:name="android.permission.INTERNET"/>';
const _ttsIntent = '''
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE"/>
        </intent>''';

void main() {
  final file = File(_manifestPath);
  if (!file.existsSync()) {
    stderr.writeln('Not found: $_manifestPath\n'
        'Run `flutter create --platforms=android --project-name kannada_helper .` first.');
    exit(1);
  }

  var xml = file.readAsStringSync();
  var changed = false;

  if (!xml.contains('android.permission.INTERNET')) {
    final open = xml.indexOf('<manifest');
    final end = xml.indexOf('>', open);
    if (open < 0 || end < 0) {
      stderr.writeln('Could not find the <manifest> tag. Patch it by hand.');
      exit(1);
    }
    xml = '${xml.substring(0, end + 1)}\n$_internet${xml.substring(end + 1)}';
    changed = true;
  }

  if (!xml.contains('TTS_SERVICE')) {
    if (xml.contains('<queries>')) {
      xml = xml.replaceFirst('<queries>', '<queries>\n$_ttsIntent');
    } else {
      xml = xml.replaceFirst(
          '</manifest>', '    <queries>\n$_ttsIntent\n    </queries>\n</manifest>');
    }
    changed = true;
  }

  if (changed) {
    file.writeAsStringSync(xml);
    stdout.writeln('Patched $_manifestPath');
  } else {
    stdout.writeln('Already patched, nothing to do.');
  }
}
