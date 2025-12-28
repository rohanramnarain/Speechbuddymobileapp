import 'package:firebase_storage/firebase_storage.dart';

class FirebaseVideoService {
  Future<String> getVideoUrl(String storagePath) async {
    if (storagePath.startsWith('http')) {
      return storagePath;
    }

    final ref = FirebaseStorage.instance.ref(storagePath);
    return ref.getDownloadURL();
  }
}
