import 'dart:convert';
import 'package:Ratedly/services/ads.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/resources/supabase_posts_methods.dart';
import 'package:Ratedly/screens/comment_screen.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/widgets/flutter_rating_bar.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/widgets/postshare.dart';
import 'package:Ratedly/widgets/rating_list_screen_postcard.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';
import 'package:Ratedly/widgets/blocked_content_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart';

// Define color schemes for both themes at top level
class _ImageViewColorSet {
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;
  final Color appBarBackgroundColor;
  final Color appBarIconColor;
  final Color dialogBackgroundColor;
  final Color dialogTextColor;
  final Color avatarBackgroundColor;
  final Color progressIndicatorColor;
  final Color buttonBackgroundColor;
  final Color dividerColor;
  final Color radioActiveColor;
  final Color errorIconColor;
  final Color badgeBackgroundColor;
  final Color badgeTextColor;

  _ImageViewColorSet({
    required this.backgroundColor,
    required this.textColor,
    required this.iconColor,
    required this.appBarBackgroundColor,
    required this.appBarIconColor,
    required this.dialogBackgroundColor,
    required this.dialogTextColor,
    required this.avatarBackgroundColor,
    required this.progressIndicatorColor,
    required this.buttonBackgroundColor,
    required this.dividerColor,
    required this.radioActiveColor,
    required this.errorIconColor,
    required this.badgeBackgroundColor,
    required this.badgeTextColor,
  });
}

class _ImageViewDarkColors extends _ImageViewColorSet {
  _ImageViewDarkColors()
      : super(
          backgroundColor: const Color(0xFF121212),
          textColor: const Color(0xFFd9d9d9),
          iconColor: const Color(0xFFd9d9d9),
          appBarBackgroundColor: const Color(0xFF121212),
          appBarIconColor: const Color(0xFFd9d9d9),
          dialogBackgroundColor: const Color(0xFF121212),
          dialogTextColor: const Color(0xFFd9d9d9),
          avatarBackgroundColor: const Color(0xFF333333),
          progressIndicatorColor: Colors.white70,
          buttonBackgroundColor: const Color(0xFF333333),
          dividerColor: const Color(0xFF333333),
          radioActiveColor: const Color(0xFFd9d9d9),
          errorIconColor: Colors.white54,
          badgeBackgroundColor: const Color(0xFF333333),
          badgeTextColor: const Color(0xFFd9d9d9),
        );
}

class _ImageViewLightColors extends _ImageViewColorSet {
  _ImageViewLightColors()
      : super(
          backgroundColor: Colors.white,
          textColor: Colors.black,
          iconColor: Colors.black,
          appBarBackgroundColor: Colors.white,
          appBarIconColor: Colors.black,
          dialogBackgroundColor: Colors.white,
          dialogTextColor: Colors.black,
          avatarBackgroundColor: Colors.grey[300]!,
          progressIndicatorColor: Colors.grey[700]!,
          buttonBackgroundColor: Colors.grey[300]!,
          dividerColor: Colors.grey[300]!,
          radioActiveColor: Colors.black,
          errorIconColor: Colors.grey[600]!,
          badgeBackgroundColor: Colors.grey[300]!,
          badgeTextColor: Colors.black,
        );
}

class ImageViewScreen extends StatefulWidget {
  final String imageUrl;
  final String postId;
  final String description;
  final String userId;
  final String username;
  final String profImage;
  final dynamic datePublished;
  final VoidCallback? onPostDeleted;

  const ImageViewScreen({
    Key? key,
    required this.imageUrl,
    required this.postId,
    required this.description,
    required this.userId,
    required this.username,
    required this.profImage,
    required this.datePublished,
    this.onPostDeleted,
  }) : super(key: key);

  @override
  State<ImageViewScreen> createState() => _ImageViewScreenState();
}

