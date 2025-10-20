import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/screens/Profile_page/image_screen.dart';
import 'package:Ratedly/screens/messaging_screen.dart';
import 'package:Ratedly/screens/Profile_page/blocked_profile_screen.dart';
import 'package:Ratedly/widgets/user_list_screen.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';
import 'package:Ratedly/resources/profile_firestore_methods.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/gestures.dart';

// Define color schemes for both themes at top level
class _OtherProfileColorSet {
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;
  final Color appBarBackgroundColor;
  final Color appBarIconColor;
  final Color progressIndicatorColor;
  final Color avatarBackgroundColor;
  final Color buttonBackgroundColor;
  final Color buttonTextColor;
  final Color dividerColor;
  final Color dialogBackgroundColor;
  final Color dialogTextColor;
  final Color errorTextColor;
  final Color radioActiveColor;
  final Color skeletonColor;

  _OtherProfileColorSet({
    required this.backgroundColor,
    required this.textColor,
    required this.iconColor,
    required this.appBarBackgroundColor,
    required this.appBarIconColor,
    required this.progressIndicatorColor,
    required this.avatarBackgroundColor,
    required this.buttonBackgroundColor,
    required this.buttonTextColor,
    required this.dividerColor,
    required this.dialogBackgroundColor,
    required this.dialogTextColor,
    required this.errorTextColor,
    required this.radioActiveColor,
    required this.skeletonColor,
  });
}

class _OtherProfileDarkColors extends _OtherProfileColorSet {
  _OtherProfileDarkColors()
      : super(
          backgroundColor: const Color(0xFF121212),
          textColor: const Color(0xFFd9d9d9),
          iconColor: const Color(0xFFd9d9d9),
          appBarBackgroundColor: const Color(0xFF121212),
          appBarIconColor: const Color(0xFFd9d9d9),
          progressIndicatorColor: const Color(0xFFd9d9d9),
          avatarBackgroundColor: const Color(0xFF333333),
          buttonBackgroundColor: const Color(0xFF333333),
          buttonTextColor: const Color(0xFFd9d9d9),
          dividerColor: const Color(0xFF333333),
          dialogBackgroundColor: const Color(0xFF121212),
          dialogTextColor: const Color(0xFFd9d9d9),
          errorTextColor: Colors.grey[600]!,
          radioActiveColor: const Color(0xFFd9d9d9),
          skeletonColor: const Color(0xFF333333).withOpacity(0.6),
        );
}

class _OtherProfileLightColors extends _OtherProfileColorSet {
  _OtherProfileLightColors()
      : super(
          backgroundColor: Colors.white,
          textColor: Colors.black,
          iconColor: Colors.black,
          appBarBackgroundColor: Colors.white,
          appBarIconColor: Colors.black,
          progressIndicatorColor: Colors.grey[700]!,
          avatarBackgroundColor: Colors.grey[300]!,
          buttonBackgroundColor: Colors.grey[300]!,
          buttonTextColor: Colors.black,
          dividerColor: Colors.grey[300]!,
          dialogBackgroundColor: Colors.white,
          dialogTextColor: Colors.black,
          errorTextColor: Colors.grey[600]!,
          radioActiveColor: Colors.black,
          skeletonColor: Colors.grey[300]!.withOpacity(0.6),
        );
}

class ExpandableBioText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color expandColor;
  final int maxLength;

  const ExpandableBioText({
    Key? key,
    required this.text,
    required this.style,
    required this.expandColor,
    this.maxLength = 115,
  }) : super(key: key);

  @override
  State<ExpandableBioText> createState() => _ExpandableBioTextState();
}

class _ExpandableBioTextState extends State<ExpandableBioText> {
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

class OtherUserProfileScreen extends StatefulWidget {
  final String uid;
  const OtherUserProfileScreen({Key? key, required this.uid}) : super(key: key);

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  var userData = {};
  int postLen = 0;
  int followers = 0;
  bool isFollowing = false;
  bool isLoading = true;
  bool _isBlockedByMe = false;
  bool _isBlocked = false;
  bool _isBlockedByThem = false;
  bool _isViewerFollower = false;
  bool hasPendingRequest = false;
  List<dynamic> _followersList = [];
  int following = 0;
  bool _isMutualFollow = false;

