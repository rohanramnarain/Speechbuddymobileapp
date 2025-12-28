import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured for Firebase.');
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('FirebaseOptions are only configured for iOS.');
    }
  }

  // Generated from ios/Runner/GoogleService-Info.plist
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBg7WbvvtTZ8ffdotyOBLnJBFzTXWRTSpQ',
    appId: '1:19215908537:ios:7451e7b56c11f0af706568',
    messagingSenderId: '19215908537',
    projectId: 'speechbuddy-30390',
    storageBucket: 'speechbuddy-30390.appspot.com',
    iosBundleId: 'com.speechbuddy.speechbuddymobileapp',
    databaseURL: 'https://speechbuddy-30390-default-rtdb.firebaseio.com',
  );
}
