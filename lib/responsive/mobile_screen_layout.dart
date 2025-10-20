import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:Ratedly/utils/colors.dart';
import 'package:Ratedly/utils/global_variable.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/resources/notification_read.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:Ratedly/screens/feed/post_card.dart'; // Create this shared widget

// Define color schemes for both themes at top level
class _NavColorSet {
  final Color backgroundColor;
  final Color iconColor;
  final Color indicatorColor;
  final Color badgeBackgroundColor;
  final Color badgeTextColor;

  _NavColorSet({
    required this.backgroundColor,
    required this.iconColor,
    required this.indicatorColor,
    required this.badgeBackgroundColor,
    required this.badgeTextColor,
  });
}

class _NavDarkColors extends _NavColorSet {
  _NavDarkColors()
      : super(
          backgroundColor: const Color(0xFF121212),
          iconColor: Colors.white,
          indicatorColor: Colors.white,
          badgeBackgroundColor: const Color(0xFF333333),
          badgeTextColor: const Color(0xFFd9d9d9),
        );
}

class _NavLightColors extends _NavColorSet {
  _NavLightColors()
      : super(
          backgroundColor: Colors.white,
          iconColor: Colors.black,
          indicatorColor: Colors.black,
          badgeBackgroundColor: Colors.grey[300]!,
          badgeTextColor: Colors.black,
        );
}

class MobileScreenLayout extends StatefulWidget {
  const MobileScreenLayout({Key? key}) : super(key: key);

  @override
  State<MobileScreenLayout> createState() => _MobileScreenLayoutState();
}

