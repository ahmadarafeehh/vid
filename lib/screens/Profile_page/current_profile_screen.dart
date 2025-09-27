import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/widgets/edit_profile_screen.dart';
import 'package:Ratedly/screens/Profile_page/image_screen.dart';
import 'package:Ratedly/screens/Profile_page/add_post_screen.dart';
import 'package:Ratedly/widgets/settings_screen.dart';
import 'package:Ratedly/widgets/user_list_screen.dart';
import 'package:Ratedly/resources/profile_firestore_methods.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:Ratedly/services/ads.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';

// Define color schemes for both themes at top level (same as in feed_screen)
class _ColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;

  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
  });
}

class _DarkColors extends _ColorSet {
  _DarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
        );
}

class _LightColors extends _ColorSet {
  _LightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.grey[100]!,
          cardColor: Colors.white,
          iconColor: Colors.grey[700]!,
        );
}

class CurrentUserProfileScreen extends StatefulWidget {
  final String uid;
  const CurrentUserProfileScreen({Key? key, required this.uid})
      : super(key: key);

  @override
  State<CurrentUserProfileScreen> createState() =>
      _CurrentUserProfileScreenState();
}

class _CurrentUserProfileScreenState extends State<CurrentUserProfileScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  var userData = {};
  int followers = 0;
  int following = 0;
  int postCount = 0;
  int viewCount = 0;
  List<dynamic> _followersList = [];
  List<dynamic> _followingList = [];
  bool isLoading = false;
  bool hasError = false;
  String errorMessage = '';
  final SupabaseProfileMethods _profileMethods = SupabaseProfileMethods();

  // Ad-related variables
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  // Helper method to get the appropriate color scheme
  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  @override
  void initState() {
    super.initState();
    getData();
    _fetchViewCount();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    BannerAd(
      adUnitId: AdHelper.currentProfileBannerAdUnitId,
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

  Future<void> _fetchViewCount() async {
    try {
      final count = await _profileMethods.getProfileViewCount(widget.uid);
      if (mounted) {
        setState(() {
          viewCount = count;
        });
      }
    } catch (e) {}
  }

  Future<void> getData() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      hasError = false;
      errorMessage = '';
    });

    try {
      final List<Future<dynamic>> queries = [
        _supabase.from('users').select().eq('uid', widget.uid).single(),
        _supabase.from('posts').select('postId').eq('uid', widget.uid),
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

      final userResponse = results[0];
      final postsResponse = results[1] as List;
      final followersResponse = results[2] as List;
      final followingResponse = results[3] as List;

      if (userResponse.isEmpty) {
        throw Exception('User data not found for UID: ${widget.uid}');
      }

      final processedData = await Future.wait([
        _processUserList(followersResponse, 'follower_id'),
        _processUserList(followingResponse, 'following_id'),
      ]);

      if (mounted) {
        setState(() {
          userData = userResponse;
          postCount = postsResponse.length;
          followers = followersResponse.length;
          following = followingResponse.length;
          _followersList = processedData[0];
          _followingList = processedData[1];
        });
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() {
          hasError = true;
          errorMessage = 'Failed to load profile data';
        });
        showSnackBar(
            context, "Please try again or contact us at ratedly9@gmail.com");
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<List<dynamic>> _processUserList(
      List<dynamic> userList, String idKey) async {
    if (userList.isEmpty) return [];

    final userIds = userList.map((user) => user[idKey] as String).toList();

    final usersData = await _supabase
        .from('users')
        .select('uid, username, photoUrl')
        .inFilter('uid', userIds);

    final userMap = {for (var user in usersData) user['uid'] as String: user};

    return userList
        .map((entry) {
          final userInfo = userMap[entry[idKey]];
          return userInfo != null
              ? {
                  'userId': entry[idKey],
                  'username': userInfo['username'],
                  'photoUrl': userInfo['photoUrl'],
                  'timestamp': entry['followed_at'],
                }
              : null;
        })
        .where((item) => item != null)
        .toList();
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: colors.textColor),
        backgroundColor: colors.backgroundColor,
        elevation: 0,
        title: Text(
          userData['username'] ?? 'Loading...',
          style:
              TextStyle(color: colors.textColor, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.menu, color: colors.textColor),
            onPressed: _navigateToSettings,
          )
        ],
      ),
      backgroundColor: colors.backgroundColor,
      body: hasError
          ? _buildErrorWidget(colors)
          : isLoading
              ? Center(
                  child: CircularProgressIndicator(color: colors.textColor))
              : Column(
                  children: [
                    // Banner Ad at the top
                    if (_isAdLoaded && _bannerAd != null)
                      Container(
                        width: double.infinity,
                        color: colors.backgroundColor,
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Divider(height: 1, color: colors.cardColor),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 50,
                              child: AdWidget(ad: _bannerAd!),
                            ),
                            const SizedBox(height: 6),
                            Divider(height: 1, color: colors.cardColor),
                          ],
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildProfileHeader(colors),
                              const SizedBox(height: 20),
                              Column(
                                children: [
                                  _buildBioSection(colors),
                                  Divider(color: colors.cardColor),
                                  _buildPostsGrid(colors),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildErrorWidget(_ColorSet colors) {
    return Center(
        child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.error_outline,
          color: colors.textColor,
          size: 64,
        ),
        const SizedBox(height: 16),
        Text(
          'Something went wrong',
          style: TextStyle(
            color: colors.textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          errorMessage,
          style: TextStyle(color: colors.textColor),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: getData,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.cardColor,
            foregroundColor: colors.textColor,
          ),
          child: const Text('Try Again'),
        ),
      ],
    ));
  }

  Widget _buildProfileHeader(_ColorSet colors) {
    return Column(
      children: [
        SizedBox(
          height: 80,
          child: Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: colors.cardColor,
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
                      size: 80,
                      color: colors.textColor,
                    )
                  : null,
            ),
          ),
        ),
        Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildMetric(postCount, "Posts", colors.textColor),
                  _buildInteractiveMetric(
                      followers, "Followers", _followersList, colors),
                  _buildInteractiveMetric(
                      following, "Following", _followingList, colors),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Center(
              child: _buildEditProfileButton(colors),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInteractiveMetric(
      int value, String label, List<dynamic> userList, _ColorSet colors) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserListScreen(
            title: label,
            userEntries: userList,
          ),
        ),
      ),
      child: _buildMetric(value, label, colors.textColor),
    );
  }

  Widget _buildEditProfileButton(_ColorSet colors) {
    return ElevatedButton(
      onPressed: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EditProfileScreen()),
        );

        if (result != null && mounted) {
          setState(() {
            userData['bio'] = result['bio'] ?? userData['bio'];
            userData['photoUrl'] = result['photoUrl'] ?? userData['photoUrl'];
          });

          await getData();
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.cardColor,
        foregroundColor: colors.textColor,
      ),
      child: const Text("Edit Profile"),
    );
  }

  Future<void> _forceRefresh() async {
    await getData();
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildMetric(int value, String label, Color textColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w400, color: textColor),
        ),
      ],
    );
  }

  Widget _buildBioSection(_ColorSet colors) {
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
          Text(
            userData['bio'] ?? '',
            style: TextStyle(color: colors.textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsGrid(_ColorSet colors) {
    return FutureBuilder<List<dynamic>>(
      future: _supabase
          .from('posts')
          .select()
          .eq('uid', widget.uid)
          .order('datePublished', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(color: colors.textColor));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to load posts',
              style: TextStyle(color: colors.textColor),
            ),
          );
        }
        final posts = snapshot.data ?? [];
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: posts.length + 1,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 5,
              mainAxisSpacing: 1.5,
              childAspectRatio: 1),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildAddPostButton(colors);
            }
            final postIndex = index - 1;
            if (postIndex < 0 || postIndex >= posts.length) return Container();
            final post = posts[postIndex];
            return _buildPostItem(post);
          },
        );
      },
    );
  }

  Widget _buildAddPostButton(_ColorSet colors) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddPostScreen(
            onPostUploaded: _forceRefresh,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: colors.cardColor,
        ),
        child: Icon(
          Icons.add_circle_outline,
          size: 40,
          color: colors.textColor,
        ),
      ),
    );
  }

  Widget _buildPostItem(Map<String, dynamic> post) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageViewScreen(
            imageUrl: post['postUrl'],
            postId: post['postId'],
            description: post['description'],
            userId: post['uid'],
            username: userData['username'] ?? '',
            profImage: userData['photoUrl'] ?? '',
            onPostDeleted: _forceRefresh,
            datePublished: post['datePublished'],
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          image: DecorationImage(
            image: NetworkImage(post['postUrl']),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }
}
