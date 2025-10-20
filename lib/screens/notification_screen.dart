import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:Ratedly/screens/Profile_page/image_screen.dart';
import 'package:Ratedly/utils/global_variable.dart';
import 'package:Ratedly/resources/profile_firestore_methods.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:Ratedly/utils/theme_provider.dart';

// Define color schemes for both themes at top level
class _NotificationColorSet {
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;
  final Color appBarBackgroundColor;
  final Color appBarIconColor;
  final Color progressIndicatorColor;
  final Color cardColor;
  final Color subtitleTextColor;
  final Color dividerColor;

  _NotificationColorSet({
    required this.backgroundColor,
    required this.textColor,
    required this.iconColor,
    required this.appBarBackgroundColor,
    required this.appBarIconColor,
    required this.progressIndicatorColor,
    required this.cardColor,
    required this.subtitleTextColor,
    required this.dividerColor,
  });
}

class _NotificationDarkColors extends _NotificationColorSet {
  _NotificationDarkColors()
      : super(
          backgroundColor: const Color(0xFF121212),
          textColor: const Color(0xFFd9d9d9),
          iconColor: const Color(0xFFd9d9d9),
          appBarBackgroundColor: const Color(0xFF121212),
          appBarIconColor: const Color(0xFFd9d9d9),
          progressIndicatorColor: const Color(0xFFd9d9d9),
          cardColor: const Color(0xFF333333),
          subtitleTextColor: const Color(0xFF999999),
          dividerColor: const Color(0xFF333333),
        );
}

class _NotificationLightColors extends _NotificationColorSet {
  _NotificationLightColors()
      : super(
          backgroundColor: Colors.white,
          textColor: Colors.black,
          iconColor: Colors.black,
          appBarBackgroundColor: Colors.white,
          appBarIconColor: Colors.black,
          progressIndicatorColor: Colors.black,
          cardColor: Colors.grey[100]!,
          subtitleTextColor: Colors.grey[700]!,
          dividerColor: Colors.grey[300]!,
        );
}

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({Key? key}) : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  _NotificationColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _NotificationDarkColors() : _NotificationLightColors();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final userProvider = Provider.of<UserProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    if (userProvider.user == null) {
      return Scaffold(
        body: Center(
            child: CircularProgressIndicator(
                color: colors.progressIndicatorColor)),
      );
    }

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: width > webScreenSize
          ? null
          : AppBar(
              backgroundColor: colors.appBarBackgroundColor,
              toolbarHeight: 100,
              automaticallyImplyLeading: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              title: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ratedly',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: colors.appBarIconColor,
                  ),
                ),
              ),
              iconTheme: IconThemeData(color: colors.appBarIconColor),
            ),
      body: _FastNotificationList(
        currentUserId: userProvider.user!.uid,
        colors: colors,
      ),
    );
  }
}

class _FastNotificationList extends StatefulWidget {
  final String currentUserId;
  final _NotificationColorSet colors;

  const _FastNotificationList({
    required this.currentUserId,
    required this.colors,
  });

  @override
  State<_FastNotificationList> createState() => _FastNotificationListState();
}

class _FastNotificationListState extends State<_FastNotificationList> {
  final List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  final int _limit = 20;
  int _page = 0;

