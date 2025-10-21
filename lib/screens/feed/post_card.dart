import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/models/user.dart' as model;
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/services/api_service.dart';
import 'package:Ratedly/screens/comment_screen.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/widgets/flutter_rating_bar.dart';
import 'package:Ratedly/widgets/postshare.dart';
import 'package:Ratedly/widgets/blocked_content_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui';

// Add this import for SupabasePostsMethods
import 'package:Ratedly/resources/supabase_posts_methods.dart';

// Video Manager to ensure only one video plays at a time
class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal();

  VideoPlayerController? _currentPlayingController;
  String? _currentPostId;

  void playVideo(VideoPlayerController controller, String postId) {
    if (_currentPlayingController != null &&
        _currentPlayingController != controller) {
      _currentPlayingController!.pause();
    }

    _currentPlayingController = controller;
    _currentPostId = postId;
    controller.play();
  }

  void pauseVideo(VideoPlayerController controller) {
    if (_currentPlayingController == controller) {
      controller.pause();
      _currentPlayingController = null;
      _currentPostId = null;
    }
  }

  void disposeController(VideoPlayerController controller, String postId) {
    if (_currentPlayingController == controller) {
      _currentPlayingController = null;
      _currentPostId = null;
    }
    controller.pause();
    controller.dispose();
  }

  bool isCurrentlyPlaying(VideoPlayerController controller) {
    return _currentPlayingController == controller;
  }

  void onPostInvisible(String postId) {
    if (_currentPostId == postId && _currentPlayingController != null) {
      _currentPlayingController!.pause();
      _currentPlayingController = null;
      _currentPostId = null;
    }
  }

  String? get currentPlayingPostId => _currentPostId;

  void pauseCurrentVideo() {
    if (_currentPlayingController != null) {
      _currentPlayingController!.pause();
      _currentPlayingController = null;
      _currentPostId = null;
    }
  }
}

// Define color schemes for both themes at top level
class _ColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;
  final Color skeletonColor;
  final Color progressIndicatorColor;

  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
    required this.skeletonColor,
    required this.progressIndicatorColor,
  });
}

class _DarkColors extends _ColorSet {
  _DarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
          skeletonColor: const Color(0xFF333333).withOpacity(0.6),
          progressIndicatorColor: Colors.white70,
        );
}

class _LightColors extends _ColorSet {
  _LightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.grey[100]!,
          cardColor: Colors.white,
          iconColor: Colors.grey[700]!,
          skeletonColor: Colors.grey[300]!.withOpacity(0.6),
          progressIndicatorColor: Colors.grey[700]!,
        );
}

class PostCard extends StatefulWidget {
  final dynamic snap;
  final VoidCallback? onRateUpdate;
  final bool isVisible;
  final VoidCallback? onCommentTap;

  const PostCard({
    Key? key,
    required this.snap,
    this.onRateUpdate,
    this.isVisible = true,
    this.onCommentTap,
  }) : super(key: key);

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with AutomaticKeepAliveClientMixin<PostCard>, WidgetsBindingObserver {
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

  // Video player variables
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoLoading = false;
  bool _isVideoPlaying = false;
  bool _isMuted = false;

  // Caption expansion state
  bool _isCaptionExpanded = false;

  late List<Map<String, dynamic>> _localRatings;
  final ApiService _apiService = ApiService();
  final VideoManager _videoManager = VideoManager();

  // SupabasePostsMethods instance
  final SupabasePostsMethods _postsMethods = SupabasePostsMethods();

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

  String get _postId => widget.snap['postId']?.toString() ?? '';

  // Check if URL is a video
  bool get _isVideo {
    final url = (widget.snap['postUrl']?.toString() ?? '').toLowerCase();
    return url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.avi') ||
        url.endsWith('.mkv') ||
        url.contains('video');
  }

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
    WidgetsBinding.instance.addObserver(this);

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
    _fetchInitialRatings();
    _fetchCommentsCount();

    if (_isVideo) {
      _initializeVideoPlayer();
    }
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isVisible != widget.isVisible && _isVideo) {
      if (widget.isVisible) {
        if (_isVideoInitialized && !_isVideoPlaying) {
          _playVideo();
        } else if (!_isVideoInitialized && !_isVideoLoading) {
          _initializeVideoPlayer();
        }
      } else {
        if (_isVideoInitialized && _isVideoPlaying) {
          _pauseVideo();
        }
        _videoManager.onPostInvisible(_postId);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeVideoController();
    _postChannel.unsubscribe();
    super.dispose();
  }

  void _disposeVideoController() {
    if (_videoController != null) {
      _videoController!.removeListener(_videoListener);
      _videoManager.disposeController(_videoController!, _postId);
      _videoController = null;
    }
    _isVideoInitialized = false;
    _isVideoPlaying = false;
    _isVideoLoading = false;
  }

  void _videoListener() {
    if (!mounted) return;

    final wasPlaying = _isVideoPlaying;
    final isNowPlaying = _videoController?.value.isPlaying ?? false;

    if (wasPlaying != isNowPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        setState(() {
          _isVideoPlaying = isNowPlaying;
        });
      });
    }

