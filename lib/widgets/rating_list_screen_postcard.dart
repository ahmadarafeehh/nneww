import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart'; // Add this import

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
  Color _getTextColor(ThemeProvider themeProvider) {
    return themeProvider.themeMode == ThemeMode.dark
        ? const Color(0xFFd9d9d9)
        : Colors.black;
  }

  Color _getBackgroundColor(ThemeProvider themeProvider) {
    return themeProvider.themeMode == ThemeMode.dark
        ? const Color(0xFF121212)
        : Colors.white;
  }

  Color _getCardColor(ThemeProvider themeProvider) {
    return themeProvider.themeMode == ThemeMode.dark
        ? const Color(0xFF333333)
        : Colors.grey[200]!;
  }

  Color _getIconColor(ThemeProvider themeProvider) {
    return themeProvider.themeMode == ThemeMode.dark
        ? const Color(0xFFd9d9d9)
        : Colors.grey[700]!;
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
      final start = _page * _limit;
      final end = start + _limit - 1;

      final response = await Supabase.instance.client
          .from('post_rating')
          .select('''
          *,
          users!userid(username, photoUrl)
        ''')
          .eq('postid', widget.postId)
          .order('timestamp', ascending: false)
          .range(start, end); // Use calculated range

      if (mounted) {
        setState(() {
          final newRatings = (response as List)
              .map<Map<String, dynamic>>((r) => r as Map<String, dynamic>)
              .toList();

          _ratings.addAll(newRatings);
          _isLoadingMore = false;
          _page++;
          _hasMore = newRatings.length == _limit;

          // Cache user info - FIXED: use 'users' instead of 'user'
          for (var rating in newRatings) {
            final userId = rating['userid'] as String?;
            if (userId != null) {
              final userData =
                  rating['users'] as Map<String, dynamic>?; // Fixed this line
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

  Widget _buildRatingItem(
      Map<String, dynamic> rating, ThemeProvider themeProvider) {
    final textColor = _getTextColor(themeProvider);
    final cardColor = _getCardColor(themeProvider);
    final iconColor = _getIconColor(themeProvider);

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
        color: cardColor,
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
              ? Icon(Icons.account_circle, size: 42, color: iconColor)
              : null,
        ),
        title: Text(
          username,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        subtitle: Text(
          timeText,
          style: TextStyle(color: textColor.withOpacity(0.6)),
        ),
        trailing: Chip(
          label: Text(
            userRating.toStringAsFixed(1),
            style: TextStyle(color: textColor),
          ),
          backgroundColor: cardColor,
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
    final textColor = _getTextColor(themeProvider);
    final backgroundColor = _getBackgroundColor(themeProvider);
    final cardColor = _getCardColor(themeProvider);
    final progressIndicatorColor = _getIconColor(themeProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text('Ratings', style: TextStyle(color: textColor)),
        backgroundColor: backgroundColor,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: _isLoading && _ratings.isEmpty
          ? Center(
              child: CircularProgressIndicator(color: progressIndicatorColor))
          : _ratings.isEmpty
              ? Center(
                  child: Text('No ratings yet',
                      style: TextStyle(color: textColor)))
              : ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _ratings.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (context, index) =>
                      Divider(color: cardColor),
                  itemBuilder: (context, index) {
                    if (index < _ratings.length) {
                      return _buildRatingItem(_ratings[index], themeProvider);
                    } else {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: _isLoadingMore
                              ? CircularProgressIndicator(
                                  color: progressIndicatorColor)
                              : const SizedBox(),
                        ),
                      );
                    }
                  },
                ),
    );
  }
}
