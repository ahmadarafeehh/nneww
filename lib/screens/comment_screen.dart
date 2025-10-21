import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:Ratedly/models/user.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/resources/supabase_posts_methods.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/widgets/comment_card.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/utils/theme_provider.dart';

// Define color schemes for both themes at top level
class _ColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;
  final Color warningColor;
  final Color semiTransparentBg;

  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
    required this.warningColor,
    required this.semiTransparentBg,
  });
}

class _DarkColors extends _ColorSet {
  _DarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF121212),
          iconColor: const Color(0xFFd9d9d9),
          warningColor: Colors.red,
          semiTransparentBg: const Color(0xCC121212),
        );
}

class _LightColors extends _ColorSet {
  _LightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.grey[100]!,
          cardColor: Colors.white,
          iconColor: Colors.grey[700]!,
          warningColor: Colors.red,
          semiTransparentBg: const Color(0xCCFFFFFF),
        );
}

/// Tiny shim so existing CommentCard code that uses `snap.id` and `snap['field']` keeps working.
class SupabaseSnap {
  final String id;
  final Map<String, dynamic> data;
  SupabaseSnap(this.id, this.data);
  operator [](String key) => data[key];
}

/// TikTok/Reels Style Comments Bottom Sheet with Transparent Background
/// TikTok/Reels Style Comments Bottom Sheet with Transparent Background
class CommentsBottomSheet extends StatefulWidget {
  final String postId;
  final String postImage;
  final bool isVideo;
  final VoidCallback onClose;
  final VideoPlayerController? videoController;

  const CommentsBottomSheet({
    Key? key,
    required this.postId,
    required this.postImage,
    required this.isVideo,
    required this.onClose,
    this.videoController,
  }) : super(key: key);

  @override
  CommentsBottomSheetState createState() => CommentsBottomSheetState();
}