    if (_videoController != null &&
        _videoController!.value.position == _videoController!.value.duration &&
        _videoController!.value.duration != Duration.zero) {
      _videoController!.seekTo(Duration.zero);
      if (widget.isVisible && !_isVideoPlaying) {
        _videoController!.play();
      }
    }
  }

  void _initializeVideoPlayer() async {
    if (_isVideoLoading || _isVideoInitialized) return;

    setState(() => _isVideoLoading = true);

    try {
      final videoUrl = widget.snap['postUrl']?.toString() ?? '';
      if (videoUrl.isEmpty) {
        throw Exception('Empty video URL');
      }

      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );

      _videoController!.addListener(_videoListener);

      await _videoController!.initialize().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('Video loading timeout');
        },
      );

      _videoController!.setLooping(true);

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
          _isVideoLoading = false;
        });

        if (widget.isVisible) {
          _playVideo();
        } else {
          _pauseVideo();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isVideoLoading = false);
      }
    }
  }

  void _playVideo() {
    if (_videoController != null &&
        _isVideoInitialized &&
        mounted &&
        widget.isVisible) {
      _videoManager.playVideo(_videoController!, _postId);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isVideoPlaying = true;
          });
        }
      });
    }
  }

  void _pauseVideo() {
    if (_videoController != null && _isVideoInitialized && mounted) {
      _videoManager.pauseVideo(_videoController!);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isVideoPlaying = false;
          });
        }
      });
    }
  }

  void _toggleMute() {
    if (_videoController != null && _isVideoInitialized && mounted) {
      setState(() {
        _isMuted = !_isMuted;
        _videoController!.setVolume(_isMuted ? 0.0 : 1.0);
      });
    }
  }

  void _toggleVideoPlayback() {
    if (!widget.isVisible) return;

    if (_isVideoPlaying) {
      _pauseVideo();
    } else {
      _playVideo();
    }
  }

  int _countItems(dynamic value) {
    try {
      if (value == null) return 0;
      if (value is List) return value.length;
      if (value is Iterable) return value.length;
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _fetchCommentsCount() async {
    try {
      final commentsResponse = await Supabase.instance.client
          .from('comments')
          .select('id')
          .eq('postid', widget.snap['postId']);

      final repliesResponse = await Supabase.instance.client
          .from('replies')
          .select('id')
          .eq('postid', widget.snap['postId']);

      final int commentsCount = _countItems(commentsResponse);
      final int repliesCount = _countItems(repliesResponse);

      final int totalCount = commentsCount + repliesCount;

      if (mounted) {
        setState(() {
          _commentCount = totalCount;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _commentCount = (widget.snap['commentsCount'] ?? 0).toInt();
        });
      }
    }
  }

  void _setupRealtime() {
    _postChannel =
        Supabase.instance.client.channel('post_${widget.snap['postId']}');

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
        _fetchCommentsCount();
      },
    );

    _postChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'replies',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'postid',
        value: widget.snap['postId'],
      ),
      callback: (payload) {
        _fetchCommentsCount();
      },
    );

    _postChannel.subscribe();
  }

  // Fetch initial ratings
  Future<void> _fetchInitialRatings() async {
    setState(() => _isLoadingRatings = true);

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

      // Initialize local ratings
      final allRatings = await Supabase.instance.client
          .from('post_rating')
          .select()
          .eq('postid', widget.snap['postId']);

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
            _showSlider = false;
          } else {
            _userRating = null;
            _showSlider = true;
          }

          // Initialize local ratings
          _localRatings = (allRatings as List<dynamic>)
              .map<Map<String, dynamic>>((r) => r as Map<String, dynamic>)
              .toList();

          _isLoadingRatings = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRatings = false);
      }
    }
  }

  // Handle realtime rating updates
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

            final user = Provider.of<UserProvider>(context, listen: false).user;
            if (user != null && newRecord['userid'] == user.uid) {
              _showSlider = false;
              _userRating = (newRecord['rating'] as num).toDouble();
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

            final user = Provider.of<UserProvider>(context, listen: false).user;
            if (user != null && newRecord['userid'] == user.uid) {
              _userRating = (newRecord['rating'] as num).toDouble();
            }
          }
          break;
        case PostgresChangeEvent.delete:
          if (oldRecord != null) {
            _localRatings.removeWhere(
              (r) => r['userid'] == oldRecord['userid'],
            );
            _totalRatingsCount--;
            _updateAverageRating();

            final user = Provider.of<UserProvider>(context, listen: false).user;
            if (user != null && oldRecord['userid'] == user.uid) {
              _showSlider = true;
              _userRating = null;
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

    final newAverage = total / _localRatings.length;
    setState(() => _averageRating = newAverage);
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

  // Rating submission handler
  void _handleRatingSubmitted(double rating) async {
    final user = Provider.of<UserProvider>(context, listen: false).user;

    if (user == null) {
      setState(() => _isRating = false);
      return;
    }

    // OPTIMISTIC UPDATE
    setState(() {
      _isRating = true;
      _userRating = rating;
      _showSlider = false;

      // Optimistic update
      if (_totalRatingsCount > 0) {
        final newTotal = _averageRating * _totalRatingsCount;
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

    // API CALL
    try {
      final success = await _postsMethods.ratePost(
        widget.snap['postId'],
        user.uid,
        rating,
      );

      if (success != 'success' && mounted) {
        _fetchInitialRatings(); // Refetch if failed
      }
    } catch (e) {
      if (mounted) {
        _fetchInitialRatings(); // Refetch on error
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRating = false;
        });
      }
    }
  }

  void _handleEditRating() {
    setState(() {
      _showSlider = true;
    });
  }

  // Expandable caption widget
  Widget _buildExpandableCaption(_ColorSet colors) {
    final caption = widget.snap['description'].toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _isCaptionExpanded = !_isCaptionExpanded;
            });
          },
          child: Container(
            width: double.infinity,
            child: _isCaptionExpanded
                ? Text(
                    caption,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.normal,
                      fontFamily: 'Inter',
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          caption,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.normal,
                            fontFamily: 'Inter',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isCaptionExpanded = true;
                          });
                        },
                        child: Container(
                          padding: EdgeInsets.all(4),
                          child: Text(
                            '...',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
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

  Widget _buildVideoPlayer(_ColorSet colors) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_isVideoInitialized)
            GestureDetector(
              onTap: _toggleVideoPlayback,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController!.value.size?.width ?? 1,
                    height: _videoController!.value.size?.height ?? 1,
                    child: VideoPlayer(_videoController!),
                  ),
                ),
              ),
            )
          else if (_isVideoLoading)
            Container(
              color: Colors.black,
              child: Center(
                child: Container(
                  width: 60,
                  height: 60,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[800]!.withOpacity(0.8),
                    shape: BoxShape.circle,
                  ),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.grey[300]!),
                    backgroundColor: Colors.grey[600]!,
                  ),
                ),
              ),
            )
          else
            Container(
              color: colors.skeletonColor,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam, size: 50, color: colors.iconColor),
                    SizedBox(height: 8),
                    Text(
                      'Video not available',
                      style: TextStyle(color: colors.iconColor),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
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

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      body: Stack(
        children: [
          _buildMediaContent(colors),
          Positioned(
            bottom: 220,
            right: 16,
            child: _buildRightActionButtons(colors),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: _buildBottomOverlay(user, colors),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent(_ColorSet colors) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: _isVideo
          ? _buildVideoPlayer(colors)
          : InteractiveViewer(
              panEnabled: true,
              scaleEnabled: true,
              minScale: 1.0,
              maxScale: 4.0,
              child: Image.network(
                widget.snap['postUrl']?.toString() ?? '',
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;

                  return Container(
                    color: colors.skeletonColor,
                    child: Center(
                      child: Container(
                        width: 50,
                        height: 50,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[800]!.withOpacity(0.8),
                          shape: BoxShape.circle,
                        ),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.grey[300]!),
                          backgroundColor: Colors.grey[600]!,
                        ),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: colors.skeletonColor,
                    child: Center(
                      child:
                          Icon(Icons.photo, size: 48, color: colors.iconColor),
                    ),
                  );
                },
                cacheWidth: (MediaQuery.of(context).size.width * 2).toInt(),
                cacheHeight: (MediaQuery.of(context).size.height * 2).toInt(),
              ),
            ),
    );
  }

  Widget _buildRightActionButtons(_ColorSet colors) {
    return Column(
      children: [
        GestureDetector(
          onTap: _navigateToProfile,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: widget.snap['profImage'] != null &&
                    widget.snap['profImage'] != "default"
                ? CircleAvatar(
                    radius: 21,
                    backgroundImage: NetworkImage(widget.snap['profImage']),
                  )
                : Icon(Icons.account_circle, size: 42, color: colors.iconColor),
          ),
        ),
        const SizedBox(height: 20),
        _buildCommentButton(colors),
        const SizedBox(height: 8),
        IconButton(
          icon: Icon(Icons.send, color: Colors.white, size: 28),
          onPressed: () => _navigateToShare(colors),
        ),
        const SizedBox(height: 8),
        if (_isVideo && _isVideoInitialized)
          Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _isMuted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
                size: 24,
              ),
              onPressed: _toggleMute,
            ),
          ),
      ],
    );
  }

  Widget _buildBottomOverlay(model.AppUser user, _ColorSet colors) {
    final datePublished = _parseDate(widget.snap['datePublished']);
    final timeagoText =
        datePublished != null ? timeago.format(datePublished) : '';

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Use the exact same RatingBar widget as ImageViewScreen
          RatingBar(
            initialRating: _userRating ?? 5.0,
            hasRated: _userRating != null,
            userRating: _userRating ?? 0.0,
            onRatingEnd: _handleRatingSubmitted,
            isRating: _isRating,
            showSlider: _showSlider,
            onEditRating: _handleEditRating,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _navigateToProfile,
                      child: Text(
                        widget.snap['username']?.toString() ?? 'Unknown',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                    if (timeagoText.isNotEmpty)
                      Text(
                        timeagoText,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                          fontFamily: 'Inter',
                        ),
                      ),
                  ],
                ),
              ),
              // Use the exact same rating summary as ImageViewScreen
              InkWell(
                onTap: _navigateToRatingList,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: _isLoadingRatings
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: colors.progressIndicatorColor,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Rated ${_averageRating.toStringAsFixed(1)} by $_totalRatingsCount ${_totalRatingsCount == 1 ? 'voter' : 'voters'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Use the new expandable caption widget instead of the original text
          if (widget.snap['description']?.toString().isNotEmpty ?? false)
            _buildExpandableCaption(colors),
        ],
      ),
    );
  }

  Widget _buildCommentButton(_ColorSet colors) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.comment_outlined, color: Colors.white, size: 28),
          onPressed: () {
            widget.onCommentTap?.call();
          },
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

  DateTime? _parseDate(dynamic date) {
    if (date == null) return null;
    if (date is DateTime) return date;
    if (date is String) return DateTime.tryParse(date);
    return null;
  }

  void _showDeleteConfirmation(_ColorSet colors) {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    final isCurrentUserPost = user != null && widget.snap['uid'] == user.uid;

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

  void _navigateToProfile() {
    if (_isVideo && _isVideoInitialized && _isVideoPlaying) {
      _pauseVideo();
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(uid: widget.snap['uid']),
      ),
    );
  }

  void _openCommentsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentsBottomSheet(
        postId: widget.snap['postId'],
        postImage: widget.snap['postUrl'],
        isVideo: _isVideo,
        onClose: () {
          // Video will automatically resume if it was playing before
        },
        videoController: _videoController,
      ),
    ).then((_) {
      _fetchCommentsCount();
    });
  }

  void _navigateToRatingList() {
    if (_isVideo && _isVideoInitialized && _isVideoPlaying) {
      _pauseVideo();
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FastRatingListScreen(
          postId: widget.snap['postId'],
        ),
      ),
    );
  }

  void _navigateToShare(_ColorSet colors) {
    if (_isVideo && _isVideoInitialized && _isVideoPlaying) {
      _pauseVideo();
    }
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;

    showDialog(
      context: context,
      builder: (context) => PostShare(
        currentUserId: user.uid,
        postId: widget.snap['postId'],
      ),
    );
  }
}

