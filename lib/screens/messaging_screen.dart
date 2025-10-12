import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';
import 'package:Ratedly/resources/messages_firestore_methods.dart';
import 'package:Ratedly/screens/Profile_page/image_screen.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Define color schemes for both themes at top level
class _MessagingColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;
  final Color appBarBackgroundColor;
  final Color appBarIconColor;
  final Color progressIndicatorColor;
  final Color buttonColor;
  final Color buttonTextColor;

  _MessagingColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
    required this.appBarBackgroundColor,
    required this.appBarIconColor,
    required this.progressIndicatorColor,
    required this.buttonColor,
    required this.buttonTextColor,
  });
}

class _MessagingDarkColors extends _MessagingColorSet {
  _MessagingDarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
          appBarBackgroundColor: const Color(0xFF121212),
          appBarIconColor: const Color(0xFFd9d9d9),
          progressIndicatorColor: const Color(0xFFd9d9d9),
          buttonColor: const Color(0xFF333333),
          buttonTextColor: const Color(0xFFd9d9d9),
        );
}

class _MessagingLightColors extends _MessagingColorSet {
  _MessagingLightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.white,
          cardColor: Colors.grey[100]!,
          iconColor: Colors.black,
          appBarBackgroundColor: Colors.white,
          appBarIconColor: Colors.black,
          progressIndicatorColor: Colors.black,
          buttonColor: Colors.grey[300]!,
          buttonTextColor: Colors.black,
        );
}

class MessagingScreen extends StatefulWidget {
  final String recipientUid;
  final String recipientUsername;
  final String recipientPhotoUrl;

  const MessagingScreen({
    Key? key,
    required this.recipientUid,
    required this.recipientUsername,
    required this.recipientPhotoUrl,
  }) : super(key: key);

  @override
  _MessagingScreenState createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  final TextEditingController _controller = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final SupabaseBlockMethods _blockMethods = SupabaseBlockMethods();
  bool _isLoading = false;
  String? chatId;
  bool _isMutuallyBlocked = false;
  bool _hasInitialScroll = false;
  final ScrollController _scrollController = ScrollController();
  bool _isInitializing = true;
  bool _hasMarkedAsRead = false;

  // Video player controllers cache for post messages
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, bool> _videoControllersInitialized = {};

