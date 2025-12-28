import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../firebase_options.dart';

class VoiceAnswerService {
  final AudioRecorder _recorder = AudioRecorder();

  static const Duration _uploadTimeout = Duration(seconds: 45);
  static const int _minBytes = 2048;

  String _fallbackStorageUrl(String objectPath) {
    final bucket = DefaultFirebaseOptions.currentPlatform.storageBucket;
    return 'gs://$bucket/$objectPath';
  }

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<bool> get isRecording => _recorder.isRecording();

  Future<String> startRecording({required String questionId}) async {
    final ok = await _recorder.hasPermission();
    if (!ok) {
      throw Exception('Microphone permission not granted.');
    }

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/voice_${questionId}_$ts.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    final started = await _recorder.isRecording();
    if (!started) {
      throw Exception('Recorder did not start.');
    }

    return path;
  }

  Future<String?> stopRecording() => _recorder.stop();

  Future<String> stopAndUpload({required String questionId}) async {
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e) {
        throw Exception(
          'Firebase is not initialized. Make sure iOS Firebase is configured (GoogleService-Info.plist is in ios/Runner and added to the Runner target). Original error: $e',
        );
      }
    }

    // Ensure we have an authenticated user for Storage rules.
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
    } catch (e) {
      throw Exception('Anonymous sign-in failed: $e');
    }

    final filePath = await _recorder.stop();
    if (filePath == null || filePath.isEmpty) {
      throw Exception('No recording was captured.');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Recorded file not found.');
    }

    // Give the OS a moment to finalize the container.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final bytes = await file.length();
    if (bytes < _minBytes) {
      throw Exception(
        'Recording was too short or empty ($bytes bytes). Try speaking for a bit longer.',
      );
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final objectPath = 'speechbuddymobileappvoiceanswers/$questionId/$ts.m4a';

    // Use the default Storage instance (it reads the bucket from FirebaseOptions).
    final ref = FirebaseStorage.instance.ref().child(objectPath);
    try {
      final data = await file.readAsBytes();
      if (data.length < _minBytes) {
        throw Exception(
          'Recording was too short or empty (${data.length} bytes). Try speaking for a bit longer.',
        );
      }

      final task = await ref
          .putData(data, SettableMetadata(contentType: 'audio/mp4'))
          .timeout(_uploadTimeout);

      if (task.state != TaskState.success) {
        throw Exception('Upload failed: ${task.state}');
      }

      // Download URL fetch can fail due to Storage rules (read/list blocked) even if the upload succeeded.
      try {
        return await ref.getDownloadURL().timeout(_uploadTimeout);
      } catch (e) {
        // ignore: avoid_print
        print('getDownloadURL failed after upload success: $e');
        return _fallbackStorageUrl(objectPath);
      }
    } on FirebaseException catch (e, st) {
      // Helpful for cases like: "Firebase Storage error (unknown): cannot parse response".
      // The underlying HTTP response is not always surfaced, but code/message/plugin usually are.
      // Keep this as a debug log only.
      // ignore: avoid_print
      print(
        'FirebaseException(plugin=${e.plugin}, code=${e.code}): ${e.message}\n$st',
      );

      final message = (e.message ?? '').trim();
      final codeLower = e.code.toLowerCase();
      final messageLower = message.toLowerCase();

      if (codeLower == 'unknown' &&
          messageLower.contains('cannot parse response')) {
        // We've observed cases where the native SDK throws here but the object still lands in Storage.
        // To keep the UI moving, return a stable gs:// reference as a best-effort success signal.
        return _fallbackStorageUrl(objectPath);
      }

      if (codeLower.contains('unauthorized') ||
          codeLower.contains('permission-denied')) {
        throw Exception(
          'Upload blocked by Firebase Storage rules (unauthorized).\n'
          'Fix options:\n'
          '1) Update Firebase Storage rules to allow writes to the folder speechbuddymobileappvoiceanswers/, OR\n'
          '2) Enable an auth method (e.g., Anonymous Auth) and require request.auth != null in rules.\n'
          'Original: ${e.message ?? e.code}',
        );
      }
      throw Exception(
        'Firebase Storage error (${e.code}): '
        '${message.isEmpty ? 'Unknown error.' : message}',
      );
    } on PlatformException catch (e, st) {
      // ignore: avoid_print
      print(
        'PlatformException(code=${e.code}, message=${e.message}, details=${e.details})\n$st',
      );
      throw Exception(
        'Firebase Storage platform error (${e.code}): ${e.message ?? 'Unknown error.'}',
      );
    } on TimeoutException {
      throw Exception(
        'Upload timed out. Check network connection and try again.',
      );
    }
  }

  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
