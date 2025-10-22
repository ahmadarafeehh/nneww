import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:Ratedly/utils/global_variable.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/resources/notification_read.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:Ratedly/screens/feed/post_card.dart';

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

  @override
  void initState() {
    super.initState();
    pageController = PageController();
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

  void _pauseCurrentVideo() {
    VideoManager().pauseCurrentVideo();
  }

  void navigationTapped(int page) async {
    _pauseCurrentVideo();

    if (page == 2) {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user != null) {
        NotificationService.markNotificationsAsRead(user.uid);
      }
    }
    pageController.jumpToPage(page);
  }

  _NavColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _NavDarkColors() : _NavLightColors();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final user = Provider.of<UserProvider>(context).user;

    // INSTANT: Always show the feed interface immediately
    // Let individual screens handle their own loading states
    return Scaffold(
      body: Stack(
        children: [
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomNavBar(user?.uid ?? '', colors),
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
            _NotificationBadgeIcon(
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

// Notification badge with real-time count from Supabase
class _NotificationBadgeIcon extends StatefulWidget {
  final String currentUserId;
  final int currentPage;
  final int pageIndex;
  final Color badgeBackgroundColor;
  final Color badgeTextColor;
  final bool isActive;
  final Color iconColor;
  final Color indicatorColor;

  const _NotificationBadgeIcon({
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
  State<_NotificationBadgeIcon> createState() => _NotificationBadgeIconState();
}

class _NotificationBadgeIconState extends State<_NotificationBadgeIcon> {
  int _notificationCount = 0;
  bool _hasLoaded = false;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationStream;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadNotificationCount();
    _setupNotificationStream();
    _startPolling();
  }

  Future<void> _loadNotificationCount() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('notifications')
          .select('id, is_read, type, target_user_id')
          .eq('target_user_id', widget.currentUserId)
          .eq('is_read', false)
          .neq('type', 'message')
          .limit(100);

      if (mounted) {
        setState(() {
          _notificationCount = response.length;
          _hasLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasLoaded = true;
        });
      }
    }
  }

  void _setupNotificationStream() {
    try {
      final supabase = Supabase.instance.client;

      _notificationStream = supabase
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('target_user_id', widget.currentUserId)
          .listen((List<Map<String, dynamic>> notifications) {
            final unreadNotifications = notifications.where((notification) {
              final targetUserId = notification['target_user_id']?.toString();
              final isRead = notification['is_read'] == true;
              final type = notification['type']?.toString();

              return targetUserId == widget.currentUserId &&
                  !isRead &&
                  type != 'message';
            }).toList();

            if (mounted) {
              setState(() {
                _notificationCount = unreadNotifications.length;
              });
            }
          }, onError: (error) {
            // Handle stream error silently
          });
    } catch (e) {
      // Handle setup error silently
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadNotificationCount();
      }
    });
  }

  @override
  void dispose() {
    _notificationStream?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  String _formatCount(int count) {
    if (count <= 0) return '0';
    if (count < 1000) {
      return count.toString();
    } else if (count < 10000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    } else {
      return '9+';
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;

    // Use the same colors as your comment count badge
    final badgeBackgroundColor =
        isDarkMode ? const Color(0xFF333333) : Colors.white;
    final badgeTextColor = isDarkMode ? const Color(0xFFd9d9d9) : Colors.black;

    final shouldShowBadge = _notificationCount > 0;
    final displayCount = _formatCount(_notificationCount);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Heart icon
        Icon(
          Icons.favorite,
          color: widget.isActive
              ? widget.indicatorColor.withOpacity(0.7)
              : widget.iconColor.withOpacity(0.3),
          size: 24,
        ),

        // Notification badge - matches comment count style
        Positioned(
          top: -6,
          right: -8,
          child: AnimatedOpacity(
            opacity: shouldShowBadge ? 1.0 : 0.0,
            duration: Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 20,
                minHeight: 20,
              ),
              decoration: BoxDecoration(
                color: badgeBackgroundColor, // Matches comment count background
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  displayCount.length > 2 ? '9+' : displayCount,
                  style: TextStyle(
                    color: badgeTextColor, // Matches comment count text color
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
