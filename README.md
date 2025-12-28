# SpeechBuddy mobile (iOS)

Flutter app that streams an MP4 from Firebase Storage and automatically pauses every 2 minutes to present questions. Questions come from a Supabase function (configurable); a local fallback prompt is shown if the API is not ready yet.

## Prerequisites
- Flutter 3.32.x+ with Xcode tooling and an iOS simulator or device.
- Firebase project with Storage enabled; anonymous access is not required if your rules allow read for the target file.

## Setup
1) Add `GoogleService-Info.plist` to `ios/Runner/` and ensure it is included in the Xcode target.
2) Set the Storage path for your MP4 in [lib/main.dart](lib/main.dart#L17-L24). You can use either a storage path (`videos/sample.mp4`) or a full download URL (as provided by Firebase Storage).
3) Update the Supabase function URL in [lib/services/question_service.dart](lib/services/question_service.dart#L8) (`_endpoint`).
4) Fetch dependencies: `flutter pub get`.

## Running (iOS only)
- Simulator: `flutter run -d ios`.
- Physical device: ensure a valid signing profile, then `flutter run -d <device-id>`.

## Behavior
- Streams the MP4 over HTTPS from Firebase Storage.
- Pauses every 2 minutes (configurable via `questionInterval` in [lib/main.dart](lib/main.dart#L20-L24)).
- Shows a modal question overlay; resume playback after selecting an option or skipping.

## Next steps
- Hook up your Supabase function response shape (adjust parsing in `QuestionService`).
- Swap `storagePath` to the real Storage location and update Firebase Storage rules accordingly.
