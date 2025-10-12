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
  // REMOVED: Ad-related variables
  // BannerAd? _bannerAd;
  // bool _isAdLoaded = false;

  // Helper method to get the appropriate color scheme
  _NotificationColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _NotificationDarkColors() : _NotificationLightColors();
  }

  @override
  void initState() {
    super.initState();
    // REMOVED: _loadBannerAd();
  }

  // REMOVED: _loadBannerAd method

  @override
  void dispose() {
    // REMOVED: _bannerAd?.dispose();
    super.dispose();
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
      body: _NotificationList(
        currentUserId: userProvider.user!.uid,
        colors: colors,
      ),
    );
  }
}

class _NotificationList extends StatefulWidget {
  final String currentUserId;
  final _NotificationColorSet colors;

  const _NotificationList({required this.currentUserId, required this.colors});

  @override
  State<_NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<_NotificationList> {
  final List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DateTime? _lastCreatedAt;
  final ScrollController _scrollController = ScrollController();
  final int _initialLimit = 10;
  final int _loadMoreLimit = 5;

  // Cache for user profiles to avoid repeated fetches
  final Map<String, Map<String, dynamic>> _userCache = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadNotifications(initialLoad: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadNotifications();
    }
  }

  // Add this method to refresh notifications
  void refreshNotifications() {
    setState(() {
      _notifications.clear();
      _lastCreatedAt = null;
      _hasMore = true;
      _isLoading = true;
    });
    _loadNotifications(initialLoad: true);
  }

  Future<void> _loadNotifications({bool initialLoad = false}) async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      if (initialLoad) {
        _isLoading = true;
        _notifications.clear();
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final supabase = Supabase.instance.client;
      final limit = initialLoad ? _initialLimit : _loadMoreLimit;
      final userId = widget.currentUserId;

      // Parse different response shapes
      List<Map<String, dynamic>> _parseResponse(dynamic resp) {
        try {
          if (resp == null) return [];
          if (resp is List) {
            return resp
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
          return [];
        } catch (e) {
          return [];
        }
      }

      // Try snake_case column names first
      List<Map<String, dynamic>> newNotifications = [];
      try {
        final response = await supabase
            .from('notifications')
            .select()
            .eq('target_user_id', userId)
            .neq('type', 'message')
            .order('created_at', ascending: false)
            .limit(limit);

        newNotifications = _parseResponse(response);
      } catch (err) {
        // If snake_case fails, try camelCase
        try {
          final response = await supabase
              .from('notifications')
              .select()
              .eq('targetUserId', userId)
              .neq('type', 'message')
              .order('createdAt', ascending: false)
              .limit(limit);

          newNotifications = _parseResponse(response);
        } catch (err) {
          // Both failed, return empty list
        }
      }

      if (newNotifications.isNotEmpty) {
        final lastNotification = newNotifications.last;
        final lastTimestamp = lastNotification['createdAt'] ??
            lastNotification['created_at'] ??
            DateTime.now().toIso8601String();

        if (lastTimestamp is String) {
          _lastCreatedAt = DateTime.tryParse(lastTimestamp);
        } else if (lastTimestamp is DateTime) {
          _lastCreatedAt = lastTimestamp;
        }

        // Prefetch user data for all notifications
        await _prefetchUserData(newNotifications);

        setState(() {
          _notifications.addAll(newNotifications);
        });
      }

      setState(() => _hasMore = newNotifications.length == limit);
    } catch (e, st) {
      setState(() => _hasMore = false);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  // Prefetch user data for all notifications to minimize database calls
  Future<void> _prefetchUserData(
      List<Map<String, dynamic>> notifications) async {
    final supabase = Supabase.instance.client;
    final Set<String> userIdsToFetch = {};

    // Identify all unique user IDs from notifications
    for (final notification in notifications) {
      final userId = _extractUserIdFromNotification(notification);
      if (userId != null &&
          userId.isNotEmpty &&
          !_userCache.containsKey(userId)) {
        userIdsToFetch.add(userId);
      }
    }

    if (userIdsToFetch.isEmpty) return;

    try {
      // For older Supabase versions without the 'in_' method, we'll use multiple OR conditions
      // or fetch users one by one (less efficient but works)
      for (final userId in userIdsToFetch) {
        try {
          final response = await supabase
              .from('users')
              .select()
              .eq('uid', userId)
              .maybeSingle();

          if (response != null) {
            final userMap = Map<String, dynamic>.from(response as Map);
            _userCache[userId] = userMap;
          }
        } catch (e) {
          // Silently handle individual user fetch errors
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  // Extract user ID from notification based on type
  String? _extractUserIdFromNotification(Map<String, dynamic> notification) {
    final type = notification['type'] as String?;

    // Helper to get field with case-insensitive lookup
    dynamic getField(String field) {
      if (notification.containsKey(field)) return notification[field];

      final snakeCase = _camelToSnake(field);
      if (notification.containsKey(snakeCase)) return notification[snakeCase];

      final customData =
          notification['customData'] ?? notification['custom_data'];
      if (customData is Map) {
        if (customData.containsKey(field)) return customData[field];
        if (customData.containsKey(snakeCase)) return customData[snakeCase];
      }

      return null;
    }

    switch (type) {
      case 'comment':
        return getField('commenterUid');
      case 'post_rating':
        return getField('raterUid');
      case 'follow_request':
        return getField('requesterId');
      case 'follow_request_accepted':
        return getField('approverId');
      case 'comment_like':
        return getField('likerUid');
      case 'follow':
        return getField('followerId');
      case 'reply':
        return getField('replierUid');
      case 'reply_like':
        return getField('likerUid');
      default:
        return null;
    }
  }

  String _camelToSnake(String input) {
    return input.replaceAllMapped(
        RegExp(r'[A-Z]'), (match) => '_${match.group(0)!.toLowerCase()}');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
          child: CircularProgressIndicator(
              color: widget.colors.progressIndicatorColor));
    }

    if (_notifications.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Text(
            'No notifications yet. Follow, rate posts, and comment.',
            style: TextStyle(color: widget.colors.textColor, fontSize: 16),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: _notifications.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _notifications.length) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
                child: CircularProgressIndicator(
                    color: widget.colors.progressIndicatorColor)),
          );
        }

        final notification = _notifications[index];
        return _NotificationItem(
          notification: notification,
          currentUserId: widget.currentUserId,
          userCache: _userCache,
          colors: widget.colors,
          refreshNotifications: refreshNotifications, // Add this line
        );
      },
    );
  }
}

