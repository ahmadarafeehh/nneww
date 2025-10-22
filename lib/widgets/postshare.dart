// lib/widgets/postshare.dart
import 'package:flutter/material.dart';
import 'package:Ratedly/resources/messages_firestore_methods.dart';
import 'package:Ratedly/resources/supabase_posts_methods.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/utils/theme_provider.dart'; // Add this import
import 'package:provider/provider.dart'; // Add this import

// Define color schemes for both themes at top level
class _PostShareColorSet {
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;
  final Color primaryColor;
  final Color secondaryColor;
  final Color blueColor;
  final Color progressIndicatorColor;
  final Color checkboxColor;
  final Color buttonBackgroundColor;
  final Color buttonTextColor;
  final Color borderColor;

  _PostShareColorSet({
    required this.backgroundColor,
    required this.textColor,
    required this.iconColor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.blueColor,
    required this.progressIndicatorColor,
    required this.checkboxColor,
    required this.buttonBackgroundColor,
    required this.buttonTextColor,
    required this.borderColor,
  });
}

class _PostShareDarkColors extends _PostShareColorSet {
  _PostShareDarkColors()
      : super(
          backgroundColor: const Color(0xFF121212),
          textColor: const Color(0xFFd9d9d9),
          iconColor: const Color(0xFFd9d9d9),
          primaryColor: const Color(0xFFd9d9d9),
          secondaryColor: const Color(0xFF333333),
          blueColor: const Color(0xFF0095f6),
          progressIndicatorColor: const Color(0xFFd9d9d9),
          checkboxColor: const Color(0xFF333333),
          buttonBackgroundColor: const Color(0xFF0095f6),
          buttonTextColor: const Color(0xFFd9d9d9),
          borderColor: const Color(0xFF333333),
        );
}

class _PostShareLightColors extends _PostShareColorSet {
  _PostShareLightColors()
      : super(
          backgroundColor: Colors.white,
          textColor: Colors.black,
          iconColor: Colors.black,
          primaryColor: Colors.black,
          secondaryColor: Colors.grey[300]!,
          blueColor: const Color(0xFF0095f6),
          progressIndicatorColor: Colors.black,
          checkboxColor: Colors.grey[300]!,
          buttonBackgroundColor: const Color(0xFF0095f6),
          buttonTextColor: Colors.white,
          borderColor: Colors.grey[400]!,
        );
}

class PostShare extends StatefulWidget {
  final String currentUserId;
  final String postId;

  const PostShare({
    Key? key,
    required this.currentUserId,
    required this.postId,
  }) : super(key: key);

  @override
  _PostShareState createState() => _PostShareState();
}

class _PostShareState extends State<PostShare> {
  final Set<String> selectedUsers = <String>{};
  bool _isSharing = false;
  final SupabaseClient _supabase = Supabase.instance.client;