  // Fast user cache - similar to search screen
  final Map<String, Map<String, dynamic>> _userCache = {};
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadNotifications();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreNotifications();
    }
  }

  // FAST LOADING: Use minimal data and bulk fetch users
  Future<void> _loadNotifications() async {
    try {
      final response = await _supabase
          .from('notifications')
          .select('id, type, created_at, custom_data, is_read')
          .eq('target_user_id', widget.currentUserId)
          .neq('type', 'message')
          .order('created_at', ascending: false)
          .limit(_limit);

      if (response.isNotEmpty) {
        _notifications.addAll(List<Map<String, dynamic>>.from(response));

        // Bulk fetch all users at once - FAST
        await _bulkFetchUsers();

        setState(() {
          _page = 1;
          _hasMore = response.length == _limit;
        });
      } else {
        setState(() => _hasMore = false);
      }
    } catch (e) {
      print('Error loading notifications: $e');
      setState(() => _hasMore = false);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreNotifications() async {
    if (!_hasMore || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final offset = _page * _limit;
      final response = await _supabase
          .from('notifications')
          .select('id, type, created_at, custom_data, is_read')
          .eq('target_user_id', widget.currentUserId)
          .neq('type', 'message')
          .order('created_at', ascending: false)
          .range(offset, offset + _limit - 1);

      if (response.isNotEmpty) {
        final newNotifications = List<Map<String, dynamic>>.from(response);
        _notifications.addAll(newNotifications);

        // Bulk fetch new users
        await _bulkFetchUsers();

        setState(() {
          _page++;
          _hasMore = response.length == _limit;
        });
      } else {
        setState(() => _hasMore = false);
      }
    } catch (e) {
      print('Error loading more notifications: $e');
      setState(() => _hasMore = false);
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }

  // FAST USER FETCHING: Bulk fetch all users at once using inFilter
  Future<void> _bulkFetchUsers() async {
    final Set<String> userIds = {};

    // Collect all user IDs from notifications
    for (final notification in _notifications) {
      final userId = _extractUserIdFromNotification(notification);
      if (userId != null &&
          userId.isNotEmpty &&
          !_userCache.containsKey(userId)) {
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
        setState(() {}); // Refresh to show user data
      }
    } catch (e) {
      print('Error bulk fetching users: $e');
    }
  }

  String? _extractUserIdFromNotification(Map<String, dynamic> notification) {
    final type = notification['type'] as String?;
    final customData = notification['custom_data'] ?? {};

    switch (type) {
      case 'comment':
        return customData['commenterUid'] ?? customData['commenter_uid'];
      case 'post_rating':
        return customData['raterUid'] ?? customData['rater_uid'];
      case 'follow_request':
        return customData['requesterId'] ?? customData['requester_id'];
      case 'follow_request_accepted':
        return customData['approverId'] ?? customData['approver_id'];
      case 'comment_like':
        return customData['likerUid'] ?? customData['liker_uid'];
      case 'follow':
        return customData['followerId'] ?? customData['follower_id'];
      case 'reply':
        return customData['replierUid'] ?? customData['replier_uid'];
      case 'reply_like':
        return customData['likerUid'] ?? customData['liker_uid'];
      default:
        return null;
    }
  }

  void refreshNotifications() {
    setState(() {
      _notifications.clear();
      _page = 0;
      _hasMore = true;
      _isLoading = true;
      _userCache.clear();
    });
    _loadNotifications();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: 10,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          decoration: BoxDecoration(
            color: widget.colors.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.colors.cardColor.withOpacity(0.7),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 180,
                  decoration: BoxDecoration(
                    color: widget.colors.cardColor.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 12,
                  width: 120,
                  decoration: BoxDecoration(
                    color: widget.colors.cardColor.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 80,
            color: widget.colors.textColor.withOpacity(0.5),
          ),
          const SizedBox(height: 20),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 18,
              color: widget.colors.textColor.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Notifications will appear here',
            style: TextStyle(
              fontSize: 14,
              color: widget.colors.subtitleTextColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => refreshNotifications(),
      child: _isLoading
          ? _buildSkeletonLoader()
          : _notifications.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: _notifications.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _notifications.length) {
                      return _isLoadingMore
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: widget.colors.progressIndicatorColor,
                                ),
                              ),
                            )
                          : const SizedBox.shrink();
                    }

                    final notification = _notifications[index];
                    return _FastNotificationItem(
                      notification: notification,
                      currentUserId: widget.currentUserId,
                      userCache: _userCache,
                      colors: widget.colors,
                      refreshNotifications: refreshNotifications,
                    );
                  },
                ),
    );
  }
}

class _FastNotificationItem extends StatelessWidget {
  final Map<String, dynamic> notification;
  final String currentUserId;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;
  final VoidCallback? refreshNotifications;

  const _FastNotificationItem({
    required this.notification,
    required this.currentUserId,
    required this.userCache,
    required this.colors,
    this.refreshNotifications,
  });