class _NotificationItem extends StatelessWidget {
  final Map<String, dynamic> notification;
  final String currentUserId;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;
  final VoidCallback? refreshNotifications; // Add this

  const _NotificationItem({
    required this.notification,
    required this.currentUserId,
    required this.userCache,
    required this.colors,
    this.refreshNotifications, // Add this
  });

  // Helper to get data from notification with case-insensitive lookup
  dynamic getField(String field) {
    // Direct key lookup
    if (notification.containsKey(field)) return notification[field];

    // Try camelCase variations
    final camelCase = field;
    if (notification.containsKey(camelCase)) return notification[camelCase];

    // Try snake_case variations
    final snakeCase = _camelToSnake(field);
    if (notification.containsKey(snakeCase)) return notification[snakeCase];

    // Check customData JSON
    final customData =
        notification['customData'] ?? notification['custom_data'];
    if (customData is Map) {
      if (customData.containsKey(field)) return customData[field];
      if (customData.containsKey(snakeCase)) return customData[snakeCase];
    }

    return null;
  }

  String _camelToSnake(String input) {
    return input.replaceAllMapped(
        RegExp(r'[A-Z]'), (match) => '_${match.group(0)!.toLowerCase()}');
  }

  @override
  Widget build(BuildContext context) {
    final type = notification['type'] as String?;

    switch (type) {
      case 'comment':
        return _CommentNotification(
          notification: notification,
          getField: getField,
          userCache: userCache,
          colors: colors,
        );
      case 'post_rating':
        return _PostRatingNotification(
          notification: notification,
          getField: getField,
          userCache: userCache,
          colors: colors,
        );
      case 'follow_request':
        return _FollowRequestNotification(
          notification: notification,
          currentUserId: currentUserId,
          getField: getField,
          userCache: userCache,
          colors: colors,
          refreshNotifications: refreshNotifications, // Pass to follow request
        );
      case 'follow_request_accepted':
        return _FollowAcceptedNotification(
          notification: notification,
          getField: getField,
          userCache: userCache,
          colors: colors,
        );
      case 'comment_like':
        return _CommentLikeNotification(
          notification: notification,
          getField: getField,
          userCache: userCache,
          colors: colors,
        );
      case 'follow':
        return _FollowNotification(
          notification: notification,
          getField: getField,
          userCache: userCache,
          colors: colors,
        );
      case 'reply':
        return _ReplyNotification(
          notification: notification,
          getField: getField,
          userCache: userCache,
          colors: colors,
        );
      case 'reply_like':
        return _ReplyLikeNotification(
          notification: notification,
          getField: getField,
          userCache: userCache,
          colors: colors,
        );
      default:
        return _NotificationTemplate(
          userId: '',
          title: 'New notification',
          timestamp: getField('created_at'),
          subtitle: 'Unknown notification type: $type',
          userCache: userCache,
          colors: colors,
        );
    }
  }
}