  // Helper method to get the appropriate color scheme
  _MessagingColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _MessagingDarkColors() : _MessagingLightColors();
  }

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  void _initializeChat() async {
    try {
      // First check mutual block status
      _isMutuallyBlocked = await _blockMethods.isMutuallyBlocked(
        currentUserId,
        widget.recipientUid,
      );

      if (_isMutuallyBlocked) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
          });
        }
        return;
      }

      final id = await SupabaseMessagesMethods().getOrCreateChat(
        currentUserId,
        widget.recipientUid,
      );

      if (mounted) {
        setState(() {
          chatId = id;
          _isInitializing = false;
        });
        // Mark messages as read immediately when chat is opened
        _markMessagesAsRead();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Something went wrong, please try again later or contact us at ratedly9@gmail.com')),
        );
      }
    }
  }

  void _markMessagesAsRead() async {
    if (chatId == null || _hasMarkedAsRead) return;

    try {
      await SupabaseMessagesMethods()
          .markMessagesAsRead(chatId!, currentUserId);
      _hasMarkedAsRead = true;
    } catch (e) {
      // Error handling without debug print
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure messages are marked as read when screen becomes active
    if (chatId != null && !_hasMarkedAsRead && !_isInitializing) {
      _markMessagesAsRead();
    }
  }

  @override
  void dispose() {
    // Mark messages as read one final time when leaving the screen
    if (chatId != null && !_hasMarkedAsRead) {
      SupabaseMessagesMethods().markMessagesAsRead(chatId!, currentUserId);
    }
    _controller.dispose();
    _scrollController.dispose();

    // Dispose all video controllers
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    _videoControllers.clear();
    _videoControllersInitialized.clear();

    super.dispose();
  }

  // -------------------------
  // Video player logic for first-second looping
  // -------------------------

  /// Initialize video controller for a video URL - only loads first second
  Future<void> _initializeVideoController(String videoUrl) async {
    if (_videoControllers.containsKey(videoUrl) ||
        _videoControllersInitialized[videoUrl] == true) {
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
        ),
      );

      // Store controller immediately to prevent duplicate initializations
      _videoControllers[videoUrl] = controller;
      _videoControllersInitialized[videoUrl] = false;

      // Set up listener for initialization
      controller.addListener(() {
        if (controller.value.isInitialized &&
            !_videoControllersInitialized[videoUrl]!) {
          _videoControllersInitialized[videoUrl] = true;

          // Configure the video to play only the first second on loop
          _configureVideoLoop(controller);

          if (mounted) {
            setState(() {});
          }
        }
      });

      // Initialize the controller but don't wait for full load
      await controller.initialize();

      // Mute the video
      await controller.setVolume(0.0);
    } catch (e) {
      // Clean up on error
      _videoControllers.remove(videoUrl)?.dispose();
      _videoControllersInitialized.remove(videoUrl);
    }
  }

  /// Configure video to play only first second on loop
  void _configureVideoLoop(VideoPlayerController controller) {
    final duration = controller.value.duration;

    // Determine the end position (1 second or video duration if shorter)
    final endPosition =
        duration.inSeconds > 0 ? const Duration(seconds: 1) : duration;

    // Set up position listener to create loop effect for first second
    controller.addListener(() {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        final currentPosition = controller.value.position;
        if (currentPosition >= endPosition) {
          // Loop back to start
          controller.seekTo(Duration.zero);
        }
      }
    });

    // Start playing
    controller.play();
  }

  /// Get video controller for a URL, initializing if needed
  VideoPlayerController? _getVideoController(String videoUrl) {
    return _videoControllers[videoUrl];
  }

  /// Check if video controller is initialized
  bool _isVideoControllerInitialized(String videoUrl) {
    return _videoControllersInitialized[videoUrl] == true;
  }

  // Helper method to detect video files by extension
  bool _isVideoFile(String url) {
    if (url.isEmpty) return false;

    final lowerUrl = url.toLowerCase();
    return lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.mov') ||
        lowerUrl.endsWith('.avi') ||
        lowerUrl.endsWith('.wmv') ||
        lowerUrl.endsWith('.flv') ||
        lowerUrl.endsWith('.mkv') ||
        lowerUrl.endsWith('.webm') ||
        lowerUrl.endsWith('.m4v') ||
        lowerUrl.endsWith('.3gp') ||
        lowerUrl.contains('/video/') ||
        lowerUrl.contains('video=true');
  }

  Widget _buildVideoPlayer(String videoUrl, _MessagingColorSet colors) {
    final controller = _getVideoController(videoUrl);
    final isInitialized = _isVideoControllerInitialized(videoUrl);

    if (!isInitialized || controller == null) {
      return Container(
        height: 150,
        color: colors.cardColor,
        child: Center(
          child: CircularProgressIndicator(
            color: colors.progressIndicatorColor,
          ),
        ),
      );
    }

    return Container(
      height: 150,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }

  // -------------------------
  // Deleted Post Handling
  // -------------------------

  // Check if post exists in database
// Check if post exists in database
  Future<bool> _checkIfPostExists(String postId) async {
    try {
      final response = await Supabase.instance.client
          .from('posts')
          .select()
          .eq('postId', postId);

      return response != null && response.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Combined status check for post existence and block status
  Future<Map<String, dynamic>> _checkPostStatus(
      Map<String, dynamic> postShare) async {
    try {
      // Check if post still exists in the database
      final bool postExists = await _checkIfPostExists(postShare['postId']);

      // Check block status
      final bool isBlocked = await _blockMethods.isMutuallyBlocked(
        currentUserId,
        postShare['postOwnerId'] ?? '',
      );

      return {
        'exists': postExists,
        'isBlocked': isBlocked,
        'postData': postShare,
      };
    } catch (e) {
      // If there's an error checking, assume post doesn't exist
      return {
        'exists': false,
        'isBlocked': false,
        'postData': postShare,
      };
    }
  }

  // Build deleted post message widget
  Widget _buildDeletedPostMessage(_MessagingColorSet colors) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.textColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.delete_outline,
            color: colors.textColor.withOpacity(0.6),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Original post deleted',
                  style: TextStyle(
                    color: colors.textColor.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The shared post is no longer available',
                  style: TextStyle(
                    color: colors.textColor.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build post content when post exists
  Widget _buildPostContent(Map<String, dynamic> postShare,
      Map<String, dynamic> data, _MessagingColorSet colors) {
    final postImageUrl = postShare['postImageUrl'] ?? '';
    final isVideo = _isVideoFile(postImageUrl);

    // Start initialization if it's a video
    if (isVideo) {
      _initializeVideoController(postImageUrl);
    }

    return GestureDetector(
      onTap: () => _navigateToPost(postShare),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: colors.cardColor,
                  backgroundImage: (postShare['postOwnerPhotoUrl'] != null &&
                          postShare['postOwnerPhotoUrl'].isNotEmpty &&
                          postShare['postOwnerPhotoUrl'] != "default" &&
                          postShare['postOwnerPhotoUrl'].startsWith('http'))
                      ? NetworkImage(postShare['postOwnerPhotoUrl']!)
                      : null,
                  child: (postShare['postOwnerPhotoUrl'] == null ||
                          postShare['postOwnerPhotoUrl'].isEmpty ||
                          postShare['postOwnerPhotoUrl'] == "default" ||
                          !postShare['postOwnerPhotoUrl'].startsWith('http'))
                      ? Icon(
                          Icons.account_circle,
                          size: 32,
                          color: colors.iconColor,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  postShare['postOwnerUsername'] ?? 'Unknown User',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: colors.textColor),
                ),
              ],
            ),
          ),
          if (postImageUrl.isNotEmpty)
            isVideo
                ? _buildVideoPlayer(postImageUrl, colors)
                : Image.network(
                    postImageUrl,
                    height: 150,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 150,
                      color: Colors.grey,
                      child: Center(
                          child: Icon(Icons.error, color: colors.iconColor)),
                    ),
                  )
          else
            Container(
              height: 150,
              color: colors.cardColor,
              child: Center(
                child: Icon(Icons.broken_image, color: colors.iconColor),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(postShare['postCaption'] ?? '',
                    style: TextStyle(color: colors.textColor)),
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(data['timestamp']),
                  style: TextStyle(
                      color: colors.textColor.withOpacity(0.6), fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------
  // End Deleted Post Handling
  // -------------------------

  void _sendMessage() async {
    if (_controller.text.isEmpty || _isLoading || _isMutuallyBlocked) return;

    setState(() => _isLoading = true);

    try {
      final chatId = await SupabaseMessagesMethods().getOrCreateChat(
        currentUserId,
        widget.recipientUid,
      );

      final res = await SupabaseMessagesMethods().sendMessage(
        chatId,
        currentUserId,
        widget.recipientUid,
        _controller.text,
      );

      if (res == 'success') {
        _controller.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && mounted) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent, // Scroll to BOTTOM
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildBlockedUI(_MessagingColorSet colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.block, size: 60, color: colors.iconColor),
          const SizedBox(height: 20),
          Text(
            'Messages with ${widget.recipientUsername} are unavailable',
            style: TextStyle(color: colors.textColor, fontSize: 16),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.buttonColor,
              foregroundColor: colors.buttonTextColor,
            ),
            onPressed: () =>
                Navigator.pop(context, true), // Return true to trigger refresh
            child: const Text('Back to Messages'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    return WillPopScope(
      onWillPop: () async {
        // Return true to trigger refresh when back button is pressed
        Navigator.pop(context, true);
        return false; // Prevent default back behavior since we're handling it
      },
      child: Scaffold(
        backgroundColor: colors.backgroundColor,
        appBar: AppBar(
          iconTheme: IconThemeData(color: colors.appBarIconColor),
          backgroundColor: colors.appBarBackgroundColor,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: colors.appBarIconColor),
            onPressed: () {
              Navigator.pop(context, true); // Return true to trigger refresh
            },
          ),
          title: _buildAppBarTitle(colors),
          elevation: 0,
        ),
        body: _isMutuallyBlocked
            ? _buildBlockedUI(colors)
            : _buildChatBody(colors),
      ),
    );
  }

  Widget _buildAppBarTitle(_MessagingColorSet colors) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProfileScreen(uid: widget.recipientUid),
        ),
      ),
      child: Row(
        children: [
          _buildUserAvatar(widget.recipientPhotoUrl, colors),
          const SizedBox(width: 10),
          Text(
            widget.recipientUsername,
            style: TextStyle(color: colors.textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(String photoUrl, _MessagingColorSet colors) {
    return CircleAvatar(
      radius: 21,
      backgroundColor: colors.cardColor,
      backgroundImage: (widget.recipientPhotoUrl.isNotEmpty &&
              widget.recipientPhotoUrl != "default")
          ? NetworkImage(widget.recipientPhotoUrl)
          : null,
      child: (widget.recipientPhotoUrl.isEmpty ||
              widget.recipientPhotoUrl == "default")
          ? Icon(
              Icons.account_circle,
              size: 42,
              color: colors.iconColor,
            )
          : null,
    );
  }

  Widget _buildChatBody(_MessagingColorSet colors) {
    return Column(
      children: [
        Expanded(child: _buildMessageList(colors)),
        _buildMessageInput(colors),
      ],
    );
  }

  Widget _buildMessageList(_MessagingColorSet colors) {
    if (_isInitializing) {
      return Center(
        child: CircularProgressIndicator(color: colors.progressIndicatorColor),
      );
    }

    if (chatId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 50, color: colors.iconColor),
            const SizedBox(height: 16),
            Text(
              'Failed to load chat',
              style: TextStyle(color: colors.textColor),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseMessagesMethods().getMessages(chatId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Center(
            child:
                CircularProgressIndicator(color: colors.progressIndicatorColor),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 50, color: colors.iconColor),
                const SizedBox(height: 16),
                Text(
                  'Error loading messages',
                  style: TextStyle(color: colors.textColor),
                ),
              ],
            ),
          );
        }

        List<Map<String, dynamic>> messages = snapshot.data ?? [];

        // FIX: Sort messages in ASCENDING order (oldest first, newest last)
        messages.sort((a, b) {
          try {
            DateTime? timeA = _parseTimestamp(a['timestamp']);
            DateTime? timeB = _parseTimestamp(b['timestamp']);

            if (timeA == null || timeB == null) return 0;

            // Sort OLDEST FIRST (ascending order)
            return timeA.compareTo(timeB);
          } catch (e) {
            return 0;
          }
        });

        // Mark messages as read
        if (messages.isNotEmpty && !_hasMarkedAsRead) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _markMessagesAsRead();
          });
        }

        // Scroll to bottom (newest messages)
        if (messages.isNotEmpty && !_hasInitialScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients && mounted) {
              _scrollController
                  .jumpTo(_scrollController.position.maxScrollExtent);
              setState(() => _hasInitialScroll = true);
            }
          });
        }

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 50, color: colors.iconColor),
                const SizedBox(height: 16),
                Text(
                  'No messages yet',
                  style: TextStyle(color: colors.textColor),
                ),
                const SizedBox(height: 8),
                Text(
                  'Send the first message!',
                  style: TextStyle(
                    color: colors.textColor.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        // FIX: Remove reverse: true to show chronological order
        return ListView.builder(
          controller: _scrollController,
          reverse: false, // OLDEST at top, NEWEST at bottom
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            return _buildMessageBubble(message, colors);
          },
        );
      },
    );
  }

  DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;

    try {
      if (timestamp is DateTime) {
        return timestamp;
      } else if (timestamp is String) {
        return DateTime.parse(timestamp);
      } else if (timestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      // Error handling without debug print
    }
    return null;
  }

  Widget _buildTextMessage(
      Map<String, dynamic> data, _MessagingColorSet colors) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(data['message'], style: TextStyle(color: colors.textColor)),
          const SizedBox(height: 4),
          Text(
            _formatTimestamp(data['timestamp']),
            style: TextStyle(
                color: colors.textColor.withOpacity(0.6), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
      Map<String, dynamic> message, _MessagingColorSet colors) {
    final isMe = message['senderId'] == currentUserId;
    final isPost = message['type'] == 'post';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color:
              isMe ? colors.cardColor : Color(isMe ? 0xFF333333 : 0xFF404040),
          borderRadius: BorderRadius.circular(12),
        ),
        child: isPost
            ? _buildPostMessage(message, colors)
            : _buildTextMessage(message, colors),
      ),
    );
  }

  Widget _buildPostMessage(
      Map<String, dynamic> data, _MessagingColorSet colors) {
    final postShare = data['postShare'] as Map<String, dynamic>?;

    if (postShare == null) {
      return BlockedContentMessage(
          message: 'Post data unavailable', colors: colors);
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _checkPostStatus(postShare),
      builder: (context, statusSnapshot) {
        // Show loading for status check only if we don't have data yet
        if (statusSnapshot.connectionState == ConnectionState.waiting &&
            !statusSnapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: CircularProgressIndicator(
                color: colors.progressIndicatorColor,
                strokeWidth: 2,
              ),
            ),
          );
        }

        final status = statusSnapshot.data ??
            {'exists': false, 'isBlocked': false, 'postData': postShare};

        final bool postExists = status['exists'] ?? false;
        final bool isBlocked = status['isBlocked'] ?? false;

        // If post doesn't exist, show deleted message
        if (!postExists) {
          return _buildDeletedPostMessage(colors);
        }

        if (isBlocked) {
          return BlockedContentMessage(colors: colors);
        }

        // Post exists and is not blocked - show normal post content
        return _buildPostContent(postShare, data, colors);
      },
    );
  }

  void _navigateToPost(Map<String, dynamic> postShare) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageViewScreen(
          imageUrl: postShare['postImageUrl'],
          postId: postShare['postId'],
          description: postShare['postCaption'] ?? '',
          userId: postShare['postOwnerId'],
          username: postShare['postOwnerUsername'] ?? 'Unknown',
          profImage: postShare['postOwnerPhotoUrl'] ?? '',
          datePublished: postShare['datePublished'],
        ),
      ),
    );
  }

  Widget _buildMessageInput(_MessagingColorSet colors) {
    return Container(
      padding:
          const EdgeInsets.fromLTRB(12, 8, 12, 12), // Reduced bottom padding
      decoration: BoxDecoration(
        color: colors.backgroundColor,
        border: Border(
          top: BorderSide(
            color: colors.cardColor.withOpacity(0.5),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.cardColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                enabled: !_isMutuallyBlocked,
                style: TextStyle(color: colors.textColor),
                decoration: InputDecoration(
                  hintText: _isMutuallyBlocked
                      ? 'Messaging is blocked'
                      : 'Type a message...',
                  hintStyle:
                      TextStyle(color: colors.textColor.withOpacity(0.6)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12, // Reduced vertical padding
                  ),
                ),
                minLines: 1,
                maxLines: 3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: colors.buttonColor,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.progressIndicatorColor,
                      ),
                    )
                  : Icon(Icons.send, color: colors.iconColor),
              onPressed: _isMutuallyBlocked ? null : _sendMessage,
              padding: const EdgeInsets.all(12), // Reduced padding
              constraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Sending...';

    DateTime? date;
    try {
      if (timestamp is DateTime) {
        date = timestamp.toUtc();
      } else if (timestamp is String) {
        date = DateTime.tryParse(timestamp)?.toUtc();
      } else if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc();
      } else {
        return 'Invalid time';
      }

      if (date == null) return 'Invalid time';

      final h = date.hour.toString().padLeft(2, '0');
      final m = date.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (e) {
      return 'Invalid time';
    }
  }
}

class BlockedContentMessage extends StatelessWidget {
  final String message;
  final _MessagingColorSet colors;

  const BlockedContentMessage({
    super.key,
    this.message = 'This content is unavailable due to blocking',
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.block, color: Colors.red[400], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
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
}