class _ImageViewScreenState extends State<ImageViewScreen> {
  int commentLen = 0;
  bool _isBlocked = false;
  final SupabasePostsMethods _postsMethods = SupabasePostsMethods();
  bool _showSlider = true;

  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  // New rating state variables
  double _averageRating = 0.0;
  int _totalRatingsCount = 0;
  double? _userRating;
  bool _isLoadingRatings = true;

  // Video player variables - simplified for TikTok/Instagram style
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoLoading = false;
  bool _isVideoPlaying = false;
  bool _showPlayButton = false; // Start with play button hidden
  bool _isMuted = false; // New state for mute/unmute

  final List<String> reportReasons = [
    'I just don\'t like it',
    'Discriminatory content',
    'Bullying or harassment',
    'Violence or hate speech',
    'Selling prohibited items',
    'Pornography or nudity',
    'Scam or fraudulent activity',
    'Spam',
    'Misinformation',
  ];

  bool _isRating = false;

  // Check if URL is a video
  bool get _isVideo {
    final url = widget.imageUrl.toLowerCase();
    return url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.avi') ||
        url.endsWith('.mkv') ||
        url.contains('video');
  }

  @override
  void initState() {
    super.initState();
    _fetchCommentsCount();
    _checkBlockStatus();
    _fetchRatingStats();
    _loadBannerAd();

    // Initialize video player if it's a video
    if (_isVideo) {
      _initializeVideoPlayer();
    }
  }

  void _initializeVideoPlayer() async {
    setState(() => _isVideoLoading = true);

    try {
      _videoController = VideoPlayerController.network(widget.imageUrl)
        ..addListener(() {
          if (mounted) {
            setState(() {
              _isVideoPlaying = _videoController!.value.isPlaying;
              // Handle video completion
              if (_videoController!.value.position ==
                  _videoController!.value.duration) {
                // Restart the video when it ends (loop)
                _videoController!.seekTo(Duration.zero);
                _videoController!.play();
              }
            });
          }
        });

      await _videoController!.initialize();
      // Set the video to loop
      _videoController!.setLooping(true);

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
          _isVideoLoading = false;
          _showPlayButton = false; // Start with play button hidden
        });

