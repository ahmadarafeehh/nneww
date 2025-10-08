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

// Define color schemes for both themes at top level
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

class FeedScreen extends StatefulWidget {
  const FeedScreen({Key? key}) : super(key: key);

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late String currentUserId;
  int _selectedTab = 1;
  late ScrollController _followingScrollController;
  late ScrollController _forYouScrollController;
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

  // Ad-related variables
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  InterstitialAd? _interstitialAd;
  int _postViewCount = 0;
  DateTime? _lastInterstitialAdTime;

  // Native ad variables
  NativeAd? _nativeAd;
  bool _isNativeAdLoaded = false;
  int _adCounter = 0;

  // stream for unread message count
  Stream<int>? _unreadCountStream;

  // Helper method to get the appropriate color scheme
  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  // -------------------------
  // Helper to unwrap Supabase/Postgrest responses
  // -------------------------
  dynamic _unwrapResponse(dynamic res) {
    if (res == null) return null;
    if (res is Map && res.containsKey('data')) return res['data'];
    return res;
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

      // Increment post view count and check if we should show interstitial ad
      setState(() {
        _postViewCount += viewsToRecord.length;
      });

      // Show interstitial ad after every 5 post views, but not too frequently
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

    _followingScrollController = ScrollController()..addListener(_onScroll);
    _forYouScrollController = ScrollController()..addListener(_onScroll);

    // create unread stream (polling, simple & robust)
    _unreadCountStream = _createUnreadCountStream();

    _loadInitialData();
    _startGuidelinesTimer();
    _loadBannerAd(); // Load the banner ad
    _loadNativeAd(); // Load the native ad
    _loadInterstitialAd(); // Load the interstitial ad
  }

  void _loadBannerAd() {
    BannerAd(
      adUnitId: AdHelper.feedBannerAdUnitId,
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

  void _loadNativeAd() {
    _nativeAd = NativeAd(
      adUnitId: AdHelper.feedNativeAdUnitId,
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isNativeAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          // Try loading again after a delay
          Future.delayed(const Duration(seconds: 30), () {
            _loadNativeAd();
          });
        },
      ),
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        cornerRadius: 10.0,
      ),
    )..load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdHelper.feedInterstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;

