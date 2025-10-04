import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/screens/Profile_page/image_screen.dart';
import 'package:Ratedly/screens/messaging_screen.dart';
import 'package:Ratedly/screens/Profile_page/blocked_profile_screen.dart';
import 'package:Ratedly/widgets/user_list_screen.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';
import 'package:Ratedly/resources/profile_firestore_methods.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:Ratedly/services/ads.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

// Define color schemes for both themes at top level
class _OtherProfileColorSet {
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;
  final Color appBarBackgroundColor;
  final Color appBarIconColor;
  final Color progressIndicatorColor;
  final Color avatarBackgroundColor;
  final Color buttonBackgroundColor;
  final Color buttonTextColor;
  final Color dividerColor;
  final Color dialogBackgroundColor;
  final Color dialogTextColor;
  final Color errorTextColor;
  final Color radioActiveColor;
  final Color adBackgroundColor;
  final Color adDividerColor;

  _OtherProfileColorSet({
    required this.backgroundColor,
    required this.textColor,
    required this.iconColor,
    required this.appBarBackgroundColor,
    required this.appBarIconColor,
    required this.progressIndicatorColor,
    required this.avatarBackgroundColor,
    required this.buttonBackgroundColor,
    required this.buttonTextColor,
    required this.dividerColor,
    required this.dialogBackgroundColor,
    required this.dialogTextColor,
    required this.errorTextColor,
    required this.radioActiveColor,
    required this.adBackgroundColor,
    required this.adDividerColor,
  });
}

class _OtherProfileDarkColors extends _OtherProfileColorSet {
  _OtherProfileDarkColors()
      : super(
          backgroundColor: const Color(0xFF121212),
          textColor: const Color(0xFFd9d9d9),
          iconColor: const Color(0xFFd9d9d9),
          appBarBackgroundColor: const Color(0xFF121212),
          appBarIconColor: const Color(0xFFd9d9d9),
          progressIndicatorColor: const Color(0xFFd9d9d9),
          avatarBackgroundColor: const Color(0xFF333333),
          buttonBackgroundColor: const Color(0xFF333333),
          buttonTextColor: const Color(0xFFd9d9d9),
          dividerColor: const Color(0xFF333333),
          dialogBackgroundColor: const Color(0xFF121212),
          dialogTextColor: const Color(0xFFd9d9d9),
          errorTextColor: Colors.grey[600]!,
          radioActiveColor: const Color(0xFFd9d9d9),
          adBackgroundColor: const Color(0xFF121212),
          adDividerColor: const Color(0xFF333333),
        );
}

class _OtherProfileLightColors extends _OtherProfileColorSet {
  _OtherProfileLightColors()
      : super(
          backgroundColor: Colors.white,
          textColor: Colors.black,
          iconColor: Colors.black,
          appBarBackgroundColor: Colors.white,
          appBarIconColor: Colors.black,
          progressIndicatorColor: Colors.grey[700]!,
          avatarBackgroundColor: Colors.grey[300]!,
          buttonBackgroundColor: Colors.grey[300]!,
          buttonTextColor: Colors.black,
          dividerColor: Colors.grey[300]!,
          dialogBackgroundColor: Colors.white,
          dialogTextColor: Colors.black,
          errorTextColor: Colors.grey[600]!,
          radioActiveColor: Colors.black,
          adBackgroundColor: Colors.white,
          adDividerColor: Colors.grey[300]!,
        );
}

class OtherUserProfileScreen extends StatefulWidget {
  final String uid;
  const OtherUserProfileScreen({Key? key, required this.uid}) : super(key: key);

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  var userData = {};
  int postLen = 0;
  int followers = 0;
  bool isFollowing = false;
  bool isLoading = true;
  bool _isBlockedByMe = false;
  bool _isBlocked = false;
  bool _isBlockedByThem = false;
  bool _isViewerFollower = false;
  bool hasPendingRequest = false;
  List<dynamic> _followersList = [];
  int following = 0;
  bool _isMutualFollow = false;

  // Ad-related variables
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  // Thumbnail cache - storing actual image data
  final Map<String, Uint8List?> _thumbnailCache = {};
  // Cache in-flight generation futures so concurrent callers share work
  final Map<String, Future<Uint8List?>> _thumbnailFutureCache = {};

  final List<String> profileReportReasons = [
    'Impersonation (Pretending to be someone else)',
    'Fake Account (Misleading or suspicious profile)',
    'Bullying or Harassment',
    'Hate Speech or Discrimination (e.g., race, religion, gender, sexual orientation)',
    'Scam or Fraud (Deceptive activity, phishing, or financial fraud)',
    'Spam (Unwanted promotions or repetitive content)',
    'Inappropriate Content (Explicit, offensive, or disturbing profile)',
  ];