        // Auto-play the video (like TikTok/Instagram)
        _playVideo();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isVideoLoading = false);
        print('Video initialization error: $e');
      }
    }
  }

  void _playVideo() {
    if (_videoController != null && _isVideoInitialized) {
      _videoController!.play();
      setState(() {
        _isVideoPlaying = true;
      });

      // Auto-hide the play button after 2 seconds
      Future.delayed(Duration(seconds: 2), () {
        if (mounted && _isVideoPlaying) {
          setState(() {
            _showPlayButton = false;
          });
        }
      });
    }
  }

  void _pauseVideo() {
    if (_videoController != null && _isVideoInitialized) {
      _videoController!.pause();
      setState(() {
        _isVideoPlaying = false;
        // Don't set _showPlayButton here - let the tap handler manage it
      });
    }
  }

  void _toggleMute() {
    if (_videoController != null && _isVideoInitialized) {
      setState(() {
        _isMuted = !_isMuted;
        _videoController!.setVolume(_isMuted ? 0.0 : 1.0);
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() {
    BannerAd(
      adUnitId: AdHelper.imagescreenAdUnitId,
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

  // Helper method to get the appropriate color scheme
  _ImageViewColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _ImageViewDarkColors() : _ImageViewLightColors();
  }

  // Add this helper method to parse the date (same as in PostCard)
  DateTime? _parseDate(dynamic date) {
    if (date == null) return null;
    if (date is DateTime) return date;
    if (date is String) return DateTime.tryParse(date);
    return null;
  }

  dynamic _unwrap(dynamic res) {
    try {
      if (res == null) return null;
      if (res is Map && res.containsKey('data')) return res['data'];
    } catch (_) {}
    return res;
  }

  int _countItems(dynamic value) {
    try {
      if (value == null) return 0;
      if (value is List) return value.length;
      if (value is Iterable) return value.length;
      if (value is Map && value['data'] is List) {
        return (value['data'] as List).length;
      }
      if (value is String) {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded.length;
        if (decoded is Map && decoded['data'] is List) {
          return (decoded['data'] as List).length;
        }
        return 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _fetchCommentsCount() async {
    try {
      final commentsRes = await Supabase.instance.client
          .from('comments')
          .select('id')
          .eq('postid', widget.postId);

      final commentsData = _unwrap(commentsRes) ?? commentsRes;
      final int computedCommentsCount = _countItems(commentsData);

      if (mounted) {
        setState(() {
          commentLen = computedCommentsCount;
        });
      }
    } catch (err) {
      if (mounted) showSnackBar(context, err.toString());
    }
  }

  // New method to fetch rating stats
  Future<void> _fetchRatingStats() async {
    setState(() => _isLoadingRatings = true);

    try {
      // Fetch ratings count
      final countResponse = await Supabase.instance.client
          .from('post_rating')
          .select()
          .eq('postid', widget.postId);

      // Fetch ratings for average calculation
      final avgResponse = await Supabase.instance.client
          .from('post_rating')
          .select('rating')
          .eq('postid', widget.postId);

      // Get current user's rating
      final user = Provider.of<UserProvider>(context, listen: false).user;
      dynamic userRatingRes;
      if (user != null) {
        userRatingRes = await Supabase.instance.client
            .from('post_rating')
            .select('rating')
            .eq('postid', widget.postId)
            .eq('userid', user.uid)
            .maybeSingle();
      }

      if (mounted) {
        setState(() {
          _totalRatingsCount = countResponse.length;

          // Calculate average rating
          if (avgResponse.isNotEmpty) {
            final ratings = avgResponse
                .map<double>((r) => (r['rating'] as num).toDouble())
                .toList();
            _averageRating = ratings.reduce((a, b) => a + b) / ratings.length;
          } else {
            _averageRating = 0.0;
          }

          // Set user rating and showSlider based on whether user has rated
          if (userRatingRes != null) {
            _userRating = (userRatingRes['rating'] as num).toDouble();
            _showSlider = false; // User has rated, hide slider
          } else {
            _userRating = null;
            _showSlider = true; // User hasn't rated, show slider
          }

          _isLoadingRatings = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRatings = false);
      }
    }
  }

  Future<void> _checkBlockStatus() async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;

    final isBlocked = await SupabaseBlockMethods().isMutuallyBlocked(
      user.uid,
      widget.userId,
    );

    if (mounted) setState(() => _isBlocked = isBlocked);
  }

  void _handleRatingSubmitted(double rating) async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) {
      setState(() => _isRating = false);
      return;
    }

    setState(() {
      _isRating = true; // Start rating
      _userRating = rating;
      _showSlider = false; // Hide slider after rating
      // Update average calculation optimistically
      if (_totalRatingsCount > 0) {
        final newTotal = _averageRating * _totalRatingsCount;
        // If user had previous rating, subtract it first
        if (_userRating != null) {
          _averageRating =
              (newTotal - _userRating! + rating) / _totalRatingsCount;
        } else {
          _totalRatingsCount++;
          _averageRating = (newTotal + rating) / _totalRatingsCount;
        }
      } else {
        _totalRatingsCount = 1;
        _averageRating = rating;
      }
    });

    try {
      final response =
          await _postsMethods.ratePost(widget.postId, user.uid, rating);

      if (response != 'success' && mounted) {
        _fetchRatingStats();
        showSnackBar(context, 'Failed to submit rating');
      }
    } catch (e) {
      if (mounted) {
        _fetchRatingStats();
        showSnackBar(context, 'Something went wrong...');
      }
    } finally {
      if (mounted) {
        setState(() => _isRating = false); // End rating
      }
    }
  }

  void _handleEditRating() {
    setState(() {
      _showSlider = true;
    });
  }

  void deletePost(String postId) async {
    try {
      await _postsMethods.deletePost(postId);
      if (mounted) {
        widget.onPostDeleted?.call();
        Navigator.of(context).pop();
      }
    } catch (err) {
      if (mounted) {
        showSnackBar(context, err.toString());
      }
    }
  }

  void _showReportDialog(_ImageViewColorSet colors) {
    String? selectedReason;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: colors.dialogBackgroundColor,
              title: Text('Report Post',
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
                      'Select a reason: \n',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.dialogTextColor,
                      ),
                    ),
                    ...reportReasons.map((reason) {
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
                      ? () {
                          _postsMethods
                              .reportPost(widget.postId, selectedReason!)
                              .then((res) {
                            Navigator.pop(context);
                            if (res == 'success') {
                              showSnackBar(
                                  context, 'Report submitted. Thank you!');
                            } else {
                              showSnackBar(context,
                                  'Something went wrong, please try again later or contact us at ratedly9@gmail.com');
                            }
                          });
                        }
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

  Widget _buildMediaContent(_ImageViewColorSet colors) {
    if (_isVideo) {
      return _buildVideoPlayer(colors);
    } else {
      return _buildImage(colors);
    }
  }

  Widget _buildVideoPlayer(_ImageViewColorSet colors) {
    return AspectRatio(
      aspectRatio:
          _isVideoInitialized ? _videoController!.value.aspectRatio : 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video player background (black)
          Container(color: Colors.black),

          // Video player
          if (_isVideoInitialized)
            GestureDetector(
              onTap: () {
                // Tap anywhere on video: pause and show pause icon
                if (_isVideoPlaying) {
                  _pauseVideo();
                  // Show the pause icon immediately
                  setState(() {
                    _showPlayButton = true;
                  });

                  // Auto-hide the pause icon after 3 seconds if not interacted with
                  Future.delayed(Duration(seconds: 3), () {
                    if (mounted && !_isVideoPlaying) {
                      setState(() {
                        _showPlayButton = false;
                      });
                    }
                  });
                }
              },
              child: VideoPlayer(_videoController!),
            )
          else if (_isVideoLoading)
            Container(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(
                  color: colors.progressIndicatorColor,
                ),
              ),
            )
          else
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam,
                        size: 50, color: colors.errorIconColor),
                    SizedBox(height: 8),
                    Text(
                      'Video not available',
                      style: TextStyle(color: colors.errorIconColor),
                    ),
                    SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _initializeVideoPlayer,
                      child: Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),

          // Play/Pause button (centered) - Only show when video is paused OR when user taps to pause
          if (_showPlayButton && _isVideoInitialized)
            Center(
              child: GestureDetector(
                onTap: () {
                  // Tap on pause icon: resume playback
                  _playVideo();
                  // Hide the pause icon after a brief delay
                  Future.delayed(Duration(milliseconds: 300), () {
                    if (mounted && _isVideoPlaying) {
                      setState(() {
                        _showPlayButton = false;
                      });
                    }
                  });
                },
                child: AnimatedOpacity(
                  opacity: _showPlayButton ? 1.0 : 0.0,
                  duration: Duration(milliseconds: 200),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isVideoPlaying ? Icons.pause : Icons.play_arrow,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

          // Ratedly indicator
          if (_isVideoInitialized)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Ratedly',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // Mute/Unmute button - Bottom right
          if (_isVideoInitialized)
            Positioned(
              bottom: 16,
              right: 16,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isMuted ? Icons.volume_off : Icons.volume_up,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage(_ImageViewColorSet colors) {
    return AspectRatio(
      aspectRatio: 1,
      child: InteractiveViewer(
        panEnabled: true,
        scaleEnabled: true,
        minScale: 1.0,
        maxScale: 4.0,
        child: Image.network(
          widget.imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return SizedBox(
              width: double.infinity,
              height: 250,
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          (loadingProgress.expectedTotalBytes ?? 1)
                      : null,
                  color: colors.progressIndicatorColor,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => SizedBox(
            width: double.infinity,
            height: 250,
            child: Center(
              child: Icon(Icons.broken_image,
                  color: colors.errorIconColor, size: 48),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final user = Provider.of<UserProvider>(context).user;

    final datePublished = _parseDate(widget.datePublished);
    final timeagoText =
        datePublished != null ? timeago.format(datePublished) : '';

    if (user == null) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: colors.progressIndicatorColor,
          ),
        ),
      );
    }

    if (_isBlocked) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: colors.appBarBackgroundColor,
          iconTheme: IconThemeData(color: colors.appBarIconColor),
        ),
        body: const BlockedContentMessage(
          message: 'Post unavailable due to blocking',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: colors.appBarIconColor),
        backgroundColor: colors.appBarBackgroundColor,
        title: Text(
          widget.username,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.textColor,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.appBarIconColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: colors.appBarIconColor),
            onPressed: () {
              if (FirebaseAuth.instance.currentUser?.uid == widget.userId) {
                showDialog(
                  context: context,
                  builder: (context) => Dialog(
                    backgroundColor: colors.dialogBackgroundColor,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shrinkWrap: true,
                      children: [
                        InkWell(
                          onTap: () {
                            deletePost(widget.postId);
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                            child: Text(
                              'Delete',
                              style: TextStyle(color: colors.dialogTextColor),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                _showReportDialog(colors);
              }
            },
          ),
        ],
      ),
      backgroundColor: colors.backgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16)
                  .copyWith(right: 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfileScreen(uid: widget.userId),
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 21,
                      backgroundColor: colors.avatarBackgroundColor,
                      backgroundImage: (widget.profImage.isNotEmpty &&
                              widget.profImage != "default")
                          ? NetworkImage(widget.profImage)
                          : null,
                      child: (widget.profImage.isEmpty ||
                              widget.profImage == "default")
                          ? Icon(Icons.account_circle,
                              size: 42, color: colors.errorIconColor)
                          : null,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ProfileScreen(uid: widget.userId),
                              ),
                            ),
                            child: Text(
                              widget.username,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colors.textColor,
                              ),
                            ),
                          ),
                          if (timeagoText.isNotEmpty)
                            Text(
                              timeagoText,
                              style: TextStyle(
                                color: colors.textColor.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Media content (image or video)
            _buildMediaContent(colors),
            if (widget.description.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.description,
                    style: TextStyle(
                      color: colors.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RatingBar(
                    initialRating: _userRating ?? 1.0,
                    hasRated: _userRating != null,
                    userRating: _userRating ?? 0.0,
                    onRatingEnd: _handleRatingSubmitted,
                    isRating: _isRating,
                    showSlider: _showSlider,
                    onEditRating: _handleEditRating,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            IconButton(
                              icon: Icon(Icons.comment_outlined,
                                  color: colors.iconColor),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      CommentsScreen(postId: widget.postId),
                                ),
                              ),
                            ),
                            if (commentLen > 0)
                              Positioned(
                                top: -6,
                                left: -6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: colors.badgeBackgroundColor,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 20,
                                    minHeight: 20,
                                  ),
                                  child: Center(
                                    child: Text(
                                      commentLen.toString(),
                                      style: TextStyle(
                                        color: colors.badgeTextColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.send, color: colors.iconColor),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => PostShare(
                                currentUserId: user.uid,
                                postId: widget.postId,
                              ),
                            );
                          },
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RatingListScreen(
                                  postId: widget.postId,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors.buttonBackgroundColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: _isLoadingRatings
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: colors.progressIndicatorColor,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Rated ${_averageRating.toStringAsFixed(1)} by $_totalRatingsCount ${_totalRatingsCount == 1 ? 'voter' : 'voters'}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colors.textColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                          ),
                        )
                      ],
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