// ===== NOTIFICATION TYPE WIDGETS =====

class _ReplyNotification extends StatelessWidget {
  final Map<String, dynamic> notification;
  final dynamic Function(String) getField;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;

  const _ReplyNotification({
    required this.notification,
    required this.getField,
    required this.userCache,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final replierUid = getField('replierUid') ?? '';
    final user = userCache[replierUid] ?? {};
    final username = user['username'] ?? 'Someone';

    return _NotificationTemplate(
      userId: replierUid,
      title: '$username replied to your comment',
      subtitle: getField('replyText'),
      timestamp: getField('created_at'),
      onTap: () => _navigateToPost(
        context,
        getField('postId'),
        commentId: getField('commentId'),
        replyId: getField('replyId'),
      ),
      userCache: userCache,
      colors: colors,
    );
  }
}

class _ReplyLikeNotification extends StatelessWidget {
  final Map<String, dynamic> notification;
  final dynamic Function(String) getField;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;

  const _ReplyLikeNotification({
    required this.notification,
    required this.getField,
    required this.userCache,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final likerUid = getField('likerUid') ?? '';
    final user = userCache[likerUid] ?? {};
    final username = user['username'] ?? 'Someone';

    return _NotificationTemplate(
      userId: likerUid,
      title: '$username liked your reply',
      subtitle: getField('replyText'),
      timestamp: getField('created_at'),
      onTap: () => _navigateToPost(
        context,
        getField('postId'),
        commentId: getField('commentId'),
        replyId: getField('replyId'),
      ),
      userCache: userCache,
      colors: colors,
    );
  }
}

class _FollowNotification extends StatelessWidget {
  final Map<String, dynamic> notification;
  final dynamic Function(String) getField;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;

  const _FollowNotification({
    required this.notification,
    required this.getField,
    required this.userCache,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final followerId = getField('followerId') ?? '';
    final user = userCache[followerId] ?? {};
    final username = user['username'] ?? 'Someone';

    return _NotificationTemplate(
      userId: followerId,
      title: '$username started following you',
      timestamp: getField('created_at'),
      onTap: () => _navigateToProfile(context, followerId),
      userCache: userCache,
      colors: colors,
    );
  }
}

class _CommentNotification extends StatelessWidget {
  final Map<String, dynamic> notification;
  final dynamic Function(String) getField;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;

  const _CommentNotification({
    required this.notification,
    required this.getField,
    required this.userCache,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final commenterUid = getField('commenterUid') ?? '';
    final user = userCache[commenterUid] ?? {};
    final username = user['username'] ?? 'Someone';

    return _NotificationTemplate(
      userId: commenterUid,
      title: '$username commented on your post',
      subtitle: getField('commentText'),
      timestamp: getField('created_at'),
      onTap: () => _navigateToPost(
        context,
        getField('postId'),
        commentId: getField('commentId'),
      ),
      userCache: userCache,
      colors: colors,
    );
  }
}

class _PostRatingNotification extends StatelessWidget {
  final Map<String, dynamic> notification;
  final dynamic Function(String) getField;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;

  const _PostRatingNotification({
    required this.notification,
    required this.getField,
    required this.userCache,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final raterUid = getField('raterUid') ?? '';
    final rating = (getField('rating') as num?)?.toDouble() ?? 0.0;
    final postId = getField('postId') ?? '';
    final user = userCache[raterUid] ?? {};
    final username = user['username'] ?? 'Someone';

    return _NotificationTemplate(
      userId: raterUid,
      title: '$username rated your post',
      subtitle: 'Rating: ${rating.toStringAsFixed(1)}',
      timestamp: getField('created_at'),
      onTap: () => _navigateToPost(context, postId),
      userCache: userCache,
      colors: colors,
    );
  }
}

class _FollowRequestNotification extends StatelessWidget {
  final Map<String, dynamic> notification;
  final String currentUserId;
  final dynamic Function(String) getField;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;
  final VoidCallback? refreshNotifications;

