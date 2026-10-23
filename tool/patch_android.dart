// Run once after `flutter create`, and again whenever a new phase adds
// entries below:
//   dart run tool/patch_android.dart
//
// Sets up android/ for the app: manifest permissions and queries, minSdk,
// and the native OCR bridge (MainActivity.kt + Tesseract4Android + ONNX Runtime).
// Each change is made only if missing, so it's safe to run any number of times.
import 'dart:io';

const _manifestPath = 'android/app/src/main/AndroidManifest.xml';

const _permissions = [
  'android.permission.INTERNET', // one-time language pack download
  'android.permission.RECORD_AUDIO', // Speak mode
  'android.permission.CAMERA', // Scan mode
  'android.permission.BLUETOOTH', // speech_to_text: Bluetooth headsets
  'android.permission.BLUETOOTH_ADMIN',
  'android.permission.BLUETOOTH_CONNECT',
];

/// Android 11+ hides these services from apps unless declared.
const _queryActions = [
  'android.intent.action.TTS_SERVICE', // Kannada audio
  'android.speech.RecognitionService', // Speak mode
];

/// The camera plugin needs Android 7.0 (API 24) or newer.
const _minSdk = 24;

/// Native libraries used by the OCR bridge (Scan mode).
const _nativeDependencies = [
  // Tesseract: finds words, reads clean printed text.
  'cz.adaptech.tesseract4android:tesseract4android:4.9.0',
  // ONNX Runtime: runs the IndicPhotoOCR PARSeq word reader.
  'com.microsoft.onnxruntime:onnxruntime-android:1.29.0',
];

void main() {
  _patchManifest();
  _patchMinSdk();
  _patchOcrBridge();
}

/// Installs the native OCR bridge: JitPack repo, native dependencies
/// and MainActivity.kt from tool/android/ (with the app's package name).
void _patchOcrBridge() {
  // 1. MainActivity.kt
  final kotlinRoot = Directory('android/app/src/main/kotlin');
  final activity = kotlinRoot.existsSync()
      ? kotlinRoot
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('MainActivity.kt'))
          .firstOrNull
      : null;
  if (activity == null) {
    stderr.writeln('MainActivity.kt not found under ${kotlinRoot.path}. '
        'Copy tool/android/MainActivity.kt there by hand.');
  } else {
    final existing = activity.readAsStringSync();
    final package =
        RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(existing)?.group(1);
    if (package == null) {
      stderr.writeln('${activity.path}: no package line found.');
    } else {
      final template = File('tool/android/MainActivity.kt')
          .readAsStringSync()
          .replaceFirst('__PACKAGE__', package);
      if (existing != template) {
        activity.writeAsStringSync(template);
        stdout.writeln('Installed OCR bridge: ${activity.path}');
      }
    }
  }

  // 2. JitPack repository (Tesseract4Android is published there)
  final rootGradle = File('android/build.gradle.kts');
  if (rootGradle.existsSync()) {
    var text = rootGradle.readAsStringSync();
    if (!text.contains('jitpack.io')) {
      text = text.replaceFirst(RegExp(r'allprojects\s*\{\s*repositories\s*\{'),
          'allprojects {\n    repositories {\n        maven { url = uri("https://jitpack.io") }');
      if (text.contains('jitpack.io')) {
        rootGradle.writeAsStringSync(text);
        stdout.writeln('Patched ${rootGradle.path}: + JitPack repository');
      } else {
        stderr.writeln('${rootGradle.path}: add maven { url = uri("https://jitpack.io") } '
            'to allprojects.repositories by hand.');
      }
    }
  } else {
    stderr.writeln('android/build.gradle.kts not found; add the JitPack repo by hand.');
  }

  // 3. Dependencies
  final appGradle = File('android/app/build.gradle.kts');
  if (appGradle.existsSync()) {
    var text = appGradle.readAsStringSync();
    for (final dep in _nativeDependencies) {
      final artifact = dep.substring(0, dep.lastIndexOf(':'));
      if (text.contains(artifact)) continue;
      final line = '    implementation("$dep")';
      final block = RegExp(r'^dependencies\s*\{', multiLine: true).firstMatch(text);
      text = block == null
          ? '${text.trimRight()}\n\ndependencies {\n$line\n}\n'
          : '${text.substring(0, block.end)}\n$line${text.substring(block.end)}';
      stdout.writeln('Patched ${appGradle.path}: + $dep');
    }
    appGradle.writeAsStringSync(text);
  } else {
    stderr.writeln('android/app/build.gradle.kts not found; add these by hand: '
        '${_nativeDependencies.join(', ')}');
  }
}

/// Makes sure minSdk is at least [_minSdk] in android/app/build.gradle(.kts).
void _patchMinSdk() {
  for (final path in ['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    var gradle = file.readAsStringSync();
    if (gradle.contains('kannada_helper:minSdk')) {
      stdout.writeln('$path: minSdk already patched.');
      return;
    }
    final kts = path.endsWith('.kts');
    final line = RegExp(r'^(\s*)minSdk(Version)?\s*=?\s*(.+)$', multiLine: true);
    final match = line.firstMatch(gradle);
    if (match == null) {
      stderr.writeln('$path: no minSdk line found. Set it to $_minSdk by hand.');
      return;
    }
    final indent = match.group(1)!;
    final current = match.group(3)!.trim();
    final replacement = kts
        ? '${indent}minSdk = maxOf($_minSdk, $current) // kannada_helper:minSdk'
        : '${indent}minSdkVersion Math.max($_minSdk, $current) // kannada_helper:minSdk';
    gradle = gradle.replaceRange(match.start, match.end, replacement);
    file.writeAsStringSync(gradle);
    stdout.writeln('Patched $path: minSdk is now at least $_minSdk');
    return;
  }
  stderr.writeln('No android/app/build.gradle(.kts) found.');
}

void _patchManifest() {
  final file = File(_manifestPath);
  if (!file.existsSync()) {
    stderr.writeln('Not found: $_manifestPath\n'
        'Run `flutter create --platforms=android --project-name kannada_helper .` first.');
    exit(1);
  }

  var xml = file.readAsStringSync();
  final added = <String>[];

  for (final permission in _permissions) {
    if (xml.contains('"$permission"')) continue;
    final open = xml.indexOf('<manifest');
    final end = xml.indexOf('>', open);
    if (open < 0 || end < 0) {
      stderr.writeln('Could not find the <manifest> tag. Patch it by hand.');
      exit(1);
    }
    xml = '${xml.substring(0, end + 1)}\n'
        '    <uses-permission android:name="$permission"/>'
        '${xml.substring(end + 1)}';
    added.add(permission);
  }

  for (final action in _queryActions) {
    if (xml.contains('"$action"')) continue;
    final intent = '        <intent>\n'
        '            <action android:name="$action"/>\n'
        '        </intent>';
    if (xml.contains('<queries>')) {
      xml = xml.replaceFirst('<queries>', '<queries>\n$intent');
    } else {
      xml = xml.replaceFirst(
          '</manifest>', '    <queries>\n$intent\n    </queries>\n</manifest>');
    }
    added.add('query $action');
  }

  if (added.isEmpty) {
    stdout.writeln('Already patched, nothing to do.');
  } else {
    file.writeAsStringSync(xml);
    stdout.writeln('Patched $_manifestPath:\n  + ${added.join('\n  + ')}');
  }
}