  void _navigateToProfile(BuildContext context, String uid) {
    if (uid.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfileScreen(uid: uid)),
    );
  }

  Future<void> _navigateToPost(BuildContext context, String postId) async {
    if (postId.isEmpty) return;

    try {
      // Fetch post data first, similar to search screen
      final response = await Supabase.instance.client
          .from('posts')
          .select()
          .eq('postId', postId)
          .maybeSingle();

      if (response != null) {
        final postData = response as Map<String, dynamic>;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageViewScreen(
              imageUrl: postData['postUrl']?.toString() ?? '',
              postId: postId,
              description: postData['description']?.toString() ?? '',
              userId: postData['uid']?.toString() ?? '',
              username: postData['username']?.toString() ?? '',
              profImage: postData['profImage']?.toString() ?? '',
              datePublished: postData['datePublished']?.toString() ?? '',
            ),
          ),
        );
      }
    } catch (e) {
      print('Error navigating to post: $e');
    }
  }

  String _extractUserId() {
    final type = notification['type'] as String?;
    final customData = notification['custom_data'] ?? {};

    switch (type) {
      case 'comment':
        return customData['commenterUid'] ?? customData['commenter_uid'] ?? '';
      case 'post_rating':
        return customData['raterUid'] ?? customData['rater_uid'] ?? '';
      case 'follow_request':
        return customData['requesterId'] ?? customData['requester_id'] ?? '';
      case 'follow_request_accepted':
        return customData['approverId'] ?? customData['approver_id'] ?? '';
      case 'comment_like':
        return customData['likerUid'] ?? customData['liker_uid'] ?? '';
      case 'follow':
        return customData['followerId'] ?? customData['follower_id'] ?? '';
      case 'reply':
        return customData['replierUid'] ?? customData['replier_uid'] ?? '';
      case 'reply_like':
        return customData['likerUid'] ?? customData['liker_uid'] ?? '';
      default:
        return '';
    }
  }

  String? _extractPostId() {
    final type = notification['type'] as String?;
    final customData = notification['custom_data'] ?? {};

    switch (type) {
      case 'comment':
      case 'post_rating':
      case 'comment_like':
      case 'reply':
      case 'reply_like':
        return customData['postId'] ?? customData['post_id'];
      default:
        return null;
    }
  }

  Future<void> _handleFollowRequest(
      BuildContext context, String requesterId, bool accept) async {
    final provider =
        Provider.of<SupabaseProfileMethods>(context, listen: false);

    try {
      if (accept) {
        await provider.acceptFollowRequest(currentUserId, requesterId);
      } else {
        await provider.declineFollowRequest(currentUserId, requesterId);
      }

      refreshNotifications?.call();
    } catch (e) {
      print('Error handling follow request: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = notification['type'] as String?;
    final customData = notification['custom_data'] ?? {};

    // Extract user ID and get cached user data
    final userId = _extractUserId();
    final user = userCache[userId] ?? {};
    final username = user['username'] ?? 'Someone';

    // Build notification content based on type
    String title;
    String? subtitle;
    VoidCallback? onTap;
    List<Widget>? actions;

    switch (type) {
      case 'comment':
        title = '$username commented on your post';
        subtitle = customData['commentText'] ?? customData['comment_text'];
        final postId = _extractPostId();
        onTap = postId != null ? () => _navigateToPost(context, postId) : null;
        break;
      case 'post_rating':
        final rating = (customData['rating'] as num?)?.toDouble() ?? 0.0;
        title = '$username rated your post';
        subtitle = 'Rating: ${rating.toStringAsFixed(1)}';
        final postId = _extractPostId();
        onTap = postId != null ? () => _navigateToPost(context, postId) : null;
        break;
      case 'follow_request':
        title = '$username wants to follow you';
        actions = [
          TextButton(
            onPressed: () => _handleFollowRequest(context, userId, true),
            child: Text('Accept', style: TextStyle(color: colors.textColor)),
          ),
          TextButton(
            onPressed: () => _handleFollowRequest(context, userId, false),
            child: Text('Decline', style: TextStyle(color: colors.textColor)),
          ),
        ];
        break;
      case 'follow_request_accepted':
        title = '$username approved your follow request';
        onTap = () => _navigateToProfile(context, userId);
        break;
      case 'comment_like':
        title = '$username liked your comment';
        subtitle = customData['commentText'] ?? customData['comment_text'];
        final postId = _extractPostId();
        onTap = postId != null ? () => _navigateToPost(context, postId) : null;
        break;
      case 'follow':
        title = '$username started following you';
        onTap = () => _navigateToProfile(context, userId);
        break;
      case 'reply':
        title = '$username replied to your comment';
        subtitle = customData['replyText'] ?? customData['reply_text'];
        final postId = _extractPostId();
        onTap = postId != null ? () => _navigateToPost(context, postId) : null;
        break;
      case 'reply_like':
        title = '$username liked your reply';
        subtitle = customData['replyText'] ?? customData['reply_text'];
        final postId = _extractPostId();
        onTap = postId != null ? () => _navigateToPost(context, postId) : null;
        break;
      default:
        title = 'New notification';
        subtitle = 'Unknown notification type: $type';
    }

    return _FastNotificationTemplate(
      userId: userId,
      title: title,
      subtitle: subtitle,
      timestamp: notification['created_at'],
      onTap: onTap,
      actions: actions,
      userCache: userCache,
      colors: colors,
    );
  }
}

class _FastNotificationTemplate extends StatelessWidget {
  final String userId;
  final String title;
  final String? subtitle;
  final dynamic timestamp;
  final VoidCallback? onTap;
  final List<Widget>? actions;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;

  const _FastNotificationTemplate({
    required this.userId,
    required this.title,
    this.subtitle,
    required this.timestamp,
    this.onTap,
    this.actions,
    required this.userCache,
    required this.colors,
  });

  void _navigateToProfile(BuildContext context, String uid) {
    if (uid.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfileScreen(uid: uid)),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    try {
      if (timestamp is DateTime) {
        return timeago.format(timestamp);
      } else if (timestamp is String) {
        return timeago.format(DateTime.parse(timestamp));
      }
      return 'Just now';
    } catch (e) {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = userCache[userId] ?? {};
    final profilePic = user['photoUrl']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: colors.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: GestureDetector(
          onTap: () => _navigateToProfile(context, userId),
          child: CircleAvatar(
            radius: 21,
            backgroundColor: Colors.transparent,
            backgroundImage: (profilePic.isNotEmpty && profilePic != "default")
                ? NetworkImage(profilePic)
                : null,
            child: (profilePic.isEmpty || profilePic == "default")
                ? Icon(
                    Icons.account_circle,
                    size: 42,
                    color: colors.iconColor,
                  )
                : null,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.textColor,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(color: colors.subtitleTextColor),
              ),
            Text(
              _formatTimestamp(timestamp),
              style: TextStyle(color: colors.subtitleTextColor),
            ),
            if (actions != null) ...actions!,
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