  const _FollowRequestNotification({
    required this.notification,
    required this.currentUserId,
    required this.getField,
    required this.userCache,
    required this.colors,
    this.refreshNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final provider =
        Provider.of<SupabaseProfileMethods>(context, listen: false);
    final requesterId = getField('requesterId') ?? '';
    final user = userCache[requesterId] ?? {};
    final username = user['username'] ?? 'Someone';

    // Create handler functions that refresh after the action
    Future<void> _handleAccept() async {
      await provider.acceptFollowRequest(currentUserId, requesterId);
      if (refreshNotifications != null) {
        refreshNotifications!(); // Trigger refresh
      }
    }

    Future<void> _handleDecline() async {
      await provider.declineFollowRequest(currentUserId, requesterId);
      if (refreshNotifications != null) {
        refreshNotifications!(); // Trigger refresh
      }
    }

    return _NotificationTemplate(
      userId: requesterId,
      title: '$username wants to follow you',
      timestamp: getField('created_at'),
      actions: [
        TextButton(
          onPressed: _handleAccept,
          child: Text('Accept', style: TextStyle(color: colors.textColor)),
        ),
        TextButton(
          onPressed: _handleDecline,
          child: Text('Decline', style: TextStyle(color: colors.textColor)),
        ),
      ],
      userCache: userCache,
      colors: colors,
    );
  }
}

class _FollowAcceptedNotification extends StatelessWidget {
  final Map<String, dynamic> notification;
  final dynamic Function(String) getField;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;

  const _FollowAcceptedNotification({
    required this.notification,
    required this.getField,
    required this.userCache,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final approverId = getField('approverId') ?? '';
    final user = userCache[approverId] ?? {};
    final username = user['username'] ?? 'Someone';

    return _NotificationTemplate(
      userId: approverId,
      title: '$username approved your follow request',
      timestamp: getField('created_at'),
      onTap: () => _navigateToProfile(context, approverId),
      userCache: userCache,
      colors: colors,
    );
  }
}

class _CommentLikeNotification extends StatelessWidget {
  final Map<String, dynamic> notification;
  final dynamic Function(String) getField;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;

  const _CommentLikeNotification({
    required this.notification,
    required this.getField,
    required this.userCache,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final likerUid = getField('likerUid') ?? '';
    final user = userCache[likerUid] ?? {};
    final username = user['username'] ?? 'Someone';

    return _NotificationTemplate(
      userId: likerUid,
      title: '$username liked your comment',
      subtitle: getField('commentText'),
      timestamp: getField('created_at'),
      onTap: () => _navigateToPost(
        context,
        getField('postId'),
        commentId: getField('commentId'),
      ),
      userCache: userCache,
      colors: colors,
    );
  }
}

class _NotificationTemplate extends StatelessWidget {
  final String userId;
  final String title;
  final String? subtitle;
  final dynamic timestamp;
  final VoidCallback? onTap;
  final List<Widget>? actions;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;

  const _NotificationTemplate({
    required this.userId,
    required this.title,
    this.subtitle,
    required this.timestamp,
    this.onTap,
    this.actions,
    required this.userCache,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: colors.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ListTile(
        leading: GestureDetector(
          onTap: () => _navigateToProfile(context, userId),
          child:
              _UserAvatar(userId: userId, userCache: userCache, colors: colors),
        ),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: colors.textColor)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null)
              Text(subtitle!,
                  style: TextStyle(color: colors.subtitleTextColor)),
            Text(_formatTimestamp(timestamp),
                style: TextStyle(color: colors.subtitleTextColor)),
            if (actions != null) Row(children: actions!),
          ],
        ),
        onTap: onTap,
      ),
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
}

class _UserAvatar extends StatelessWidget {
  final String userId;
  final Map<String, Map<String, dynamic>> userCache;
  final _NotificationColorSet colors;

  const _UserAvatar({
    required this.userId,
    required this.userCache,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final user = userCache[userId] ?? {};
    final profilePic = user['photoUrl']?.toString() ?? '';

    return CircleAvatar(
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
    );
  }
}

void _navigateToProfile(BuildContext context, String uid) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => ProfileScreen(uid: uid)),
  );
}

void _navigateToPost(BuildContext context, dynamic postId,
    {String? commentId, String? replyId}) async {
  if (postId == null) return;

  final supabase = Supabase.instance.client;
  try {
    final response = await supabase
        .from('posts')
        .select()
        .eq('postId', postId.toString())
        .maybeSingle();

    if (response != null) {
      final postData = response as Map<String, dynamic>;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageViewScreen(
            imageUrl: postData['postUrl'],
            postId: postId.toString(),
            description: postData['description'],
            userId: postData['uid'],
            username: postData['username'],
            profImage: postData['profImage'],
            datePublished: postData['datePublished'],
          ),
        ),
      );
    }
  } catch (e) {
    // Error handling
  }
}
