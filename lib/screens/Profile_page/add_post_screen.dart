// lib/screens/Profile_page/add_post_screen.dart
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/resources/supabase_posts_methods.dart';
import 'package:Ratedly/utils/colors.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/models/user.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_player/video_player.dart';
// replaced video_editor with video_trimmer:
import 'package:video_trimmer/video_trimmer.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

class AddPostScreen extends StatefulWidget {
  final VoidCallback? onPostUploaded;
  const AddPostScreen({Key? key, this.onPostUploaded}) : super(key: key);

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  Uint8List? _file; // bytes used for upload (image or trimmed video)
  bool isLoading = false;
  bool _isVideo = false;
  final TextEditingController _descriptionController = TextEditingController();
  final double _maxFileSize = 2.5 * 1024 * 1024;
  final double _maxVideoSize = 50 * 1024 * 1024;

  // Video preview and trimming variables
  VideoPlayerController? _previewVideoController;
  final Trimmer _trimmer = Trimmer(); // video_trimmer Trimmer
  bool _isPreviewingVideo = false;
  bool _isTrimmingVideo = false;
  double _selectedStart = 0.0;
  double _selectedEnd = 30.0;
  double _videoDuration = 0.0;

  // store original picked path (reliable input for trimming)
  String? _originalVideoPath;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _previewVideoController?.dispose();
    // Trimmer does not require explicit dispose in pub docs; avoid calling unknown methods.
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectMedia(BuildContext parentContext) async {
    return showDialog<void>(
      context: parentContext,
      builder: (BuildContext context) {
        return SimpleDialog(
          backgroundColor: mobileBackgroundColor,
          title: Text(
            'Create a Post',
            style: TextStyle(color: primaryColor),
          ),
          children: <Widget>[
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text('Choose Image from Gallery',
                  style: TextStyle(color: primaryColor)),
              onPressed: () async {
                Navigator.pop(context);
                await _pickAndProcessImage(ImageSource.gallery);
              },
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text('Choose Video from Gallery',
                  style: TextStyle(color: primaryColor)),
              onPressed: () async {
                Navigator.pop(context);
                await _pickVideoFromGallery();
              },
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text("Cancel", style: TextStyle(color: primaryColor)),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndProcessImage(ImageSource source) async {
    try {
      setState(() {
        _isVideo = false;
        isLoading = true;
        _isPreviewingVideo = false;
        _previewVideoController?.dispose();
      });

      final pickedFile = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        Uint8List? compressedImage =
            await FlutterImageCompress.compressWithFile(
          pickedFile.path,
          minWidth: 800,
          minHeight: 800,
          quality: 80,
          format: CompressFormat.jpeg,
        );

        if (compressedImage != null && compressedImage.length > _maxFileSize) {
          compressedImage = await _compressUntilUnderLimit(compressedImage);
        }

        if (compressedImage != null) {
          setState(() {
            _file = compressedImage;
            isLoading = false;
          });
        } else {
          final Uint8List fallback = await pickedFile.readAsBytes();
          setState(() {
            _file = fallback;
            isLoading = false;
          });
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (context.mounted) {
        showSnackBar(
            context, 'Please try again or contact us at ratedly9@gmail.com');
      }
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      setState(() {
        _isVideo = true;
        isLoading = true;
        _isPreviewingVideo = false;
      });

      final pickedFile = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (pickedFile != null) {
        final File videoFile = File(pickedFile.path);

        // store original path for trimming
        _originalVideoPath = pickedFile.path;

        // Check video size
        if (await videoFile.length() > _maxVideoSize) {
          if (context.mounted) {
            showSnackBar(context,
                'Video too large (max 50MB). Please choose a shorter video.');
          }
          setState(() => isLoading = false);
          return;
        }

        // Initialize video preview and load into trimmer
        await _initializeVideoPreview(videoFile);
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (context.mounted) {
        showSnackBar(context, 'Failed to pick video: $e');
      }
    }
  }

  Future<void> _initializeVideoPreview(File videoFile) async {
    try {
      // initialize preview player
      _previewVideoController = VideoPlayerController.file(videoFile)
        ..addListener(() {
          if (mounted) {
            setState(() {});
          }
        });

      await _previewVideoController!.initialize();

      // Get video duration in seconds as double
      final duration = _previewVideoController!.value.duration;
      _videoDuration = duration.inSeconds.toDouble();

      // Set trimming bounds (first 30 seconds or full video if shorter)
      _selectedStart = 0.0;
      _selectedEnd = _videoDuration > 30.0 ? 30.0 : _videoDuration;

      // load video into Trimmer for trimming
      try {
        await _trimmer.loadVideo(videoFile: videoFile);
      } catch (_) {
        // ignore load errors (we still can try to trim using original path)
      }

      setState(() {
        _isPreviewingVideo = true;
        isLoading = false;
        _file = null; // Clear file until trimming is done
      });

      // Auto-play preview
      await _previewVideoController!.play();
    } catch (e) {
      setState(() => isLoading = false);
      if (context.mounted) {
        showSnackBar(context, 'Failed to load video: $e');
      }
    }
  }

  /// Trim using the video_trimmer package (Trimmer.saveTrimmedVideo)
  /// Trim using the video_trimmer package (Trimmer.saveTrimmedVideo)
  Future<void> _trimAndSaveVideo() async {
    if (_originalVideoPath == null) {
      if (context.mounted) showSnackBar(context, 'No video available to trim.');
      return;
    }

    setState(() {
      _isTrimmingVideo = true;
    });

    try {
      final double startSec = _selectedStart;
      final double durationSec = (_selectedEnd - _selectedStart);
      final double endSec = startSec + durationSec;

      String? producedPath;

      final completer = Completer<String?>();
      try {
        await _trimmer.saveTrimmedVideo(
          startValue: startSec,
          endValue: endSec,
          onSave: (String? outputPath) {
            if (!completer.isCompleted) completer.complete(outputPath);
          },
        );
      } catch (e) {
        if (!completer.isCompleted) completer.complete(null);
      }

      // wait for callback (timeout to avoid hanging)
      try {
        producedPath = await completer.future.timeout(
          const Duration(seconds: 60),
          onTimeout: () => null,
        );
      } catch (_) {
        producedPath = null;
      }

      // If trimmer didn't return a path, fallback to copying original (not trimmed)
      bool usedFallback = false;
      if (producedPath == null || producedPath.isEmpty) {
        final Directory appDocDir = await getApplicationDocumentsDirectory();
        final String outputPath =
            '${appDocDir.path}/trimmed_video_fallback_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final File inFile = File(_originalVideoPath!);
        await inFile.copy(outputPath);
        producedPath = outputPath;
        usedFallback = true;
      }

      if (producedPath == null || producedPath.isEmpty) {
        throw Exception('Trimming failed (no output produced).');
      }

      final File trimmedFile = File(producedPath);
      if (!await trimmedFile.exists()) {
        throw Exception('Trimmed file not found at $producedPath');
      }

      // Debug info: file size and we'll check duration after init
      debugPrint('Trimmed file path: $producedPath');
      final int fileLen = await trimmedFile.length();
      debugPrint('Trimmed file size: $fileLen bytes');

      // read bytes for upload (you may instead upload the File to avoid memory pressure)
      final Uint8List videoBytes = await trimmedFile.readAsBytes();

      // initialize preview controller to play the trimmed file
      try {
        await _previewVideoController?.pause();
        await _previewVideoController?.dispose();
      } catch (_) {}

      _previewVideoController = VideoPlayerController.file(trimmedFile)
        ..addListener(() {
          if (mounted) setState(() {});
        });

      await _previewVideoController!.initialize();

      // Extra debug: print duration
      final dur = _previewVideoController!.value.duration;
      debugPrint('Trimmed file duration: ${dur.inSeconds}s');

      // Important: start playback of trimmed file (this fixes the "picture" issue)
      _previewVideoController!.setLooping(true);
      _previewVideoController!.setVolume(1.0);
      await _previewVideoController!.play();

      if (mounted) {
        setState(() {
          _file = videoBytes; // used for upload
          _isTrimmingVideo = false;
          _isPreviewingVideo =
              false; // go back to main view where trimmed preview plays
          _isVideo = true;
          _originalVideoPath = producedPath; // now points to trimmed file
        });
      }

      if (context.mounted) {
        if (usedFallback) {
          showSnackBar(context,
              'Trimming not supported on this device — using original clip (fallback).');
        } else {
          showSnackBar(context, 'Video trimmed successfully!');
        }
      }
    } catch (e) {
      setState(() => _isTrimmingVideo = false);
      debugPrint('Trim error: $e');
      if (context.mounted) {
        showSnackBar(context,
            'Failed to trim video: $e\n(Ensure video_trimmer is configured and supports your platform.)');
      }
    }
  }

  Widget _buildVideoTrimmer() {
    // If preview controller isn't initialized yet, show loader
    final bool previewReady =
        _previewVideoController?.value.isInitialized ?? false;

    return Column(
      children: [
        // Video preview
        AspectRatio(
          aspectRatio: previewReady
              ? _previewVideoController!.value.aspectRatio
              : 16 / 9,
          child: Stack(
            children: [
              if (previewReady)
                VideoPlayer(_previewVideoController!)
              else
                Center(child: CircularProgressIndicator(color: primaryColor)),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: IconButton(
                    icon: Icon(
                      _previewVideoController?.value.isPlaying ?? false
                          ? Icons.pause
                          : Icons.play_arrow,
                      size: 50,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    onPressed: () {
                      if (_previewVideoController?.value.isPlaying ?? false) {
                        _previewVideoController?.pause();
                      } else {
                        _previewVideoController?.play();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Duration info
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Video will be trimmed to 30 seconds maximum',
            style: TextStyle(color: primaryColor.withOpacity(0.7)),
          ),
        ),

        // Trim slider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select 30-second segment:',
                style:
                    TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildTrimSlider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(Duration(seconds: _selectedStart.toInt())),
                    style: TextStyle(color: primaryColor),
                  ),
                  Text(
                    _formatDuration(Duration(seconds: _selectedEnd.toInt())),
                    style: TextStyle(color: primaryColor),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Trim button
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isTrimmingVideo
              ? CircularProgressIndicator(color: primaryColor)
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blueColor,
                    foregroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                  ),
                  onPressed: _trimAndSaveVideo,
                  child: Text('Trim Video to Selected Segment'),
                ),
        ),

        // Cancel button
        TextButton(
          onPressed: () {
            setState(() {
              _isPreviewingVideo = false;
              try {
                _previewVideoController?.dispose();
              } catch (_) {}
            });
          },
          child: Text('Choose Different Video',
              style: TextStyle(color: primaryColor)),
        ),
      ],
    );
  }

  Widget _buildTrimSlider() {
    // Ensure maximum 30-second selection
    if (_selectedEnd - _selectedStart > 30) {
      _selectedEnd = _selectedStart + 30;
    }

    final double maxValue = _videoDuration > 0 ? _videoDuration : 1;
    final int divisionsCandidate =
        _videoDuration.toInt() > 0 ? _videoDuration.toInt() : 1;
    final int divisions = (divisionsCandidate.clamp(1, 60)).toInt();

    return Column(
      children: [
        RangeSlider(
          values: RangeValues(_selectedStart, _selectedEnd),
          min: 0,
          max: maxValue,
          divisions: divisions,
          labels: RangeLabels(
            _formatDuration(Duration(seconds: _selectedStart.toInt())),
            _formatDuration(Duration(seconds: _selectedEnd.toInt())),
          ),
          onChanged: (values) {
            final newStart = values.start;
            final newEnd = values.end;

            // Ensure maximum 30-second duration
            if ((newEnd - newStart) <= 30) {
              setState(() {
                _selectedStart = newStart;
                _selectedEnd = newEnd;
              });

              // Seek video to new start position (if initialized)
              if (_previewVideoController?.value.isInitialized ?? false) {
                _previewVideoController
                    ?.seekTo(Duration(seconds: _selectedStart.toInt()));
              }
            } else {
              // Clamp end to maintain 30s window
              setState(() {
                _selectedEnd = newStart + 30;
              });
            }
          },
          activeColor: blueColor,
          inactiveColor: primaryColor.withOpacity(0.3),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<Uint8List?> _compressUntilUnderLimit(Uint8List imageBytes) async {
    int quality = 75;
    Uint8List? compressedImage = imageBytes;

    while (quality >= 50 &&
        compressedImage != null &&
        compressedImage.length > _maxFileSize) {
      compressedImage = await FlutterImageCompress.compressWithList(
        compressedImage,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      quality -= 5;
    }
    return compressedImage;
  }

  void _rotateImage() {
    if (_file == null || _isVideo) return;

    try {
      final image = img.decodeImage(_file!);
      if (image == null) return;
      final rotated = img.copyRotate(image, angle: 90);
      setState(() =>
          _file = Uint8List.fromList(img.encodeJpg(rotated, quality: 80)));
    } catch (e) {
      if (context.mounted) {
        showSnackBar(
            context, 'Please try again or contact us at ratedly9@gmail.com');
      }
    }
  }

  void postMedia(AppUser user) async {
    if (user.uid.isEmpty) {
      if (context.mounted) {
        showSnackBar(context, "User information missing");
      }
      return;
    }

    if (_file == null) {
      if (context.mounted) {
        showSnackBar(context, "Please select media first.");
      }
      return;
    }

    // Size checks
    if (!_isVideo && _file!.length > _maxFileSize) {
      if (context.mounted) {
        showSnackBar(context,
            "Image too large (max 2.5MB). Please choose a smaller image.");
      }
      return;
    }

    if (_isVideo && _file!.length > _maxVideoSize) {
      if (context.mounted) {
        showSnackBar(context,
            "Video too large (max 50MB). Please choose a shorter video.");
      }
      return;
    }

    setState(() => isLoading = true);

    try {
      final String res;

      if (_isVideo) {
        // upload trimmed video bytes (if you prefer path-based upload, change uploadVideoPost to accept File)
        res = await SupabasePostsMethods().uploadVideoPost(
          _descriptionController.text,
          _file!,
          user.uid,
          user.username ?? '',
          user.photoUrl ?? '',
          user.gender ?? '',
        );
      } else {
        res = await SupabasePostsMethods().uploadPost(
          _descriptionController.text,
          _file!,
          user.uid,
          user.username ?? '',
          user.photoUrl ?? '',
          user.gender ?? '',
        );
      }

      if (res == "success" && context.mounted) {
        setState(() => isLoading = false);
        showSnackBar(context, _isVideo ? 'Video Posted!' : 'Posted!');
        clearMedia();
        widget.onPostUploaded?.call();
        Navigator.pop(context);
      } else if (context.mounted) {
        setState(() => isLoading = false);
        showSnackBar(context, 'Error: $res');
      }
    } catch (err) {
      if (context.mounted) {
        setState(() => isLoading = false);
        showSnackBar(context, err.toString());
      }
    }
  }

  void clearMedia() {
    setState(() {
      _file = null;
      _isVideo = false;
      _isPreviewingVideo = false;
      try {
        _previewVideoController?.dispose();
      } catch (_) {}
      _previewVideoController = null;
      _originalVideoPath = null;
      // keep trimmer loaded state as-is; reloading next time is fine
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;

    if (user == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    final String photoUrl = user.photoUrl ?? '';

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: primaryColor),
        backgroundColor: mobileBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primaryColor),
          onPressed: () {
            clearMedia();
            Navigator.pop(context);
          },
        ),
        title: Text('Ratedly', style: TextStyle(color: primaryColor)),
        actions: [
          if (!_isPreviewingVideo && _file != null)
            TextButton(
              onPressed: () => postMedia(user),
              child: Text(
                "Post",
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16.0,
                ),
              ),
            ),
        ],
      ),
      body: _file == null && !_isPreviewingVideo
          ? Center(
              child: IconButton(
                icon: Icon(Icons.upload, color: primaryColor, size: 50),
                onPressed: () => _selectMedia(context),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (isLoading)
                    LinearProgressIndicator(
                      color: primaryColor,
                      backgroundColor: primaryColor.withOpacity(0.2),
                    ),
                  if (_isPreviewingVideo)
                    _buildVideoTrimmer()
                  else
                    Container(
                      height: MediaQuery.of(context).size.height * 0.5,
                      decoration: _isVideo
                          ? BoxDecoration(
                              color: Colors.black,
                              border: Border.all(color: primaryColor),
                            )
                          : BoxDecoration(
                              image: DecorationImage(
                                image: MemoryImage(_file!),
                                fit: BoxFit.cover,
                              ),
                            ),
                      child: _isVideo
                          ? (_previewVideoController?.value.isInitialized ??
                                  false)
                              ? AspectRatio(
                                  aspectRatio: _previewVideoController!
                                      .value.aspectRatio,
                                  child: VideoPlayer(_previewVideoController!),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.videocam,
                                        size: 80, color: primaryColor),
                                    SizedBox(height: 16),
                                    Text(
                                      'Video Ready to Post',
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Tap Post to upload',
                                      style: TextStyle(
                                        color: primaryColor.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                )
                          : null,
                    ),
                  if (!_isVideo && !_isPreviewingVideo)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blueColor,
                          foregroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => SimpleDialog(
                            title: Text('Edit Image',
                                style: TextStyle(color: primaryColor)),
                            backgroundColor: mobileBackgroundColor,
                            children: [
                              SimpleDialogOption(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _rotateImage();
                                },
                                child: Text('Rotate 90°',
                                    style: TextStyle(color: primaryColor)),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('Edit Photo'),
                      ),
                    ),
                  if (!_isPreviewingVideo)
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 21,
                            backgroundColor: Colors.transparent,
                            backgroundImage:
                                (photoUrl.isNotEmpty && photoUrl != "default")
                                    ? NetworkImage(photoUrl)
                                    : null,
                            child: (photoUrl.isEmpty || photoUrl == "default")
                                ? Icon(Icons.account_circle,
                                    size: 42, color: primaryColor)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _descriptionController,
                              decoration: InputDecoration(
                                hintText: "Write a caption...",
                                hintStyle: TextStyle(
                                    color: primaryColor.withOpacity(0.6)),
                                border: InputBorder.none,
                              ),
                              style: TextStyle(color: primaryColor),
                              maxLines: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
