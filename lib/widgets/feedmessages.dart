import 'package:flutter/material.dart';
import 'package:Ratedly/screens/messaging_screen.dart';
import 'package:Ratedly/resources/messages_firestore_methods.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:provider/provider.dart';

// Define color schemes for both themes at top level
class _FeedMessagesColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;
  final Color appBarBackgroundColor;
  final Color appBarIconColor;
  final Color progressIndicatorColor;
  final Color unreadBadgeColor;

  _FeedMessagesColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
    required this.appBarBackgroundColor,
    required this.appBarIconColor,
    required this.progressIndicatorColor,
    required this.unreadBadgeColor,
  });
}

class _FeedMessagesDarkColors extends _FeedMessagesColorSet {
  _FeedMessagesDarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
          appBarBackgroundColor: const Color(0xFF121212),
          appBarIconColor: const Color(0xFFd9d9d9),
          progressIndicatorColor: const Color(0xFFd9d9d9),
          unreadBadgeColor: const Color(0xFFd9d9d9).withOpacity(0.1),
        );
}

class _FeedMessagesLightColors extends _FeedMessagesColorSet {
  _FeedMessagesLightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.white,
          cardColor: Colors.grey[100]!,
          iconColor: Colors.black,
          appBarBackgroundColor: Colors.white,
          appBarIconColor: Colors.black,
          progressIndicatorColor: Colors.black,
          unreadBadgeColor: Colors.black.withOpacity(0.1),
        );
}

class FeedMessages extends StatefulWidget {
  final String currentUserId;

  const FeedMessages({Key? key, required this.currentUserId}) : super(key: key);

  @override
  _FeedMessagesState createState() => _FeedMessagesState();
}

