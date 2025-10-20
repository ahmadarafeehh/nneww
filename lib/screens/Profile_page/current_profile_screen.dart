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
import 'package:video_player/video_player.dart';
import 'package:flutter/gestures.dart';

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

class ExpandableBioText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color expandColor;
  final int maxLength;

  const ExpandableBioText({
    Key? key,
    required this.text,
    required this.style,
    required this.expandColor,
    this.maxLength = 115,
  }) : super(key: key);

  @override
  State<ExpandableBioText> createState() => _ExpandableBioTextState();
}

class _ExpandableBioTextState extends State<ExpandableBioText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final shouldTruncate = widget.text.length > widget.maxLength;

    if (!shouldTruncate || _isExpanded) {
      return Text(
        widget.text,
        style: widget.style,
      );
    }

    final truncatedText = widget.text.substring(0, widget.maxLength);

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$truncatedText... ',
            style: widget.style,
          ),
          TextSpan(
            text: 'more',
            style: widget.style.copyWith(
              color: widget.expandColor,
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                setState(() {
                  _isExpanded = true;
                });
              },
          ),
        ],
      ),
    );
  }
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

  // Video player controllers cache
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, bool> _videoControllersInitialized = {};

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
          ad.dispose();
        },
      ),
    ).load();
  }

  // -------------------------
  // Video player logic for first-second looping
  // -------------------------

  /// Initialize video controller for a video URL - only loads first second
  Future<void> _initializeVideoController(String videoUrl) async {
    if (_videoControllers.containsKey(videoUrl) ||
        _videoControllersInitialized[videoUrl] == true) {
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
        ),
      );

      // Store controller immediately to prevent duplicate initializations
      _videoControllers[videoUrl] = controller;
      _videoControllersInitialized[videoUrl] = false;

      // Set up listener for initialization
      controller.addListener(() {
        if (controller.value.isInitialized &&
            !_videoControllersInitialized[videoUrl]!) {
          _videoControllersInitialized[videoUrl] = true;

          // Configure the video to play only the first second on loop
          _configureVideoLoop(controller);

          if (mounted) {
            setState(() {});
          }
        }
      });

      // Initialize the controller but don't wait for full load
      await controller.initialize();

      // Mute the video
      await controller.setVolume(0.0);
    } catch (e) {
      // Clean up on error
      _videoControllers.remove(videoUrl)?.dispose();
      _videoControllersInitialized.remove(videoUrl);
    }
  }

  /// Configure video to play only first second on loop
  void _configureVideoLoop(VideoPlayerController controller) {
    final duration = controller.value.duration;

    // Determine the end position (1 second or video duration if shorter)
    final endPosition =
        duration.inSeconds > 0 ? const Duration(seconds: 1) : duration;

    // Set up position listener to create loop effect for first second
    controller.addListener(() {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        final currentPosition = controller.value.position;
        if (currentPosition >= endPosition) {
          // Loop back to start
          controller.seekTo(Duration.zero);
        }
      }
    });

    // Start playing
    controller.play();
  }

  /// Get video controller for a URL, initializing if needed
  VideoPlayerController? _getVideoController(String videoUrl) {
    return _videoControllers[videoUrl];
  }

  /// Check if video controller is initialized
  bool _isVideoControllerInitialized(String videoUrl) {
    return _videoControllersInitialized[videoUrl] == true;
  }

  // Helper method to detect video files by extension
  bool _isVideoFile(String url) {
    if (url.isEmpty) return false;

    final lowerUrl = url.toLowerCase();
    return lowerUrl.endsWith('.mp4') ||
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
  }

  Widget _buildVideoPlayer(String videoUrl, _ColorSet colors) {
    final controller = _getVideoController(videoUrl);
    final isInitialized = _isVideoControllerInitialized(videoUrl);

    if (!isInitialized || controller == null) {
      return Container(
        color: colors.cardColor,
        child: Center(
          child: CircularProgressIndicator(
            color: colors.textColor,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  // -------------------------
  // End video player logic
  // -------------------------

  // -------------------------
  // Placeholder Methods
  // -------------------------

  Widget _buildProfileSkeleton(_ColorSet colors) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildProfileHeaderSkeleton(colors),
            const SizedBox(height: 20),
            Column(
              children: [
                _buildBioSectionSkeleton(colors),
                const SizedBox(height: 16),
                Divider(color: colors.cardColor),
                _buildPostsGridSkeleton(colors),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeaderSkeleton(_ColorSet colors) {
    return Column(
      children: [
        // Profile picture skeleton
        SizedBox(
          height: 80,
          child: Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.cardColor.withOpacity(0.6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Metrics skeleton
        SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMetricSkeleton(colors),
              _buildMetricSkeleton(colors),
              _buildMetricSkeleton(colors),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Edit profile button skeleton
        Container(
          width: 120,
          height: 36,
          decoration: BoxDecoration(
            color: colors.cardColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricSkeleton(_ColorSet colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          height: 16,
          width: 30,
          decoration: BoxDecoration(
            color: colors.cardColor.withOpacity(0.8),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 12,
          width: 50,
          decoration: BoxDecoration(
            color: colors.cardColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _buildBioSectionSkeleton(_ColorSet colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Username skeleton
          Container(
            height: 18,
            width: 120,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.8),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          // Bio lines skeleton
          Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 14,
            width: 250,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 14,
            width: 200,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsGridSkeleton(_ColorSet colors) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 7, // 6 posts + 1 add button
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 5,
        mainAxisSpacing: 1.5,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: colors.cardColor.withOpacity(0.5),
          ),
        );
      },
    );
  }

  Widget _buildErrorWidgetSkeleton(_ColorSet colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.cardColor.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 20,
            width: 200,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 16,
            width: 150,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 100,
            height: 40,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------
  // End Placeholder Methods
  // -------------------------

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

      final userResponse = results[0];
      final postsResponse = results[1] as List;
      final followersResponse = results[2] as List;
      final followingResponse = results[3] as List;

      if (userResponse.isEmpty) {
        throw Exception('User data not found for UID: ${widget.uid}');
      }

      // Pre-initialize video controllers for video posts
      for (final post in postsResponse) {
        final postUrl = post['postUrl'] ?? '';
        if (_isVideoFile(postUrl)) {
          _initializeVideoController(postUrl);
        }
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
        title: isLoading
            ? Container(
                height: 16,
                width: 120,
                decoration: BoxDecoration(
                  color: colors.cardColor.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
              )
            : Text(
                userData['username'] ?? 'Loading...',
                style: TextStyle(
                    color: colors.textColor, fontWeight: FontWeight.bold),
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
              ? _buildProfileSkeleton(colors)
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
    final String bio = userData['bio'] ?? '';

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
          if (bio.isNotEmpty)
            ExpandableBioText(
              text: bio,
              style: TextStyle(color: colors.textColor),
              expandColor: colors.textColor.withOpacity(0.8),
            ),
        ],
      ),
    );
  }

  Widget _buildPostsGrid(_ColorSet colors) {
    return FutureBuilder<List<dynamic>>(
      future: _supabase
          .from('posts')
          .select('postId, postUrl, description, uid, datePublished')
          .eq('uid', widget.uid)
          .order('datePublished', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildPostsGridSkeleton(colors);
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
            return _buildPostItem(post, colors);
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

  Widget _buildPostItem(Map<String, dynamic> post, _ColorSet colors) {
    final postUrl = post['postUrl'] ?? '';
    final isVideo = _isVideoFile(postUrl);

    // Start initialization if it's a video
    if (isVideo) {
      _initializeVideoController(postUrl);
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageViewScreen(
            imageUrl: postUrl,
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
          color: isVideo ? colors.cardColor : null,
        ),
        child: isVideo
            ? _buildVideoPlayer(postUrl, colors)
            : Image.network(
                postUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: colors.cardColor,
                    child: Icon(
                      Icons.broken_image,
                      color: colors.iconColor,
                    ),
                  );
                },
              ),
      ),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();

    // Dispose all video controllers
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    _videoControllers.clear();
    _videoControllersInitialized.clear();

    super.dispose();
  }
}
