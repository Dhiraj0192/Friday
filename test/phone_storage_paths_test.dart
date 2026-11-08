import 'package:flutter_test/flutter_test.dart';

import 'package:private_agent/services/phone_storage_service.dart';

void main() {
  group('PhoneStorageService.pathProblem', () {
    test('plain folder and file names pass', () {
      expect(PhoneStorageService.pathProblem('Download', 'notes.txt'), isNull);
      expect(PhoneStorageService.pathProblem('Documents', 'Shopping list 2026.md'), isNull);
      expect(PhoneStorageService.pathProblem('Friday Notes'), isNull);
    });

    test('a file name that climbs out of the folder is refused', () {
      for (final name in ['../secret.txt', '..', 'a/b.txt', r'a\b.txt', '/etc/hosts', 'x\x00.txt', '']) {
        expect(PhoneStorageService.pathProblem('Download', name), isNotNull, reason: name);
      }
    });

    test('a folder that is a path, or the apps\' Android folder, is refused', () {
      for (final folder in ['../..', 'Download/../Android', 'Android', 'android', '/data', '']) {
        expect(PhoneStorageService.pathProblem(folder, 'a.txt'), isNotNull, reason: folder);
      }
    });

    test('a refused path never reaches the phone', () async {
      // No platform channel is mocked here: an unsafe call must return before it.
      final res = await PhoneStorageService.instance.deleteFile(fileName: '../../important');
      expect(res['success'], isFalse);
      expect(res['message'], contains('plain name'));
    });
  });
}