class _FeedMessagesState extends State<FeedMessages>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _existingChats = [];
  List<String> _blockedUsers = [];
  List<Map<String, dynamic>> _suggestedUsers = [];

  // Caches for optimized performance
  final Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, Map<String, dynamic>> _lastMessageCache = {};
  final Map<String, int> _unreadCountCache = {};

  bool _isLoading = true;
  bool _showSuggestions = false;
  bool _loadingMore = false;
  bool _hasMoreChats = true;

  @override
  bool get wantKeepAlive => true;

  _FeedMessagesColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _FeedMessagesDarkColors() : _FeedMessagesLightColors();
  }

  @override
  void initState() {
    super.initState();
    print('🔵 FeedMessages initState called for user: ${widget.currentUserId}');
    WidgetsBinding.instance.addObserver(this);
    _loadInitialDataUltraFast();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    print('🔵 FeedMessages dispose called');
    super.dispose();
  }

  Future<void> _loadInitialDataUltraFast() async {
    if (!mounted) return;

    print('🔄 Starting _loadInitialDataUltraFast');
    setState(() {
      _isLoading = true;
    });

    try {
      await Future.wait([
        _loadBlockedUsers(),
        _loadChatsMinimal(),
      ]);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      print('✅ _loadInitialDataUltraFast completed');
      print(
          '📊 Current state: ${_existingChats.length} chats, ${_blockedUsers.length} blocked users');

      // Don't wait for background loading
      _loadAdditionalDataInBackground().catchError((e) {
        print('❌ Background loading error: $e');
      });
    } catch (e) {
      print('❌ _loadInitialDataUltraFast error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadChatsMinimal() async {
    print('🔄 Loading minimal chats from Supabase...');

    final chats = await _supabase
        .from('chats')
        .select()
        .contains('participants', [widget.currentUserId])
        .order('last_updated', ascending: false)
        .limit(11);

    print('📥 Raw chats from DB: ${chats.length} total');

    if (chats.isEmpty) {
      print('📭 No chats found in database');
      _existingChats = [];
      return;
    }

    final validChats = <Map<String, dynamic>>[];
    for (final chat in chats) {
      final participants = List<String>.from(chat['participants']);
      final otherUserId = participants.firstWhere(
        (id) => id != widget.currentUserId,
        orElse: () => '',
      );

      print(
          '💬 Processing chat ${chat['id']} with participants: $participants');
      print('   👤 Other user ID: $otherUserId');
      print('   🚫 Is blocked: ${_blockedUsers.contains(otherUserId)}');

      if (otherUserId.isNotEmpty && !_blockedUsers.contains(otherUserId)) {
        print('   ✅ Adding to valid chats');
        validChats.add(chat);
      } else {
        print('   ❌ Skipping - blocked or invalid user');
      }
    }

    print('📋 Final valid chats: ${validChats.length}');

    if (mounted) {
      setState(() {
        _existingChats = validChats;
        _hasMoreChats = chats.length == 11;
      });
    }
  }

  Future<void> _loadAdditionalDataInBackground() async {
    print('🔄 Starting background data loading...');

    if (_existingChats.isEmpty) {
      print('📭 No existing chats to load additional data for');
      return;
    }

    final userIDs = <String>[];
    for (final chat in _existingChats) {
      final participants = List<String>.from(chat['participants']);
      final otherUserId = participants.firstWhere(
        (id) => id != widget.currentUserId,
      );
      userIDs.add(otherUserId);
    }

    print('👥 Loading data for users: $userIDs');

    await Future.wait([
      _loadUsersBatch(userIDs),
      _loadLastMessagesBatch(
          _existingChats.map((c) => c['id'] as String).toList()),
      _loadUnreadCountsBatch(_existingChats),
      _loadSuggestions(),
    ]);

    print('✅ Background data loading completed');
  }

  Future<void> _loadUsersBatch(List<String> userIds) async {
    if (userIds.isEmpty) {
      print('👥 No user IDs to load');
      return;
    }

    print('👥 Loading user batch for IDs: $userIds');

    final users =
        await _supabase.from('users').select().inFilter('uid', userIds);

    print('👥 Retrieved ${users.length} users from database');

    for (final user in users) {
      _userCache[user['uid']] = user;
      print('   👤 Cached user: ${user['username']} (${user['uid']})');
    }

    // Handle missing users - create default entries for users not found
    for (final userId in userIds) {
      if (!_userCache.containsKey(userId)) {
        print(
            '   ❌ User not found in database: $userId, creating default entry');
        _userCache[userId] = {
          'uid': userId,
          'username': 'Not Found',
          'photo_url': 'default'
        };
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadLastMessagesBatch(List<String> chatIds) async {
    if (chatIds.isEmpty) {
      print('💬 No chat IDs to load messages for');
      return;
    }

    print('💬 Loading last messages for chats: $chatIds');

    final messages = await _supabase
        .from('messages')
        .select()
        .inFilter('chat_id', chatIds)
        .order('timestamp', ascending: false);

    print('💬 Retrieved ${messages.length} total messages');

    final messagesByChat = <String, Map<String, dynamic>>{};
    for (final message in messages) {
      final chatId = message['chat_id'] as String;
      if (!messagesByChat.containsKey(chatId)) {
        messagesByChat[chatId] = message;
        print('   💬 Cached last message for chat $chatId');
      }
    }
    _lastMessageCache.addAll(messagesByChat);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadUnreadCountsBatch(List<Map<String, dynamic>> chats) async {
    print('🔢 Loading unread counts for ${chats.length} chats');

    for (final chat in chats) {
      final count = await SupabaseMessagesMethods()
          .getUnreadCount(chat['id'], widget.currentUserId)
          .first;
      _unreadCountCache[chat['id']] = count;
      print('   🔢 Chat ${chat['id']} unread count: $count');
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadMoreChats() async {
    if (!_hasMoreChats) {
      print('📭 No more chats to load');
      return;
    }

    if (_loadingMore) {
      print('⏳ Already loading more chats');
      return;
    }

    print('🔄 Loading more chats...');

    setState(() {
      _loadingMore = true;
    });

    final start = _existingChats.length;
    final end = start + 10;

    final moreChats = await _supabase
        .from('chats')
        .select()
        .contains('participants', [widget.currentUserId])
        .order('last_updated', ascending: false)
        .range(start, end);

    print('📥 Loaded ${moreChats.length} more chats');

    if (moreChats.isEmpty) {
      print('📭 No more chats available');
      setState(() {
        _hasMoreChats = false;
        _loadingMore = false;
      });
      return;
    }

    setState(() {
      _existingChats.addAll(moreChats);
      _loadingMore = false;
      _hasMoreChats = moreChats.length == 11;
    });

    print('📊 Total chats now: ${_existingChats.length}');

    _processNewChats(moreChats);
  }

  void _processNewChats(List<Map<String, dynamic>> newChats) async {
    print('🔄 Processing ${newChats.length} new chats');

    final newUserIds = <String>{};
    final newChatIds = <String>[];

    for (final chat in newChats) {
      final participants = List<String>.from(chat['participants']);
      final otherUserId = participants.firstWhere(
        (id) => id != widget.currentUserId,
      );
      if (!_userCache.containsKey(otherUserId)) {
        newUserIds.add(otherUserId);
      }
      newChatIds.add(chat['id'] as String);
    }

    print('👥 New user IDs to load: $newUserIds');
    print('💬 New chat IDs to load: $newChatIds');

    if (newUserIds.isNotEmpty) {
      await _loadUsersBatch(newUserIds.toList());
    }

    if (newChatIds.isNotEmpty) {
      await _loadLastMessagesBatch(newChatIds);
    }

    await _loadUnreadCountsBatch(newChats);
  }

  void _refreshData() {
    print('🔄 Manual refresh triggered');
    _loadInitialDataUltraFast();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('📱 App lifecycle state changed: $state');
    if (state == AppLifecycleState.resumed) {
      _refreshData();
    }
  }

  Future<void> _loadBlockedUsers() async {
    print('🔄 Loading blocked users...');

    try {
      final blockedUsers =
          await SupabaseBlockMethods().getBlockedUsers(widget.currentUserId);

      print('🚫 Blocked users loaded: $blockedUsers');

      if (mounted) {
        setState(() {
          _blockedUsers = blockedUsers;
        });
      }
    } catch (e) {
      print('❌ Error loading blocked users: $e');
      if (mounted) {
        setState(() {
          _blockedUsers = [];
        });
      }
    }
  }

  Future<void> _loadSuggestions() async {
    print('💡 Checking for user suggestions...');

    if (_existingChats.length >= 3) {
      print('💡 Enough chats (${_existingChats.length}), skipping suggestions');
      return;
    }

    final suggestedUserIds =
        await _getSuggestedUsers(3 - _existingChats.length);

    print('💡 Suggested user IDs: $suggestedUserIds');

    if (suggestedUserIds.isNotEmpty) {
      final users = await _supabase
          .from('users')
          .select()
          .inFilter('uid', suggestedUserIds);

      print('💡 Loaded ${users.length} suggested users');

      if (mounted) {
        setState(() {
          _suggestedUsers = users.cast<Map<String, dynamic>>();
          _showSuggestions = users.isNotEmpty;
        });
      }
    } else {
      print('💡 No suggested users found');
    }
  }

  Future<List<String>> _getSuggestedUsers(int count) async {
    if (count <= 0) {
      return [];
    }

    print('💡 Getting $count suggested users');

    final existingUserIds = _existingChats.map((chat) {
      final participants = List<String>.from(chat['participants']);
      return participants.firstWhere((id) => id != widget.currentUserId);
    }).toList();

    print('💡 Existing user IDs in chats: $existingUserIds');

    final followsData = await _supabase
        .from('follows')
        .select('follower_id, following_id')
        .or('follower_id.eq.${widget.currentUserId},following_id.eq.${widget.currentUserId}');

    final following = <String>[];
    final followers = <String>[];

    for (final follow in followsData) {
      if (follow['follower_id'] == widget.currentUserId) {
        following.add(follow['following_id'] as String);
      }
      if (follow['following_id'] == widget.currentUserId) {
        followers.add(follow['follower_id'] as String);
      }
    }

    print('💡 Following: $following');
    print('💡 Followers: $followers');

    List<String> candidates = [...following, ...followers]
        .where((id) => id != widget.currentUserId)
        .where((id) => !existingUserIds.contains(id))
        .where((id) => !_blockedUsers.contains(id))
        .toSet()
        .toList();

    print('💡 Candidate users after filtering: $candidates');

    return candidates.take(count).toList();
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Just now';
    final Duration difference = DateTime.now().difference(timestamp);

    if (difference.inDays > 0) return '${difference.inDays}d';
    if (difference.inHours > 0) return '${difference.inHours}h';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m';
    return 'Just now';
  }

  Widget _buildBlockedMessageItem(_FeedMessagesColorSet colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: colors.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.block, color: Colors.red[400], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This conversation is unavailable due to blocking',
              style: TextStyle(
                color: colors.textColor.withOpacity(0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(String photoUrl, _FeedMessagesColorSet colors) {
    final hasValidPhoto =
        photoUrl.isNotEmpty && photoUrl != "default" && photoUrl != "null";

    return CircleAvatar(
      radius: 21,
      backgroundColor: colors.cardColor,
      backgroundImage: hasValidPhoto ? NetworkImage(photoUrl) : null,
      child: !hasValidPhoto
          ? Icon(
              Icons.account_circle,
              size: 42,
              color: colors.iconColor,
            )
          : null,
    );
  }

  Widget _buildSuggestionItem(
      Map<String, dynamic> userData, _FeedMessagesColorSet colors) {
    final username = userData['username'] ?? 'Unknown';
    final photoUrl = userData['photo_url'] ?? '';
    final userId = userData['uid'] ?? '';

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.cardColor, width: 0.5),
        ),
      ),
      child: ListTile(
        leading: _buildUserAvatar(photoUrl, colors),
        title: Text(username, style: TextStyle(color: colors.textColor)),
        trailing: Icon(Icons.person_add_alt_1, color: colors.iconColor),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MessagingScreen(
                recipientUid: userId,
                recipientUsername: username,
                recipientPhotoUrl: photoUrl,
              ),
            ),
          );

          if (result == true) {
            _refreshData();
          }
        },
      ),
    );
  }

  Widget _buildChatItem(
      Map<String, dynamic> chat, _FeedMessagesColorSet colors) {
    final participants = List<String>.from(chat['participants']);
    final otherUserId = participants.firstWhere(
      (id) => id != widget.currentUserId,
      orElse: () => '',
    );

    print('🏗️ Building chat item for chat ${chat['id']}');
    print('   👥 Participants: $participants');
    print('   👤 Other user ID: $otherUserId');

    if (otherUserId.isEmpty) {
      print('   ❌ Empty other user ID, returning empty widget');
      return const SizedBox.shrink();
    }

    // Return empty widget if user is blocked - they won't appear at all
    if (_blockedUsers.contains(otherUserId)) {
      print('   🚫 User $otherUserId is blocked, skipping chat');
      return const SizedBox.shrink();
    }

    final userData = _userCache[otherUserId];
    if (userData == null) {
      print('   ⏳ User data not cached yet, showing skeleton for $otherUserId');
      return _buildDetailedChatSkeleton(colors);
    }

    // Use default values if user data is incomplete
    final username = userData['username'] ?? 'Unknown User';
    final photoUrl = userData['photo_url'] ?? 'default';

    final lastMessageData = _lastMessageCache[chat['id']];

    String lastMessage = 'No messages yet';
    String timestampText = '';
    bool isCurrentUserSender = false;
    bool isMessageRead = false;

    if (lastMessageData != null) {
      isMessageRead = lastMessageData['is_read'] ?? false;
      lastMessage = lastMessageData['message'] ?? '';
      final DateTime? timestamp = lastMessageData['timestamp'] is String
          ? DateTime.parse(lastMessageData['timestamp'])
          : lastMessageData['timestamp'];
      timestampText = _formatTimestamp(timestamp);
      isCurrentUserSender =
          lastMessageData['sender_id'] == widget.currentUserId;
    }

    final unreadCount = _unreadCountCache[chat['id']] ?? 0;

    print('   ✅ Building chat with $username ($otherUserId)');
    print('   💬 Last message: $lastMessage');
    print('   🔢 Unread count: $unreadCount');

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.cardColor, width: 0.5),
        ),
      ),
      child: ListTile(
        leading: _buildUserAvatar(photoUrl, colors),
        title: Text(username, style: TextStyle(color: colors.textColor)),
        subtitle: Row(
          children: [
            if (isCurrentUserSender)
              Icon(
                isMessageRead ? Icons.done_all : Icons.done,
                size: 16,
                color: colors.textColor.withOpacity(0.6),
              ),
            Expanded(
              child: Text(
                lastMessage,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textColor.withOpacity(0.6)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              timestampText,
              style: TextStyle(
                color: colors.textColor.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: unreadCount > 0
            ? Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.unreadBadgeColor,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  unreadCount.toString(),
                  style: TextStyle(color: colors.textColor, fontSize: 12),
                ),
              )
            : null,
        onTap: () async {
          await SupabaseMessagesMethods()
              .markMessagesAsRead(chat['id'], widget.currentUserId);

          _unreadCountCache[chat['id']] = 0;
          setState(() {});

          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MessagingScreen(
                recipientUid: otherUserId,
                recipientUsername: username,
                recipientPhotoUrl: photoUrl,
              ),
            ),
          );

          if (result == true) {
            _refreshData();
          }
        },
      ),
    );
  }

  Widget _buildDetailedChatSkeleton(_FeedMessagesColorSet colors) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.cardColor, width: 0.5),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 21,
          backgroundColor: colors.cardColor.withOpacity(0.5),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 14,
              width: 120,
              decoration: BoxDecoration(
                color: colors.cardColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 12,
              width: 180,
              decoration: BoxDecoration(
                color: colors.cardColor.withOpacity(0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
        trailing: Container(
          width: 40,
          height: 20,
          decoration: BoxDecoration(
            color: colors.cardColor.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionSkeleton(_FeedMessagesColorSet colors) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.cardColor, width: 0.5),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 21,
          backgroundColor: colors.cardColor.withOpacity(0.5),
        ),
        title: Container(
          height: 16,
          width: 100,
          decoration: BoxDecoration(
            color: colors.cardColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        trailing: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: colors.cardColor.withOpacity(0.4),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeaderSkeleton(_FeedMessagesColorSet colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Container(
        height: 18,
        width: 80,
        decoration: BoxDecoration(
          color: colors.cardColor.withOpacity(0.6),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _buildEmptyStateSkeleton(_FeedMessagesColorSet colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.chat_bubble_outline,
          size: 64,
          color: colors.textColor.withOpacity(0.3),
        ),
        const SizedBox(height: 16),
        Container(
          height: 20,
          width: 150,
          decoration: BoxDecoration(
            color: colors.cardColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 16,
          width: 200,
          decoration: BoxDecoration(
            color: colors.cardColor.withOpacity(0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    print('🏗️ Building FeedMessages widget');
    print(
        '📊 Current state: isLoading=$_isLoading, chats=${_existingChats.length}, blockedUsers=${_blockedUsers.length}');

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        iconTheme: IconThemeData(color: colors.appBarIconColor),
        backgroundColor: colors.appBarBackgroundColor,
        title: Text('Messages', style: TextStyle(color: colors.textColor)),
        elevation: 0,
      ),
      body: _isLoading
          ? _buildEnhancedSkeletonLoading(colors)
          : _buildContent(colors),
    );
  }

  Widget _buildEnhancedSkeletonLoading(_FeedMessagesColorSet colors) {
    print('🎨 Building enhanced skeleton loading');
    return ListView(
      children: [
        _buildSectionHeaderSkeleton(colors),
        _buildDetailedChatSkeleton(colors),
        _buildDetailedChatSkeleton(colors),
        _buildDetailedChatSkeleton(colors),
        _buildSectionHeaderSkeleton(colors),
        _buildSuggestionSkeleton(colors),
        _buildSuggestionSkeleton(colors),
        _buildDetailedChatSkeleton(colors),
        _buildDetailedChatSkeleton(colors),
      ],
    );
  }

  Widget _buildContent(_FeedMessagesColorSet colors) {
    final hasChats = _existingChats.isNotEmpty;
    final hasSuggestions = _showSuggestions && _suggestedUsers.isNotEmpty;

    print(
        '📦 Building content: hasChats=$hasChats, hasSuggestions=$hasSuggestions');

    if (!hasChats && !hasSuggestions) {
      print('📭 Showing empty state');
      return Center(
        child: _buildEmptyStateSkeleton(colors),
      );
    }

    final totalItemCount = _existingChats.length +
        _suggestedUsers.length +
        (_hasMoreChats ? 1 : 0);

    print(
        '📋 Total item count: $totalItemCount (${_existingChats.length} chats + ${_suggestedUsers.length} suggestions)');

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollNotification) {
        if (scrollNotification is ScrollEndNotification) {
          final metrics = scrollNotification.metrics;
          if (metrics.extentAfter < 500) {
            _loadMoreChats();
          }
        }
        return false;
      },
      child: ListView.builder(
        itemCount: totalItemCount,
        itemBuilder: (context, index) {
          print('🔨 Building list item at index: $index');

          if (index < _existingChats.length) {
            final chat = _existingChats[index];
            print('   💬 Building chat item for index $index');
            return _buildChatItem(chat, colors);
          } else if (index < _existingChats.length + _suggestedUsers.length) {
            final suggestionIndex = index - _existingChats.length;
            final userData = _suggestedUsers[suggestionIndex];
            print('   💡 Building suggestion item for index $index');
            return _buildSuggestionItem(userData, colors);
          } else {
            print('   🔄 Building loading indicator for index $index');
            return _buildLoadingIndicator(colors);
          }
        },
      ),
    );
  }

  Widget _buildLoadingIndicator(_FeedMessagesColorSet colors) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: CircularProgressIndicator(
          color: colors.progressIndicatorColor,
        ),
      ),
    );
  }
}
