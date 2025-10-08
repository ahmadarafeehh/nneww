import 'package:flutter/material.dart';
import 'package:Ratedly/screens/messaging_screen.dart';
import 'package:Ratedly/resources/messages_firestore_methods.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/utils/theme_provider.dart'; // Add this import
import 'package:provider/provider.dart'; // Add this import

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

class _FeedMessagesState extends State<FeedMessages> {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _existingChats = [];
  List<String> _blockedUsers = [];
  List<String> _suggestedUserIds = [];
  bool _showSuggestions = false;

  // Helper method to get the appropriate color scheme
  _FeedMessagesColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _FeedMessagesDarkColors() : _FeedMessagesLightColors();
  }

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    final blockedUsers =
        await SupabaseBlockMethods().getBlockedUsers(widget.currentUserId);
    setState(() {
      _blockedUsers = blockedUsers;
    });
  }

  Future<List<String>> _getSuggestedUsers(int count) async {
    if (count <= 0) return [];

    final existingUserIds = _existingChats.map((chat) {
      final participants = List<String>.from(chat['participants']);
      return participants.firstWhere((id) => id != widget.currentUserId);
    }).toList();

    final blockedUsers =
        await SupabaseBlockMethods().getBlockedUsers(widget.currentUserId);

    // Get following and followers from Supabase
    final followingResponse = await _supabase
        .from('follows')
        .select('following_id')
        .eq('follower_id', widget.currentUserId);

    final followersResponse = await _supabase
        .from('follows')
        .select('follower_id')
        .eq('following_id', widget.currentUserId);

    final following = (followingResponse as List)
        .map((r) => r['following_id'] as String)
        .toList();
    final followers = (followersResponse as List)
        .map((r) => r['follower_id'] as String)
        .toList();

    List<String> candidates = [...following, ...followers]
        .where((id) => id != widget.currentUserId)
        .where((id) => !existingUserIds.contains(id))
        .where((id) => !blockedUsers.contains(id))
        .toSet()
        .toList();

    List<String> suggested = candidates.take(count).toList();
    count -= suggested.length;

    if (count > 0) {
      final allUsers = await _supabase
          .from('users')
          .select('uid')
          .not(
              'uid',
              'in',
              '(${[
                ...existingUserIds,
                widget.currentUserId,
                ...blockedUsers
              ].map((id) => "'$id'").join(',')})')
          .limit(50);

      final allUserIds =
          (allUsers as List).map((user) => user['uid'] as String).toList();
      allUserIds.shuffle();
      suggested.addAll(allUserIds.take(count));
    }

    return suggested;
  }

  void _loadSuggestions() async {
    final existingCount = _existingChats.length;
    if (existingCount >= 3) return;

    final suggestions = await _getSuggestedUsers(3 - existingCount);
    if (mounted) {
      setState(() {
        _suggestedUserIds = suggestions;
        _showSuggestions = suggestions.isNotEmpty;
      });
    }
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
    return CircleAvatar(
      radius: 21,
      backgroundColor: colors.cardColor,
      backgroundImage: (photoUrl.isNotEmpty && photoUrl != "default")
          ? NetworkImage(photoUrl)
          : null,
      child: (photoUrl.isEmpty || photoUrl == "default")
          ? Icon(
              Icons.account_circle,
              size: 42,
              color: colors.iconColor,
            )
          : null,
    );
  }

  Widget _buildSuggestionItem(String userId, _FeedMessagesColorSet colors) {
    return FutureBuilder(
      future: _supabase.from('users').select().eq('uid', userId).single(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError)
          return const SizedBox.shrink();

        final userData = snapshot.data as Map<String, dynamic>;
        final username = userData['username'] ?? 'Unknown';
        final photoUrl = userData['photo_url'] ?? '';

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
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MessagingScreen(
                  recipientUid: userId,
                  recipientUsername: username,
                  recipientPhotoUrl: photoUrl,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatItem(
      Map<String, dynamic> chat, _FeedMessagesColorSet colors) {
    final participants = List<String>.from(chat['participants']);
    final otherUserId = participants
        .firstWhere((id) => id != widget.currentUserId, orElse: () => '');

    if (otherUserId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder(
      future: Future.wait<dynamic>([
        _supabase.from('users').select().eq('uid', otherUserId).single(),
        SupabaseBlockMethods()
            .isMutuallyBlocked(widget.currentUserId, otherUserId)
      ]),
      builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final userData = snapshot.data![0] as Map<String, dynamic>;
        final isMutuallyBlocked = snapshot.data![1] as bool;

        if (isMutuallyBlocked) {
          return _buildBlockedMessageItem(colors);
        }

        final username = userData['username'] ?? 'Unknown';
        final photoUrl = userData['photo_url'] ?? '';

        return FutureBuilder(
          future: _supabase
              .from('messages')
              .select()
              .eq('chat_id', chat['id'])
              .order('timestamp', ascending: false)
              .limit(1)
              .maybeSingle(),
          builder: (context, messageSnapshot) {
            String lastMessage = 'No messages yet';
            String timestampText = '';
            bool isCurrentUserSender = false;
            bool isMessageRead = false;

            if (messageSnapshot.hasData && messageSnapshot.data != null) {
              final messageData = messageSnapshot.data as Map<String, dynamic>;

              isMessageRead = messageData['is_read'] ?? false;
              lastMessage = messageData['message'] ?? '';
              final DateTime? timestamp = messageData['timestamp'] is String
                  ? DateTime.parse(messageData['timestamp'])
                  : messageData['timestamp'];
              timestampText = _formatTimestamp(timestamp);
              isCurrentUserSender =
                  messageData['sender_id'] == widget.currentUserId;
            }

            return StreamBuilder<int>(
              stream: SupabaseMessagesMethods()
                  .getUnreadCount(chat['id'], widget.currentUserId),
              builder: (context, unreadSnapshot) {
                final unreadCount = unreadSnapshot.data ?? 0;

                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: colors.cardColor, width: 0.5),
                    ),
                  ),
                  child: ListTile(
                    leading: _buildUserAvatar(photoUrl, colors),
                    title: Text(username,
                        style: TextStyle(color: colors.textColor)),
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
                            style: TextStyle(
                                color: colors.textColor.withOpacity(0.6)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timestampText,
                          style: TextStyle(
                              color: colors.textColor.withOpacity(0.6),
                              fontSize: 12),
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
                              style: TextStyle(
                                  color: colors.textColor, fontSize: 12),
                            ),
                          )
                        : null,
                    onTap: () {
                      SupabaseMessagesMethods()
                          .markMessagesAsRead(chat['id'], widget.currentUserId);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MessagingScreen(
                            recipientUid: otherUserId,
                            recipientUsername: username,
                            recipientPhotoUrl: photoUrl,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        iconTheme: IconThemeData(color: colors.appBarIconColor),
        backgroundColor: colors.appBarBackgroundColor,
        title: Text('Messages', style: TextStyle(color: colors.textColor)),
        elevation: 0,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _supabase
            .from('chats')
            .select()
            .contains('participants', [widget.currentUserId]),
        builder: (context, chatSnapshot) {
          if (chatSnapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                    color: colors.progressIndicatorColor));
          }

          if (!chatSnapshot.hasData || chatSnapshot.data!.isEmpty) {
            if (_suggestedUserIds.isEmpty) {
              _loadSuggestions();
            }

            return _suggestedUserIds.isEmpty
                ? Center(
                    child: Text(
                      'No chats yet',
                      style:
                          TextStyle(color: colors.textColor.withOpacity(0.6)),
                    ),
                  )
                : Column(
                    children: _suggestedUserIds
                        .map((userId) => _buildSuggestionItem(userId, colors))
                        .toList(),
                  );
          }

          final allChats = chatSnapshot.data!;
          _existingChats = allChats.where((chat) {
            final participants = List<String>.from(chat['participants']);
            final otherUserId = participants.firstWhere(
                (id) => id != widget.currentUserId,
                orElse: () => '');
            return otherUserId.isNotEmpty &&
                !_blockedUsers.contains(otherUserId);
          }).toList();

          if (_suggestedUserIds.isEmpty) {
            _loadSuggestions();
          }

          return Column(
            children: [
              ..._existingChats
                  .map((chat) => _buildChatItem(chat, colors))
                  .toList(),
              if (_showSuggestions)
                ..._suggestedUserIds
                    .map((userId) => _buildSuggestionItem(userId, colors))
                    .toList(),
            ],
          );
        },
      ),
    );
  }
}