class _MobileScreenLayoutState extends State<MobileScreenLayout> {
  int _page = 0;
  late PageController pageController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // Initialize controller immediately for fast rendering
    pageController = PageController();
    _markInitialized();
  }

  void _markInitialized() {
    // Mark as initialized in the next frame to show skeleton first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    });
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  void onPageChanged(int page) {
    setState(() {
      _page = page;
    });
  }

  // UPDATED METHOD - Same approach as PostCard
  void _pauseCurrentVideo() {
    VideoManager().pauseCurrentVideo();
  }

  void navigationTapped(int page) async {
    // PAUSE VIDEO BEFORE NAVIGATING - SAME AS POSTCARD APPROACH
    _pauseCurrentVideo();

    if (page == 2) {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user != null) {
        // Don't wait for this to complete - fire and forget
        NotificationService.markNotificationsAsRead(user.uid);
      }
    }
    pageController.jumpToPage(page);
  }

  // Helper method to get the appropriate color scheme
  _NavColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _NavDarkColors() : _NavLightColors();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final user = Provider.of<UserProvider>(context).user;

    // Show skeleton immediately while checking user or during initial frame
    if (user?.uid == null || !_initialized) {
      return const FeedSkeleton(); // Use shared skeleton widget
    }

    final currentUserId = user!.uid;

    return Scaffold(
      body: Stack(
        children: [
          // Main content - takes full screen
          SafeArea(
            top: false,
            bottom: false,
            child: PageView(
              controller: pageController,
              onPageChanged: onPageChanged,
              children: homeScreenItems,
              physics: const NeverScrollableScrollPhysics(),
            ),
          ),

          // Bottom navigation bar without container background
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomNavBar(currentUserId, colors),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(String currentUserId, _NavColorSet colors) {
    return SafeArea(
      top: false,
      child: Container(
        height: 70,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildCustomNavItem(Icons.home, 0, colors),
            _buildCustomNavItem(Icons.search, 1, colors),
            _buildCustomNotificationNavItem(currentUserId, 2, colors),
            _buildCustomNavItem(Icons.person, 3, colors),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomNavItem(IconData icon, int index, _NavColorSet colors) {
    final isActive = _page == index;

    return InkWell(
      onTap: () => navigationTapped(index),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 50,
        height: 50,
        decoration: isActive
            ? BoxDecoration(
                color: colors.indicatorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              )
            : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive
                  ? colors.indicatorColor.withOpacity(0.7)
                  : colors.iconColor.withOpacity(0.3),
              size: 24,
            ),
            if (isActive) ...[
              const SizedBox(height: 4),
              Container(
                height: 2,
                width: 8,
                decoration: BoxDecoration(
                  color: colors.indicatorColor.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCustomNotificationNavItem(
      String userId, int index, _NavColorSet colors) {
    final isActive = _page == index;

    return InkWell(
      onTap: () => navigationTapped(index),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 50,
        height: 50,
        decoration: isActive
            ? BoxDecoration(
                color: colors.indicatorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              )
            : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FastNotificationBadgeIcon(
              currentUserId: userId,
              currentPage: _page,
              pageIndex: index,
              badgeBackgroundColor: colors.badgeBackgroundColor,
              badgeTextColor: colors.badgeTextColor,
              isActive: isActive,
              iconColor: colors.iconColor,
              indicatorColor: colors.indicatorColor,
            ),
            if (isActive) ...[
              const SizedBox(height: 4),
              Container(
                height: 2,
                width: 8,
                decoration: BoxDecoration(
                  color: colors.indicatorColor.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Optimized notification badge that loads faster
class _FastNotificationBadgeIcon extends StatefulWidget {
  final String currentUserId;
  final int currentPage;
  final int pageIndex;
  final Color badgeBackgroundColor;
  final Color badgeTextColor;
  final bool isActive;
  final Color iconColor;
  final Color indicatorColor;

  const _FastNotificationBadgeIcon({
    Key? key,
    required this.currentUserId,
    required this.currentPage,
    required this.pageIndex,
    required this.badgeBackgroundColor,
    required this.badgeTextColor,
    required this.isActive,
    required this.iconColor,
    required this.indicatorColor,
  }) : super(key: key);

  @override
  State<_FastNotificationBadgeIcon> createState() =>
      _FastNotificationBadgeIconState();
}

class _FastNotificationBadgeIconState
    extends State<_FastNotificationBadgeIcon> {
  int _notificationCount = 0;
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationCount();
  }

  void _loadNotificationCount() {
    // Load initial count quickly, then update with stream
    _getInitialCount().then((count) {
      if (mounted) {
        setState(() {
          _notificationCount = count;
          _hasLoaded = true;
        });
      }
    });

    // Then listen for updates
    _setupNotificationStream();
  }

  Future<int> _getInitialCount() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('notifications')
          .select('id')
          .eq('target_user_id', widget.currentUserId)
          .eq('is_read', false)
          .limit(100); // Limit for performance

      return response.length;
    } catch (e) {
      return 0;
    }
  }

  void _setupNotificationStream() {
    final supabase = Supabase.instance.client;

    supabase
        .from('notifications')
        .stream(primaryKey: ['id']).map((notifications) {
      return notifications.where((notification) {
        final targetUserId = notification['target_user_id'];
        final isRead = notification['is_read'] ?? false;
        return targetUserId == widget.currentUserId && isRead == false;
      }).toList();
    }).listen((notifications) {
      if (mounted) {
        setState(() {
          _notificationCount = notifications.length;
        });
      }
    });
  }

  String _formatCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else if (count < 10000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    } else {
      return '${(count ~/ 1000)}k';
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedCount = _formatCount(_notificationCount);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Icon(
          Icons.favorite,
          color: widget.isActive
              ? widget.indicatorColor.withOpacity(0.7)
              : widget.iconColor.withOpacity(0.3),
          size: 24,
        ),
        if (_notificationCount > 0)
          Positioned(
            top: -8,
            right: -8,
            child: Container(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.badgeBackgroundColor,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  formattedCount,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Add this at the bottom of mobile_screen_layout.dart (after all other classes)
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    final skeletonColor = isDarkMode
        ? const Color(0xFF333333).withOpacity(0.6)
        : Colors.grey[300]!.withOpacity(0.6);
    final backgroundColor =
        isDarkMode ? const Color(0xFF121212) : Colors.grey[100]!;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          _buildSkeletonPageView(skeletonColor, backgroundColor),
          _buildSkeletonTabs(context),
          _buildSkeletonMessageButton(context),
        ],
      ),
    );
  }

  Widget _buildSkeletonPageView(Color skeletonColor, Color backgroundColor) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: 2,
      itemBuilder: (ctx, index) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: backgroundColor,
          child: Stack(
            children: [
              Container(color: skeletonColor),
              Positioned(
                bottom: 220,
                right: 16,
                child: Column(
                  children: [
                    CircleAvatar(radius: 21, backgroundColor: skeletonColor),
                    const SizedBox(height: 20),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: skeletonColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: skeletonColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: skeletonColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 18,
                              width: 120,
                              decoration: BoxDecoration(
                                color: skeletonColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          Container(
                            height: 32,
                            width: 120,
                            decoration: BoxDecoration(
                              color: skeletonColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkeletonTabs(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSkeletonTab('For You'),
            const SizedBox(width: 40),
            _buildSkeletonTab('Following'),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonTab(String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 18,
          width: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 2,
          width: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonMessageButton(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 16,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.message, color: Colors.white, size: 24),
      ),
    );
  }
}
