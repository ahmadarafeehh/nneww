import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/models/user.dart' as model;
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/services/api_service.dart';
import 'package:Ratedly/screens/comment_screen.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/widgets/rating_section.dart';
import 'package:Ratedly/widgets/postshare.dart';
import 'package:Ratedly/widgets/blocked_content_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:Ratedly/utils/theme_provider.dart'; // Add this import

// Define color schemes for both themes at top level
class _ColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;

  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
  });
}

class _DarkColors extends _ColorSet {
  _DarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
        );
}

class _LightColors extends _ColorSet {
  _LightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.grey[100]!,
          cardColor: Colors.white,
          iconColor: Colors.grey[700]!,
        );
}

class PostCard extends StatefulWidget {
  final dynamic snap;
  final VoidCallback? onRateUpdate;

  const PostCard({
    Key? key,
    required this.snap,
    this.onRateUpdate,
  }) : super(key: key);

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with AutomaticKeepAliveClientMixin<PostCard> {
  late int _commentCount;
  bool _isBlocked = false;
  bool _viewRecorded = false;
  late RealtimeChannel _postChannel;
  bool _isLoadingRatings = true;
  int _totalRatingsCount = 0;
  double _averageRating = 0.0;
  double? _userRating;
  bool _showSlider = true;
  bool _isRating = false;

  late List<Map<String, dynamic>> _localRatings;
  final ApiService _apiService = ApiService();
  final List<String> _reportReasons = [
    'I just don\'t like it',
    'Discriminatory content (e.g., religion, race, gender, or other)',
    'Bullying or harassment',
    'Violence, hate speech, or harmful content',
    'Selling prohibited items',
    'Pornography or nudity',
    'Scam or fraudulent activity',
    'Spam',
    'Misinformation',
  ];

  // Helper method to get the appropriate color scheme
  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Convert dynamic list to typed list
    _localRatings = [];
    if (widget.snap['ratings'] != null) {
      _localRatings = (widget.snap['ratings'] as List<dynamic>)
          .map<Map<String, dynamic>>((r) => r as Map<String, dynamic>)
          .toList();
    }

    _commentCount = (widget.snap['commentsCount'] ?? 0).toInt();
    _setupRealtime();
    _checkBlockStatus();
    _recordView();
    _fetchInitialRatings(); // Remove _fetchUserRating() from here
    _fetchCommentsCount(); // Fetch comment count from server
  }

  // Helper method to unwrap Supabase responses
  dynamic _unwrapResponse(dynamic res) {
    if (res == null) return null;
    if (res is Map && res.containsKey('data')) return res['data'];
    return res;
  }

  // Helper method to count items from various response formats
  int _countItems(dynamic value) {
    try {
      if (value == null) return 0;
      if (value is List) return value.length;
      if (value is Iterable) return value.length;
      if (value is Map && value['data'] is List) {
        return (value['data'] as List).length;
      }
      if (value is String) {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded.length;
        if (decoded is Map && decoded['data'] is List) {
          return (decoded['data'] as List).length;
        }
        return 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  // Fetch comment count from server
  Future<void> _fetchCommentsCount() async {
    try {
      final commentsRes = await Supabase.instance.client
          .from('comments')
          .select('id')
          .eq('postid', widget.snap['postId']);

      final commentsData = _unwrapResponse(commentsRes) ?? commentsRes;
      final int computedCommentsCount = _countItems(commentsData);

      if (mounted) {
        setState(() {
          _commentCount = computedCommentsCount;
        });
      }
    } catch (err) {
      // Keep the current value if there's an error
      print('Error fetching comments count: $err');
    }
  }

  bool _hasUserRated() {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return false;

    return _localRatings.any((rating) => rating['userid'] == user.uid);
  }

  void _setupRealtime() {
    _postChannel =
        Supabase.instance.client.channel('post_${widget.snap['postId']}');

    // Set up both subscriptions first
    _postChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'post_rating',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'postid',
        value: widget.snap['postId'],
      ),
      callback: (payload) {
        _handleRatingUpdate(payload);
      },
    );

    // Also subscribe to comment changes to update count in real-time
    _postChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'comments',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'postid',
        value: widget.snap['postId'],
      ),
      callback: (payload) {
        // Refresh comment count when comments change
        _fetchCommentsCount();
      },
    );

