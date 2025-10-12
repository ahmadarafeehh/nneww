import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:Ratedly/resources/supabase_posts_methods.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';

class ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color expandColor;
  final int maxLength;

  const ExpandableText({
    Key? key,
    required this.text,
    required this.style,
    required this.expandColor,
    this.maxLength = 115,
  }) : super(key: key);

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final shouldTruncate = widget.text.length > widget.maxLength;

    if (!shouldTruncate || _isExpanded) {
      return Text(
        widget.text,
        style: widget.style,
      );
    }

    final truncatedText = widget.text.substring(0, widget.maxLength);

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$truncatedText... ',
            style: widget.style,
          ),
          TextSpan(
            text: 'more',
            style: widget.style.copyWith(
              color: widget.expandColor,
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                setState(() {
                  _isExpanded = true;
                });
              },
          ),
        ],
      ),
    );
  }
}

class CommentCard extends StatefulWidget {
  final dynamic snap;
  final String currentUserId;
  final String postId;
  final VoidCallback onReply;
  final Function(String, String)? onNestedReply;
  final int initialRepliesToShow;
  final Function(int)? onRepliesExpanded;
  final bool isReplying;
  final bool isLiked;
  final int likeCount;
  final Function(String, bool, int)? onLikeChanged;

  const CommentCard({
    super.key,
    required this.snap,
    required this.currentUserId,
    required this.postId,
    required this.onReply,
    this.onNestedReply,
    this.initialRepliesToShow = 2,
    this.onRepliesExpanded,
    required this.isReplying,
    this.isLiked = false,
    this.likeCount = 0,
    this.onLikeChanged,
  });

