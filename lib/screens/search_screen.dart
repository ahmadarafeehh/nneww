import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:Ratedly/screens/Profile_page/image_screen.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:Ratedly/services/ads.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:video_player/video_player.dart';

// Define color schemes for both themes at top level
class _SearchColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;
  final Color dividerColor;
  final Color progressIndicatorColor;
  final Color errorColor;
  final Color gridBackgroundColor;
  final Color gridItemBackgroundColor;
  final Color appBarBackgroundColor;
  final Color hintTextColor;
  final Color borderColor;
  final Color focusedBorderColor;

  _SearchColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
    required this.dividerColor,
    required this.progressIndicatorColor,
    required this.errorColor,
    required this.gridBackgroundColor,
    required this.gridItemBackgroundColor,
    required this.appBarBackgroundColor,
    required this.hintTextColor,
    required this.borderColor,
    required this.focusedBorderColor,
  });
}

class _SearchDarkColors extends _SearchColorSet {
  _SearchDarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF121212),
          iconColor: const Color(0xFFd9d9d9),
          dividerColor: const Color(0xFF333333),
          progressIndicatorColor: const Color(0xFFd9d9d9),
          errorColor: Colors.red,
          gridBackgroundColor: const Color(0xFF121212),
          gridItemBackgroundColor: const Color(0xFF333333),
          appBarBackgroundColor: const Color(0xFF121212),
          hintTextColor: const Color(0xFF666666),
          borderColor: const Color(0xFF333333),
          focusedBorderColor: const Color(0xFFd9d9d9),
        );
}

