import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../models/question.dart';
import '../services/question_service.dart';
import '../services/voice_answer_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.storagePath,
    this.questionInterval = const Duration(seconds: 10),
  });

  final String storagePath;
  final Duration questionInterval;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  final QuestionService _questionService = QuestionService();

  VideoPlayerController? _controller;
  Timer? _questionTimer;

  bool _isLoadingVideo = true;
  String? _videoError;

  bool _isFetchingQuestion = false;
  String? _questionError;
  Question? _question;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _questionTimer?.cancel();
    _controller?.removeListener(_handleControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    VideoPlayerController? controller;
    try {
      controller = await _createControllerWithFallback(widget.storagePath);
      controller.addListener(_handleControllerUpdate);

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _isLoadingVideo = false;
        _videoError = null;
      });

      try {
        await controller.play();
      } catch (e) {
        // If play fails but initialize succeeded, keep the UI visible.
        debugPrint('Video play failed: $e');
      }

      _scheduleNextQuestion();
    } catch (e) {
      debugPrint('Video init failed: $e');
      try {
        await controller?.dispose();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _videoError = 'Unable to load video URL.\n$e';
        _isLoadingVideo = false;
      });
    }
  }

  Future<VideoPlayerController> _createControllerWithFallback(
    String url,
  ) async {
    final uri = Uri.parse(url);

    // iOS AVFoundation is frequently flaky with Firebase download URLs.
    // Prefer downloading to a temp file first for stability.
    if (Platform.isIOS) {
      try {
        return await _downloadAndCreateFileController(uri);
      } catch (e) {
        debugPrint('iOS download-first failed, falling back to stream: $e');
      }
    }

    // Primary: stream from network.
    final networkController = VideoPlayerController.networkUrl(uri);
    try {
      await networkController.initialize();
      return networkController;
    } catch (e) {
      debugPrint('Network video init failed, falling back to download: $e');
      try {
        await networkController.dispose();
      } catch (_) {}
    }

    // Fallback: download to a local temp file and play from disk.
    return _downloadAndCreateFileController(uri);
  }

  Future<VideoPlayerController> _downloadAndCreateFileController(
    Uri uri,
  ) async {
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Video download failed (HTTP ${response.statusCode}).');
    }

    final fileName = 'speechbuddy_cached_video.mp4';
    final file = File('${Directory.systemTemp.path}/$fileName');
    await file.writeAsBytes(response.bodyBytes, flush: true);

    final fileController = VideoPlayerController.file(file);
    await fileController.initialize();
    return fileController;
  }

  void _handleControllerUpdate() {
    final controller = _controller;
    if (controller == null) return;
    if (!controller.value.isInitialized) return;

    final value = controller.value;

    final ended =
        value.duration != Duration.zero && value.position >= value.duration;
    if (ended) {
      _questionTimer?.cancel();
      return;
    }
  }

  void _scheduleNextQuestion() {
    _questionTimer?.cancel();
    _questionTimer = Timer(widget.questionInterval, () {
      _triggerQuestion(pauseVideo: true);
    });
  }

  Future<void> _triggerQuestion({required bool pauseVideo}) async {
    if (_isFetchingQuestion) return;

    // Always cancel the countdown while we're paused/asking.
    _questionTimer?.cancel();

    if (pauseVideo) {
      _controller?.pause();
    }

    if (!mounted) return;
    setState(() {
      _isFetchingQuestion = true;
      _questionError = null;
      _question = null;
    });

    try {
      final q = await _questionService.fetchQuestion();
      if (!mounted) return;
      setState(() {
        _question = q;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _questionError = 'Unable to load question.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingQuestion = false;
        });
      }
    }
  }

  void _selectAnswer(String answer) {
    setState(() {
      _question = null;
      _questionError = null;
    });
    _resumePlayback();
  }

  void _resumePlayback() {
    _controller?.play();
    _scheduleNextQuestion();
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isInitialized = controller?.value.isInitialized ?? false;
    final isPlaying = controller?.value.isPlaying ?? true;

    // Spec: when video is paused, show split UI.
    final showSplit = isInitialized && !isPlaying;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _videoError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _videoError!,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: _isLoadingVideo
                          ? const CircularProgressIndicator(color: Colors.white)
                          : _buildPlayer(),
                    ),
                  ),
                  if (!showSplit && isInitialized) _buildControls(),
                  if (showSplit)
                    const Divider(height: 1, color: Colors.white12),
                  if (showSplit)
                    Expanded(
                      child: _QuestionPanel(
                        isLoading: _isFetchingQuestion,
                        error: _questionError,
                        question: _question,
                        onSelect: _selectAnswer,
                        onResume: _resumePlayback,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildPlayer() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(controller),
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            colors: const VideoProgressColors(playedColor: Colors.indigo),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final controller = _controller!;
    final isPlaying = controller.value.isPlaying;

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _format(controller.value.position),
            style: const TextStyle(color: Colors.white70),
          ),
          IconButton(
            onPressed: _togglePlayback,
            icon: Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
            ),
            color: Colors.white,
            iconSize: 40,
          ),
          Text(
            _format(controller.value.duration),
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}