  @override
  State<CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<CommentCard> {
  final List<String> _reportReasons = const [
    'I just don\'t like it',
    'Discriminatory content',
    'Bullying or harassment',
    'Violence or hate speech',
    'Selling prohibited items',
    'Pornography or nudity',
    'Scam or fraudulent activity',
    'Spam',
    'Misinformation',
  ];

  final Map<String, bool> _replyLikes = {};
  final Map<String, int> _replyLikeCounts = {};

  bool _isLiked = false;
  int _likeCount = 0;
  late int _repliesToShow;

  StreamSubscription<List<Map<String, dynamic>>>? _repliesSub;
  List<Map<String, dynamic>> _replies = [];

  @override
  void initState() {
    super.initState();
    _repliesToShow = widget.initialRepliesToShow;
    _isLiked = widget.isLiked;
    _likeCount = widget.likeCount;
    _subscribeToReplies();
  }

  @override
  void dispose() {
    _repliesSub?.cancel();
    super.dispose();
  }

  // Helper to get theme-aware colors
  Color _getTextColor(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    return themeProvider.themeMode == ThemeMode.dark
        ? const Color(0xFFd9d9d9)
        : Colors.black;
  }

  Color _getCardColor(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    return themeProvider.themeMode == ThemeMode.dark
        ? const Color(0xFF121212)
        : Colors.white;
  }

  Future<void> _fetchLikeStatus() async {
    try {
      final likeCheck = await Supabase.instance.client
          .from('comment_likes')
          .select()
          .eq(
              'comment_id',
              widget.snap['commentId'] ??
                  widget.snap['commentid'] ??
                  widget.snap.id)
          .eq('uid', widget.currentUserId)
          .maybeSingle();

      setState(() {
        _isLiked = likeCheck != null;
      });
    } catch (e) {
      if (kDebugMode) print('Error fetching like status: $e');
      setState(() {
        _isLiked = false;
      });
    }
  }

  Future<void> _deleteComment(BuildContext context) async {
    final textColor = _getTextColor(context);
    final cardColor = _getCardColor(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: Text('Delete Comment', style: TextStyle(color: textColor)),
        content: Text('Are you sure you want to delete this comment?',
            style: TextStyle(color: textColor.withOpacity(0.8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: textColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Colors.red[400])),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      try {
        await SupabasePostsMethods().deleteComment(
          widget.postId,
          widget.snap['commentId'] ??
              widget.snap['commentid'] ??
              widget.snap.id,
        );

        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment deleted')),
        );
      } catch (e) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Something went wrong, please try again later or contact us at ratedly9@gmail.com')),
        );
      }
    }
  }

  void _showReportDialog(BuildContext context, {String? replyId}) {
    String? selectedReason;
    final textColor = _getTextColor(context);
    final cardColor = _getCardColor(context);

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: cardColor,
          title: Text('Report Comment', style: TextStyle(color: textColor)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why are you reporting this ${replyId != null ? "reply" : "comment"}?',
                  style: TextStyle(color: textColor.withOpacity(0.8)),
                ),
                const SizedBox(height: 12),
                ..._reportReasons.map(
                  (reason) => RadioListTile<String>(
                    title: Text(reason, style: TextStyle(color: textColor)),
                    value: reason,
                    groupValue: selectedReason,
                    activeColor: textColor,
                    onChanged: (v) => setState(() => selectedReason = v),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: textColor)),
            ),
            TextButton(
              onPressed: selectedReason == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      final idToReport = replyId ??
                          widget.snap['commentId'] ??
                          widget.snap['commentid'] ??
                          widget.snap.id;
                      try {
                        final res = await SupabasePostsMethods().reportComment(
                          postId: widget.postId,
                          commentId: idToReport,
                          reason: selectedReason!,
                        );

                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              res == 'success'
                                  ? 'Report submitted. Thank you!'
                                  : 'Error submitting report.',
                            ),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Error submitting report.')),
                        );
                      }
                    },
              child: Text('Submit', style: TextStyle(color: textColor)),
            ),
          ],
        ),
      ),
    );
  }

  void _expandReplies() {
    final newCount = _repliesToShow + 1;
    setState(() => _repliesToShow = newCount);
    widget.onRepliesExpanded?.call(newCount);
  }

  Future<Map<String, dynamic>?> _fetchUser(String uid) async {
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select()
          .eq('uid', uid)
          .maybeSingle();

      if (res == null) {
        return null;
      }

      if (res is Map) {
        if (res.containsKey('data')) {
          final d = res['data'];
          if (d is Map) {
            return Map<String, dynamic>.from(d);
          } else if (d is List && d.isNotEmpty) {
            return Map<String, dynamic>.from(d[0]);
          }
        } else {
          return Map<String, dynamic>.from(res);
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('fetchUser error: $e');
      }
    }
    return null;
  }

  Future<void> _fetchReplyLikesStatus() async {
    try {
      final replyIds = _replies.map((r) => r['id'].toString()).toList();
      if (replyIds.isEmpty) return;

      // Initialize all replies to not liked first
      setState(() {
        for (var id in replyIds) {
          _replyLikes[id] = false;
        }
      });

      final res = await Supabase.instance.client
          .from('reply_likes')
          .select('reply_id')
          .eq('uid', widget.currentUserId)
          .inFilter('reply_id', replyIds);

      setState(() {
        for (var like in res) {
          _replyLikes[like['reply_id']] = true;
        }
      });
    } catch (e) {
      if (kDebugMode) print('Error fetching reply likes: $e');
    }
  }

  void _subscribeToReplies() {
    final commentId =
        widget.snap['commentId'] ?? widget.snap['commentid'] ?? widget.snap.id;

    _repliesSub = Supabase.instance.client
        .from('replies')
        .stream(primaryKey: ['id'])
        .eq('commentid', commentId)
        .listen((List<Map<String, dynamic>> data) async {
          if (mounted) {
            setState(() {
              _replies = data;

              // Initialize like counts from reply data
              for (var reply in _replies) {
                final replyId = reply['id'].toString();
                final dynamic rawReplyLikeCount = reply['like_count'] ?? 0;
                final int likeCount = (rawReplyLikeCount is num)
                    ? rawReplyLikeCount.toInt()
                    : int.tryParse(rawReplyLikeCount.toString()) ?? 0;
                _replyLikeCounts[replyId] = likeCount;
              }
            });
            await _fetchReplyLikesStatus();
          }
        });
  }

  Future<void> _fetchInitialReplies() async {
    final commentId =
        widget.snap['commentId'] ?? widget.snap['commentid'] ?? widget.snap.id;

    try {
      final res = await Supabase.instance.client
          .from('replies')
          .select()
          .eq('commentid', commentId)
          .order('like_count', ascending: false);

      if (mounted) {
        setState(() {
          _replies = List<Map<String, dynamic>>.from(res);

          // Initialize like counts from reply data
          for (var reply in _replies) {
            final replyId = reply['id'].toString();
            final dynamic rawReplyLikeCount = reply['like_count'] ?? 0;
            final int likeCount = (rawReplyLikeCount is num)
                ? rawReplyLikeCount.toInt()
                : int.tryParse(rawReplyLikeCount.toString()) ?? 0;
            _replyLikeCounts[replyId] = likeCount;
          }
        });
        await _fetchReplyLikesStatus();
      }
    } catch (e) {
      if (kDebugMode) print('Error fetching initial replies: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchReplies(String commentId) async {
    try {
      dynamic res;

      try {
        res = await Supabase.instance.client
            .from('replies')
            .select()
            .eq('commentid', commentId)
            .order('like_count', ascending: false);
      } catch (_) {
        res = await Supabase.instance.client
            .from('replies')
            .select()
            .eq('commentid', commentId);
      }

      if (res == null) {
        return [];
      }

      dynamic raw = res;
      if (raw is Map && raw.containsKey('data')) {
        raw = raw['data'];
      }

      if (raw is List) {
        final list = raw
            .map<Map<String, dynamic>>((e) => (e is Map)
                ? Map<String, dynamic>.from(e)
                : Map<String, dynamic>.from(e as Map))
            .toList();

        list.sort((a, b) {
          final na = a['like_count'] ?? a['likecount'] ?? 0;
          final nb = b['like_count'] ?? b['likecount'] ?? 0;
          final ia =
              (na is num) ? na.toInt() : int.tryParse(na.toString()) ?? 0;
          final ib =
              (nb is num) ? nb.toInt() : int.tryParse(nb.toString()) ?? 0;
          return ib.compareTo(ia);
        });

        return list;
      }
    } catch (e) {
      if (kDebugMode) {
        print('fetchReplies exception: $e');
      }
    }
    return [];
  }

  Widget _buildRepliesList() {
    if (_replies.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleReplies = _replies.take(_repliesToShow).toList();
    final textColor = _getTextColor(context);

    return Column(
      children: [
        ...visibleReplies.map((data) => _buildReplyItem(data)),
        if (_replies.length > _repliesToShow)
          GestureDetector(
            onTap: _expandReplies,
            child: Padding(
              padding: const EdgeInsets.only(left: 40, top: 8),
              child: Row(
                children: [
                  Icon(Icons.keyboard_arrow_down,
                      size: 16, color: textColor.withOpacity(0.6)),
                  const SizedBox(width: 4),
                  Text('Show more',
                      style: TextStyle(
                          fontSize: 12, color: textColor.withOpacity(0.6))),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReplyItem(Map<String, dynamic> data) {
    final String replyId = (data['id'] ?? '').toString();
    final String replyUid = (data['uid'] ?? '').toString();
    final String replyName = (data['name'] ?? 'User').toString();
    final String replyText =
        (data['reply_text'] ?? data['text'] ?? '').toString();

    // Get initial like count from reply data
    final dynamic rawReplyLikeCount = data['like_count'] ?? 0;
    final int initialReplyLikeCount = (rawReplyLikeCount is num)
        ? rawReplyLikeCount.toInt()
        : int.tryParse(rawReplyLikeCount.toString()) ?? 0;

    // Use state if available, otherwise initial values
    final bool isReplyLiked = _replyLikes[replyId] ?? false;
    final int replyLikeCount =
        _replyLikeCounts[replyId] ?? initialReplyLikeCount;

    final dynamic rawDate = data['date_published'] ?? data['datepublished'];
    DateTime replyDate;
    if (rawDate == null) {
      replyDate = DateTime.now();
    } else if (rawDate is String) {
      replyDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      try {
        replyDate = (rawDate as dynamic).toDate();
      } catch (_) {
        replyDate = DateTime.now();
      }
    }

    final textColor = _getTextColor(context);
    final cardColor = _getCardColor(context);

    return Padding(
      padding: const EdgeInsets.only(left: 40, top: 4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: cardColor, borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FutureBuilder<Map<String, dynamic>?>(
                  future: _fetchUser(replyUid),
                  builder: (ctx, userSnap) {
                    final user = userSnap.data ?? <String, dynamic>{};
                    return CircleAvatar(
                      radius: 12,
                      backgroundColor: cardColor,
                      backgroundImage: (user['photoUrl'] != null &&
                              (user['photoUrl'] as String).isNotEmpty &&
                              user['photoUrl'] != 'default')
                          ? NetworkImage(user['photoUrl'])
                          : null,
                      child: (user['photoUrl'] == null ||
                              (user['photoUrl'] as String).isEmpty ||
                              user['photoUrl'] == 'default')
                          ? Icon(Icons.account_circle,
                              size: 24, color: textColor.withOpacity(0.8))
                          : null,
                    );
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: replyName,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: textColor),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            ProfileScreen(uid: replyUid)),
                                  );
                                },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      ExpandableText(
                        text: replyText,
                        style: TextStyle(color: textColor.withOpacity(0.9)),
                        expandColor: textColor.withOpacity(0.8),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        try {
                          final result = await SupabasePostsMethods().likeReply(
                            postId: widget.postId,
                            commentId: widget.snap['commentId'] ??
                                widget.snap['commentid'] ??
                                widget.snap.id,
                            replyId: replyId,
                            uid: widget.currentUserId,
                          );

                          if (result['action'] == 'liked' ||
                              result['action'] == 'unliked') {
                            setState(() {
                              _replyLikeCounts[replyId] = result['like_count'];
                              _replyLikes[replyId] =
                                  result['action'] == 'liked';
                            });
                          } else if (result['action'] == 'error') {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Failed to like reply: ${result['error']}')),
                            );
                          }
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Failed to like reply: ${e.toString()}')),
                          );
                        }
                      },
                      icon: Icon(
                        isReplyLiked ? Icons.favorite : Icons.favorite_border,
                        color: isReplyLiked
                            ? Colors.red[400]
                            : textColor.withOpacity(0.6),
                        size: 16,
                      ),
                    ),
                    Text(replyLikeCount.toString(),
                        style: TextStyle(
                            fontSize: 12, color: textColor.withOpacity(0.8))),
                  ],
                ),
                const SizedBox(width: 4),
                if (!widget.isReplying) ...[
                  PopupMenuButton<String>(
                    constraints: const BoxConstraints(minWidth: 140),
                    icon: Icon(Icons.more_vert,
                        size: 16, color: textColor.withOpacity(0.8)),
                    color: cardColor,
                    onSelected: (choice) async {
                      if (choice == 'delete') {
                        try {
                          final res = await SupabasePostsMethods().deleteReply(
                            postId: widget.postId,
                            commentId: widget.snap['commentId'] ??
                                widget.snap['commentid'] ??
                                widget.snap.id,
                            replyId: replyId,
                          );
                          if (!mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(res == 'success'
                                  ? 'Reply deleted'
                                  : 'Error deleting reply')));
                        } catch (e) {
                          if (!mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                  'Error deleting reply: ${e.toString()}')));
                        }
                      } else {
                        _showReportDialog(context, replyId: replyId);
                      }
                    },
                    itemBuilder: (ctx) {
                      if (replyUid == widget.currentUserId) {
                        return [
                          PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete Reply',
                                  style: TextStyle(color: _getTextColor(ctx))))
                        ];
                      } else {
                        return [
                          PopupMenuItem(
                              value: 'report',
                              child: Text('Report Reply',
                                  style: TextStyle(color: _getTextColor(ctx))))
                        ];
                      }
                    },
                  )
                ] else ...[
                  const SizedBox(width: 44),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat.yMMMd().format(replyDate),
                    style: TextStyle(
                        fontSize: 10, color: textColor.withOpacity(0.6))),
                TextButton(
                  onPressed: () => widget.onNestedReply?.call(
                    data['commentId'] ??
                        widget.snap['commentId'] ??
                        widget.snap['commentid'] ??
                        widget.snap.id,
                    data['name'] ?? replyName,
                  ),
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 20),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: Text('Reply',
                      style: TextStyle(
                          fontSize: 10, color: textColor.withOpacity(0.8))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final likesDynamic = widget.snap['likes'] ?? widget.snap['Likes'] ?? [];
    final List<String> likes = (likesDynamic is String)
        ? (likesDynamic.isEmpty
            ? <String>[]
            : List<String>.from(jsonDecode(likesDynamic) as List))
        : List<String>.from(likesDynamic as List<dynamic>);

    final bool isLiked = likes.contains(widget.currentUserId);
    final dynamic rawLikeCount =
        widget.snap['like_count'] ?? widget.snap['likecount'] ?? 0;
    final int likeCount = (rawLikeCount is num)
        ? rawLikeCount.toInt()
        : int.tryParse(rawLikeCount.toString()) ?? 0;

    final textColor = _getTextColor(context);
    final cardColor = _getCardColor(context);

    final String commentText =
        (widget.snap['comment_text'] ?? widget.snap['text'] ?? '').toString();

    return FutureBuilder<bool>(
      future: SupabaseBlockMethods().isMutuallyBlocked(
        widget.currentUserId,
        widget.snap['uid'],
      ),
      builder: (context, blockSnapshot) {
        final isBlocked = blockSnapshot.data ?? false;
        if (isBlocked) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          color: cardColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<Map<String, dynamic>?>(
                    future: _fetchUser(widget.snap['uid'] ?? ''),
                    builder: (context, userSnapshot) {
                      final userData = userSnapshot.data ?? <String, dynamic>{};

                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ProfileScreen(uid: widget.snap['uid'] ?? ''),
                          ),
                        ),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 21,
                                backgroundColor: cardColor,
                                backgroundImage:
                                    (userData['photoUrl'] != null &&
                                            (userData['photoUrl'] as String)
                                                .isNotEmpty &&
                                            userData['photoUrl'] != "default")
                                        ? NetworkImage(userData['photoUrl'])
                                        : null,
                                child: (userData['photoUrl'] == null ||
                                        (userData['photoUrl'] as String)
                                            .isEmpty ||
                                        userData['photoUrl'] == "default")
                                    ? Icon(
                                        Icons.account_circle,
                                        size: 42,
                                        color: textColor.withOpacity(0.8),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: widget.snap['name'] ?? 'User',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: textColor),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => ProfileScreen(
                                                uid: widget.snap['uid'] ?? '')),
                                      );
                                    },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          ExpandableText(
                            text: commentText,
                            style: TextStyle(color: textColor.withOpacity(0.9)),
                            expandColor: textColor.withOpacity(0.8),
                          ),
                          // Show character counter only when comment reaches 250 characters
                          if (commentText.length >= 250)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${commentText.length}/250',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textColor.withOpacity(0.6),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Builder(builder: (ctx) {
                                  final dynamic rawDate =
                                      widget.snap['date_published'] ??
                                          widget.snap['datepublished'];
                                  DateTime date;
                                  if (rawDate == null) {
                                    date = DateTime.now();
                                  } else if (rawDate is String) {
                                    date = DateTime.tryParse(rawDate) ??
                                        DateTime.now();
                                  } else {
                                    try {
                                      date = (rawDate as dynamic).toDate();
                                    } catch (_) {
                                      date = DateTime.now();
                                    }
                                  }
                                  return Text(
                                    DateFormat.yMMMd().format(date),
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                        color: textColor.withOpacity(0.6)),
                                  );
                                }),
                                TextButton(
                                  onPressed: widget.onReply,
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(50, 20),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text('Reply',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: textColor.withOpacity(0.8))),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!widget.isReplying) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: PopupMenuButton<String>(
                        constraints: const BoxConstraints(minWidth: 140),
                        icon: Icon(Icons.more_vert,
                            size: 16, color: textColor.withOpacity(0.8)),
                        color: cardColor,
                        onSelected: (choice) {
                          if (choice == 'delete') {
                            _deleteComment(context);
                          } else if (choice == 'report') {
                            _showReportDialog(context);
                          }
                        },
                        itemBuilder: (ctx) {
                          if (widget.snap['uid'] == widget.currentUserId) {
                            return [
                              PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete',
                                      style: TextStyle(
                                          color: _getTextColor(ctx)))),
                            ];
                          } else {
                            return [
                              PopupMenuItem(
                                  value: 'report',
                                  child: Text('Report',
                                      style: TextStyle(
                                          color: _getTextColor(ctx)))),
                            ];
                          }
                        },
                      ),
                    ),
                  ] else ...[
                    const SizedBox(width: 40),
                  ],
                  Column(
                    children: [
                      IconButton(
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () async {
                          final bool previousLikeState = _isLiked;
                          final int previousLikeCount = _likeCount;

                          setState(() {
                            _isLiked = !_isLiked;
                            _likeCount += _isLiked ? 1 : -1;
                          });

                          if (widget.onLikeChanged != null) {
                            widget.onLikeChanged!(
                              widget.snap['commentId'] ??
                                  widget.snap['commentid'] ??
                                  widget.snap.id,
                              _isLiked,
                              _likeCount,
                            );
                          }

                          try {
                            await SupabasePostsMethods().likeComment(
                              widget.postId,
                              widget.snap['commentId'] ??
                                  widget.snap['commentid'] ??
                                  widget.snap.id,
                              widget.currentUserId,
                            );
                          } catch (e) {
                            setState(() {
                              _isLiked = previousLikeState;
                              _likeCount = previousLikeCount;
                            });

                            if (widget.onLikeChanged != null) {
                              widget.onLikeChanged!(
                                widget.snap['commentId'] ??
                                    widget.snap['commentid'] ??
                                    widget.snap.id,
                                previousLikeState,
                                previousLikeCount,
                              );
                            }

                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Failed to like comment. Please try again.'),
                              ),
                            );
                          }
                        },
                        icon: Icon(
                          _isLiked ? Icons.favorite : Icons.favorite_border,
                          color: _isLiked
                              ? Colors.red[400]
                              : textColor.withOpacity(0.6),
                          size: 16,
                        ),
                      ),
                      Text(
                        _likeCount.toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildRepliesList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