class FastRatingListScreen extends StatefulWidget {
  final String postId;

  const FastRatingListScreen({
    super.key,
    required this.postId,
  });

  @override
  State<FastRatingListScreen> createState() => _FastRatingListScreenState();
}

class _FastRatingListScreenState extends State<FastRatingListScreen> {
  late final RealtimeChannel _ratingsChannel;
  List<Map<String, dynamic>> _ratings = [];
  int _page = 0;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();

  final Map<String, Map<String, dynamic>> _userCache = {};
  final _supabase = Supabase.instance.client;

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
    _ratingsChannel = _supabase.channel('post_ratings_${widget.postId}');

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
      final response = await _supabase
          .from('post_rating')
          .select()
          .eq('postid', widget.postId)
          .order('timestamp', ascending: false)
          .range(0, _limit - 1);

      if (mounted) {
        _ratings = List<Map<String, dynamic>>.from(response);

        await _bulkFetchUsers();

        setState(() {
          _isLoading = false;
          _page = 1;
          _hasMore = _ratings.length == _limit;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _bulkFetchUsers() async {
    final Set<String> userIds = {};

    for (final rating in _ratings) {
      final userId = rating['userid'] as String? ?? '';
      if (userId.isNotEmpty && !_userCache.containsKey(userId)) {
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
        setState(() {});
      }
    } catch (e) {
      // Error handled silently
    }
  }

  Future<void> _loadMoreRatings() async {
    if (!_hasMore || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final response = await _supabase
          .from('post_rating')
          .select()
          .eq('postid', widget.postId)
          .order('timestamp', ascending: false)
          .range(_page * _limit, (_page * _limit) + _limit - 1);

      if (mounted) {
        final newRatings = List<Map<String, dynamic>>.from(response);

        await _bulkFetchUsers();

        setState(() {
          _ratings.addAll(newRatings);
          _isLoadingMore = false;
          _page++;
          _hasMore = newRatings.length == _limit;
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
          ? Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.skeletonColor,
                  shape: BoxShape.circle,
                ),
              ),
            )
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
                              ? Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: colors.skeletonColor,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : const SizedBox(),
                        ),
                      );
                    }
                  },
                ),
    );
  }
}