  // Video player controllers cache
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, bool> _videoControllersInitialized = {};

  // Add the missing profileReportReasons list
  final List<String> profileReportReasons = [
    'Impersonation (Pretending to be someone else)',
    'Fake Account (Misleading or suspicious profile)',
    'Bullying or Harassment',
    'Hate Speech or Discrimination (e.g., race, religion, gender, sexual orientation)',
    'Scam or Fraud (Deceptive activity, phishing, or financial fraud)',
    'Spam (Unwanted promotions or repetitive content)',
    'Inappropriate Content (Explicit, offensive, or disturbing profile)',
  ];

  // Add these for faster loading
  List<dynamic> _posts = [];
  Timer? _searchDebounce;
  bool _postsLoading = false;

  // Helper method to get the appropriate color scheme
  _OtherProfileColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _OtherProfileDarkColors() : _OtherProfileLightColors();
  }

  @override
  void initState() {
    super.initState();
    _loadDataInParallel();
  }

  // -------------------------
  // OPTIMIZED: Parallel data loading like search screen
  // -------------------------
  Future<void> _loadDataInParallel() async {
    setState(() => isLoading = true);

    try {
      await Future.wait([
        _loadUserData(),
        _loadPosts(),
        _loadBlockStatus(),
      ]);

      if (!_isBlocked && mounted) {
        await _loadRelationshipData();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
            context, "Please try again or contact us at ratedly9@gmail.com");
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      final userResponse =
          await _supabase.from('users').select().eq('uid', widget.uid).single();

      if (mounted) {
        setState(() {
          userData = userResponse;
        });
      }
    } catch (e) {
      // User data is essential, so we might want to handle this differently
    }
  }

  Future<void> _loadPosts() async {
    try {
      final postsResponse = await _supabase
          .from('posts')
          .select('postId, postUrl, description, datePublished, uid')
          .eq('uid', widget.uid)
          .order('datePublished', ascending: false);

      // Pre-initialize video controllers for video posts
      _preInitializeVideoControllers(postsResponse);

      if (mounted) {
        setState(() {
          _posts = postsResponse;
          postLen = postsResponse.length;
        });
      }
    } catch (e) {
      // Posts can load separately
    }
  }

  Future<void> _loadBlockStatus() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final isBlockedByMe = await SupabaseBlockMethods().isBlockInitiator(
        currentUserId: currentUserId,
        targetUserId: widget.uid,
      );

      final isBlockedByThem = await SupabaseBlockMethods().isUserBlocked(
        currentUserId: currentUserId,
        targetUserId: widget.uid,
      );

      if (mounted) {
        setState(() {
          _isBlockedByMe = isBlockedByMe;
          _isBlockedByThem = isBlockedByThem;
          _isBlocked = isBlockedByMe || isBlockedByThem;
        });
      }

