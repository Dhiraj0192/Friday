import 'package:flutter/services.dart';

/// Direct Phone Storage File CRUD Service:
/// Create, write, read, edit, list, and delete files on device storage (Downloads, Documents, etc.)
/// without navigating through phone settings or file manager apps.
class PhoneStorageService {
  PhoneStorageService._();
  static final PhoneStorageService instance = PhoneStorageService._();

  static const MethodChannel _channel = MethodChannel('com.privateagent/accessibility');

  /// Why [folder] / [fileName] may not be used, or null when they are safe:
  /// one plain name each, never a path, never `..`, never the apps' private
  /// `Android` folder. MainActivity checks the same again on the resolved path.
  static String? pathProblem(String folder, [String? fileName]) {
    final f = folder.trim();
    if (!_isPlainName(f)) return 'Folder "$folder" must be a single folder name.';
    if (f.toLowerCase() == 'android') return 'The Android folder holds app data; Friday stays out of it.';
    if (fileName != null && !_isPlainName(fileName.trim())) {
      return 'File name "$fileName" must be a plain name, not a path.';
    }
    return null;
  }

  static bool _isPlainName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      !name.contains('/') &&
      !name.contains('\\') &&
      !name.contains('\x00');

  static Map<String, dynamic> _refused(String why) => {'success': false, 'message': why};

  Future<Map<String, dynamic>> createFile({
    required String fileName,
    required String content,
    String folder = 'Download',
    bool append = false,
  }) async {
    final problem = pathProblem(folder, fileName);
    if (problem != null) return _refused(problem);
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('manageStorageFile', {
        'action': append ? 'edit' : 'create',
        'folder': folder,
        'fileName': fileName,
        'content': content,
        'append': append,
      });
      return res ?? {'success': false, 'message': 'Storage invocation returned null.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> readFile({
    required String fileName,
    String folder = 'Download',
  }) async {
    final problem = pathProblem(folder, fileName);
    if (problem != null) return _refused(problem);
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('manageStorageFile', {
        'action': 'read',
        'folder': folder,
        'fileName': fileName,
      });
      return res ?? {'success': false, 'message': 'File not accessible.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> listFiles({String folder = 'Download'}) async {
    final problem = pathProblem(folder);
    if (problem != null) return {..._refused(problem), 'files': []};
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('manageStorageFile', {
        'action': 'list',
        'folder': folder,
      });
      return res ?? {'success': false, 'files': []};
    } catch (e) {
      return {'success': false, 'files': [], 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> deleteFile({
    required String fileName,
    String folder = 'Download',
  }) async {
    final problem = pathProblem(folder, fileName);
    if (problem != null) return _refused(problem);
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('manageStorageFile', {
        'action': 'delete',
        'folder': folder,
        'fileName': fileName,
      });
      return res ?? {'success': false, 'message': 'Delete failed.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}