  // Helper method to get the appropriate color scheme
  _OtherProfileColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _OtherProfileDarkColors() : _OtherProfileLightColors();
  }

  @override
  void initState() {
    super.initState();
    print('🔄 OtherUserProfileScreen initState called for uid: ${widget.uid}');
    _checkAuthAndLoadData();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    BannerAd(
      adUnitId: AdHelper.otherProfileBannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _bannerAd = ad as BannerAd;
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          print('Failed to load a banner ad: ${err.message}');
          ad.dispose();
        },
      ),
    ).load();
  }

  // -------------------------
  // Video Player Thumbnail Logic
  // -------------------------

  /// Public entry point used by UI code. This method:
  /// - returns cached bytes if available
  /// - otherwise awaits a shared future so concurrent calls share the same work
  /// - does not permanently cache `null` so transient failures can be retried later
  Future<Uint8List?> _getVideoThumbnail(String videoUrl) async {
    // Basic validation
    if (videoUrl.isEmpty || !videoUrl.startsWith('http')) {
      print('❌ Invalid video URL format: $videoUrl');
      return null;
    }

    // Return cached bytes if we have them
    if (_thumbnailCache.containsKey(videoUrl) &&
        _thumbnailCache[videoUrl] != null) {
      // Debug print showing size
      final bytes = _thumbnailCache[videoUrl];
      print(
          '✅ Returning cached thumbnail for $videoUrl (${bytes?.length ?? 0} bytes)');
      return bytes;
    }

    // If a generation Future exists, await it (so multiple callers share in-flight work)
    if (_thumbnailFutureCache.containsKey(videoUrl)) {
      print('⏳ Awaiting existing thumbnail generation for $videoUrl');
      try {
        final bytes = await _thumbnailFutureCache[videoUrl];
        return bytes;
      } catch (e) {
        // If in-flight generation failed, we'll attempt a new generation below.
        print('⚠️ Existing thumbnail future failed for $videoUrl: $e');
      }
    }

    // Create a generation future, cache it, and await it
    final future = _generateThumbnailWithVideoPlayer(videoUrl);
    _thumbnailFutureCache[videoUrl] = future;

    final result = await future;

    // Remove future cache entry so subsequent attempts can retry if necessary
    _thumbnailFutureCache.remove(videoUrl);

    return result;
  }

  /// Generate thumbnail using video_player package - SIMPLIFIED APPROACH
  Future<Uint8List?> _generateThumbnailWithVideoPlayer(String videoUrl) async {
    VideoPlayerController? controller;
    try {
      print('🔄 Generating thumbnail with video_player for: $videoUrl');

      // Create video controller
      controller = VideoPlayerController.network(videoUrl);

      // Initialize the controller
      await controller.initialize();

      // Get the video dimensions
      final videoWidth = controller.value.size.width;
      final videoHeight = controller.value.size.height;

      if (videoWidth == 0 || videoHeight == 0) {
        print('❌ Invalid video dimensions for $videoUrl');
        return null;
      }

      print('📐 Video dimensions: ${videoWidth}x$videoHeight');

      // Seek to 1 second to get a good frame (avoid black frames at start)
      await controller.seekTo(Duration(seconds: 1));

      // Wait for the frame to be ready
      await Future.delayed(Duration(milliseconds: 200));

      // Use VideoPlayer widget to capture the frame
      final thumbnail = await _captureVideoFrame(controller);

      if (thumbnail != null && thumbnail.isNotEmpty) {
        _thumbnailCache[videoUrl] = thumbnail;
        print(
            '✅ Video player thumbnail succeeded (${thumbnail.length} bytes) for $videoUrl');
        return thumbnail;
      }

      print('❌ Video player thumbnail generation failed for $videoUrl');
      return null;
    } catch (e, st) {
      print(
          '❌ Error generating thumbnail with video_player for $videoUrl: $e\n$st');
      return null;
    } finally {
      // Always dispose the controller
      controller?.dispose();
    }
  }

  /// Capture video frame using VideoPlayer widget and repaint boundary
  Future<Uint8List?> _captureVideoFrame(
      VideoPlayerController controller) async {
    try {
      // Create a repaint boundary to capture the video frame
      final repaintBoundary = GlobalKey();

      // Build a widget tree with the video player
      final widget = MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Container(
              width: 300,
              height: 300,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      );

      // This approach is complex and might not work directly
      // For a simpler solution, let's use a fallback approach

      return await _generateFallbackThumbnail();
    } catch (e) {
      print('❌ Error capturing video frame: $e');
      return await _generateFallbackThumbnail();
    }
  }

  /// Generate a simple fallback thumbnail
  Future<Uint8List?> _generateFallbackThumbnail() async {
    try {
      // Create a simple placeholder image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()
        ..color = Colors.grey[300]!
        ..style = PaintingStyle.fill;

      // Draw a simple rectangle
      canvas.drawRect(Rect.fromLTWH(0, 0, 300, 300), paint);

      // Draw a play icon
      final iconPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      final path = Path();
      path.moveTo(110, 80);
      path.lineTo(110, 220);
      path.lineTo(210, 150);
      path.close();
      canvas.drawPath(path, iconPaint);

      // Convert to image
      final picture = recorder.endRecording();
      final image = await picture.toImage(300, 300);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (e) {
      print('❌ Error generating fallback thumbnail: $e');
      return null;
    }
  }

  // -------------------------
  // End thumbnail logic
  // -------------------------

  Future<void> _checkAuthAndLoadData() async {
    print('🔐 Checking auth and loading data...');
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser == null) {
      print('👤 No current user, loading public data');
      await _loadPublicData();
      return;
    }

    print('👤 Current user: ${currentUser.uid}');
    await _checkBlockStatus();
    if (!_isBlocked && mounted) {
      await _otherGetData();
    }
  }

  Future<void> _loadPublicData() async {
    if (!mounted) return;

    try {
      print('📡 Loading public user data for uid: ${widget.uid}');
      final userResponse =
          await _supabase.from('users').select().eq('uid', widget.uid).single();

      if (userResponse.isEmpty) {
        print('❌ User profile not found');
        if (mounted) showSnackBar(context, "User profile not found");
        return;
      }

      print('✅ User data loaded: ${userResponse['username']}');

      final List<Future<dynamic>> queries = [
        _supabase.from('posts').select('postId, postUrl').eq('uid', widget.uid),
        _supabase
            .from('user_followers')
            .select('follower_id, followed_at')
            .eq('user_id', widget.uid),
        _supabase
            .from('user_following')
            .select('following_id, followed_at')
            .eq('user_id', widget.uid),
      ];

      final results = await Future.wait(queries);

      final postsResponse = results[0] as List;
      final followersResponse = results[1] as List;
      final followingResponse = results[2] as List;

      // Debug: Print post information
      print('📊 Posts found: ${postsResponse.length}');
      for (int i = 0; i < postsResponse.length; i++) {
        final post = postsResponse[i];
        final postUrl = post['postUrl'] ?? '';
        final isVideo = _isVideoFile(postUrl);
        print(
            '   Post $i: ${post['postId']} - URL: $postUrl - IsVideo: $isVideo');
      }

      List<dynamic> processedFollowers = [];
      if (followersResponse.isNotEmpty) {
        final followerIds =
            followersResponse.map((f) => f['follower_id'] as String).toList();

        final followersData = await _supabase
            .from('users')
            .select('uid, username, photoUrl')
            .inFilter('uid', followerIds);

        final followerMap = {
          for (var f in followersData) f['uid'] as String: f
        };

        for (var follower in followersResponse) {
          final followerId = follower['follower_id'] as String;
          final followerInfo = followerMap[followerId];
          if (followerInfo != null) {
            processedFollowers.add({
              'userId': followerId,
              'username': followerInfo['username'],
              'photoUrl': followerInfo['photoUrl'],
              'timestamp': follower['followed_at']
            });
          }
        }
      }

      if (mounted) {
        setState(() {
          userData = userResponse;
          postLen = postsResponse.length;
          followers = followersResponse.length;
          following = followingResponse.length;
          _followersList = processedFollowers;
          hasPendingRequest = false;
          isFollowing = false;
          _isMutualFollow = false;
          isLoading = false;
        });
        print('✅ Public data loaded successfully');
      }
    } catch (e) {
      print('❌ Error loading public data: $e');
      if (mounted) {
        showSnackBar(
            context, "Please try again or contact us at ratedly9@gmail.com");
      }
    }
  }

  Future<void> _checkBlockStatus() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

    print('🔒 Checking block status...');
    final isBlockedByMe = await SupabaseBlockMethods().isBlockInitiator(
      currentUserId: currentUserId,
      targetUserId: widget.uid,
    );

    final isBlockedByThem = await SupabaseBlockMethods().isUserBlocked(
      currentUserId: currentUserId,
      targetUserId: widget.uid,
    );

    if (mounted) {
      setState(() {
        _isBlockedByMe = isBlockedByMe;
        _isBlockedByThem = isBlockedByThem;
        _isBlocked = isBlockedByMe || isBlockedByThem;
      });
    }

    print(
        '📊 Block status - ByMe: $_isBlockedByMe, ByThem: $_isBlockedByThem, Blocked: $_isBlocked');

    if (_isBlocked && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => BlockedProfileScreen(
              uid: widget.uid,
              isBlocker: _isBlockedByMe,
            ),
          ),
        );
      });
    }
  }

  Future<void> _otherGetData() async {
    if (!mounted) return;

    try {
      final currentUserId = _firebaseAuth.currentUser?.uid;
      print('📡 Loading user data with auth for uid: ${widget.uid}');

      final userResponse =
          await _supabase.from('users').select().eq('uid', widget.uid).single();

      final List<Future<dynamic>> queries = [
        _supabase.from('posts').select('postId, postUrl').eq('uid', widget.uid),
        _supabase
            .from('user_followers')
            .select('follower_id, followed_at')
            .eq('user_id', widget.uid),
        _supabase
            .from('user_following')
            .select('following_id, followed_at')
            .eq('user_id', widget.uid),
      ];

      if (currentUserId != null) {
        queries.addAll([
          _supabase
              .from('user_following')
              .select()
              .eq('user_id', currentUserId)
              .eq('following_id', widget.uid)
              .maybeSingle(),
          _supabase
              .from('user_follow_request')
              .select()
              .eq('user_id', widget.uid)
              .eq('requester_id', currentUserId)
              .maybeSingle(),
        ]);
      }

      final results = await Future.wait(queries);

      final postsResponse = results[0] as List;
      final followersResponse = results[1] as List;
      final followingResponse = results[2] as List;

      // Debug: Print post information
      print('📊 Posts found: ${postsResponse.length}');
      for (int i = 0; i < postsResponse.length; i++) {
        final post = postsResponse[i];
        final postUrl = post['postUrl'] ?? '';
        final isVideo = _isVideoFile(postUrl);
        print(
            '   Post $i: ${post['postId']} - URL: $postUrl - IsVideo: $isVideo');
      }

      dynamic isFollowingResponse;
      dynamic followRequestResponse;

      if (currentUserId != null) {
        isFollowingResponse = results.length > 3 ? results[3] : null;
        followRequestResponse = results.length > 4 ? results[4] : null;
      }

      List<dynamic> processedFollowers = [];
      if (followersResponse.isNotEmpty) {
        final followerIds =
            followersResponse.map((f) => f['follower_id'] as String).toList();

        final followersData = await _supabase
            .from('users')
            .select('uid, username, photoUrl')
            .inFilter('uid', followerIds);

        final followerMap = {
          for (var f in followersData) f['uid'] as String: f
        };

        for (var follower in followersResponse) {
          final followerId = follower['follower_id'] as String;
          final followerInfo = followerMap[followerId];
          if (followerInfo != null) {
            processedFollowers.add({
              'userId': followerId,
              'username': followerInfo['username'],
              'photoUrl': followerInfo['photoUrl'],
              'timestamp': follower['followed_at']
            });
          }
        }
      }

      bool isMutualFollow = false;
      if (currentUserId != null) {
        final otherFollowsCurrent = await _supabase
            .from('user_following')
            .select()
            .eq('user_id', widget.uid)
            .eq('following_id', currentUserId)
            .maybeSingle();

        isMutualFollow =
            isFollowingResponse != null && otherFollowsCurrent != null;
      }

      if (mounted) {
        setState(() {
          userData = userResponse;
          postLen = postsResponse.length;
          followers = followersResponse.length;
          following = followingResponse.length;
          _followersList = processedFollowers;
          _isMutualFollow = isMutualFollow;

          if (currentUserId != null) {
            hasPendingRequest = followRequestResponse != null;
            isFollowing = isFollowingResponse != null;
          }
          isLoading = false;
        });
        print('✅ User data loaded successfully');
      }

      if (currentUserId != null) {
        await _checkIfViewerIsFollower();
      }
    } catch (e) {
      print('❌ Error loading user data: $e');
      if (mounted) {
        showSnackBar(
            context, "Please try again or contact us at ratedly9@gmail.com");
      }
    }
  }

  Future<void> _checkIfViewerIsFollower() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

    final followersResponse = await _supabase
        .from('user_followers')
        .select()
        .eq('user_id', currentUserId)
        .eq('follower_id', widget.uid)
        .maybeSingle();

    if (mounted) {
      setState(() {
        _isViewerFollower = followersResponse != null;
      });
    }
  }

  void _otherHandleFollow() async {
    try {
      final currentUserId = _firebaseAuth.currentUser?.uid;

      if (currentUserId == null) {
        if (mounted) {
          showSnackBar(context, "Please sign in to follow users");
        }
        return;
      }

      final targetUserId = widget.uid;
      final isPrivate = userData['isPrivate'] ?? false;

      if (isFollowing) {
        await SupabaseProfileMethods()
            .unfollowUser(currentUserId, targetUserId);
        if (mounted) {
          setState(() {
            isFollowing = false;
            _isMutualFollow = false;
          });
        }
      } else if (hasPendingRequest) {
        await SupabaseProfileMethods().declineFollowRequest(
          targetUserId,
          currentUserId,
        );
        if (mounted) {
          setState(() {
            hasPendingRequest = false;
          });
        }
      } else {
        await SupabaseProfileMethods().followUser(
          currentUserId,
          targetUserId,
        );
        if (isPrivate) {
          setState(() {
            hasPendingRequest = true;
          });
        } else {
          setState(() {
            isFollowing = true;
            _checkMutualFollowAfterFollow();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
            context, "Please try again or contact us at ratedly9@gmail.com");
      }
    }
  }

  Future<void> _checkMutualFollowAfterFollow() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

    final otherFollowsCurrent = await _supabase
        .from('user_following')
        .select()
        .eq('user_id', widget.uid)
        .eq('following_id', currentUserId)
        .maybeSingle();

    if (mounted) {
      setState(() {
        _isMutualFollow = otherFollowsCurrent != null;
      });
    }
  }

  void _otherNavigateToMessaging() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;

    if (currentUserId == null) {
      if (mounted) {
        showSnackBar(context, "Please sign in to message users");
      }
      return;
    }

    final userResponse = await _supabase
        .from('users')
        .select('username, photoUrl')
        .eq('uid', widget.uid)
        .single();

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MessagingScreen(
            recipientUid: widget.uid,
            recipientUsername: userResponse['username'] ?? '',
            recipientPhotoUrl: userResponse['photoUrl'] ?? '',
          ),
        ),
      );
    }
  }

  void _showProfileReportDialog(_OtherProfileColorSet colors) {
    final currentUserId = _firebaseAuth.currentUser?.uid;

    if (currentUserId == null) {
      if (mounted) {
        showSnackBar(context, "Please sign in to report profiles");
      }
      return;
    }

    String? selectedReason;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: colors.dialogBackgroundColor,
              title: Text('Report Profile',
                  style: TextStyle(color: colors.dialogTextColor)),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thank you for helping keep our community safe.\n\nPlease let us know the reason for reporting this content. Your report is anonymous, and our moderators will review it as soon as possible. \n\n If you prefer not to see this user posts or content, you can choose to block them.',
                      style: TextStyle(
                          color: colors.dialogTextColor, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Select a reason:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colors.dialogTextColor),
                    ),
                    ...profileReportReasons.map((reason) {
                      return RadioListTile<String>(
                        title: Text(reason,
                            style: TextStyle(color: colors.dialogTextColor)),
                        value: reason,
                        groupValue: selectedReason,
                        activeColor: colors.radioActiveColor,
                        onChanged: (value) {
                          setState(() => selectedReason = value);
                        },
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(color: colors.dialogTextColor)),
                ),
                TextButton(
                  onPressed: selectedReason != null
                      ? () => _submitProfileReport(selectedReason!)
                      : null,
                  child: Text('Submit',
                      style: TextStyle(color: colors.dialogTextColor)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitProfileReport(String reason) async {
    try {
      await _supabase.from('reports').insert({
        'user_id': widget.uid,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
        'type': 'profile',
      });

      if (mounted) {
        Navigator.pop(context);
        showSnackBar(context, 'Report submitted. Thank you!');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
            context, 'Please try again or contact us at ratedly9@gmail.com');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final currentUserId = _firebaseAuth.currentUser?.uid;
    final isCurrentUser = currentUserId == widget.uid;
    final isAuthenticated = currentUserId != null;

    print('🎨 Building OtherUserProfileScreen - isLoading: $isLoading');

    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: colors.appBarBackgroundColor,
          elevation: 0,
          leading: BackButton(color: colors.appBarIconColor),
        ),
        backgroundColor: colors.backgroundColor,
        body: Center(
          child:
              CircularProgressIndicator(color: colors.progressIndicatorColor),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
          iconTheme: IconThemeData(color: colors.appBarIconColor),
          backgroundColor: colors.appBarBackgroundColor,
          elevation: 0,
          title: Text(
            userData['username'] ?? 'User',
            style:
                TextStyle(color: colors.textColor, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          leading: BackButton(color: colors.appBarIconColor),
          actions: [
            if (isAuthenticated)
              PopupMenuButton(
                icon: Icon(Icons.more_vert, color: colors.appBarIconColor),
                onSelected: (value) async {
                  if (value == 'block') {
                    try {
                      setState(() => isLoading = true);
                      final currentUserId = _firebaseAuth.currentUser?.uid;
                      if (currentUserId == null) {
                        return;
                      }

                      await SupabaseBlockMethods().blockUser(
                        currentUserId: currentUserId,
                        targetUserId: widget.uid,
                      );

                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BlockedProfileScreen(
                              uid: widget.uid,
                              isBlocker: true,
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        showSnackBar(context,
                            "Please try again or contact us at ratedly9@gmail.com");
                      }
                    } finally {
                      if (mounted) setState(() => isLoading = false);
                    }
                  } else if (value == 'remove_follower') {
                    final currentUserId = _firebaseAuth.currentUser?.uid;
                    if (currentUserId == null) return;

                    try {
                      await SupabaseProfileMethods()
                          .removeFollower(currentUserId, widget.uid);
                      if (mounted) {
                        setState(() {
                          _isViewerFollower = false;
                          followers = followers - 1;
                        });

                        showSnackBar(context, "Follower removed successfully");
                      }
                    } catch (e) {
                      if (mounted) {
                        showSnackBar(context,
                            "Please try again or contact us at ratedly9@gmail.com");
                      }
                    }
                  } else if (value == 'report') {
                    _showProfileReportDialog(colors);
                  }
                },
                itemBuilder: (context) => [
                  if (_isViewerFollower)
                    PopupMenuItem(
                      value: 'remove_follower',
                      child: Text('Remove Follower',
                          style: TextStyle(color: colors.textColor)),
                    ),
                  if (!isCurrentUser)
                    PopupMenuItem(
                      value: 'report',
                      child: Text('Report Profile',
                          style: TextStyle(color: colors.textColor)),
                    ),
                  PopupMenuItem(
                    value: 'block',
                    child: Text('Block User',
                        style: TextStyle(color: colors.textColor)),
                  ),
                ],
              )
          ]),
      backgroundColor: colors.backgroundColor,
      body: Column(
        children: [
          // Banner Ad at the top
          if (_isAdLoaded && _bannerAd != null)
            Container(
              width: double.infinity,
              color: colors.adBackgroundColor,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(height: 1, color: colors.adDividerColor),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 50,
                    child: AdWidget(ad: _bannerAd!),
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: colors.adDividerColor),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildOtherProfileHeader(colors),
                    const SizedBox(height: 20),
                    _buildOtherBioSection(colors),
                    Divider(color: colors.dividerColor),
                    _buildOtherPostsGrid(colors)
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherProfileHeader(_OtherProfileColorSet colors) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: colors.avatarBackgroundColor,
          radius: 45,
          backgroundImage: (userData['photoUrl'] != null &&
                  userData['photoUrl'].isNotEmpty &&
                  userData['photoUrl'] != "default")
              ? NetworkImage(userData['photoUrl'])
              : null,
          child: (userData['photoUrl'] == null ||
                  userData['photoUrl'].isEmpty ||
                  userData['photoUrl'] == "default")
              ? Icon(
                  Icons.account_circle,
                  size: 90,
                  color: colors.iconColor,
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildOtherMetric(postLen, "Posts", colors),
                        _buildOtherInteractiveMetric(
                            followers, "Followers", _followersList, colors),
                        _buildOtherMetric(following, "Following", colors),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildOtherInteractionButtons(colors),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOtherInteractiveMetric(int value, String label,
      List<dynamic> userList, _OtherProfileColorSet colors) {
    List<dynamic> validEntries = userList.where((entry) {
      return entry['userId'] != null && entry['userId'].toString().isNotEmpty;
    }).toList();

    return GestureDetector(
      onTap: validEntries.isEmpty
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserListScreen(
                    title: label,
                    userEntries: validEntries,
                  ),
                ),
              ),
      child: _buildOtherMetric(validEntries.length, label, colors),
    );
  }

  Widget _buildOtherInteractionButtons(_OtherProfileColorSet colors) {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    final bool isCurrentUser = currentUserId == widget.uid;
    final bool isPrivateAccount = userData['isPrivate'] ?? false;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isCurrentUser) _buildFollowButton(isPrivateAccount, colors),
            const SizedBox(width: 5),
            if (!isCurrentUser)
              ElevatedButton(
                onPressed: _otherNavigateToMessaging,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.buttonBackgroundColor,
                  foregroundColor: colors.buttonTextColor,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  minimumSize: const Size(100, 40),
                ),
                child: Text("Message",
                    style: TextStyle(color: colors.buttonTextColor)),
              ),
          ],
        ),
        const SizedBox(height: 5),
      ],
    );
  }

  Widget _buildFollowButton(
      bool isPrivateAccount, _OtherProfileColorSet colors) {
    final isPending = hasPendingRequest && isPrivateAccount;

    return ElevatedButton(
        onPressed: _otherHandleFollow,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.buttonBackgroundColor,
          foregroundColor: colors.buttonTextColor,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          side: BorderSide(
            color: colors.buttonBackgroundColor,
          ),
          minimumSize: const Size(100, 40),
        ),
        child: Text(
          isFollowing
              ? 'Unfollow'
              : isPending
                  ? 'Requested'
                  : 'Follow',
          style: TextStyle(
              fontWeight: FontWeight.w600, color: colors.buttonTextColor),
        ));
  }

  Widget _buildOtherMetric(
      int value, String label, _OtherProfileColorSet colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 13.6,
            fontWeight: FontWeight.bold,
            color: colors.textColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: colors.textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildOtherBioSection(_OtherProfileColorSet colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            userData['username'] ?? '',
            style: TextStyle(
                color: colors.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(userData['bio'] ?? '',
              style: TextStyle(color: colors.textColor)),
        ],
      ),
    );
  }

  Widget _buildPrivateAccountMessage(_OtherProfileColorSet colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock, size: 60, color: colors.errorTextColor),
        const SizedBox(height: 20),
        Text('This Account is Private',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textColor)),
        const SizedBox(height: 10),
        Text('Follow to see their posts',
            style: TextStyle(fontSize: 14, color: colors.textColor)),
      ],
    );
  }

  Widget _buildOtherPostsGrid(_OtherProfileColorSet colors) {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    final bool isCurrentUser = currentUserId == widget.uid;
    final bool isPrivate = userData['isPrivate'] ?? false;
    final bool shouldHidePosts = isPrivate && !isFollowing && !isCurrentUser;
    final bool isMutuallyBlocked = _isBlockedByMe || _isBlockedByThem;

    print(
        '📊 Building posts grid - shouldHidePosts: $shouldHidePosts, isMutuallyBlocked: $isMutuallyBlocked');

    if (isMutuallyBlocked) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 50, color: Colors.red),
            const SizedBox(height: 10),
            Text('Posts unavailable due to blocking',
                style: TextStyle(color: colors.errorTextColor)),
          ],
        ),
      );
    }

    if (shouldHidePosts) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.3,
        child: _buildPrivateAccountMessage(colors),
      );
    }

    return FutureBuilder<List<dynamic>>(
      future: _supabase
          .from('posts')
          .select('postId, postUrl, description, datePublished, uid')
          .eq('uid', widget.uid)
          .order('datePublished', ascending: false),
      builder: (context, snapshot) {
        print(
            '📦 Posts FutureBuilder - ConnectionState: ${snapshot.connectionState}');

        if (snapshot.connectionState == ConnectionState.waiting) {
          print('⏳ Posts FutureBuilder - Waiting for data...');
          return Center(
              child: CircularProgressIndicator(
                  color: colors.progressIndicatorColor));
        }

        if (snapshot.hasError) {
          print('❌ Posts FutureBuilder - Error: ${snapshot.error}');
          return Center(
              child: Text('Failed to load posts',
                  style: TextStyle(color: colors.textColor)));
        }

        final posts = snapshot.data ?? [];
        print('✅ Posts FutureBuilder - Loaded ${posts.length} posts');

        if (posts.isEmpty) {
          return SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  'This user has no posts.',
                  style: TextStyle(
                    fontSize: 16,
                    color: colors.errorTextColor,
                  ),
                ),
              ));
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: posts.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 5,
            mainAxisSpacing: 1.5,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final post = posts[index];
            print('🎬 Building post item $index: ${post['postId']}');
            return _buildOtherPostItem(post, colors);
          },
        );
      },
    );
  }

  Widget _buildOtherPostItem(
      Map<String, dynamic> post, _OtherProfileColorSet colors) {
    final postUrl = post['postUrl'] ?? '';
    final isVideo = _isVideoFile(postUrl);

    print('\n=== POST ITEM DEBUG ===');
    print('📄 Post ID: ${post['postId']}');
    print('🔗 Post URL: $postUrl');
    print('🎥 Is Video: $isVideo');
    print('=== POST ITEM DEBUG ===\n');

    return FutureBuilder<bool>(
      future: SupabaseBlockMethods().isMutuallyBlocked(
        _firebaseAuth.currentUser?.uid ?? '',
        post['uid'] ?? '',
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!) {
          print('🚫 Post ${post['postId']} is blocked');
          return Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: colors.avatarBackgroundColor,
            ),
            child: const Center(
              child: Icon(
                Icons.block,
                color: Colors.red,
                size: 30,
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ImageViewScreen(
                imageUrl: postUrl,
                postId: post['postId'] ?? '',
                description: post['description'] ?? '',
                userId: post['uid'] ?? '',
                username: userData['username'] ?? '',
                profImage: userData['photoUrl'] ?? '',
                datePublished: post['datePublished'],
              ),
            ),
          ),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isVideo ? colors.avatarBackgroundColor : null,
            ),
            child: isVideo
                ? _buildVideoThumbnail(postUrl, colors)
                : _buildImageThumbnail(postUrl, colors),
          ),
        );
      },
    );
  }

  Widget _buildVideoThumbnail(String videoUrl, _OtherProfileColorSet colors) {
    print('🎬 Building video thumbnail for: $videoUrl');

    return FutureBuilder<Uint8List?>(
      future: _getVideoThumbnail(videoUrl),
      builder: (context, snapshot) {
        print(
            '📊 VideoThumbnail FutureBuilder - ConnectionState: ${snapshot.connectionState}');

        // Show loading indicator while generating thumbnail
        if (snapshot.connectionState == ConnectionState.waiting) {
          print('⏳ VideoThumbnail - Waiting for thumbnail generation...');
          return _buildVideoLoading(colors);
        }

        // Show error state or fallback
        if (snapshot.hasError) {
          print('❌ VideoThumbnail - Error: ${snapshot.error}');
          return _buildVideoFallback(colors);
        }

        // Show fallback if no thumbnail data
        if (snapshot.data == null) {
          print('❌ VideoThumbnail - No thumbnail data received');
          return _buildVideoFallback(colors);
        }

        // Success - show the actual thumbnail
        try {
          print('✅ VideoThumbnail - Success! Displaying actual thumbnail');
          return Stack(
            fit: StackFit.expand,
            children: [
              // Actual video thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    print('❌ Image.memory error: $error');
                    return _buildVideoFallback(colors);
                  },
                ),
              ),
              // Semi-transparent overlay with play icon
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black.withOpacity(0.2),
                ),
                child: Center(
                  child: Icon(
                    Icons.play_circle_filled,
                    color: Colors.white.withOpacity(0.9),
                    size: 35,
                  ),
                ),
              ),
            ],
          );
        } catch (e) {
          print('❌ Error building thumbnail widget: $e');
          return _buildVideoFallback(colors);
        }
      },
    );
  }

  Widget _buildVideoLoading(_OtherProfileColorSet colors) {
    return Container(
      color: colors.avatarBackgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: colors.progressIndicatorColor,
              strokeWidth: 2,
            ),
            const SizedBox(height: 8),
            Text(
              'Loading...',
              style: TextStyle(
                color: colors.textColor,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoFallback(_OtherProfileColorSet colors) {
    print('🔄 Using video fallback UI');
    return Container(
      color: colors.avatarBackgroundColor.withOpacity(0.7),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_filled,
              color: colors.iconColor,
              size: 40,
            ),
            const SizedBox(height: 4),
            Text(
              'Video',
              style: TextStyle(
                color: colors.textColor,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(String imageUrl, _OtherProfileColorSet colors) {
    print('🖼️ Building image thumbnail for: $imageUrl');
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: colors.avatarBackgroundColor,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        (loadingProgress.expectedTotalBytes ?? 1)
                    : null,
                color: colors.progressIndicatorColor,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          print('❌ Image.network error: $error');
          return Container(
            color: colors.avatarBackgroundColor,
            child: Center(
              child: Icon(
                Icons.broken_image,
                color: colors.errorTextColor,
                size: 30,
              ),
            ),
          );
        },
      ),
    );
  }

  // Helper method to detect video files by extension
  bool _isVideoFile(String url) {
    if (url.isEmpty) {
      print('❌ _isVideoFile: URL is empty');
      return false;
    }

    final lowerUrl = url.toLowerCase();
    final isVideo = lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.mov') ||
        lowerUrl.endsWith('.avi') ||
        lowerUrl.endsWith('.wmv') ||
        lowerUrl.endsWith('.flv') ||
        lowerUrl.endsWith('.mkv') ||
        lowerUrl.endsWith('.webm') ||
        lowerUrl.endsWith('.m4v') ||
        lowerUrl.endsWith('.3gp') ||
        lowerUrl.contains('/video/') ||
        lowerUrl.contains('video=true');

    print('🔍 _isVideoFile: $url -> $isVideo');
    return isVideo;
  }

  @override
  void dispose() {
    print('♻️ Disposing OtherUserProfileScreen');
    _bannerAd?.dispose();

    // Clear thumbnail cache to free memory
    _thumbnailCache.clear();
    _thumbnailFutureCache.clear();

    super.dispose();
  }
}