  // Helper method to get the appropriate color scheme
  _PostShareColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _PostShareDarkColors() : _PostShareLightColors();
  }

  Future<void> _sharePost() async {
    if (_isSharing || selectedUsers.isEmpty) return;

    setState(() => _isSharing = true);

    try {
      // Fetch post data from Supabase
      final postResponse = await _supabase
          .from('posts')
          .select()
          .eq('postId', widget.postId)
          .single();

      if (postResponse.isEmpty) {
        throw Exception('Post does not exist');
      }

      final Map<String, dynamic> postData = postResponse;
      final String postImageUrl = (postData['postUrl'] ?? '').toString();
      final String postCaption = (postData['description'] ?? '').toString();
      final String postOwnerId = (postData['uid'] ?? '').toString();

      // Fetch user data from Supabase
      final userResponse = await _supabase
          .from('users')
          .select()
          .eq('uid', postOwnerId)
          .single();

      final Map<String, dynamic> userData = userResponse;
      final String postOwnerUsername =
          (userData['username'] ?? 'Unknown User').toString();
      final String postOwnerPhotoUrl =
          (userData['photoUrl'] ?? '').toString().trim();

      // iterate recipients
      for (final userId in selectedUsers) {
        // Get or create chat in Firestore (keeps your existing chat model)
        final chatId = await SupabaseMessagesMethods()
            .getOrCreateChat(widget.currentUserId, userId);

        // Use Supabase method to insert message/post share into Supabase chat_messages table.
        await SupabasePostsMethods().sharePostThroughChat(
          chatId: chatId,
          senderId: widget.currentUserId,
          receiverId: userId,
          postId: widget.postId,
          postImageUrl: postImageUrl,
          postCaption: postCaption,
          postOwnerId: postOwnerId,
          postOwnerUsername: postOwnerUsername,
          postOwnerPhotoUrl: postOwnerPhotoUrl,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Post shared with ${selectedUsers.length} user(s)'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Something went wrong, please try again later or contact us at ratedly9@gmail.com',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    return Dialog(
      backgroundColor: colors.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: colors.borderColor),
      ),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share Post',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textColor,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _getChatsWithUsers(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                        child: CircularProgressIndicator(
                            color: colors.progressIndicatorColor));
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_alt_outlined,
                              size: 40,
                              color: colors.iconColor.withOpacity(0.6)),
                          const SizedBox(height: 16),
                          Text(
                            'No users to share with yet!\nFollow other users to share content.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.textColor.withOpacity(0.8),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final chatsWithUsers = snapshot.data!;
                  return ListView.builder(
                    itemCount: chatsWithUsers.length,
                    itemBuilder: (context, index) {
                      final chat = chatsWithUsers[index];
                      final otherUserId = chat['otherUserId'];
                      final userData = chat['userData'];

                      return ListTile(
                        tileColor: colors.backgroundColor,
                        leading: CircleAvatar(
                          radius: 21,
                          backgroundColor: Colors.transparent,
                          backgroundImage: (userData['photoUrl'] != null &&
                                  (userData['photoUrl'] as String).isNotEmpty &&
                                  userData['photoUrl'] != "default")
                              ? NetworkImage(userData['photoUrl'] as String)
                              : null,
                          child: (userData['photoUrl'] == null ||
                                  (userData['photoUrl'] as String).isEmpty ||
                                  userData['photoUrl'] == "default")
                              ? Icon(
                                  Icons.account_circle,
                                  size: 42,
                                  color: colors.iconColor,
                                )
                              : null,
                        ),
                        title: Text(
                          (userData['username'] ?? 'Unknown User').toString(),
                          style: TextStyle(color: colors.textColor),
                        ),
                        trailing: Checkbox(
                          value: selectedUsers.contains(otherUserId),
                          checkColor: colors.primaryColor,
                          fillColor: MaterialStateProperty.resolveWith<Color?>(
                            (states) => colors.checkboxColor,
                          ),
                          onChanged: _isSharing
                              ? null
                              : (bool? selected) {
                                  setState(() {
                                    if (selected == true) {
                                      selectedUsers.add(otherUserId);
                                    } else {
                                      selectedUsers.remove(otherUserId);
                                    }
                                  });
                                },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _isSharing || selectedUsers.isEmpty ? null : _sharePost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.buttonBackgroundColor,
                  foregroundColor: colors.buttonTextColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSharing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              colors.progressIndicatorColor),
                        ),
                      )
                    : const Text('Share Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getChatsWithUsers() async {
    try {
      // Get chats where current user is a participant
      final chatsResponse = await _supabase
          .from('chats')
          .select()
          .contains('participants', [widget.currentUserId]);

      final List<Map<String, dynamic>> chatsWithUsers = [];

      for (final chat in chatsResponse) {
        final participants =
            List<String>.from(chat['participants'] ?? <String>[]);
        final otherUserId = participants.firstWhere(
          (userId) => userId != widget.currentUserId,
          orElse: () => '',
        );

        if (otherUserId.isEmpty) continue;

        // Get user data from Supabase
        final userResponse = await _supabase
            .from('users')
            .select()
            .eq('uid', otherUserId)
            .single();

        chatsWithUsers.add({
          'chat': chat,
          'otherUserId': otherUserId,
          'userData': userResponse,
        });
      }

      return chatsWithUsers;
    } catch (e) {
      return [];
    }
  }
}
