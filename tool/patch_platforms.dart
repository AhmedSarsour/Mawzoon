// Adds what flutter_local_notifications 22.3.1 needs to the generated
// android/ and ios/ folders. Run once after `flutter create .`:
//
//   dart run tool/patch_platforms.dart
//
// Safe to run twice (idempotent). Fails loudly if a template has moved on.
import 'dart:io';

/// A generated file no longer looks like the template this was written for.
class PatchFailure implements Exception {
  PatchFailure(this.file, this.anchor);
  final String file;
  final String anchor;
  @override
  String toString() => '$file: could not find "$anchor". Patch it by hand '
      '(see the flutter_local_notifications README) and update this script.';
}

const String _bootPermission =
    '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>';

const String _receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
''';

String _insertBefore(String source, String anchor, String text, String file) {
  final int at = source.indexOf(anchor);
  if (at < 0) throw PatchFailure(file, anchor);
  return source.replaceRange(at, at, text);
}

String _insertAfter(String source, String anchor, String text, String file) {
  final int at = source.indexOf(anchor);
  if (at < 0) throw PatchFailure(file, anchor);
  return source.replaceRange(at + anchor.length, at + anchor.length, text);
}

/// Boot permission + the two scheduling receivers (reschedule after reboot).
String patchManifest(String s) {
  const String f = 'AndroidManifest.xml';
  if (!s.contains('RECEIVE_BOOT_COMPLETED')) {
    s = _insertBefore(s, '<application', '$_bootPermission\n    ', f);
  }
  if (!s.contains('ScheduledNotificationReceiver')) {
    s = _insertBefore(s, '    </application>', _receivers, f);
  }
  return s;
}

/// Core-library desugaring, which the plugin's scheduling code needs.
String patchGradleKts(String s) {
  const String f = 'app/build.gradle.kts';
  if (!s.contains('isCoreLibraryDesugaringEnabled')) {
    s = _insertAfter(
      s,
      'compileOptions {\n',
      '        isCoreLibraryDesugaringEnabled = true\n',
      f,
    );
  }
  if (!s.contains('desugar_jdk_libs')) {
    s = _insertBefore(
      s,
      'flutter {\n',
      'dependencies {\n'
          '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
          '}\n\n',
      f,
    );
  }
  return s;
}

/// Makes the app the notification-centre delegate, so taps reach Dart.
String patchAppDelegate(String s) {
  const String f = 'AppDelegate.swift';
  if (!s.contains('import UserNotifications')) {
    s = _insertAfter(s, 'import UIKit\n', 'import UserNotifications\n', f);
  }
  if (!s.contains('UNUserNotificationCenter.current().delegate')) {
    s = _insertBefore(
      s,
      '    return super.application(application, didFinishLaunchingWithOptions',
      '    UNUserNotificationCenter.current().delegate =\n'
          '      self as? UNUserNotificationCenterDelegate\n',
      f,
    );
  }
  return s;
}

void main(List<String> args) {
  final String root = args.isEmpty ? '.' : args.first;
  final Map<String, String Function(String)> patches =
      <String, String Function(String)>{
    '$root/android/app/src/main/AndroidManifest.xml': patchManifest,
    '$root/android/app/build.gradle.kts': patchGradleKts,
    '$root/ios/Runner/AppDelegate.swift': patchAppDelegate,
  };
  bool failed = false;
  patches.forEach((String path, String Function(String) patch) {
    final File file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('skip     $path (not generated)');
      return;
    }
    try {
      final String before = file.readAsStringSync();
      final String after = patch(before);
      if (after == before) {
        stdout.writeln('ok       $path (already patched)');
      } else {
        file.writeAsStringSync(after);
        stdout.writeln('patched  $path');
      }
    } on PatchFailure catch (e) {
      failed = true;
      stderr.writeln('FAILED   $e');
    }
  });
  if (failed) exitCode = 1;
}