    // Subscribe only once at the end
    _postChannel.subscribe();
  }

  Future<void> _fetchInitialRatings() async {
    try {
      // Fetch ratings count
      final countResponse = await Supabase.instance.client
          .from('post_rating')
          .select()
          .eq('postid', widget.snap['postId']);

      // Fetch ratings for average calculation
      final avgResponse = await Supabase.instance.client
          .from('post_rating')
          .select('rating')
          .eq('postid', widget.snap['postId']);

      // Get current user's rating
      final user = Provider.of<UserProvider>(context, listen: false).user;
      dynamic userRatingRes;
      if (user != null) {
        userRatingRes = await Supabase.instance.client
            .from('post_rating')
            .select('rating')
            .eq('postid', widget.snap['postId'])
            .eq('userid', user.uid)
            .maybeSingle();
      }

      if (mounted) {
        setState(() {
          _totalRatingsCount = countResponse.length;

          // Calculate average rating
          if (avgResponse.isNotEmpty) {
            final ratings = avgResponse
                .map<double>((r) => (r['rating'] as num).toDouble())
                .toList();
            _averageRating = ratings.reduce((a, b) => a + b) / ratings.length;
          } else {
            _averageRating = 0.0;
          }

          // Set user rating and showSlider based on whether user has rated
          if (userRatingRes != null) {
            _userRating = (userRatingRes['rating'] as num).toDouble();
            _showSlider = false; // User has rated, hide slider
          } else {
            _userRating = null;
            _showSlider = true; // User hasn't rated, show slider
          }

          _isLoadingRatings = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRatings = false;
        });
      }
    }
  }

  void _handleRatingUpdate(PostgresChangePayload payload) {
    final newRecord = payload.newRecord;
    final oldRecord = payload.oldRecord;
    final eventType = payload.eventType;

    setState(() {
      switch (eventType) {
        case PostgresChangeEvent.insert:
          if (newRecord != null) {
            _localRatings.insert(0, newRecord);
            _totalRatingsCount++;
            _updateAverageRating();

            // Update slider state based on whether current user rated
            final user = Provider.of<UserProvider>(context, listen: false).user;
            if (user != null && newRecord['userid'] == user.uid) {
              _showSlider = false;
            }
          }
          break;
        case PostgresChangeEvent.update:
          if (oldRecord != null && newRecord != null) {
            final index = _localRatings.indexWhere(
              (r) => r['userid'] == oldRecord['userid'],
            );
            if (index != -1) _localRatings[index] = newRecord;
            _updateAverageRating();
          }
          break;
        case PostgresChangeEvent.delete:
          if (oldRecord != null) {
            _localRatings.removeWhere(
              (r) => r['userid'] == oldRecord['userid'],
            );
            _totalRatingsCount--;
            _updateAverageRating();

            // If the deleted rating was from current user, show slider
            final user = Provider.of<UserProvider>(context, listen: false).user;
            if (user != null && oldRecord['userid'] == user.uid) {
              _showSlider = true;
            }
          }
          break;
        default:
          break;
      }
    });

    widget.onRateUpdate?.call();
  }

  void _updateAverageRating() {
    if (_localRatings.isEmpty) {
      setState(() => _averageRating = 0.0);
      return;
    }

    final total = _localRatings.fold(
        0.0, (sum, r) => sum + (r['rating'] as num).toDouble());

    setState(() => _averageRating = total / _localRatings.length);
  }

  @override
  void dispose() {
    _postChannel.unsubscribe();
    super.dispose();
  }

  Future<void> _checkBlockStatus() async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;

    final isBlocked = await _apiService.isMutuallyBlocked(
      user.uid,
      widget.snap['uid'],
    );

    if (mounted) setState(() => _isBlocked = isBlocked);
  }

  Future<void> _recordView() async {
    if (_viewRecorded) return;

    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user != null) {
      await _apiService.recordPostView(
        widget.snap['postId'],
        user.uid,
      );
      if (mounted) setState(() => _viewRecorded = true);
    }
  }

  void _handleRatingSubmitted(double rating) async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;

    setState(() {
      _isRating = true;
      _userRating = rating;
      _showSlider = false;

      // Update average calculation optimistically
      if (_totalRatingsCount > 0) {
        final newTotal = _averageRating * _totalRatingsCount;
        // If user had previous rating, subtract it first
        if (_userRating != null) {
          _averageRating =
              (newTotal - _userRating! + rating) / _totalRatingsCount;
        } else {
          _totalRatingsCount++;
          _averageRating = (newTotal + rating) / _totalRatingsCount;
        }
      } else {
        _totalRatingsCount = 1;
        _averageRating = rating;
      }
    });

    try {
      final success = await _apiService.ratePost(
        widget.snap['postId'],
        user.uid,
        rating,
      );

      if (!success && mounted) {
        // Revert on failure
        _fetchInitialRatings();
      } else if (widget.onRateUpdate != null) {
        widget.onRateUpdate!();
      }
    } catch (e) {
      if (mounted) {
        _fetchInitialRatings();
      }
    } finally {
      if (mounted) {
        setState(() => _isRating = false);
      }
    }
  }

  void _handleEditRating() {
    setState(() {
      _showSlider = true;
    });
  }

  void _showReportDialog(_ColorSet colors) {
    String? selectedReason;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: colors.cardColor,
          title: Text('Report Post', style: TextStyle(color: colors.textColor)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thank you for helping keep our community safe.\n\nPlease let us know the reason for reporting this content.',
                  style: TextStyle(color: colors.textColor.withOpacity(0.7)),
                ),
                const SizedBox(height: 16),
                ..._reportReasons
                    .map((reason) => RadioListTile<String>(
                          title: Text(reason,
                              style: TextStyle(color: colors.textColor)),
                          value: reason,
                          groupValue: selectedReason,
                          activeColor: colors.textColor,
                          onChanged: (value) =>
                              setState(() => selectedReason = value),
                        ))
                    .toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: colors.textColor)),
            ),
            TextButton(
              onPressed: selectedReason != null
                  ? () => _submitReport(selectedReason!)
                  : null,
              child: Text('Submit', style: TextStyle(color: colors.textColor)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport(String reason) async {
    Navigator.pop(context);
    try {
      await _apiService.reportPost(widget.snap['postId'], reason);
      showSnackBar(context, 'Report submitted successfully');
    } catch (e) {
      showSnackBar(
          context, 'Please try again or contact us at ratedly9@gmail.com');
    }
  }

  Future<void> _deletePost() async {
    try {
      await _apiService.deletePost(widget.snap['postId']);
      showSnackBar(context, 'Post deleted successfully');
    } catch (e) {
      showSnackBar(
          context, 'Please try again or contact us at ratedly9@gmail.com');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    if (_isBlocked) {
      return const BlockedContentMessage(
        message: 'Post unavailable due to blocking',
      );
    }

    final user = Provider.of<UserProvider>(context).user;
    if (user == null) return const SizedBox.shrink();

    return Container(
      color: colors.backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          _buildHeader(user, colors),
          _buildImageSection(colors),
          RatingSection(
            postId: widget.snap['postId'],
            userId: user.uid,
            ratings: _localRatings,
            onRatingEnd: _handleRatingSubmitted,
            showSlider: _showSlider,
            onEditRating: _handleEditRating,
            isRating: _isRating,
            hasRated: _userRating != null,
            userRating: _userRating ?? 0.0,
          ),
          _buildActionBar(user, colors),
        ],
      ),
    );
  }

  // Add this helper method to parse the date
  DateTime? _parseDate(dynamic date) {
    if (date == null) return null;
    if (date is DateTime) return date;
    if (date is String) return DateTime.tryParse(date);
    return null;
  }

// In the _buildHeader method, modify the Column to include the date
  Widget _buildHeader(model.AppUser user, _ColorSet colors) {
    final datePublished = _parseDate(widget.snap['datePublished']);
    final timeagoText =
        datePublished != null ? timeago.format(datePublished) : '';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16)
          .copyWith(right: 0),
      child: Row(
        children: [
          _buildUserAvatar(colors),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _navigateToProfile(),
                    child: Text(
                      widget.snap['username']?.toString() ?? 'Unknown',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.textColor,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                  if (timeagoText.isNotEmpty)
                    Text(
                      timeagoText,
                      style: TextStyle(
                        color: colors.textColor.withOpacity(0.6),
                        fontSize: 12,
                        fontFamily: 'Inter',
                      ),
                    ),
                ],
              ),
            ),
          ),
          _buildMoreButton(user, colors),
        ],
      ),
    );
  }

  Widget _buildActionBar(model.AppUser user, _ColorSet colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          _buildCommentButton(colors),
          IconButton(
            icon: Icon(Icons.send, color: colors.textColor),
            onPressed: () => showDialog(
              context: context,
              builder: (context) => PostShare(
                currentUserId: user.uid,
                postId: widget.snap['postId'],
              ),
            ),
          ),
          const Spacer(),
          _buildRatingSummary(colors),
        ],
      ),
    );
  }

  Widget _buildRatingSummary(_ColorSet colors) {
    return InkWell(
      onTap: () => _navigateToRatingList(),
      child: Container(
        decoration: BoxDecoration(
          color: colors.cardColor,
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: _isLoadingRatings
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: colors.textColor,
                  strokeWidth: 2,
                ),
              )
            : Text(
                'Rated ${_averageRating.toStringAsFixed(1)} by $_totalRatingsCount ${_totalRatingsCount == 1 ? 'voter' : 'voters'}',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textColor,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Inter',
                ),
              ),
      ),
    );
  }

  // FIXED: Only pass postId to RatingListScreen
  void _navigateToRatingList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RatingListScreen(
          postId: widget.snap['postId'],
        ),
      ),
    );
  }

  Widget _buildUserAvatar(_ColorSet colors) {
    return GestureDetector(
      onTap: () => _navigateToProfile(),
      child: CircleAvatar(
        radius: 21,
        backgroundColor: colors.cardColor,
        backgroundImage: widget.snap['profImage'] != null &&
                widget.snap['profImage'] != "default"
            ? NetworkImage(widget.snap['profImage'])
            : null,
        child: widget.snap['profImage'] == null ||
                widget.snap['profImage'] == "default"
            ? Icon(Icons.account_circle, size: 42, color: colors.iconColor)
            : null,
      ),
    );
  }

  Widget _buildMoreButton(model.AppUser user, _ColorSet colors) {
    final isCurrentUserPost = widget.snap['uid'] == user.uid;

    return IconButton(
      icon: Icon(Icons.more_vert, color: colors.textColor),
      onPressed: () => isCurrentUserPost
          ? _showDeleteConfirmation(colors)
          : _showReportDialog(colors),
    );
  }

  void _showDeleteConfirmation(_ColorSet colors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.cardColor,
        title: Text('Delete Post', style: TextStyle(color: colors.textColor)),
        content: Text('Are you sure you want to delete this post?',
            style: TextStyle(color: colors.textColor.withOpacity(0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePost();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSection(_ColorSet colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: InteractiveViewer(
            panEnabled: true,
            scaleEnabled: true,
            minScale: 1.0,
            maxScale: 4.0,
            child: Image.network(
              widget.snap['postUrl']?.toString() ?? '',
              fit: BoxFit.cover,
              width: double.infinity,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      color: colors.textColor,
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Icon(Icons.broken_image,
                      size: 48, color: colors.iconColor),
                );
              },
            ),
          ),
        ),
        if (widget.snap['description']?.toString().isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Text(
              widget.snap['description'].toString(),
              style: TextStyle(
                color: colors.textColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                fontFamily: 'Inter',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCommentButton(_ColorSet colors) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.comment_outlined, color: colors.textColor),
          onPressed: () => _navigateToComments(),
        ),
        if (_commentCount > 0)
          Positioned(
            top: -6,
            left: -6,
            child: Container(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 20,
                minHeight: 20,
              ),
              decoration: BoxDecoration(
                color: colors.cardColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _commentCount.toString(),
                  style: TextStyle(
                    color: colors.textColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(uid: widget.snap['uid']),
      ),
    );
  }

  void _navigateToComments() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CommentsScreen(postId: widget.snap['postId']),
      ),
    ).then((_) {
      // Refresh comment count when returning from comments screen
      _fetchCommentsCount();
    });
  }
}

