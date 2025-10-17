import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:Ratedly/utils/colors.dart';
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
        await NotificationService.markNotificationsAsRead(user.uid);
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

    if (user?.uid == null) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: colors.iconColor,
          ),
        ),
      );
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
        // Removed margin and decoration to eliminate the grey box
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
                  ? colors.indicatorColor
                      .withOpacity(0.7) // Transparent active icon
                  : colors.iconColor
                      .withOpacity(0.3), // More transparent inactive icon
              size: 24,
            ),
            if (isActive) ...[
              const SizedBox(height: 4),
              Container(
                height: 2,
                width: 8,
                decoration: BoxDecoration(
                  color: colors.indicatorColor
                      .withOpacity(0.7), // Transparent indicator
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
            NotificationBadgeIcon(
              currentUserId: userId,
              currentPage: _page,
              pageIndex: index,
              badgeBackgroundColor: colors.badgeBackgroundColor,
              badgeTextColor: colors.badgeTextColor,
              isActive: isActive,
              iconColor: colors.iconColor,
              indicatorColor: colors.indicatorColor, // Added this line
            ),
            if (isActive) ...[
              const SizedBox(height: 4),
              Container(
                height: 2,
                width: 8,
                decoration: BoxDecoration(
                  color: colors.indicatorColor
                      .withOpacity(0.7), // Transparent indicator
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

class NotificationBadgeIcon extends StatelessWidget {
  final String currentUserId;
  final int currentPage;
  final int pageIndex;
  final Color badgeBackgroundColor;
  final Color badgeTextColor;
  final bool isActive;
  final Color iconColor;
  final Color indicatorColor; // Added this parameter

  const NotificationBadgeIcon({
    Key? key,
    required this.currentUserId,
    required this.currentPage,
    required this.pageIndex,
    required this.badgeBackgroundColor,
    required this.badgeTextColor,
    required this.isActive,
    required this.iconColor,
    required this.indicatorColor, // Added this parameter
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getUnreadNotificationsStream(currentUserId),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        final formattedCount = _formatCount(count);

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none, // Allow badge to extend beyond icon bounds
          children: [
            Icon(
              Icons.favorite,
              color: isActive
                  ? indicatorColor.withOpacity(
                      0.7) // Use indicatorColor instead of red for active
                  : iconColor
                      .withOpacity(0.3), // More transparent when inactive
              size: 24, // Explicit size for consistent positioning
            ),
            if (count > 0)
              Positioned(
                top: -8, // Adjusted position for floating nav
                right: -8, // Adjusted position for floating nav
                child: Container(
                  padding:
                      const EdgeInsets.all(4), // Match comment count padding
                  constraints: const BoxConstraints(
                    minWidth: 18, // Slightly smaller for floating nav
                    minHeight: 18, // Slightly smaller for floating nav
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red, // Use red for notifications
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          badgeBackgroundColor, // Use theme background as border
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      formattedCount,
                      style: TextStyle(
                        color: Colors.white, // Always white on red
                        fontSize: 9, // Slightly smaller for floating nav
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
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

  Stream<List<Map<String, dynamic>>> _getUnreadNotificationsStream(
      String userId) {
    final supabase = Supabase.instance.client;

    return supabase
        .from('notifications')
        .stream(primaryKey: ['id']).map((notifications) {
      return notifications.where((notification) {
        final targetUserId =
            notification['target_user_id'] ?? notification['targetUserId'];
        final isRead =
            notification['is_read'] ?? notification['isRead'] ?? false;
        return targetUserId == userId && isRead == false;
      }).toList();
    });
  }
}
