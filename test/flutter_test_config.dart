import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Every test starts with an in-memory secure storage. Without it, a real
/// platform call inside testWidgets' fake clock never returns and the test hangs.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FlutterSecureStorage.setMockInitialValues({});
  await testMain();
}