// SINGLE RatingListScreen class definition
class RatingListScreen extends StatefulWidget {
  final String postId;

  const RatingListScreen({
    super.key,
    required this.postId,
  });

  @override
  State<RatingListScreen> createState() => _RatingListScreenState();
}

class _RatingListScreenState extends State<RatingListScreen> {
  late final RealtimeChannel _ratingsChannel;
  List<Map<String, dynamic>> _ratings = [];
  int _page = 0;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();
  final Map<String, Map<String, dynamic>> _userCache = {};

  // Helper method to get the appropriate color scheme
  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  @override
  void initState() {
    super.initState();
    _setupRealtime();
    _fetchInitialRatings();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
          _scrollController.position.maxScrollExtent) {
        _loadMoreRatings();
      }
    });
  }

  void _setupRealtime() {
    _ratingsChannel =
        Supabase.instance.client.channel('post_ratings_${widget.postId}');

    _ratingsChannel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'post_rating',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'postid',
            value: widget.postId,
          ),
          callback: (payload) {
            _handleRealtimeUpdate(payload);
          },
        )
        .subscribe();
  }

  Future<void> _fetchInitialRatings() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client
          .from('post_rating')
          .select('''
            *,
            users!userid (username, photoUrl)
        ''')
          .eq('postid', widget.postId)
          .order('timestamp', ascending: false)
          .range(0, _limit - 1);

      if (mounted) {
        setState(() {
          _ratings = (response as List)
              .map<Map<String, dynamic>>((r) => r as Map<String, dynamic>)
              .toList();
          _isLoading = false;
          _page = 1;
          _hasMore = _ratings.length == _limit;

          // Cache user info
          for (var rating in _ratings) {
            final userId = rating['userid'] as String?;
            if (userId != null) {
              final userData = rating['users'] as Map<String, dynamic>?;
              if (userData != null) {
                _userCache[userId] = userData;
              }
            }
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreRatings() async {
    if (!_hasMore || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final response = await Supabase.instance.client
          .from('post_rating')
          .select('*, user:userid (username, photoUrl)')
          .eq('postid', widget.postId)
          .order('timestamp', ascending: false)
          .range(_page * _limit, (_page * _limit) + _limit - 1);

      if (mounted) {
        setState(() {
          final newRatings = (response as List)
              .map<Map<String, dynamic>>((r) => r as Map<String, dynamic>)
              .toList();

          _ratings.addAll(newRatings);
          _isLoadingMore = false;
          _page++;
          _hasMore = newRatings.length == _limit;

          // Cache user info
          for (var rating in newRatings) {
            final userId = rating['userid'] as String?;
            if (userId != null) {
              final userData = rating['user'] as Map<String, dynamic>?;
              if (userData != null) {
                _userCache[userId] = userData;
              }
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _handleRealtimeUpdate(PostgresChangePayload payload) {
    final newRecord = payload.newRecord;
    final oldRecord = payload.oldRecord;
    final eventType = payload.eventType;

    setState(() {
      switch (eventType) {
        case PostgresChangeEvent.insert:
          if (newRecord != null) {
            // Insert at top for new ratings
            _ratings.insert(0, newRecord);
          }
          break;
        case PostgresChangeEvent.update:
          if (oldRecord != null && newRecord != null) {
            final index = _ratings.indexWhere(
              (r) => r['userid'] == oldRecord['userid'],
            );
            if (index != -1) _ratings[index] = newRecord;
          }
          break;
        case PostgresChangeEvent.delete:
          if (oldRecord != null) {
            _ratings.removeWhere(
              (r) => r['userid'] == oldRecord['userid'],
            );
          }
          break;
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _ratingsChannel.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildRatingItem(Map<String, dynamic> rating, _ColorSet colors) {
    final userId = rating['userid'] as String? ?? '';
    final userRating = (rating['rating'] as num?)?.toDouble() ?? 0.0;
    final timestampStr = rating['timestamp'] as String?;
    final timestamp = timestampStr != null
        ? DateTime.tryParse(timestampStr) ?? DateTime.now()
        : DateTime.now();
    final timeText = timeago.format(timestamp);

    // Get user info from cache or use fallback
    final userData = _userCache[userId] ?? {};
    final photoUrl = userData['photoUrl'] as String? ?? '';
    final username = userData['username'] as String? ?? 'Deleted user';

    return Container(
      decoration: BoxDecoration(
        color: colors.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          radius: 21,
          backgroundImage: (photoUrl.isNotEmpty && photoUrl != 'default')
              ? NetworkImage(photoUrl)
              : null,
          child: (photoUrl.isEmpty || photoUrl == 'default')
              ? Icon(Icons.account_circle, size: 42, color: colors.iconColor)
              : null,
        ),
        title: Text(
          username,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.textColor,
          ),
        ),
        subtitle: Text(
          timeText,
          style: TextStyle(color: colors.textColor.withOpacity(0.6)),
        ),
        trailing: Chip(
          label: Text(
            userRating.toStringAsFixed(1),
            style: TextStyle(color: colors.textColor),
          ),
          backgroundColor: colors.cardColor,
        ),
        onTap: username == 'Deleted user'
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(uid: userId),
                  ),
                ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        title: Text('Ratings', style: TextStyle(color: colors.textColor)),
        backgroundColor: colors.backgroundColor,
        iconTheme: IconThemeData(color: colors.textColor),
      ),
      body: _isLoading && _ratings.isEmpty
          ? Center(child: CircularProgressIndicator(color: colors.textColor))
          : _ratings.isEmpty
              ? Center(
                  child: Text('No ratings yet',
                      style: TextStyle(color: colors.textColor)))
              : ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _ratings.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (context, index) =>
                      Divider(color: colors.cardColor),
                  itemBuilder: (context, index) {
                    if (index < _ratings.length) {
                      return _buildRatingItem(_ratings[index], colors);
                    } else {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: _isLoadingMore
                              ? CircularProgressIndicator(
                                  color: colors.textColor)
                              : const SizedBox(),
                        ),
                      );
                    }
                  },
                ),
    );
  }
}