          // Set full screen content callback
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              ad.dispose();
              _loadInterstitialAd(); // Load a new ad
            },
            onAdFailedToShowFullScreenContent:
                (InterstitialAd ad, AdError error) {
              ad.dispose();
              _loadInterstitialAd(); // Load a new ad
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('InterstitialAd failed to load: $error');
          // Try loading again after a delay
          Future.delayed(const Duration(seconds: 30), () {
            _loadInterstitialAd();
          });
        },
      ),
    );
  }

  void _showInterstitialAd() {
    // Don't show ads too frequently (at least 2 minutes between ads)
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
      // If no ad is loaded, try to load one
      _loadInterstitialAd();
    }
  }

  // creates a simple stream that queries unread count every 5 seconds
  Stream<int> _createUnreadCountStream() async* {
    // If no signed-in user, yield 0 periodically so StreamBuilder stays stable
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
        // NOTE: use the real column name 'receiver_id' (your table uses that)
        final data = await _supabase
            .from('messages')
            .select('id') // fetch ids only
            .eq('receiver_id', currentUserId) // <-- correct column
            .eq('is_read', false);

        // when awaited, data is usually a List of rows
        final int count =
            (data is List) ? data.length : 0; // FIXED: Changed => to ?
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

  void _onScroll() {
    final currentController = _selectedTab == 1
        ? _forYouScrollController
        : _followingScrollController;

    if (currentController.position.pixels >=
            currentController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        ((_selectedTab == 1 && _hasMoreForYou) ||
            (_selectedTab == 0 && _hasMoreFollowing))) {
      _loadData(loadMore: true);
    }
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    try {
      // Ensure we use FirebaseAuth for current user
      currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
      // recreate unread stream to pick up userId if it changed
      _unreadCountStream = _createUnreadCountStream();

      // If not signed in, still attempt public "For You" feed
      if (currentUserId.isEmpty) {
        _blockedUsers = [];
        _followingIds = [];
        await _loadData();
        return;
      }

      // 1) blockedUsers
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
      // 2) following ids
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
      // 3) load posts
      await _loadData();
    } catch (e, st) {
      // On error, still clear the loading state so the UI doesn't hang
      if (mounted) setState(() => _isLoading = false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showGuidelinesPopup() {
    if (!mounted) return;
    setState(() => _isPopupShown = true);

    showDialog(
      context: context, // <-- use named parameter
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
              // Rename postScore to score for compatibility
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
      }
    } catch (e, st) {
      if (mounted)
        setState(() {
          _isLoadingMore = false;
          _isLoading = false; // avoid permanent spinner
        });
    }
  }

  @override
  void dispose() {
    _followingScrollController.dispose();
    _forYouScrollController.dispose();
    _guidelinesTimer?.cancel();
    _bannerAd?.dispose();
    _nativeAd?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: _buildAppBar(width, colors),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.textColor))
          : _buildFeedBodyWithAd(width, colors),
    );
  }

  AppBar? _buildAppBar(double width, _ColorSet colors) {
    return width > webScreenSize
        ? null
        : AppBar(
            iconTheme: IconThemeData(color: colors.textColor),
            backgroundColor: colors.backgroundColor,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTab('For You', 1, colors),
                const SizedBox(width: 20),
                _buildTab('Following', 0, colors),
              ],
            ),
            centerTitle: true,
            actions: [_buildMessageButton(colors)],
          );
  }

  Widget _buildTab(String text, int index, _ColorSet colors) {
    return GestureDetector(
      onTap: () {
        _switchTab(index);
        // Show interstitial ad when switching tabs
        _showInterstitialAd();
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color:
                  _selectedTab == index ? colors.textColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Text(
          text,
          style: TextStyle(
            color: colors.textColor,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  void _switchTab(int index) {
    if (_selectedTab == index) return;

    setState(() {
      _selectedTab = index;
      _isLoading = true;
    });

    if (index == 0) {
      _offsetFollowing = 0;
      _followingPosts.clear();
      _hasMoreFollowing = true;
    } else {
      _offsetForYou = 0;
      _forYouPosts.clear();
      _hasMoreForYou = true;
    }

    _loadData().then((_) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Widget _buildFeedBodyWithAd(double width, _ColorSet colors) {
    return Column(
      children: [
        // Banner Ad at the top (with a little spacing + dividers)
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
          child: _selectedTab == 1
              ? _buildForYouFeed(width, colors)
              : _buildFollowingFeed(width, colors),
        ),
      ],
    );
  }

  Widget _buildFollowingFeed(double width, _ColorSet colors) {
    // Show message if not following anyone and not loading
    if (!_isLoading && _followingIds.isEmpty) {
      return _buildNoFollowingMessage(colors);
    }
    return _buildPostsListView(
        _followingPosts, width, _followingScrollController, colors);
  }

  Widget _buildForYouFeed(double width, _ColorSet colors) {
    return _buildPostsListViewWithAds(
        _forYouPosts, width, _forYouScrollController, colors);
  }

  // Helper widget to display message when not following anyone
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

  Widget _buildPostsListView(
    List<Map<String, dynamic>> posts,
    double width,
    ScrollController controller,
    _ColorSet colors,
  ) {
    return ListView.builder(
      controller: controller,
      itemCount: posts.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (ctx, index) {
        if (index >= posts.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
                child: CircularProgressIndicator(color: colors.textColor)),
          );
        }

        final post = posts[index];
        final postId = post['postId']?.toString() ?? '';

        return Container(
          color: colors.backgroundColor,
          margin: EdgeInsets.symmetric(
            horizontal: width > webScreenSize ? width * 0.3 : 0,
            vertical: width > webScreenSize ? 15 : 0,
          ),
          child: PostCard(snap: post),
        );
      },
    );
  }

  Widget _buildPostsListViewWithAds(
    List<Map<String, dynamic>> posts,
    double width,
    ScrollController controller,
    _ColorSet colors,
  ) {
    // Only show ads if they're loaded
    final bool showAds = _isNativeAdLoaded;
    final int adInterval = 4; // Show an ad every 4 posts
    final int numAds = showAds ? (posts.length / adInterval).floor() : 0;
    final int totalItems = posts.length + numAds + (_isLoadingMore ? 1 : 0);

    return ListView.builder(
      controller: controller,
      itemCount: totalItems,
      itemBuilder: (ctx, index) {
        // Show loading indicator at the end
        if (_isLoadingMore && index == totalItems - 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(color: colors.textColor),
            ),
          );
        }

        // Calculate if this position should be an ad
        if (showAds && (index + 1) % adInterval == 0) {
          final int adIndex = (index + 1) ~/ adInterval - 1;

          // Make sure we don't exceed the available ads
          if (adIndex < numAds) {
            return Container(
              color: colors.backgroundColor,
              margin: EdgeInsets.symmetric(
                horizontal: width > webScreenSize ? width * 0.3 : 16,
                vertical: width > webScreenSize ? 15 : 8,
              ),
              height: 300,
              child: AdWidget(ad: _nativeAd!),
            );
          }
        }

        // Calculate the actual post index accounting for ads
        final int postIndex =
            showAds ? index - ((index + 1) ~/ adInterval) : index;

        // Ensure we don't go out of bounds
        if (postIndex < posts.length) {
          final post = posts[postIndex];
          final postId = post['postId']?.toString() ?? '';

          if (postId.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scheduleViewRecording(postId);
            });
          }

          return Container(
            color: colors.backgroundColor,
            margin: EdgeInsets.symmetric(
              horizontal: width > webScreenSize ? width * 0.3 : 0,
              vertical: width > webScreenSize ? 15 : 0,
            ),
            child: PostCard(snap: post),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  // optional helper to clear all "viewed" markers (used for debugging)
  Future<void> resetForYouViewedPosts() async {
    try {
      await _supabase
          .from('user_post_views')
          .delete()
          .eq('user_id', currentUserId);
      if (mounted) {
        setState(() {
          _offsetForYou = 0;
          _forYouPosts.clear();
          _hasMoreForYou = true;
        });
        _loadData();
      }
    } catch (e) {}
  }

  // Messages button + unread badge
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
              onPressed: () {
                _navigateToMessages();
                // Show interstitial ad when navigating to messages
                _showInterstitialAd();
              },
              icon: Icon(Icons.message, color: colors.textColor),
            ),
            if (count > 0)
              Positioned(
                top: -2, // Moved to top-left
                left: -3, // Moved to top-left
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

  void _navigateToMessages() {
    if (currentUserId.isEmpty) {
      // if user not signed in, ask to sign in (or route accordingly)
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
