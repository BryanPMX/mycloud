import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Manrope'],
        await rootBundle.loadString('assets/fonts/OFL-Manrope.txt'));
    yield LicenseEntryWithLineBreaks(['DM Serif Display'],
        await rootBundle.loadString('assets/fonts/OFL-DMSerifDisplay.txt'));
  });
  runApp(App(config: AppConfig.fromEnvironment()));
}