class CommentsBottomSheetState extends State<CommentsBottomSheet> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _replyFocusNode = FocusNode();

  final Map<String, bool> _commentLikes = {};
  final Map<String, int> _commentLikeCounts = {};

  bool _shouldResumeVideo = false;

  // reply state
  String? replyingToCommentId;
  final ValueNotifier<String?> replyingToUsernameNotifier = ValueNotifier(null);
  final TextEditingController commentEditingController =
      TextEditingController();
  final Map<String, int> _expandedReplies = {};

  // Supabase methods
  final SupabasePostsMethods _postsMethods = SupabasePostsMethods();
  final SupabaseClient _supabase = Supabase.instance.client;

  // local comments list (each is Map with DB row fields)
  final List<Map<String, dynamic>> _comments = [];

  // Banned words detection
  static const List<String> _bannedWords = [
    'hang yourself',
    'kill yourself',
    'kys',
    'fuck you',
    'fuck off',
    'bitch',
    'whore',
    'cunt',
    'nigger',
    'nigga',
    'die',
    'suicide',
    'slut',
    'retard',
  ];
  bool _containsBannedWords = false;

  // Loading states
  bool _isLoadingComments = false;
  bool _isPostingComment = false;

  // Helper method to get the appropriate color scheme
  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  @override
  void initState() {
    super.initState();

    // Store video state before opening comments
    if (widget.isVideo && widget.videoController != null) {
      _shouldResumeVideo = widget.videoController!.value.isPlaying;
      if (_shouldResumeVideo) {
        widget.videoController!.pause();
      }
    }

    commentEditingController.addListener(_checkForBannedWords);
    _replyFocusNode.addListener(_onReplyFocusChange);
    _loadComments();
  }

  void _onReplyFocusChange() {
    if (_replyFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _replyFocusNode.dispose();
    _scrollController.dispose();
    commentEditingController.removeListener(_checkForBannedWords);
    commentEditingController.dispose();
    replyingToUsernameNotifier.dispose();

    // Resume video if it was playing before comments opened
    if (widget.isVideo &&
        widget.videoController != null &&
        _shouldResumeVideo) {
      widget.videoController!.play();
    }

    widget.onClose();
    super.dispose();
  }

  // Helper to normalise different client return shapes
  dynamic _unwrap(dynamic res) {
    try {
      if (res == null) return null;
      if (res is Map && res.containsKey('data')) return res['data'];
    } catch (_) {}
    return res;
  }

  Future<void> _fetchAllLikeStatuses(String userId) async {
    try {
      final commentIds =
          _comments.map((c) => c['id']?.toString() ?? '').toList();

      if (commentIds.isEmpty) return;

      final res = await _supabase
          .from('comment_likes')
          .select()
          .eq('uid', userId)
          .inFilter('comment_id', commentIds);

      final likedComments = List<Map<String, dynamic>>.from(res ?? []);

      setState(() {
        // Reset all likes to false first
        for (var commentId in commentIds) {
          _commentLikes[commentId] = false;
        }

        // Set liked comments to true
        for (var like in likedComments) {
          final commentId = like['comment_id']?.toString() ?? '';
          _commentLikes[commentId] = true;
        }
      });
    } catch (e) {
      if (kDebugMode) print('Error fetching like statuses: $e');
    }
  }

  // Add a method to update like status
  void _updateCommentLike(String commentId, bool isLiked, int likeCount) {
    setState(() {
      _commentLikes[commentId] = isLiked;
      _commentLikeCounts[commentId] = likeCount;
    });
  }

  void _checkForBannedWords() {
    final text = commentEditingController.text.toLowerCase();
    final containsBanned = _bannedWords.any((word) => text.contains(word));
    if (containsBanned != _containsBannedWords) {
      setState(() {
        _containsBannedWords = containsBanned;
      });
    }
  }

  bool get isReplying => replyingToCommentId != null;

  void startReply(String commentId, String username) {
    replyingToCommentId = commentId;
    replyingToUsernameNotifier.value = username;
    commentEditingController.clear();

    // Clear focus and request focus for reply
    FocusScope.of(context).requestFocus(FocusNode());
    _replyFocusNode.requestFocus();
  }

  Future<void> _loadComments() async {
    try {
      setState(() => _isLoadingComments = true);

      // Get user from provider
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user == null) return;

      // Fetch comments
      final res = await _supabase
          .from('comments')
          .select()
          .eq('postid', widget.postId)
          .order('like_count', ascending: false)
          .order('date_published', ascending: false);

      final rows = _unwrap(res) ?? res;

      if (rows is List) {
        // Update comments and like counts
        setState(() {
          _comments.clear();
          _comments.addAll(List<Map<String, dynamic>>.from(rows));

          // Initialize like counts
          for (var comment in _comments) {
            final commentId = comment['id']?.toString() ?? '';
            _commentLikeCounts[commentId] = (comment['like_count'] ?? 0) as int;
          }
        });

        // Then fetch like status for all comments
        await _fetchAllLikeStatuses(user.uid);
      }
    } catch (e) {
      if (mounted) showSnackBar(context, 'Failed to load comments: $e');
    } finally {
      if (mounted) setState(() => _isLoadingComments = false);
    }
  }

  Future<void> postComment(String uid, String name, String profilePic) async {
    final text = commentEditingController.text.trim();
    final maxCommentLength = 250;

    // Check character limit first
    if (text.length > maxCommentLength) {
      if (!mounted) return;
      showSnackBar(context,
          "Comments cannot exceed $maxCommentLength characters. Your comment is ${text.length} characters.");
      return;
    }

    // Prevent posting if banned words are present
    if (_containsBannedWords) {
      if (!mounted) return;
      showSnackBar(context, "Comment contains banned words");
      return;
    }

    if (text.isEmpty) {
      if (!mounted) return;
      showSnackBar(context, "Comment cannot be empty");
      return;
    }

    try {
      setState(() => _isPostingComment = true);

      String res;
      if (replyingToCommentId != null) {
        // Post reply
        res = await _postsMethods.postReply(
          postId: widget.postId,
          commentId: replyingToCommentId!,
          uid: uid,
          name: name,
          profilePic: profilePic,
          text: text,
        );

        if (res != 'success') {
          if (mounted) showSnackBar(context, "Could not post reply: $res");
        }
      } else {
        // Post top-level comment
        res = await _postsMethods.postComment(
          widget.postId,
          text,
          uid,
          name,
          profilePic,
        );

        if (res != 'success') {
          if (mounted) showSnackBar(context, "Could not post comment: $res");
        }
      }

      if (!mounted) return;

      // Refresh comments after posting
      if (res == 'success') {
        commentEditingController.clear();
        replyingToCommentId = null;
        replyingToUsernameNotifier.value = null;
        await _loadComments(); // Reload comments to show the new one
      }
    } catch (err) {
      if (!mounted) return;
      showSnackBar(context,
          'Please try again later or contact us at ratedly9@gmail.com');
    } finally {
      if (mounted) setState(() => _isPostingComment = false);
    }
  }

  Widget _buildCommentsContent(_ColorSet colors, AppUser user) {
    final safeUsername = user.username ?? 'Someone';
    final safePhotoUrl = user.photoUrl ?? '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            Colors.black.withOpacity(0.6),
            Colors.black.withOpacity(0.4),
            Colors.transparent,
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
        ),
      ),
      child: Column(
        children: [
          // Drag handle bar - indicates swipe to close
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Comments',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Comments list - MORE TRANSPARENT
          Expanded(
            child: _isLoadingComments
                ? Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      backgroundColor: Colors.white.withOpacity(0.2),
                    ),
                  )
                : _comments.isEmpty
                    ? Center(
                        child: Text(
                          'No comments yet, be the first to comment!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        child: ListView.builder(
                          controller: _scrollController,
                          key: PageStorageKey('comments_${widget.postId}'),
                          itemCount: _comments.length,
                          itemBuilder: (ctx, index) {
                            final row = _comments[index];
                            final snap =
                                SupabaseSnap(row['id']?.toString() ?? '', row);
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black
                                    .withOpacity(0.3), // More transparent
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                  width: 0.5,
                                ),
                              ),
                              child: CommentCard(
                                snap: snap,
                                currentUserId: user.uid,
                                postId: widget.postId,
                                onReply: () => startReply(
                                    snap.id, snap['name']?.toString() ?? ''),
                                onNestedReply: (commentId, username) =>
                                    startReply(commentId, username),
                                initialRepliesToShow:
                                    _expandedReplies[snap.id] ?? 2,
                                onRepliesExpanded: (newCount) {
                                  _expandedReplies[snap.id] = newCount;
                                },
                                isReplying: isReplying,
                                isLiked: _commentLikes[snap.id] ?? false,
                                likeCount: _commentLikeCounts[snap.id] ?? 0,
                                onLikeChanged: _updateCommentLike,
                                // Force transparent styling for comments sheet
                                forcedTransparent: true,
                              ),
                            );
                          },
                        ),
                      ),
          ),

          // Bottom input bar - MORE TRANSPARENT
          _buildBottomInputBar(colors, safeUsername, safePhotoUrl),
        ],
      ),
    );
  }

  Widget _buildBottomInputBar(
      _ColorSet colors, String safeUsername, String safePhotoUrl) {
    return Container(
      padding: const EdgeInsets.only(
        left: 16,
        right: 8,
        top: 12,
        bottom: 20,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5), // More transparent
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_containsBannedWords)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Warning: Using such words will get you banned!',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (_isPostingComment)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: LinearProgressIndicator(
                color: Colors.white,
                backgroundColor: Colors.white.withOpacity(0.2),
              ),
            ),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white.withOpacity(0.9),
                backgroundImage:
                    (safePhotoUrl.isNotEmpty && safePhotoUrl != "default")
                        ? NetworkImage(safePhotoUrl)
                        : null,
                child: (safePhotoUrl.isEmpty || safePhotoUrl == "default")
                    ? Icon(Icons.account_circle, size: 36, color: Colors.grey)
                    : null,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: ValueListenableBuilder<String?>(
                    valueListenable: replyingToUsernameNotifier,
                    builder: (context, replyingToUsername, _) {
                      return TextField(
                        focusNode: _replyFocusNode,
                        controller: commentEditingController,
                        style: TextStyle(color: Colors.white),
                        enabled: !_isPostingComment,
                        maxLength: 250,
                        decoration: InputDecoration(
                          hintText: replyingToUsername != null
                              ? 'Replying to @$replyingToUsername'
                              : 'Comment as $safeUsername',
                          hintStyle:
                              TextStyle(color: Colors.white.withOpacity(0.8)),
                          border: InputBorder.none,
                          counterStyle:
                              TextStyle(color: Colors.white.withOpacity(0.6)),
                          filled: true,
                          fillColor: Colors.white
                              .withOpacity(0.08), // More transparent
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: Colors.white
                                  .withOpacity(0.2), // Lighter border
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: Colors.white
                                  .withOpacity(0.4), // Lighter border
                              width: 1.5,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              _isPostingComment
                  ? Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Consumer<UserProvider>(
                      builder: (context, userProvider, _) {
                        final user = userProvider.user;
                        if (user == null) {
                          return const SizedBox.shrink();
                        }
                        return InkWell(
                          onTap: _containsBannedWords
                              ? null
                              : () => postComment(
                                  user.uid, safeUsername, safePhotoUrl),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 16),
                            decoration: BoxDecoration(
                              color: _containsBannedWords
                                  ? Colors.white.withOpacity(0.1)
                                  : Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              'Post',
                              style: TextStyle(
                                color: _containsBannedWords
                                    ? Colors.white.withOpacity(0.4)
                                    : Colors.black,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final UserProvider userProvider = Provider.of<UserProvider>(context);
    final AppUser? user = userProvider.user;

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator(color: colors.textColor)),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () {
          // Close comments when tapping on transparent areas
          Navigator.of(context).pop();
        },
        child: Container(
          height: MediaQuery.of(context).size.height,
          child: Stack(
            children: [
              // Full screen transparent overlay
              Container(
                color: Colors.black.withOpacity(0.3),
              ),

              // Comments Panel - Draggable from bottom
              DraggableScrollableSheet(
                initialChildSize: 0.7,
                minChildSize: 0.3,
                maxChildSize: 0.9,
                builder: (context, scrollController) {
                  _scrollController.addListener(() {
                    // Sync the drag controller with our scroll controller
                  });
                  return _buildCommentsContent(colors, user);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