class _SearchLightColors extends _SearchColorSet {
  _SearchLightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.grey[100]!,
          cardColor: Colors.white,
          iconColor: Colors.grey[700]!,
          dividerColor: Colors.grey[300]!,
          progressIndicatorColor: Colors.grey[700]!,
          errorColor: Colors.red,
          gridBackgroundColor: Colors.grey[100]!,
          gridItemBackgroundColor: Colors.grey[300]!,
          appBarBackgroundColor: Colors.grey[100]!,
          hintTextColor: Colors.grey[600]!,
          borderColor: Colors.grey[400]!,
          focusedBorderColor: Colors.black,
        );
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController searchController = TextEditingController();
  final _supabase = Supabase.instance.client;
  bool isShowUsers = false;
  bool _isSearchFocused = false;
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;

  List<Map<String, dynamic>> _allPosts = [];
  Set<String> blockedUsersSet = {};
  bool _isLoading = true;

  // Ad-related variables
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  // Pagination helpers
  int _offset = 0;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  final int _postsLimit = 20;

  // Scroll controller
  final ScrollController _scrollController = ScrollController();

  // Suggested users
  List<String> _rotatedSuggestedUsers = [];
  final Random _random = Random();

  // Video player controllers cache
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, bool> _videoControllersInitialized = {};

  // Helper method to get the appropriate color scheme
  _SearchColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _SearchDarkColors() : _SearchLightColors();
  }

  @override
  void initState() {
    super.initState();
    _initData();
    _loadBannerAd();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 300 &&
          !_isLoadingMore &&
          _hasMorePosts &&
          !isShowUsers) {
        _loadMorePosts();
      }
    });
  }

  void _loadBannerAd() {
    BannerAd(
      adUnitId: AdHelper.searchBannerAdUnitId,
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

  @override
  void dispose() {
    searchController.dispose();
    _scrollController.dispose();
    _bannerAd?.dispose();

    // Dispose all video controllers
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    _videoControllers.clear();
    _videoControllersInitialized.clear();

    super.dispose();
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

  Widget _buildVideoPlayer(String videoUrl, _SearchColorSet colors) {
    final controller = _getVideoController(videoUrl);
    final isInitialized = _isVideoControllerInitialized(videoUrl);

    if (!isInitialized || controller == null) {
      return Center(
        child: CircularProgressIndicator(
          color: colors.progressIndicatorColor,
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

  Future<void> _initData() async {
    await _loadBlockedUsers();
    await _fetchPosts();
    _rotateSuggestedUsers();
    setState(() => _isLoading = false);
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final response = await _supabase
          .from('users')
          .select('blockedUsers')
          .eq('uid', currentUserId)
          .single();

      final blockedUsers = response['blockedUsers'] as List<dynamic>?;
      blockedUsersSet = Set<String>.from(blockedUsers ?? []);
    } catch (e) {
      blockedUsersSet = {};
    }
  }

  Future<void> _fetchPosts() async {
    try {
      final excludedUsers = [...blockedUsersSet, currentUserId];

      final response = await _supabase.rpc('get_search_feed', params: {
        'current_user_id': currentUserId,
        'excluded_users': excludedUsers,
        'page_offset': 0,
        'page_limit': _postsLimit,
      });

      if (response is List && response.isNotEmpty) {
        _allPosts = response.map<Map<String, dynamic>>((post) {
          final Map<String, dynamic> convertedPost = {};
          (post as Map).forEach((key, value) {
            convertedPost[key.toString()] = value;
          });
          return convertedPost;
        }).toList();

        _offset = _allPosts.length;
        _hasMorePosts = _allPosts.length == _postsLimit;
      } else {
        _allPosts = [];
        _hasMorePosts = false;
      }
    } catch (e) {
      _allPosts = [];
      _hasMorePosts = false;
    }
  }

  Future<void> _loadMorePosts() async {
    if (!_hasMorePosts || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final excludedUsers = [...blockedUsersSet, currentUserId];

      final response = await _supabase.rpc('get_search_feed', params: {
        'current_user_id': currentUserId,
        'excluded_users': excludedUsers,
        'page_offset': _offset ~/ _postsLimit,
        'page_limit': _postsLimit,
      });

      if (response is List && response.isNotEmpty) {
        final newPosts = response.map<Map<String, dynamic>>((post) {
          final Map<String, dynamic> convertedPost = {};
          (post as Map).forEach((key, value) {
            convertedPost[key.toString()] = value;
          });
          return convertedPost;
        }).toList();

        setState(() {
          _allPosts.addAll(newPosts);
          _offset += newPosts.length;
          _hasMorePosts = newPosts.length == _postsLimit;
        });
      } else {
        setState(() => _hasMorePosts = false);
      }
    } catch (e) {
      setState(() => _hasMorePosts = false);
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }

  void _rotateSuggestedUsers() {
    final suggestedUserIds = _allPosts
        .map((post) => post['uid']?.toString())
        .whereType<String>()
        .where((uid) => !blockedUsersSet.contains(uid) && uid != currentUserId)
        .toSet()
        .toList();

    if (suggestedUserIds.isEmpty) {
      _rotatedSuggestedUsers = [];
      return;
    }

    suggestedUserIds.shuffle(_random);
    _rotatedSuggestedUsers = suggestedUserIds.take(5).toList();
  }

  // SIMPLIFIED: Faster navigation without extra checks
  void _navigateToProfile(String uid) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfileScreen(uid: uid)),
    ).then((_) {
      if (mounted) {
        setState(() {
          isShowUsers = false;
          searchController.clear();
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> _fetchUsersByIds(
      List<String> userIds) async {
    if (userIds.isEmpty) return [];

    try {
      final response =
          await _supabase.from('users').select().inFilter('uid', userIds);

      final users = List<Map<String, dynamic>>.from(response);

      // Simple filter - remove blocked users and current user
      return users.where((user) {
        final userId = user['uid']?.toString() ?? '';
        return !blockedUsersSet.contains(userId) && userId != currentUserId;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _searchUsers(String query) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .ilike('username', '$query%')
          .limit(15);

      final users = List<Map<String, dynamic>>.from(response);

      // Simple filter
      return users.where((user) {
        final userId = user['uid']?.toString() ?? '';
        return !blockedUsersSet.contains(userId) && userId != currentUserId;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: colors.progressIndicatorColor))
          : Column(
              children: [
                if (_isAdLoaded && _bannerAd != null)
                  Container(
                    width: double.infinity,
                    color: colors.backgroundColor,
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Divider(height: 1, color: colors.dividerColor),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 50,
                          child: AdWidget(ad: _bannerAd!),
                        ),
                        const SizedBox(height: 6),
                        Divider(height: 1, color: colors.dividerColor),
                      ],
                    ),
                  ),
                Expanded(
                  child:
                      _isSearchFocused && searchController.text.trim().isEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(top: 15.0),
                              child: _buildSuggestedUsers(colors),
                            )
                          : isShowUsers
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 15.0),
                                  child: _buildUserSearch(colors),
                                )
                              : _buildPostsGrid(colors),
                ),
              ],
            ),
      appBar: AppBar(
        backgroundColor: colors.appBarBackgroundColor,
        toolbarHeight: 80,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.iconColor),
        title: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: SizedBox(
            height: 48,
            child: TextFormField(
              controller: searchController,
              style: TextStyle(color: colors.textColor),
              decoration: InputDecoration(
                hintText: 'Search for a user...',
                hintStyle: TextStyle(color: colors.hintTextColor),
                filled: true,
                fillColor: colors.cardColor,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.borderColor),
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: colors.focusedBorderColor, width: 2),
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
              onTap: () {
                if (searchController.text.trim().isEmpty) {
                  setState(() {
                    isShowUsers = false;
                    _isSearchFocused = true;
                  });
                }
              },
              onChanged: (value) {
                setState(() {
                  isShowUsers = value.trim().isNotEmpty;
                  _isSearchFocused = false;
                });
              },
              onFieldSubmitted: (_) {
                setState(() {
                  isShowUsers = true;
                  _isSearchFocused = false;
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestedUsers(_SearchColorSet colors) {
    if (_rotatedSuggestedUsers.isEmpty) {
      return Center(
        child: Text('No suggestions available.',
            style: TextStyle(color: colors.textColor)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            'Suggested users',
            style: TextStyle(
                color: colors.textColor.withOpacity(0.7),
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchUsersByIds(_rotatedSuggestedUsers),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(
                        color: colors.progressIndicatorColor));
              }

              final users = snapshot.data ?? [];

              if (users.isEmpty) {
                return Center(
                    child: Text('No suggestions found.',
                        style: TextStyle(color: colors.textColor)));
              }

              return ListView.builder(
                padding: const EdgeInsets.only(top: 8),
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  final userId = user['uid'] as String? ?? '';

                  return ListTile(
                    onTap: () => _navigateToProfile(userId),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: CircleAvatar(
                      backgroundColor: colors.gridItemBackgroundColor,
                      backgroundImage: (user['photoUrl'] != null &&
                              user['photoUrl'] != "default")
                          ? NetworkImage(user['photoUrl'])
                          : null,
                      radius: 20,
                      child: (user['photoUrl'] == null ||
                              user['photoUrl'] == "default")
                          ? Icon(Icons.account_circle,
                              size: 40, color: colors.iconColor)
                          : null,
                    ),
                    title: Text(
                      user['username']?.toString() ?? 'Unknown',
                      style: TextStyle(color: colors.textColor),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUserSearch(_SearchColorSet colors) {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      return Center(
          child: Text('Please enter a username.',
              style: TextStyle(color: colors.textColor)));
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _searchUsers(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                  color: colors.progressIndicatorColor));
        }

        final users = snapshot.data ?? [];

        if (users.isEmpty) {
          return Center(
              child: Text('No users found.',
                  style: TextStyle(color: colors.textColor)));
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final userId = user['uid'] as String? ?? '';

            return ListTile(
              onTap: () => _navigateToProfile(userId),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: CircleAvatar(
                backgroundColor: colors.gridItemBackgroundColor,
                backgroundImage:
                    (user['photoUrl'] != null && user['photoUrl'] != "default")
                        ? NetworkImage(user['photoUrl'])
                        : null,
                radius: 20,
                child:
                    (user['photoUrl'] == null || user['photoUrl'] == "default")
                        ? Icon(Icons.account_circle,
                            size: 40, color: colors.iconColor)
                        : null,
              ),
              title: Text(
                user['username']?.toString() ?? 'Unknown',
                style: TextStyle(color: colors.textColor),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPostsGrid(_SearchColorSet colors) {
    if (_allPosts.isEmpty) {
      return Center(
        child:
            Text('No posts found.', style: TextStyle(color: colors.textColor)),
      );
    }

    final topPosts =
        _allPosts.length >= 3 ? _allPosts.sublist(0, 3) : _allPosts;
    final remainingPosts = _allPosts.length > 3 ? _allPosts.sublist(3) : [];

    return Stack(
      children: [
        ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(8.0),
          children: [
            if (topPosts.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Divider(color: colors.dividerColor),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            'Top posts for this week 🏆',
                            style: TextStyle(
                              color: colors.textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(color: colors.dividerColor),
                        ),
                      ],
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 1,
                      crossAxisSpacing: 8.0,
                      mainAxisSpacing: 8.0,
                    ),
                    itemCount: topPosts.length,
                    itemBuilder: (context, index) {
                      final post = topPosts[index];
                      final postUrl = post['postUrl']?.toString() ?? '';
                      return _buildPostItem(post, postUrl, colors, true);
                    },
                  ),
                  if (remainingPosts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Divider(color: colors.dividerColor),
                    ),
                ],
              ),
            if (remainingPosts.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1,
                  crossAxisSpacing: 8.0,
                  mainAxisSpacing: 8.0,
                ),
                itemCount: remainingPosts.length,
                itemBuilder: (context, index) {
                  final post = remainingPosts[index];
                  final postUrl = post['postUrl']?.toString() ?? '';
                  return _buildPostItem(post, postUrl, colors, false);
                },
              ),
          ],
        ),
        if (_isLoadingMore)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.backgroundColor.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CircularProgressIndicator(
                  color: colors.progressIndicatorColor,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPostItem(Map<String, dynamic> post, String postUrl,
      _SearchColorSet colors, bool isTopPost) {
    final isVideo = _isVideoFile(postUrl);

    // Start initialization if it's a video
    if (isVideo) {
      _initializeVideoController(postUrl);
    }

    return InkWell(
      onTap: () async {
        final userId = post['uid']?.toString() ?? '';
        if (userId.isEmpty) return;

        final user = await _fetchUserById(userId);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageViewScreen(
              imageUrl: postUrl,
              postId: post['postId'],
              description: post['description']?.toString() ?? '',
              userId: userId,
              username: user?['username']?.toString() ?? '',
              profImage: user?['photoUrl']?.toString() ?? '',
              datePublished: post['datePublished'],
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.gridItemBackgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: isTopPost ? Border.all(color: Colors.amber, width: 2) : null,
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            if (postUrl.isNotEmpty)
              isVideo
                  ? _buildVideoPlayer(postUrl, colors)
                  : Image.network(
                      postUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            color: colors.progressIndicatorColor,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.broken_image,
                            color: colors.iconColor);
                      },
                    )
            else
              Icon(Icons.broken_image, color: colors.iconColor),
            if (isTopPost)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.emoji_events,
                    color: Colors.amber,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchUserById(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('uid', userId)
          .maybeSingle();
      return response as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }
}