      if (_isBlocked && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => BlockedProfileScreen(
                uid: widget.uid,
                isBlocker: _isBlockedByMe,
              ),
            ),
          );
        });
      }
    } catch (e) {
      // Block status can fail without breaking the whole screen
    }
  }

  Future<void> _loadRelationshipData() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      // Load followers, following, and relationship status in parallel
      // Explicitly cast each future to Future<dynamic> to resolve type inference issues
      final results = await Future.wait<dynamic>([
        _supabase
            .from('user_followers')
            .select('follower_id, followed_at')
            .eq('user_id', widget.uid)
            .then((value) => value as List<dynamic>),
        _supabase
            .from('user_following')
            .select('following_id, followed_at')
            .eq('user_id', widget.uid)
            .then((value) => value as List<dynamic>),
        _supabase
            .from('user_following')
            .select()
            .eq('user_id', currentUserId)
            .eq('following_id', widget.uid)
            .maybeSingle()
            .then((value) => value as Map<String, dynamic>?),
        _supabase
            .from('user_follow_request')
            .select()
            .eq('user_id', widget.uid)
            .eq('requester_id', currentUserId)
            .maybeSingle()
            .then((value) => value as Map<String, dynamic>?),
        _supabase
            .from('user_following')
            .select()
            .eq('user_id', widget.uid)
            .eq('following_id', currentUserId)
            .maybeSingle()
            .then((value) => value as Map<String, dynamic>?),
      ]);

      // Now we can safely cast the results since we've explicitly typed them
      final followersResponse = results[0] as List<dynamic>;
      final followingResponse = results[1] as List<dynamic>;
      final isFollowingResponse = results[2] as Map<String, dynamic>?;
      final followRequestResponse = results[3] as Map<String, dynamic>?;
      final otherFollowsCurrent = results[4] as Map<String, dynamic>?;

      // Process followers with user data
      List<dynamic> processedFollowers = [];
      if (followersResponse.isNotEmpty) {
        final followerIds =
            followersResponse.map((f) => f['follower_id'] as String).toList();

        final followersData = await _supabase
            .from('users')
            .select('uid, username, photoUrl')
            .inFilter('uid', followerIds);

        final followerMap = {
          for (var f in followersData) f['uid'] as String: f
        };

        for (var follower in followersResponse) {
          final followerId = follower['follower_id'] as String;
          final followerInfo = followerMap[followerId];
          if (followerInfo != null) {
            processedFollowers.add({
              'userId': followerId,
              'username': followerInfo['username'],
              'photoUrl': followerInfo['photoUrl'],
              'timestamp': follower['followed_at']
            });
          }
        }
      }

      if (mounted) {
        setState(() {
          followers = followersResponse.length;
          following = followingResponse.length;
          _followersList = processedFollowers;
          isFollowing = isFollowingResponse != null;
          hasPendingRequest = followRequestResponse != null;
          _isMutualFollow =
              isFollowingResponse != null && otherFollowsCurrent != null;
        });
      }
    } catch (e) {
      // Relationship data is non-essential for initial display
      if (mounted) {
        setState(() {
          // Set default values if relationship data fails to load
          followers = 0;
          following = 0;
          _followersList = [];
          isFollowing = false;
          hasPendingRequest = false;
          _isMutualFollow = false;
        });
      }
    }
  }

  // -------------------------
  // Video player logic for first-second looping (OPTIMIZED)
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

      // Initialize without waiting for completion
      controller.initialize().then((_) {
        if (mounted && _videoControllers.containsKey(videoUrl)) {
          _videoControllersInitialized[videoUrl] = true;
          _configureVideoLoop(controller);
          controller.setVolume(0.0);
          setState(() {});
        }
      });
    } catch (e) {
      // Clean up on error
      _videoControllers.remove(videoUrl)?.dispose();
      _videoControllersInitialized.remove(videoUrl);
    }
  }

  /// Configure video to play only first second on loop
  void _configureVideoLoop(VideoPlayerController controller) {
    final duration = controller.value.duration;
    final endPosition =
        duration.inSeconds > 0 ? const Duration(seconds: 1) : duration;

    controller.addListener(() {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        final currentPosition = controller.value.position;
        if (currentPosition >= endPosition) {
          controller.seekTo(Duration.zero);
        }
      }
    });

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

  /// Pre-initialize video controllers for posts
  void _preInitializeVideoControllers(List<dynamic> posts) {
    for (final post in posts) {
      final postUrl = post['postUrl'] ?? '';
      if (_isVideoFile(postUrl)) {
        // Start initialization but don't wait for it
        _initializeVideoController(postUrl);
      }
    }
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

  // -------------------------
  // OPTIMIZED: Skeleton Loading Widgets
  // -------------------------

  Widget _buildOtherProfileSkeleton(_OtherProfileColorSet colors) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildOtherProfileHeaderSkeleton(colors),
            const SizedBox(height: 20),
            _buildOtherBioSectionSkeleton(colors),
            Divider(color: colors.dividerColor),
            _buildOtherPostsGridSkeleton(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherProfileHeaderSkeleton(_OtherProfileColorSet colors) {
    return Column(
      children: [
        // Profile picture skeleton
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.skeletonColor,
          ),
        ),
        const SizedBox(height: 16),
        // Metrics skeleton
        SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildOtherMetricSkeleton(colors),
              _buildOtherMetricSkeleton(colors),
              _buildOtherMetricSkeleton(colors),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Interaction buttons skeleton
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 40,
              decoration: BoxDecoration(
                color: colors.skeletonColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 100,
              height: 40,
              decoration: BoxDecoration(
                color: colors.skeletonColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtherMetricSkeleton(_OtherProfileColorSet colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          height: 16,
          width: 30,
          decoration: BoxDecoration(
            color: colors.skeletonColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 12,
          width: 50,
          decoration: BoxDecoration(
            color: colors.skeletonColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _buildOtherBioSectionSkeleton(_OtherProfileColorSet colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 18,
            width: 120,
            decoration: BoxDecoration(
              color: colors.skeletonColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.skeletonColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 14,
            width: 250,
            decoration: BoxDecoration(
              color: colors.skeletonColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 14,
            width: 200,
            decoration: BoxDecoration(
              color: colors.skeletonColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherPostsGridSkeleton(_OtherProfileColorSet colors) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 5,
        mainAxisSpacing: 1.5,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: colors.skeletonColor,
          ),
        );
      },
    );
  }

  Widget _buildAppBarTitleSkeleton(_OtherProfileColorSet colors) {
    return Container(
      height: 16,
      width: 120,
      decoration: BoxDecoration(
        color: colors.skeletonColor,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  // -------------------------
  // OPTIMIZED: Remaining methods with performance improvements
  // -------------------------

  void _otherHandleFollow() async {
    try {
      final currentUserId = _firebaseAuth.currentUser?.uid;
      if (currentUserId == null) {
        if (mounted) {
          showSnackBar(context, "Please sign in to follow users");
        }
        return;
      }

      final targetUserId = widget.uid;
      final isPrivate = userData['isPrivate'] ?? false;

      if (isFollowing) {
        await SupabaseProfileMethods()
            .unfollowUser(currentUserId, targetUserId);
        if (mounted) {
          setState(() {
            isFollowing = false;
            _isMutualFollow = false;
          });
        }
      } else if (hasPendingRequest) {
        await SupabaseProfileMethods().declineFollowRequest(
          targetUserId,
          currentUserId,
        );
        if (mounted) {
          setState(() {
            hasPendingRequest = false;
          });
        }
      } else {
        await SupabaseProfileMethods().followUser(
          currentUserId,
          targetUserId,
        );
        if (isPrivate) {
          setState(() {
            hasPendingRequest = true;
          });
        } else {
          setState(() {
            isFollowing = true;
          });
          // Check mutual follow in background without blocking UI
          _checkMutualFollowAfterFollow();
        }
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
            context, "Please try again or contact us at ratedly9@gmail.com");
      }
    }
  }

  Future<void> _checkMutualFollowAfterFollow() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

    final otherFollowsCurrent = await _supabase
        .from('user_following')
        .select()
        .eq('user_id', widget.uid)
        .eq('following_id', currentUserId)
        .maybeSingle();

    if (mounted) {
      setState(() {
        _isMutualFollow = otherFollowsCurrent != null;
      });
    }
  }

  void _otherNavigateToMessaging() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) {
      if (mounted) {
        showSnackBar(context, "Please sign in to message users");
      }
      return;
    }

    // Use existing userData instead of fetching again
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MessagingScreen(
            recipientUid: widget.uid,
            recipientUsername: userData['username'] ?? '',
            recipientPhotoUrl: userData['photoUrl'] ?? '',
          ),
        ),
      );
    }
  }

  void _showProfileReportDialog(_OtherProfileColorSet colors) {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) {
      if (mounted) {
        showSnackBar(context, "Please sign in to report profiles");
      }
      return;
    }

    String? selectedReason;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: colors.dialogBackgroundColor,
              title: Text('Report Profile',
                  style: TextStyle(color: colors.dialogTextColor)),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thank you for helping keep our community safe.\n\nPlease let us know the reason for reporting this content. Your report is anonymous, and our moderators will review it as soon as possible. \n\n If you prefer not to see this user posts or content, you can choose to block them.',
                      style: TextStyle(
                          color: colors.dialogTextColor, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Select a reason:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colors.dialogTextColor),
                    ),
                    ...profileReportReasons.map((reason) {
                      return RadioListTile<String>(
                        title: Text(reason,
                            style: TextStyle(color: colors.dialogTextColor)),
                        value: reason,
                        groupValue: selectedReason,
                        activeColor: colors.radioActiveColor,
                        onChanged: (value) {
                          setState(() => selectedReason = value);
                        },
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(color: colors.dialogTextColor)),
                ),
                TextButton(
                  onPressed: selectedReason != null
                      ? () => _submitProfileReport(selectedReason!)
                      : null,
                  child: Text('Submit',
                      style: TextStyle(color: colors.dialogTextColor)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitProfileReport(String reason) async {
    try {
      await _supabase.from('reports').insert({
        'user_id': widget.uid,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
        'type': 'profile',
      });

      if (mounted) {
        Navigator.pop(context);
        showSnackBar(context, 'Report submitted. Thank you!');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
            context, 'Please try again or contact us at ratedly9@gmail.com');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final currentUserId = _firebaseAuth.currentUser?.uid;
    final isCurrentUser = currentUserId == widget.uid;
    final isAuthenticated = currentUserId != null;

    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: colors.appBarBackgroundColor,
          elevation: 0,
          leading: BackButton(color: colors.appBarIconColor),
          title: _buildAppBarTitleSkeleton(colors),
          centerTitle: true,
        ),
        backgroundColor: colors.backgroundColor,
        body: _buildOtherProfileSkeleton(colors),
      );
    }

    return Scaffold(
      appBar: AppBar(
          iconTheme: IconThemeData(color: colors.appBarIconColor),
          backgroundColor: colors.appBarBackgroundColor,
          elevation: 0,
          title: Text(
            userData['username'] ?? 'User',
            style:
                TextStyle(color: colors.textColor, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          leading: BackButton(color: colors.appBarIconColor),
          actions: [
            if (isAuthenticated)
              PopupMenuButton(
                icon: Icon(Icons.more_vert, color: colors.appBarIconColor),
                onSelected: (value) async {
                  if (value == 'block') {
                    try {
                      setState(() => isLoading = true);
                      final currentUserId = _firebaseAuth.currentUser?.uid;
                      if (currentUserId == null) return;

                      await SupabaseBlockMethods().blockUser(
                        currentUserId: currentUserId,
                        targetUserId: widget.uid,
                      );

                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BlockedProfileScreen(
                              uid: widget.uid,
                              isBlocker: true,
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        showSnackBar(context,
                            "Please try again or contact us at ratedly9@gmail.com");
                      }
                    } finally {
                      if (mounted) setState(() => isLoading = false);
                    }
                  } else if (value == 'remove_follower') {
                    final currentUserId = _firebaseAuth.currentUser?.uid;
                    if (currentUserId == null) return;

                    try {
                      await SupabaseProfileMethods()
                          .removeFollower(currentUserId, widget.uid);
                      if (mounted) {
                        setState(() {
                          _isViewerFollower = false;
                          followers = followers - 1;
                        });
                        showSnackBar(context, "Follower removed successfully");
                      }
                    } catch (e) {
                      if (mounted) {
                        showSnackBar(context,
                            "Please try again or contact us at ratedly9@gmail.com");
                      }
                    }
                  } else if (value == 'report') {
                    _showProfileReportDialog(colors);
                  }
                },
                itemBuilder: (context) => [
                  if (_isViewerFollower)
                    PopupMenuItem(
                      value: 'remove_follower',
                      child: Text('Remove Follower',
                          style: TextStyle(color: colors.textColor)),
                    ),
                  if (!isCurrentUser)
                    PopupMenuItem(
                      value: 'report',
                      child: Text('Report Profile',
                          style: TextStyle(color: colors.textColor)),
                    ),
                  PopupMenuItem(
                    value: 'block',
                    child: Text('Block User',
                        style: TextStyle(color: colors.textColor)),
                  ),
                ],
              )
          ]),
      backgroundColor: colors.backgroundColor,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildOtherProfileHeader(colors),
              const SizedBox(height: 20),
              _buildOtherBioSection(colors),
              Divider(color: colors.dividerColor),
              _buildOtherPostsGrid(colors)
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtherProfileHeader(_OtherProfileColorSet colors) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: colors.avatarBackgroundColor,
          radius: 45,
          backgroundImage: (userData['photoUrl'] != null &&
                  userData['photoUrl'].isNotEmpty &&
                  userData['photoUrl'] != "default")
              ? NetworkImage(userData['photoUrl'])
              : null,
          child: (userData['photoUrl'] == null ||
                  userData['photoUrl'].isEmpty ||
                  userData['photoUrl'] == "default")
              ? Icon(
                  Icons.account_circle,
                  size: 90,
                  color: colors.iconColor,
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildOtherMetric(postLen, "Posts", colors),
                        _buildOtherInteractiveMetric(
                            followers, "Followers", _followersList, colors),
                        _buildOtherMetric(following, "Following", colors),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildOtherInteractionButtons(colors),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOtherInteractiveMetric(int value, String label,
      List<dynamic> userList, _OtherProfileColorSet colors) {
    List<dynamic> validEntries = userList.where((entry) {
      return entry['userId'] != null && entry['userId'].toString().isNotEmpty;
    }).toList();

    return GestureDetector(
      onTap: validEntries.isEmpty
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserListScreen(
                    title: label,
                    userEntries: validEntries,
                  ),
                ),
              ),
      child: _buildOtherMetric(validEntries.length, label, colors),
    );
  }

  Widget _buildOtherInteractionButtons(_OtherProfileColorSet colors) {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    final bool isCurrentUser = currentUserId == widget.uid;
    final bool isPrivateAccount = userData['isPrivate'] ?? false;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isCurrentUser) _buildFollowButton(isPrivateAccount, colors),
            const SizedBox(width: 5),
            if (!isCurrentUser)
              ElevatedButton(
                onPressed: _otherNavigateToMessaging,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.buttonBackgroundColor,
                  foregroundColor: colors.buttonTextColor,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  minimumSize: const Size(100, 40),
                ),
                child: Text("Message",
                    style: TextStyle(color: colors.buttonTextColor)),
              ),
          ],
        ),
        const SizedBox(height: 5),
      ],
    );
  }

  Widget _buildFollowButton(
      bool isPrivateAccount, _OtherProfileColorSet colors) {
    final isPending = hasPendingRequest && isPrivateAccount;

    return ElevatedButton(
        onPressed: _otherHandleFollow,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.buttonBackgroundColor,
          foregroundColor: colors.buttonTextColor,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          side: BorderSide(
            color: colors.buttonBackgroundColor,
          ),
          minimumSize: const Size(100, 40),
        ),
        child: Text(
          isFollowing
              ? 'Unfollow'
              : isPending
                  ? 'Requested'
                  : 'Follow',
          style: TextStyle(
              fontWeight: FontWeight.w600, color: colors.buttonTextColor),
        ));
  }

  Widget _buildOtherMetric(
      int value, String label, _OtherProfileColorSet colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 13.6,
            fontWeight: FontWeight.bold,
            color: colors.textColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: colors.textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildOtherBioSection(_OtherProfileColorSet colors) {
    final String bio = userData['bio'] ?? '';

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            userData['username'] ?? '',
            style: TextStyle(
                color: colors.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
          const SizedBox(height: 4),
          if (bio.isNotEmpty)
            ExpandableBioText(
              text: bio,
              style: TextStyle(color: colors.textColor),
              expandColor: colors.textColor.withOpacity(0.8),
            ),
        ],
      ),
    );
  }

  Widget _buildPrivateAccountMessage(_OtherProfileColorSet colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock, size: 60, color: colors.errorTextColor),
        const SizedBox(height: 20),
        Text('This Account is Private',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textColor)),
        const SizedBox(height: 10),
        Text('Follow to see their posts',
            style: TextStyle(fontSize: 14, color: colors.textColor)),
      ],
    );
  }

  Widget _buildOtherPostsGrid(_OtherProfileColorSet colors) {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    final bool isCurrentUser = currentUserId == widget.uid;
    final bool isPrivate = userData['isPrivate'] ?? false;
    final bool shouldHidePosts = isPrivate && !isFollowing && !isCurrentUser;
    final bool isMutuallyBlocked = _isBlockedByMe || _isBlockedByThem;

    if (isMutuallyBlocked) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 50, color: Colors.red),
            const SizedBox(height: 10),
            Text('Posts unavailable due to blocking',
                style: TextStyle(color: colors.errorTextColor)),
          ],
        ),
      );
    }

    if (shouldHidePosts) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.3,
        child: _buildPrivateAccountMessage(colors),
      );
    }

    // Use pre-loaded posts instead of FutureBuilder
    if (_posts.isEmpty) {
      return SizedBox(
          height: 200,
          child: Center(
            child: Text(
              'This user has no posts.',
              style: TextStyle(
                fontSize: 16,
                color: colors.errorTextColor,
              ),
            ),
          ));
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _posts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 5,
        mainAxisSpacing: 1.5,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final post = _posts[index];
        return _buildOtherPostItem(post, colors);
      },
    );
  }

  Widget _buildOtherPostItem(
      Map<String, dynamic> post, _OtherProfileColorSet colors) {
    final postUrl = post['postUrl'] ?? '';
    final isVideo = _isVideoFile(postUrl);

    return FutureBuilder<bool>(
      future: SupabaseBlockMethods().isMutuallyBlocked(
        _firebaseAuth.currentUser?.uid ?? '',
        post['uid'] ?? '',
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!) {
          return Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: colors.avatarBackgroundColor,
            ),
            child: const Center(
              child: Icon(
                Icons.block,
                color: Colors.red,
                size: 30,
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ImageViewScreen(
                imageUrl: postUrl,
                postId: post['postId'] ?? '',
                description: post['description'] ?? '',
                userId: post['uid'] ?? '',
                username: userData['username'] ?? '',
                profImage: userData['photoUrl'] ?? '',
                datePublished: post['datePublished'],
              ),
            ),
          ),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isVideo ? colors.avatarBackgroundColor : null,
            ),
            child: isVideo
                ? _buildVideoPlayer(postUrl, colors)
                : _buildImageThumbnail(postUrl, colors),
          ),
        );
      },
    );
  }

  Widget _buildVideoPlayer(String videoUrl, _OtherProfileColorSet colors) {
    if (!_videoControllers.containsKey(videoUrl)) {
      _initializeVideoController(videoUrl);
    }

    final controller = _getVideoController(videoUrl);
    final isInitialized = _isVideoControllerInitialized(videoUrl);

    if (!isInitialized || controller == null) {
      return _buildVideoLoading(colors);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _buildVideoLoading(_OtherProfileColorSet colors) {
    return Container(
      color: colors.avatarBackgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: colors.progressIndicatorColor,
              strokeWidth: 2,
            ),
            const SizedBox(height: 8),
            Text(
              'Loading...',
              style: TextStyle(
                color: colors.textColor,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(String imageUrl, _OtherProfileColorSet colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: colors.avatarBackgroundColor,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        (loadingProgress.expectedTotalBytes ?? 1)
                    : null,
                color: colors.progressIndicatorColor,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: colors.avatarBackgroundColor,
            child: Center(
              child: Icon(
                Icons.broken_image,
                color: colors.errorTextColor,
                size: 30,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    _videoControllers.clear();
    _videoControllersInitialized.clear();
    super.dispose();
  }
}
