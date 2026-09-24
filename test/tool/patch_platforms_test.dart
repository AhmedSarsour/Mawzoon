import 'package:flutter_test/flutter_test.dart';

import '../../tool/patch_platforms.dart';

// Trimmed from what `flutter create` (Flutter 3.41) generates.
const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="mawzoon">
        <activity android:name=".MainActivity" />
    </application>
</manifest>
''';

const String _gradle = '''
android {
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
    }
}

flutter {
    source = "../.."
}
''';

const String _appDelegate = '''
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
''';

void main() {
  final Map<String, (String Function(String), String, List<String>)> cases =
      <String, (String Function(String), String, List<String>)>{
    'manifest': (
      patchManifest,
      _manifest,
      <String>['RECEIVE_BOOT_COMPLETED', 'ScheduledNotificationBootReceiver'],
    ),
    'gradle': (
      patchGradleKts,
      _gradle,
      <String>['isCoreLibraryDesugaringEnabled = true', 'desugar_jdk_libs'],
    ),
    'app delegate': (
      patchAppDelegate,
      _appDelegate,
      <String>['import UserNotifications', 'UNUserNotificationCenter'],
    ),
  };

  cases.forEach((String name, (String Function(String), String, List<String>) c) {
    final (String Function(String) patch, String template, List<String> adds) = c;

    test('$name: adds what the plugin needs', () {
      final String out = patch(template);
      for (final String a in adds) {
        expect(out, contains(a));
      }
    });

    test('$name: running twice changes nothing', () {
      final String once = patch(template);
      expect(patch(once), once);
    });

    test('$name: a moved-on template fails loudly', () {
      expect(() => patch('nothing familiar'), throwsA(isA<PatchFailure>()));
    });
  });

  test('delegate is set before the app finishes launching', () {
    final String out = patchAppDelegate(_appDelegate);
    expect(
      out.indexOf('UNUserNotificationCenter'),
      lessThan(out.indexOf('return super.application')),
    );
  });
}
