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
import 'package:Ratedly/widgets/guidelines_popup.dart';
import 'package:Ratedly/widgets/feedmessages.dart';
import 'package:Ratedly/services/ads.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';

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
  String? _currentPlayingPostId; // Track which post should actually play video

  // Ad-related variables - ONLY INTERSTITIAL REMAINS
  InterstitialAd? _interstitialAd;
  int _postViewCount = 0;
  DateTime? _lastInterstitialAdTime;

  Stream<int>? _unreadCountStream;

  // Caching for performance
  static final Map<String, List<String>> _blockedUsersCache = {};
  static DateTime? _lastBlockedUsersCacheTime;

  // Helper method to get the appropriate color scheme
  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  // Helper to unwrap Supabase/Postgrest responses
  dynamic _unwrapResponse(dynamic res) {
    if (res == null) return null;
    if (res is Map && res.containsKey('data')) return res['data'];
    return res;
  }

  // ADD THIS METHOD - Same approach as PostCard
  void _pauseCurrentVideo() {
    VideoManager().pauseCurrentVideo();
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
    _loadInterstitialAd(); // Only load interstitial ad
  }

  // Update visibility based on current page - FIXED VERSION
  void _updatePostVisibility(int page, List<Map<String, dynamic>> posts) {
    if (!mounted || posts.isEmpty) return;

    // Get the current playing post ID before we update anything
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
          _currentPlayingPostId =
              postId; // This is the only post that should play video
          // Schedule view recording for the visible post
          _scheduleViewRecording(postId);
        }
      }

      // Set adjacent posts as "visible" only for preloading content, but they won't play videos
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
      VideoManager().onPostInvisible(previouslyPlayingPostId);
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

  Stream<int> _createUnreadCountStream() async* {
    if (currentUserId.isEmpty) {
      yield 0;
      while (mounted) {
        await Future.delayed(const Duration(seconds: 5));
        yield 0;
      }
      return;
    }

    while (mounted) {
      try {
        final data = await _supabase
            .from('messages')
            .select('id')
            .eq('receiver_id', currentUserId)
            .eq('is_read', false);

        final int count = (data is List) ? data.length : 0;
        yield count;
      } catch (e, st) {
        yield 0;
      }
      await Future.delayed(const Duration(seconds: 5));
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

  // OPTIMIZED: Parallel loading of blocked users and following IDs
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

  // OPTIMIZED: Parallel loading of initial data
  Future<void> _loadInitialData() async {
    if (!mounted) return;

    try {
      currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
      _unreadCountStream = _createUnreadCountStream();

      if (currentUserId.isEmpty) {
        _blockedUsers = [];
        _followingIds = [];
        await _loadData();
        return;
      }

      // PARALLEL LOADING: Load blocked users and following IDs simultaneously
      await Future.wait([
        _loadBlockedUsers(),
        _loadFollowingIds(),
      ]);

      // Then load posts (depends on the above data)
      await _loadData();
    } catch (e, st) {
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
    } catch (e, st) {
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
    VideoManager().pauseCurrentVideo();
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
    // Pause all videos when the feed screen is disposed
    VideoManager().pauseCurrentVideo();
    _currentPlayingPostId = null;
    _followingPageController.dispose();
    _forYouPageController.dispose();
    _guidelinesTimer?.cancel();
    _interstitialAd?.dispose();
    super.dispose();
  }

  bool _isPostVisible(String postId) {
    return _postVisibility[postId] ?? false;
  }

  // NEW METHOD: Check if post should actually play video
  bool _shouldPostPlayVideo(String postId) {
    return postId == _currentPlayingPostId;
  }

  // =============================
  // Skeleton Loading Widgets
  // =============================

  Widget _buildFeedSkeleton(_ColorSet colors) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: 3, // Show 3 skeleton posts
      itemBuilder: (ctx, index) {
        return _buildPostSkeleton(colors);
      },
    );
  }

  Widget _buildPostSkeleton(_ColorSet colors) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: colors.backgroundColor,
      child: Stack(
        children: [
          // Media content skeleton (full screen)
          Container(
            color: colors.skeletonColor,
            width: double.infinity,
            height: double.infinity,
          ),

          // Right side action buttons skeleton
          Positioned(
            bottom: 220,
            right: 16,
            child: Column(
              children: [
                // User avatar skeleton
                CircleAvatar(
                  radius: 21,
                  backgroundColor: colors.skeletonColor,
                ),
                const SizedBox(height: 20),
                // Comment button skeleton
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.skeletonColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 8),
                // Share button skeleton
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.skeletonColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),

          // Bottom overlay skeleton
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rating section skeleton
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.skeletonColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Username and rating summary
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 18,
                              width: 120,
                              decoration: BoxDecoration(
                                color: colors.skeletonColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 14,
                              width: 80,
                              decoration: BoxDecoration(
                                color: colors.skeletonColor.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 32,
                        width: 120,
                        decoration: BoxDecoration(
                          color: colors.skeletonColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Description skeleton
                  Container(
                    height: 16,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colors.skeletonColor.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 16,
                    width: 200,
                    decoration: BoxDecoration(
                      color: colors.skeletonColor.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFollowingSkeleton(_ColorSet colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.skeletonColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 20,
              width: 200,
              decoration: BoxDecoration(
                color: colors.skeletonColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 16,
              width: 250,
              decoration: BoxDecoration(
                color: colors.skeletonColor.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
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
          // Main feed content
          _isLoading ? _buildFeedSkeleton(colors) : _buildFeedBody(colors),

          // Overlay tabs at the top
          if (width <= webScreenSize) _buildOverlayTabs(colors),

          // Overlay message button at top right
          if (width <= webScreenSize) _buildOverlayMessageButton(colors),
        ],
      ),
    );
  }

  Widget _buildOverlayTabs(_ColorSet colors) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8, // Below status bar
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildOverlayTab('For You', 1, colors),
            const SizedBox(width: 40), // Increased spacing between tabs
            _buildOverlayTab('Following', 0, colors),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayTab(String text, int index, _ColorSet colors) {
    return GestureDetector(
      onTap: () {
        _switchTab(index);
        _showInterstitialAd();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 18, // Slightly larger font for better visibility
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 4),
          // Underline indicator
          Container(
            height: 2,
            width: 60, // Fixed width for underline
            decoration: BoxDecoration(
              color: _selectedTab == index ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayMessageButton(_ColorSet colors) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 16,
      child: GestureDetector(
        onTap: _navigateToMessages, // Add this GestureDetector
        child: StreamBuilder<int>(
          stream: _unreadCountStream,
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            final formattedCount = _formatMessageCount(count);

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.message,
                    color: Colors.white,
                    size: 24,
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
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          formattedCount,
                          style: TextStyle(
                            color: Colors.white,
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

  AppBar? _buildAppBar(double width, _ColorSet colors) {
    return null; // Remove the AppBar completely
  }

  Widget _buildFeedBody(_ColorSet colors) {
    return SizedBox.expand(
      child: _selectedTab == 1
          ? _buildForYouFeed(colors)
          : _buildFollowingFeed(colors),
    );
  }

  Widget _buildFollowingFeed(_ColorSet colors) {
    if (!_isLoading && _followingIds.isEmpty) {
      return _buildNoFollowingMessage(colors);
    }
    return _buildPostsPageView(
        _followingPosts, _followingPageController, colors, false);
  }

  Widget _buildForYouFeed(_ColorSet colors) {
    return _buildPostsPageView(
        _forYouPosts, _forYouPageController, colors, true);
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
            isVisible: _shouldPostPlayVideo(postId), // Use the new method
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

  Widget _buildMessageButton(_ColorSet colors) {
    return StreamBuilder<int>(
      stream: _unreadCountStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final formattedCount = _formatMessageCount(count);

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            IconButton(
              onPressed: _navigateToMessages,
              icon: Icon(Icons.message, color: colors.textColor),
            ),
            if (count > 0)
              Positioned(
                top: -2,
                left: -3,
                child: _buildUnreadCountBadge(formattedCount, colors),
              ),
          ],
        );
      },
    );
  }

  Widget _buildUnreadCountBadge(String count, _ColorSet colors) {
    return Container(
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
          count,
          style: TextStyle(
            color: colors.textColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
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

  // UPDATED METHOD - Same approach as PostCard
  void _navigateToMessages() {
    // Pause video before navigating - SAME AS POSTCARD APPROACH
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
