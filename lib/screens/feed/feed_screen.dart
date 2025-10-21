// lib/screens/feed/feed_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/global_variable.dart';
import 'package:Ratedly/screens/feed/post_card.dart';
import 'package:Ratedly/screens/comment_screen.dart';
import 'package:Ratedly/widgets/guidelines_popup.dart';
import 'package:Ratedly/widgets/feedmessages.dart';
import 'package:Ratedly/services/ads.dart';
import 'package:Ratedly/utils/theme_provider.dart';

// Define color schemes for both themes at top level
class _ColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;
  final Color skeletonColor;
  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
    required this.skeletonColor,
  });
}

class _DarkColors extends _ColorSet {
  _DarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
          skeletonColor: const Color(0xFF333333).withOpacity(0.6),
        );
}

class _LightColors extends _ColorSet {
  _LightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.grey[100]!,
          cardColor: Colors.white,
          iconColor: Colors.grey[700]!,
          skeletonColor: Colors.grey[300]!.withOpacity(0.6),
        );
}

class FeedScreen extends StatefulWidget {
  const FeedScreen({Key? key}) : super(key: key);

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late String currentUserId;
  int _selectedTab = 1;

  // Replace ScrollControllers with PageControllers for TikTok-style vertical scrolling
  late PageController _followingPageController;
  late PageController _forYouPageController;

  List<Map<String, dynamic>> _followingPosts = [];
  List<Map<String, dynamic>> _forYouPosts = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _offsetFollowing = 0;
  int _offsetForYou = 0;
  bool _hasMoreFollowing = true;
  bool _hasMoreForYou = true;

  Timer? _guidelinesTimer;
  bool _isPopupShown = false;
  List<String> _blockedUsers = [];
  List<String> _followingIds = [];
  bool _viewRecordingScheduled = false;
  final Set<String> _pendingViews = {};

  // Track current page for each tab
  int _currentForYouPage = 0;
  int _currentFollowingPage = 0;
  final Map<String, bool> _postVisibility = {};
  String? _currentPlayingPostId;

  // Ad-related variables
  InterstitialAd? _interstitialAd;
  int _postViewCount = 0;
  DateTime? _lastInterstitialAdTime;

  Stream<int>? _unreadCountStream;
  StreamController<int>? _unreadCountController;
  Timer? _unreadCountTimer;

  // FAST CACHING: Similar to search screen
  final Map<String, Map<String, dynamic>> _userCache = {};
  static final Map<String, List<String>> _blockedUsersCache = {};
  static DateTime? _lastBlockedUsersCacheTime;

  // Helper method to get the appropriate color scheme
  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  // FAST UNWRAP: Same as search screen
  dynamic _unwrapResponse(dynamic res) {
    if (res == null) return null;
    if (res is Map && res.containsKey('data')) return res['data'];
    return res;
  }

  void _pauseCurrentVideo() {
    // Simple pause method - you can implement this based on your VideoManager
    _currentPlayingPostId = null;
  }

  void _scheduleViewRecording(String postId) {
    _pendingViews.add(postId);
    if (!_viewRecordingScheduled) {
      _viewRecordingScheduled = true;
      Future.delayed(const Duration(seconds: 1), _recordPendingViews);
    }
  }

