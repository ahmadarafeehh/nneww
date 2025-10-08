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
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:Ratedly/services/ads.dart';
import 'package:Ratedly/utils/theme_provider.dart'; // Add this import
import 'package:provider/provider.dart'; // Add this import

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
  final Color adBackgroundColor;
  final Color adDividerColor;

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
    required this.adBackgroundColor,
    required this.adDividerColor,
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
    adBackgroundColor: const Color(0xFF121212),
    adDividerColor: const Color(0xFF333333),
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
    adBackgroundColor: Colors.white,
    adDividerColor: Colors.grey[300]!,
  );
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

  // Ad-related variables
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  final List<String> profileReportReasons = [
    'Impersonation (Pretending to be someone else)',
    'Fake Account (Misleading or suspicious profile)',
    'Bullying or Harassment',
    'Hate Speech or Discrimination (e.g., race, religion, gender, sexual orientation)',
    'Scam or Fraud (Deceptive activity, phishing, or financial fraud)',
    'Spam (Unwanted promotions or repetitive content)',
    'Inappropriate Content (Explicit, offensive, or disturbing profile)',
  ];

  // Helper method to get the appropriate color scheme
  _OtherProfileColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _OtherProfileDarkColors() : _OtherProfileLightColors();
  }

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadData();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    BannerAd(
      adUnitId: AdHelper.otherProfileBannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _bannerAd = ad as BannerAd;
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          print('Failed to load a banner ad: ${err.message}');
          ad.dispose();
        },
      ),
    ).load();
  }

  Future<void> _checkAuthAndLoadData() async {
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser == null) {
      await _loadPublicData();
      return;
    }

    await _checkBlockStatus();
    if (!_isBlocked && mounted) {
      await _otherGetData();
    }
  }

  Future<void> _loadPublicData() async {
    if (!mounted) return;

    try {
      final userResponse =
      await _supabase.from('users').select().eq('uid', widget.uid).single();

      if (userResponse.isEmpty) {
        if (mounted) showSnackBar(context, "User profile not found");
        return;
      }

      final List<Future<dynamic>> queries = [
        _supabase.from('posts').select('postId').eq('uid', widget.uid),
        _supabase
            .from('user_followers')
            .select('follower_id, followed_at')
            .eq('user_id', widget.uid),
        _supabase
            .from('user_following')
            .select('following_id, followed_at')
            .eq('user_id', widget.uid),
      ];

      final results = await Future.wait(queries);

      final postsResponse = results[0] as List;
      final followersResponse = results[1] as List;
      final followingResponse = results[2] as List;

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
          userData = userResponse;
          postLen = postsResponse.length;
          followers = followersResponse.length;
          following = followingResponse.length;
          _followersList = processedFollowers;
          hasPendingRequest = false;
          isFollowing = false;
          _isMutualFollow = false;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
            context, "Please try again or contact us at ratedly9@gmail.com");
      }
    }
  }

  Future<void> _checkBlockStatus() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

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
  }

  Future<void> _otherGetData() async {
    if (!mounted) return;

    try {
      final currentUserId = _firebaseAuth.currentUser?.uid;

      final userResponse =
      await _supabase.from('users').select().eq('uid', widget.uid).single();

      final List<Future<dynamic>> queries = [
        _supabase.from('posts').select('postId').eq('uid', widget.uid),
        _supabase
            .from('user_followers')
            .select('follower_id, followed_at')
            .eq('user_id', widget.uid),
        _supabase
            .from('user_following')
            .select('following_id, followed_at')
            .eq('user_id', widget.uid),
      ];

      if (currentUserId != null) {
        queries.addAll([
          _supabase
              .from('user_following')
              .select()
              .eq('user_id', currentUserId)
              .eq('following_id', widget.uid)
              .maybeSingle(),
          _supabase
              .from('user_follow_request')
              .select()
              .eq('user_id', widget.uid)
              .eq('requester_id', currentUserId)
              .maybeSingle(),
        ]);
      }

      final results = await Future.wait(queries);

      final postsResponse = results[0] as List;
      final followersResponse = results[1] as List;
      final followingResponse = results[2] as List;

      dynamic isFollowingResponse;
      dynamic followRequestResponse;

      if (currentUserId != null) {
        isFollowingResponse = results.length > 3 ? results[3] : null;
        followRequestResponse = results.length > 4 ? results[4] : null;
      }

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

      bool isMutualFollow = false;
      if (currentUserId != null) {
        final otherFollowsCurrent = await _supabase
            .from('user_following')
            .select()
            .eq('user_id', widget.uid)
            .eq('following_id', currentUserId)
            .maybeSingle();

        isMutualFollow =
            isFollowingResponse != null && otherFollowsCurrent != null;
      }

      if (mounted) {
        setState(() {
          userData = userResponse;
          postLen = postsResponse.length;
          followers = followersResponse.length;
          following = followingResponse.length;
          _followersList = processedFollowers;
          _isMutualFollow = isMutualFollow;

          if (currentUserId != null) {
            hasPendingRequest = followRequestResponse != null;
            isFollowing = isFollowingResponse != null;
          }
          isLoading = false;
        });
      }

      if (currentUserId != null) {
        await _checkIfViewerIsFollower();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
            context, "Please try again or contact us at ratedly9@gmail.com");
      }
    }
  }

  Future<void> _checkIfViewerIsFollower() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

    final followersResponse = await _supabase
        .from('user_followers')
        .select()
        .eq('user_id', currentUserId)
        .eq('follower_id', widget.uid)
        .maybeSingle();

    if (mounted) {
      setState(() {
        _isViewerFollower = followersResponse != null;
      });
    }
  }

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
            _checkMutualFollowAfterFollow();
          });
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

    final userResponse = await _supabase
        .from('users')
        .select('username, photoUrl')
        .eq('uid', widget.uid)
        .single();

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MessagingScreen(
            recipientUid: widget.uid,
            recipientUsername: userResponse['username'] ?? '',
            recipientPhotoUrl: userResponse['photoUrl'] ?? '',
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
        ),
        backgroundColor: colors.backgroundColor,
        body: Center(
          child:
          CircularProgressIndicator(color: colors.progressIndicatorColor),
        ),
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
                      if (currentUserId == null) {
                        return;
                      }

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
      body: Column(
        children: [
          // Banner Ad at the top
          if (_isAdLoaded && _bannerAd != null)
            Container(
              width: double.infinity,
              color: colors.adBackgroundColor,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(height: 1, color: colors.adDividerColor),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 50,
                    child: AdWidget(ad: _bannerAd!),
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: colors.adDividerColor),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
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
          ),
        ],
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
          Text(userData['bio'] ?? '',
              style: TextStyle(color: colors.textColor)),
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

    return FutureBuilder<List<dynamic>>(
      future: _supabase
          .from('posts')
          .select()
          .eq('uid', widget.uid)
          .order('datePublished', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                  color: colors.progressIndicatorColor));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Failed to load posts',
                  style: TextStyle(color: colors.textColor)));
        }
        final posts = snapshot.data ?? [];

        if (posts.isEmpty) {
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
          itemCount: posts.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 5,
            mainAxisSpacing: 1.5,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final post = posts[index];
            return _buildOtherPostItem(post, colors);
          },
        );
      },
    );
  }

  Widget _buildOtherPostItem(
      Map<String, dynamic> post, _OtherProfileColorSet colors) {
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
                imageUrl: post['postUrl'] ?? '',
                postId: post['postId'] ?? '',
                description: post['description'] ?? '',
                userId: post['uid'] ?? '',
                username: userData['username'] ?? '',
                profImage: userData['photoUrl'] ?? '',
                datePublished: post['datePublished'], // ✅ FIXED - pass actual date
              ),
            ),
          ),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(
                image: NetworkImage(post['postUrl'] ?? ''),
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }
}