class _QuestionPanel extends StatelessWidget {
  const _QuestionPanel({
    required this.isLoading,
    required this.error,
    required this.question,
    required this.onSelect,
    required this.onResume,
  });

  final bool isLoading;
  final String? error;
  final Question? question;
  final void Function(String answer) onSelect;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _buildBody(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isLoading && question == null && error == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Loading question…',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          TextButton(onPressed: onResume, child: const Text('Resume video')),
        ],
      );
    }

    if (error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Question',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(error!, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          TextButton(onPressed: onResume, child: const Text('Resume video')),
        ],
      );
    }

    final q = question;
    if (q == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Paused',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onResume, child: const Text('Resume video')),
        ],
      );
    }

    return _QuestionContent(
      question: q,
      onSelect: onSelect,
      onResume: onResume,
    );
  }
}

class _QuestionContent extends StatefulWidget {
  const _QuestionContent({
    required this.question,
    required this.onSelect,
    required this.onResume,
  });

  final Question question;
  final void Function(String answer) onSelect;
  final VoidCallback onResume;

  @override
  State<_QuestionContent> createState() => _QuestionContentState();
}

class _QuestionContentState extends State<_QuestionContent> {
  final VoiceAnswerService _voice = VoiceAnswerService();

  bool _isRecording = false;
  bool _isUploading = false;
  String? _voiceError;

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }

  Future<void> _toggleVoiceAnswer() async {
    if (_isUploading) return;
    setState(() {
      _voiceError = null;
    });

    try {
      if (!_isRecording) {
        await _voice.startRecording(questionId: widget.question.id);
        if (!mounted) return;
        setState(() {
          _isRecording = true;
        });
        return;
      }

      setState(() {
        _isUploading = true;
      });

      final url = await _voice.stopAndUpload(questionId: widget.question.id);
      if (!mounted) return;
      setState(() {
        _isRecording = false;
      });

      // Treat voice as an answer. Store URL in the answer string.
      widget.onSelect('voice:$url');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _voiceError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            q.prompt,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isUploading ? null : _toggleVoiceAnswer,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _isUploading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isRecording ? 'Stop recording' : 'Speak to answer'),
          ),
          if (_voiceError != null) ...[
            const SizedBox(height: 8),
            Text(_voiceError!, style: const TextStyle(color: Colors.black54)),
          ],
          const SizedBox(height: 16),
          ...q.options.map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton(
                onPressed: _isRecording || _isUploading
                    ? null
                    : () => widget.onSelect(option),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(option),
              ),
            ),
          ),
          TextButton(
            onPressed: _isRecording || _isUploading
                ? null
                : () => widget.onSelect('skipped'),
            child: const Text('Skip and continue'),
          ),
          TextButton(
            onPressed: _isRecording || _isUploading ? null : widget.onResume,
            child: const Text('Resume video'),
          ),
        ],
      ),
    );
  }
}
