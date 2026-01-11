import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'screens/video_player_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Ensure Storage writes have an authenticated user.
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
    } catch (e) {
      debugPrint('Anonymous sign-in failed: $e');
    }
  } catch (e) {
    // App can still run video/questions; voice upload will fail until Firebase is configured.
    debugPrint('Firebase.initializeApp failed: $e');
  }
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpeechBuddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const VideoPlayerScreen(
        storagePath:
            'https://firebasestorage.googleapis.com/v0/b/speechbuddy-30390.appspot.com/o/2ECFABB1-98C9-4440-900F-A7130CDE9285.mov?alt=media&token=2497d900-59e9-44e2-a88f-7d0f160fee49',
        questionInterval: Duration(milliseconds: 31550),
      ),
    );
  }
}