  Future<void> _recordPendingViews() async {
    if (_pendingViews.isEmpty || !mounted) {
      _viewRecordingScheduled = false;
      return;
    }

    final viewsToRecord = _pendingViews.toList();
    _pendingViews.clear();

    try {
      await _supabase.from('user_post_views').upsert(
            viewsToRecord
                .map((postId) => {
                      'user_id': currentUserId,
                      'post_id': postId,
                      'viewed_at': DateTime.now().toUtc().toIso8601String(),
                    })
                .toList(),
          );

      setState(() {
        _postViewCount += viewsToRecord.length;
      });

      if (_postViewCount >= 10) {
        _showInterstitialAd();
        _postViewCount = 0;
      }
    } catch (e) {
      // Handle error silently
    } finally {
      _viewRecordingScheduled = false;
    }
  }

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Initialize PageControllers for TikTok-style vertical scrolling
    _followingPageController = PageController();
    _forYouPageController = PageController();
    _unreadCountStream = _createUnreadCountStream();
    _loadInitialData();
    _startGuidelinesTimer();
    _loadInterstitialAd();
  }

  // FIXED STREAM: Using broadcast stream to prevent multiple listeners error
  Stream<int> _createUnreadCountStream() {
    _unreadCountController = StreamController<int>.broadcast();

    if (currentUserId.isEmpty) {
      _unreadCountController!.add(0);
      return _unreadCountController!.stream;
    }

    // Start periodic updates
    _unreadCountTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final data = await _supabase
            .from('messages')
            .select('id')
            .eq('receiver_id', currentUserId)
            .eq('is_read', false);

        final int count = (data is List) ? data.length : 0;
        if (_unreadCountController != null &&
            !_unreadCountController!.isClosed) {
          _unreadCountController!.add(count);
        }
      } catch (e) {
        if (_unreadCountController != null &&
            !_unreadCountController!.isClosed) {
          _unreadCountController!.add(0);
        }
      }
    });

    // Initial data
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final data = await _supabase
            .from('messages')
            .select('id')
            .eq('receiver_id', currentUserId)
            .eq('is_read', false);

        final int count = (data is List) ? data.length : 0;
        if (_unreadCountController != null &&
            !_unreadCountController!.isClosed) {
          _unreadCountController!.add(count);
        }
      } catch (e) {
        if (_unreadCountController != null &&
            !_unreadCountController!.isClosed) {
          _unreadCountController!.add(0);
        }
      }
    });

    return _unreadCountController!.stream;
  }

  // FAST USER BULK FETCH: Similar to search screen
  Future<void> _bulkFetchUsers(List<Map<String, dynamic>> posts) async {
    final Set<String> userIds = {};

    // Collect all unique user IDs from posts
    for (final post in posts) {
      final userId = post['uid']?.toString() ?? '';
      if (userId.isNotEmpty && !_userCache.containsKey(userId)) {
        userIds.add(userId);
      }
    }

    if (userIds.isEmpty) return;

    try {
      final response = await _supabase
          .from('users')
          .select('uid, username, photoUrl')
          .inFilter('uid', userIds.toList());

      if (response.isNotEmpty) {
        for (final user in response) {
          final userMap = Map<String, dynamic>.from(user);
          _userCache[userMap['uid']] = userMap;
        }
      }
    } catch (e) {}
  }

  void _updatePostVisibility(int page, List<Map<String, dynamic>> posts) {
    if (!mounted || posts.isEmpty) return;

    final previouslyPlayingPostId = _currentPlayingPostId;

    setState(() {
      // Clear all visibility first
      for (final post in posts) {
        final postId = post['postId']?.toString() ?? '';
        if (postId.isNotEmpty) {
          _postVisibility[postId] = false;
        }
      }

      // Set current page as the ONLY truly visible post for video playback
      if (page < posts.length) {
        final currentPost = posts[page];
        final postId = currentPost['postId']?.toString() ?? '';
        if (postId.isNotEmpty) {
          _postVisibility[postId] = true;
          _currentPlayingPostId = postId;
          _scheduleViewRecording(postId);
        }
      }

      // Set adjacent posts as "visible" only for preloading content
      if (page > 0) {
        final previousPost = posts[page - 1];
        final previousPostId = previousPost['postId']?.toString() ?? '';
        if (previousPostId.isNotEmpty) {
          _postVisibility[previousPostId] = true;
        }
      }

      if (page < posts.length - 1) {
        final nextPost = posts[page + 1];
        final nextPostId = nextPost['postId']?.toString() ?? '';
        if (nextPostId.isNotEmpty) {
          _postVisibility[nextPostId] = true;
        }
      }
    });

    // If we changed the playing post, pause the previous one
    if (previouslyPlayingPostId != null &&
        previouslyPlayingPostId != _currentPlayingPostId) {
      // You can implement this if you have a VideoManager with this method
      // VideoManager().onPostInvisible(previouslyPlayingPostId);
    }
  }

  void _onPageChanged(int page, bool isForYou) {
    if (isForYou) {
      _currentForYouPage = page;
      _updatePostVisibility(page, _forYouPosts);
    } else {
      _currentFollowingPage = page;
      _updatePostVisibility(page, _followingPosts);
    }

    // Load more data when approaching the end
    final currentPosts = isForYou ? _forYouPosts : _followingPosts;
    final hasMore = isForYou ? _hasMoreForYou : _hasMoreFollowing;
    if (page >= currentPosts.length - 3 && hasMore && !_isLoadingMore) {
      _loadData(loadMore: true);
    }
  }

  // Method to open comments with transparent overlay
  void _openComments(BuildContext context, Map<String, dynamic> post) {
    final postId = post['postId']?.toString() ?? '';
    final isVideo = post['isVideo'] == true;
    final postImage = post['postUrl']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor:
          Colors.black.withOpacity(0.4), // Reduced opacity for more visibility
      isDismissible: true,
      enableDrag: true,
      builder: (context) => CommentsBottomSheet(
        postId: postId,
        postImage: postImage,
        isVideo: isVideo,
        onClose: () {},
        // The videoController will be passed from PostCard
      ),
    );
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdHelper.feedInterstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              ad.dispose();
              _loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent:
                (InterstitialAd ad, AdError error) {
              ad.dispose();
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          Future.delayed(const Duration(seconds: 30), () {
            _loadInterstitialAd();
          });
        },
      ),
    );
  }

  void _showInterstitialAd() {
    final now = DateTime.now();
    if (_lastInterstitialAdTime != null &&
        now.difference(_lastInterstitialAdTime!) <
            const Duration(minutes: 10)) {
      return;
    }

    if (_interstitialAd != null) {
      _interstitialAd!.show();
      _lastInterstitialAdTime = now;
    } else {
      _loadInterstitialAd();
    }
  }

  void _startGuidelinesTimer() {
    _guidelinesTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isPopupShown) {
        _checkAndShowGuidelines();
      }
    });
  }

  void _checkAndShowGuidelines() async {
    final prefs = await SharedPreferences.getInstance();
    final bool agreed =
        prefs.getBool('agreed_to_guidelines_$currentUserId') ?? false;
    final bool dontShow =
        prefs.getBool('dont_show_again_$currentUserId') ?? false;

    if (!(agreed && dontShow)) {
      _showGuidelinesPopup();
    } else {
      _guidelinesTimer?.cancel();
    }
  }

  // FAST BLOCKED USERS: Using cache like search screen
  Future<void> _loadBlockedUsers() async {
    final now = DateTime.now();
    // Check cache first
    if (_blockedUsersCache[currentUserId] != null &&
        _lastBlockedUsersCacheTime != null &&
        now.difference(_lastBlockedUsersCacheTime!) < Duration(minutes: 5)) {
      _blockedUsers = _blockedUsersCache[currentUserId]!;
      return;
    }

    try {
      final userResponseRaw = await _supabase
          .from('users')
          .select('blockedUsers')
          .eq('uid', currentUserId)
          .maybeSingle();

      final userResponse = _unwrapResponse(userResponseRaw);
      if (userResponse != null && userResponse is Map) {
        final blocked = userResponse['blockedUsers'];
        if (blocked is List) {
          _blockedUsers = blocked.map((e) => e.toString()).toList();
        } else if (blocked is String) {
          try {
            final parsed = jsonDecode(blocked) as List;
            _blockedUsers = parsed.map((e) => e.toString()).toList();
          } catch (_) {
            _blockedUsers = [];
          }
        } else {
          _blockedUsers = [];
        }
      } else {
        _blockedUsers = [];
      }

      // Update cache
      _blockedUsersCache[currentUserId] = _blockedUsers;
      _lastBlockedUsersCacheTime = now;
    } catch (e) {
      _blockedUsers = [];
    }
  }

  // FAST FOLLOWING: Minimal query
  Future<void> _loadFollowingIds() async {
    try {
      final followingResponseRaw = await _supabase
          .from('user_following')
          .select('following_id')
          .eq('user_id', currentUserId);

      final followingResponse = _unwrapResponse(followingResponseRaw);
      if (followingResponse is List) {
        _followingIds = followingResponse
            .map((row) => row['following_id'].toString())
            .toList();
      } else {
        _followingIds = [];
      }
    } catch (e) {
      _followingIds = [];
    }
  }

  // FAST INITIAL LOAD: Parallel loading like search screen
  Future<void> _loadInitialData() async {
    if (!mounted) return;

    try {
      currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

      if (currentUserId.isEmpty) {
        _blockedUsers = [];
        _followingIds = [];
        await _loadData();
        return;
      }

      // PARALLEL LOADING: Same pattern as search screen
      await Future.wait([
        _loadBlockedUsers(),
        _loadFollowingIds(),
      ]);

      await _loadData();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showGuidelinesPopup() {
    if (!mounted) return;
    setState(() => _isPopupShown = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => GuidelinesPopup(
        userId: currentUserId,
        onAgreed: () {},
      ),
    ).then((_) {
      if (mounted) setState(() => _isPopupShown = false);
    });
  }

  // FAST DATA LOADING: Using RPC calls and bulk user fetch
  Future<void> _loadData({bool loadMore = false}) async {
    if ((_selectedTab == 1 && !_hasMoreForYou && loadMore) ||
        (_selectedTab == 0 && !_hasMoreFollowing && loadMore) ||
        _isLoadingMore) {
      return;
    }

    if (mounted) setState(() => _isLoadingMore = true);

    try {
      List<Map<String, dynamic>> newPosts = [];
      final excludedUsers = [..._blockedUsers, currentUserId];

      if (_selectedTab == 0) {
        if (_followingIds.isEmpty) {
          setState(() {
            _hasMoreFollowing = false;
            _isLoadingMore = false;
          });
          return;
        }

        final responseRaw = await _supabase.rpc('get_following_feed', params: {
          'current_user_id': currentUserId,
          'excluded_users': excludedUsers,
          'following_ids': _followingIds,
          'page_offset': _offsetFollowing,
          'page_limit': 5,
        });

        final response = _unwrapResponse(responseRaw);
        if (response is List) {
          newPosts = response.map<Map<String, dynamic>>((post) {
            final Map<String, dynamic> convertedPost = {};
            (post as Map).forEach((key, value) {
              convertedPost[key.toString()] = value;
            });
            convertedPost['postId'] = convertedPost['postId']?.toString();
            return convertedPost;
          }).toList();
        } else {
          newPosts = [];
        }

        _offsetFollowing += newPosts.length;
        _hasMoreFollowing = newPosts.length == 5;
      } else {
        final responseRaw = await _supabase.rpc('get_for_you_feed', params: {
          'current_user_id': currentUserId,
          'excluded_users': excludedUsers,
          'page_offset': _offsetForYou,
          'page_limit': 5,
        });

        final response = _unwrapResponse(responseRaw);
        if (response is List) {
          newPosts = response.map<Map<String, dynamic>>((post) {
            final Map<String, dynamic> convertedPost = {};
            (post as Map).forEach((key, value) {
              if (key.toString() == 'postScore') {
                convertedPost['score'] = value;
              } else {
                convertedPost[key.toString()] = value;
              }
            });
            convertedPost['postId'] = convertedPost['postId']?.toString();
            return convertedPost;
          }).toList();
        } else {
          newPosts = [];
        }

        _offsetForYou += newPosts.length;
        _hasMoreForYou = newPosts.length == 5;
      }

      // FAST USER BULK FETCH: Fetch all users at once
      await _bulkFetchUsers(newPosts);

      if (mounted) {
        setState(() {
          if (_selectedTab == 0) {
            _followingPosts =
                loadMore ? [..._followingPosts, ...newPosts] : newPosts;
          } else {
            _forYouPosts = loadMore ? [..._forYouPosts, ...newPosts] : newPosts;
          }
          _isLoadingMore = false;
        });

        // Update visibility after new posts are loaded
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final currentPage =
                _selectedTab == 1 ? _currentForYouPage : _currentFollowingPage;
            final currentPosts =
                _selectedTab == 1 ? _forYouPosts : _followingPosts;
            _updatePostVisibility(currentPage, currentPosts);
          }
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isLoadingMore = false;
          _isLoading = false;
        });
    }
  }

  void _switchTab(int index) {
    if (_selectedTab == index) return;

    // Pause any currently playing video when switching tabs
    _pauseCurrentVideo();
    _currentPlayingPostId = null;

    setState(() {
      _selectedTab = index;
      _isLoading = true;
    });

    if (index == 0) {
      _offsetFollowing = 0;
      _followingPosts.clear();
      _hasMoreFollowing = true;
      _currentFollowingPage = 0;
    } else {
      _offsetForYou = 0;
      _forYouPosts.clear();
      _hasMoreForYou = true;
      _currentForYouPage = 0;
    }

    _loadData().then((_) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _pauseCurrentVideo();
    _currentPlayingPostId = null;
    _followingPageController.dispose();
    _forYouPageController.dispose();
    _guidelinesTimer?.cancel();
    _interstitialAd?.dispose();
    // Clean up stream resources
    _unreadCountTimer?.cancel();
    _unreadCountController?.close();
    super.dispose();
  }

  bool _shouldPostPlayVideo(String postId) {
    return postId == _currentPlayingPostId;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      body: Stack(
        children: [
          // Main feed content - ALWAYS show feed body
          _buildFeedBody(colors),

          // Overlay tabs at the top - ALWAYS VISIBLE
          if (width <= webScreenSize) _buildOverlayTabs(colors),

          // Overlay message button at top right - ALWAYS VISIBLE
          if (width <= webScreenSize) _buildOverlayMessageButton(colors),

          // Show loading indicator over the content if still loading
          if (_isLoading)
            Container(
              color: colors.backgroundColor.withOpacity(0.7),
              child: Center(
                child: CircularProgressIndicator(color: colors.textColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlayTabs(_ColorSet colors) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // For You tab with text label
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'For You',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 4),
                _buildOverlayTab(1, colors),
              ],
            ),
            const SizedBox(width: 40),
            // Following tab with text label
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Following',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 4),
                _buildOverlayTab(0, colors),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayTab(int index, _ColorSet colors) {
    return GestureDetector(
      onTap: () {
        _switchTab(index);
        _showInterstitialAd();
      },
      child: Container(
        height: 24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 2,
              width: 60,
              decoration: BoxDecoration(
                color:
                    _selectedTab == index ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayMessageButton(_ColorSet colors) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 16,
      child: GestureDetector(
        onTap: _navigateToMessages,
        child: StreamBuilder<int>(
          stream: _unreadCountStream,
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            final formattedCount = _formatMessageCount(count);

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Material(
                  color: Colors.transparent,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    icon: Icon(
                      Icons.message,
                      color: colors.iconColor,
                      size: 24,
                    ),
                    onPressed: _navigateToMessages,
                  ),
                ),
                if (count > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      decoration: BoxDecoration(
                        color: colors.cardColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          formattedCount,
                          style: TextStyle(
                            color: colors.textColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeedBody(_ColorSet colors) {
    return SizedBox.expand(
      child: _selectedTab == 1
          ? _buildForYouFeed(colors)
          : _buildFollowingFeed(colors),
    );
  }

  Widget _buildFollowingFeed(_ColorSet colors) {
    // Show empty state or loading within the feed
    if (_isLoading && _followingPosts.isEmpty) {
      return _buildLoadingFeed(colors);
    }
    if (!_isLoading && _followingIds.isEmpty) {
      return _buildNoFollowingMessage(colors);
    }
    return _buildPostsPageView(
        _followingPosts, _followingPageController, colors, false);
  }

  Widget _buildForYouFeed(_ColorSet colors) {
    // Show loading state if no posts yet
    if (_isLoading && _forYouPosts.isEmpty) {
      return _buildLoadingFeed(colors);
    }
    return _buildPostsPageView(
        _forYouPosts, _forYouPageController, colors, true);
  }

  Widget _buildLoadingFeed(_ColorSet colors) {
    return Center(
      child: CircularProgressIndicator(color: colors.textColor),
    );
  }

  Widget _buildNoFollowingMessage(_ColorSet colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Text(
          "Follow users to see their posts here!",
          style: TextStyle(
            color: colors.textColor.withOpacity(0.7),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildPostsPageView(
    List<Map<String, dynamic>> posts,
    PageController controller,
    _ColorSet colors,
    bool isForYou,
  ) {
    return PageView.builder(
      controller: controller,
      scrollDirection: Axis.vertical,
      itemCount: posts.length + (_isLoadingMore ? 1 : 0),
      onPageChanged: (page) => _onPageChanged(page, isForYou),
      itemBuilder: (ctx, index) {
        if (index >= posts.length) {
          return _buildLoadingIndicator(colors);
        }

        final post = posts[index];
        final postId = post['postId']?.toString() ?? '';

        return Container(
          width: double.infinity,
          height: double.infinity,
          color: colors.backgroundColor,
          child: PostCard(
            snap: post,
            isVisible: _shouldPostPlayVideo(postId),
            onCommentTap: () => _openComments(context, post),
          ),
        );
      },
    );
  }

  Widget _buildLoadingIndicator(_ColorSet colors) {
    return Center(
      child: CircularProgressIndicator(color: colors.textColor),
    );
  }

  String _formatMessageCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else if (count < 10000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    } else {
      return '${(count ~/ 1000)}k';
    }
  }

  void _navigateToMessages() {
    _pauseCurrentVideo();
    if (currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to view messages')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FeedMessages(currentUserId: currentUserId),
      ),
    );
  }
}
