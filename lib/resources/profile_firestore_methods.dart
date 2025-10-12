import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:Ratedly/resources/storage_methods.dart';
import 'package:Ratedly/services/notification_service.dart';

class SupabaseProfileMethods {
  final SupabaseClient _supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();

  // Helper to normalise different client return shapes
  dynamic _unwrap(dynamic res) {
    try {
      if (res == null) return null;
      // PostgrestResponse-like map
      if (res is Map && res.containsKey('data')) return res['data'];
    } catch (_) {}
    return res;
  }

  // Helper method to check if URL is from Supabase Storage (video)
  bool _isVideoUrl(String url) {
    return url.contains('supabase.co/storage/v1/object/public/videos') ||
        url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.avi') ||
        url.endsWith('.mkv');
  }

  // Helper method to delete video from Supabase Storage using URL
  Future<void> _deleteVideoFromUrl(String videoUrl) async {
    try {
      // Extract the file path from the Supabase storage URL
      // URL format: https://project-ref.supabase.co/storage/v1/object/public/videos/user-uid/filename.mp4
      final uri = Uri.parse(videoUrl);
      final pathSegments = uri.pathSegments;

      // Find the index of 'videos' in the path
      final videosIndex = pathSegments.indexOf('videos');
      if (videosIndex != -1 && videosIndex < pathSegments.length - 1) {
        // The path after 'videos' is the file path (user-uid/filename.mp4)
        final filePath = pathSegments.sublist(videosIndex + 1).join('/');
        await StorageMethods().deleteVideoFromSupabase('videos', filePath);
      } else {
        // Fallback: try to extract filename from URL
        final fileName = videoUrl.split('/').last;
        await StorageMethods().deleteVideoFromSupabase('videos', fileName);
      }
    } catch (e) {
      rethrow;
    }
  }

  // NEW: Method to delete all user posts (both images and videos)
  Future<void> _deleteAllUserPosts(String uid) async {
    try {
      // Get all user posts with their URLs
      final postsResponse = await _supabase
          .from('posts')
          .select('postId, postUrl')
          .eq('uid', uid);

      final posts = _unwrap(postsResponse) ?? postsResponse;

      if (posts is List && posts.isNotEmpty) {
        for (final post in posts) {
          final postUrl = post['postUrl']?.toString() ?? '';
          final postId = post['postId']?.toString() ?? '';

          if (postUrl.isNotEmpty) {
            // Check if it's a video (Supabase storage) or image (Firebase storage)
            if (_isVideoUrl(postUrl)) {
              // It's a video - delete from Supabase Storage
              await _deleteVideoFromUrl(postUrl);
            } else {
              // It's an image - delete from Firebase Storage
              await StorageMethods().deleteImage(postUrl);
            }
          }

          // Delete post views
          await _supabase.from('post_views').delete().eq('postid', postId);

          // Delete related comments/replies/ratings/notifications for this post
          await _supabase.from('comments').delete().eq('postid', postId);
          await _supabase.from('replies').delete().eq('postid', postId);
          await _supabase.from('post_rating').delete().eq('postid', postId);
          await _supabase
              .from('notifications')
              .delete()
              .eq('custom_data->>postId', postId);
        }
      }

      // Finally, delete all user posts from the database
      await _supabase.from('posts').delete().eq('uid', uid);
    } catch (e) {
      rethrow;
    }
  }

  // Helper method to record push notifications (still using Firebase)
  Future<void> _recordPushNotification({
    required String type,
    required String targetUserId,
    required String title,
    required String body,
    required Map<String, dynamic> customData,
  }) async {
    try {
      // This still uses Firebase for push notifications
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      await firestore.collection('Push Not').add({
        'type': type,
        'targetUserId': targetUserId,
        'title': title,
        'body': body,
        'customData': customData,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {}
    }
  }

  // private or public account
  Future<void> toggleAccountPrivacy(String uid, bool isPrivate) async {
    await _supabase
        .from('users')
        .update({'isPrivate': isPrivate}).eq('uid', uid);
  }

  Future<void> approveAllFollowRequests(String userId) async {
    try {
      // Get all follow requests for this user
      final response = await _supabase
          .from('user_follow_request')
          .select('requester_id, requested_at')
          .eq('user_id', userId);

      final List<dynamic> requests = _unwrap(response) ?? response;

      if (requests.isEmpty) return;

      for (final request in requests) {
        try {
          final requesterId = request['requester_id'] as String;

          // Add to followers/following
          await _supabase.from('user_followers').upsert({
            'user_id': userId,
            'follower_id': requesterId,
            'followed_at': DateTime.now().toUtc().toIso8601String(),
          });

          await _supabase.from('user_following').upsert({
            'user_id': requesterId,
            'following_id': userId,
            'followed_at': DateTime.now().toUtc().toIso8601String(),
          });

          // Get user data for push notification
          final userResponse = await _supabase
              .from('users')
              .select('username')
              .eq('uid', userId)
              .maybeSingle();

          final userData = _unwrap(userResponse) ?? userResponse;
          final String username = userData?['username'] ?? 'Someone';

          // CRITICAL FIX: Delete the old follow_request notification
          await _supabase
              .from('notifications')
              .delete()
              .eq('target_user_id', userId)
              .eq('type', 'follow_request')
              .eq('custom_data->>requesterId', requesterId);

          // Create new follow notification instead of follow_request_accepted
          await _supabase.from('notifications').insert({
            'target_user_id':
                userId, // The user who switched to public sees who followed them
            'type': 'follow',
            'custom_data': {'followerId': requesterId},
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });

          // Send push notification as "started following you"
          await _recordPushNotification(
            type: 'follow',
            targetUserId: userId,
            title: 'New Follower',
            body: '$username started following you',
            customData: {'followerId': requesterId},
          );

          _notificationService.triggerServerNotification(
            type: 'follow',
            targetUserId: userId,
            title: 'New Follower',
            body: '$username started following you',
            customData: {'followerId': requesterId},
          );
        } catch (e) {
          // Continue with other requests even if one fails
          if (kDebugMode) {
            print('Error processing follow request: $e');
          }
        }
      }

      // Delete all follow requests for this user
      await _supabase
          .from('user_follow_request')
          .delete()
          .eq('user_id', userId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> removeFollower(String currentUserId, String followerId) async {
    try {
      // Remove from followers
      await _supabase
          .from('user_followers')
          .delete()
          .eq('user_id', currentUserId)
          .eq('follower_id', followerId);

      // Remove from following
      await _supabase
          .from('user_following')
          .delete()
          .eq('user_id', followerId)
          .eq('following_id', currentUserId);

      // Remove any follow requests
      await _supabase
          .from('user_follow_request')
          .delete()
          .eq('user_id', currentUserId)
          .eq('requester_id', followerId);

      await _supabase
          .from('user_follow_request')
          .delete()
          .eq('user_id', followerId)
          .eq('requester_id', currentUserId);

      // Delete any related notifications
      await _supabase
          .from('notifications')
          .delete()
          .eq('target_user_id', followerId)
          .eq('type', 'follow_request_accepted')
          .eq('custom_data->>approverId', currentUserId);
    } catch (e) {
      rethrow;
    }
  }

  // Record a profile view
  Future<void> recordProfileView(
      String profileOwnerUid, String viewerUid) async {
    try {
      if (profileOwnerUid == viewerUid) return; // Don't record self-views

      await _supabase.from('user_profile_views').upsert({
        'user_id': viewerUid,
        'profileowneruid': profileOwnerUid,
        'viewed_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {}
  }

// Get profile view count
  Future<int> getProfileViewCount(String profileOwnerUid) async {
    try {
      final response = await _supabase
          .from('user_profile_views')
          .select()
          .eq('profileowneruid', profileOwnerUid);

      return response.length;
    } catch (e) {
      return 0;
    }
  }

// Get profile viewers with user info
  Future<List<Map<String, dynamic>>> getProfileViewers(
      String profileOwnerUid) async {
    try {
      final response = await _supabase
          .from('user_profile_views')
          .select('''
          user_id, 
          viewed_at,
          users:user_id (username, photoUrl)
        ''')
          .eq('profileowneruid', profileOwnerUid)
          .order('viewed_at', ascending: false);

      // Process the response to get a list of viewers with their info
      List<Map<String, dynamic>> viewers = [];
      for (var item in response) {
        viewers.add({
          'user_id': item['user_id'],
          'viewed_at': item['viewed_at'],
          'username': item['users']['username'],
          'photoUrl': item['users']['photoUrl'],
        });
      }
      return viewers;
    } catch (e) {
      return [];
    }
  }

  Future<void> unfollowUser(String uid, String unfollowId) async {
    try {
      // Remove from following
      await _supabase
          .from('user_following')
          .delete()
          .eq('user_id', uid)
          .eq('following_id', unfollowId);

      // Remove from followers
      await _supabase
          .from('user_followers')
          .delete()
          .eq('user_id', unfollowId)
          .eq('follower_id', uid);

      // Remove any follow requests
      await _supabase
          .from('user_follow_request')
          .delete()
          .eq('user_id', unfollowId)
          .eq('requester_id', uid);

      // Delete follow notifications
      await _supabase
          .from('notifications')
          .delete()
          .eq('target_user_id', unfollowId)
          .eq('type', 'follow')
          .eq('custom_data->>followerId', uid);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> followUser(String uid, String followId) async {
    try {
      // First check if already following in the user_following table
      final existingFollowing = await _supabase
          .from('user_following')
          .select()
          .eq('user_id', uid)
          .eq('following_id', followId)
          .maybeSingle();

      // If already following, unfollow instead
      if (existingFollowing != null) {
        await unfollowUser(uid, followId);
        return;
      }

      // Check if target user is private
      final targetSel = await _supabase
          .from('users')
          .select('isPrivate')
          .eq('uid', followId)
          .maybeSingle();
      final targetUser = _unwrap(targetSel) ?? targetSel;

      final isPrivate = targetUser?['isPrivate'] ?? false;
      final timestamp = DateTime.now();

      if (isPrivate) {
        // Check if follow request already exists
        final existingRequest = await _supabase
            .from('user_follow_request')
            .select()
            .eq('user_id', followId)
            .eq('requester_id', uid)
            .maybeSingle();

        if (existingRequest != null) {
          return; // Request already exists
        }

        // Send follow request for private account using insert
        final followRequestResult =
            await _supabase.from('user_follow_request').insert({
          'user_id': followId,
          'requester_id': uid,
          'requested_at': timestamp.toIso8601String(),
        });

        // Get requester info for push notification
        final requesterSel = await _supabase
            .from('users')
            .select('username')
            .eq('uid', uid)
            .maybeSingle();
        final requesterData = _unwrap(requesterSel) ?? requesterSel;
        final String requesterUsername =
            requesterData?['username'] ?? 'Someone';

        // Send push notification
        _notificationService.triggerServerNotification(
          type: 'follow_request',
          targetUserId: followId,
          title: 'New Follow Request',
          body: '$requesterUsername wants to follow you',
          customData: {'requesterId': uid},
        );

        // Record push notification
        await _recordPushNotification(
          type: 'follow_request',
          targetUserId: followId,
          title: 'New Follow Request',
          body: '$requesterUsername wants to follow you',
          customData: {'requesterId': uid},
        );

        // Create in-app notification (store only UID)
        await _createFollowRequestNotification(uid, followId);
      } else {
        // Public account - follow directly using insert
        final followersResult = await _supabase.from('user_followers').insert({
          'user_id': followId,
          'follower_id': uid,
          'followed_at': timestamp.toIso8601String(),
        });

        final followingResult = await _supabase.from('user_following').insert({
          'user_id': uid,
          'following_id': followId,
          'followed_at': timestamp.toIso8601String(),
        });

        // Get follower info for push notification
        final followerSel = await _supabase
            .from('users')
            .select('username')
            .eq('uid', uid)
            .maybeSingle();
        final followerData = _unwrap(followerSel) ?? followerSel;
        final String followerUsername = followerData?['username'] ?? 'Someone';

        // Send push notification
        _notificationService.triggerServerNotification(
          type: 'follow',
          targetUserId: followId,
          title: 'New Follower',
          body: '$followerUsername started following you',
          customData: {'followerId': uid},
        );

        // Record push notification
        await _recordPushNotification(
          type: 'follow',
          targetUserId: followId,
          title: 'New Follower',
          body: '$followerUsername started following you',
          customData: {'followerId': uid},
        );

        // Create in-app notification (store only UID)
        await createFollowNotification(uid, followId);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _createFollowRequestNotification(
      String requesterUid, String targetUid) async {
    await _supabase.from('notifications').insert({
      'target_user_id': targetUid,
      'type': 'follow_request',
      'custom_data': {
        'requesterId': requesterUid,
      },
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> acceptFollowRequest(
      String targetUid, String requesterUid) async {
    try {
      // Remove the follow request
      await _supabase
          .from('user_follow_request')
          .delete()
          .eq('user_id', targetUid)
          .eq('requester_id', requesterUid);

      // Delete the follow request notification
      await _supabase
          .from('notifications')
          .delete()
          .eq('target_user_id', targetUid)
          .eq('type', 'follow_request')
          .eq('custom_data->>requesterId', requesterUid);

      // Add to followers/following
      final timestamp = DateTime.now();
      await _supabase.from('user_followers').upsert({
        'user_id': targetUid,
        'follower_id': requesterUid,
        'followed_at': timestamp.toIso8601String(),
      });

      await _supabase.from('user_following').upsert({
        'user_id': requesterUid,
        'following_id': targetUid,
        'followed_at': timestamp.toIso8601String(),
      });

      // Get user info for push notification
      final targetSel = await _supabase
          .from('users')
          .select('username')
          .eq('uid', targetUid)
          .maybeSingle();
      final targetUserData = _unwrap(targetSel) ?? targetSel;
      final String username = targetUserData?['username'] ?? 'Someone';

      // Create notification (store only UID)
      await _supabase.from('notifications').insert({
        'target_user_id': requesterUid,
        'type': 'follow_request_accepted',
        'custom_data': {
          'approverId': targetUid,
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Send push notification
      _notificationService.triggerServerNotification(
        type: 'follow_request_accepted',
        targetUserId: requesterUid,
        title: 'Follow Request Approved',
        body: '$username approved your follow request',
        customData: {'approverId': targetUid},
      );

      // Record push notification
      await _recordPushNotification(
        type: 'follow_request_accepted',
        targetUserId: requesterUid,
        title: 'Follow Request Approved',
        body: '$username approved your follow request',
        customData: {'approverId': targetUid},
      );

      // Create follow notification (store only UID)
      await createFollowNotification(requesterUid, targetUid);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> declineFollowRequest(
      String targetUid, String requesterUid) async {
    try {
      // Remove the follow request
      await _supabase
          .from('user_follow_request')
          .delete()
          .eq('user_id', targetUid)
          .eq('requester_id', requesterUid);

      // Delete the follow request notification
      await _supabase
          .from('notifications')
          .delete()
          .eq('target_user_id', targetUid)
          .eq('type', 'follow_request')
          .eq('custom_data->>requesterId', requesterUid);

      // Remove any following relationship that might exist
      await _supabase
          .from('user_following')
          .delete()
          .eq('user_id', requesterUid)
          .eq('following_id', targetUid);
    } catch (e) {
      rethrow;
    }
  }

  Future<String> reportProfile(String userId, String reason) async {
    String res = "Some error occurred";
    try {
      await _supabase.from('reports').insert({
        'user_id': userId,
        'reason': reason,
        'type': 'profile',
        'created_at': DateTime.now().toIso8601String(),
      });
      res = 'success';
    } catch (err) {
      res = err.toString();
    }
    return res;
  }

  Future<bool> hasPendingRequest(String requesterUid, String targetUid) async {
    try {
      final requests = await _supabase
          .from('user_follow_request')
          .select()
          .eq('user_id', targetUid)
          .eq('requester_id', requesterUid);

      final data = _unwrap(requests) ?? requests;
      return data.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> createFollowNotification(
    String followerUid,
    String followedUid,
  ) async {
    await _supabase.from('notifications').insert({
      'target_user_id': followedUid,
      'type': 'follow',
      'custom_data': {
        'followerId': followerUid,
      },
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _deleteUserActorNotifications(String uid) async {
    try {
      // Delete notifications where user was the actor (based on custom_data fields)
      // Use proper JSONB query syntax for each field
      await _supabase.from('notifications').delete().or(
          'custom_data->>raterUid.eq.${uid},' +
              'custom_data->>followerId.eq.${uid},' +
              'custom_data->>commenterUid.eq.${uid},' +
              'custom_data->>likerUid.eq.${uid},' +
              'custom_data->>requesterId.eq.${uid},' +
              'custom_data->>approverId.eq.${uid},' +
              'custom_data->>replierUid.eq.${uid}');
    } catch (e) {
      // Log error but don't fail the entire deletion process
      if (kDebugMode) {
        print('Error deleting actor notifications: $e');
      }
    }
  }

  Future<void> _deleteUserPostViews(String uid) async {
    try {
      // Delete records where user is the viewer
      await _supabase.from('user_post_views').delete().eq('user_id', uid);

      // Get all post IDs for the user first, then delete views for those posts
      final postsResponse =
          await _supabase.from('posts').select('postId').eq('uid', uid);

      final posts = _unwrap(postsResponse) ?? postsResponse;

      if (posts is List && posts.isNotEmpty) {
        final postIds =
            posts.map<String>((post) => post['postId'] as String).toList();

        // Use a loop instead of in_ method
        for (final postId in postIds) {
          await _supabase
              .from('user_post_views')
              .delete()
              .eq('post_id', postId);
        }
      }
    } catch (e) {
      // Log error but don't fail the entire deletion process
      if (kDebugMode) {
        print('Error deleting user post views: $e');
      }
    }
  }

  Future<String> deleteEntireUserAccount(
      String uid, firebase_auth.AuthCredential? credential) async {
    String res = "Some error occurred";
    String? profilePicUrl;

    try {
      firebase_auth.User? currentUser =
          firebase_auth.FirebaseAuth.instance.currentUser;
      if (currentUser == null || currentUser.uid != uid) {
        throw Exception("User not authenticated or UID mismatch");
      }

      // Only reauthenticate if credential is provided (non-Apple)
      if (credential != null) {
        await currentUser.reauthenticateWithCredential(credential);
      }

      // Get user data
      final userSel =
          await _supabase.from('users').select().eq('uid', uid).maybeSingle();
      final userData = _unwrap(userSel) ?? userSel;

      profilePicUrl = userData?['photoUrl'] as String?;

      // NEW: Delete all user posts (both images and videos) and their associated data
      await _deleteAllUserPosts(uid);

      // Clean up followers/following relationships
      // Get followers
      final followers = await _supabase
          .from('user_followers')
          .select('follower_id, followed_at')
          .eq('user_id', uid);

      final followersData = _unwrap(followers) ?? followers;

      // Clean up followers' following lists
      for (var follower in followersData) {
        await _supabase
            .from('user_following')
            .delete()
            .eq('user_id', follower['follower_id'])
            .eq('following_id', uid);
      }

      // Get following
      final following = await _supabase
          .from('user_following')
          .select('following_id, followed_at')
          .eq('user_id', uid);

      final followingData = _unwrap(following) ?? following;

      // Clean up following's followers lists
      for (var followed in followingData) {
        await _supabase
            .from('user_followers')
            .delete()
            .eq('user_id', followed['following_id'])
            .eq('follower_id', uid);
      }

      // Delete user's comments
      await _supabase.from('comments').delete().eq('uid', uid);

      // Remove user's ratings from all posts
      await _supabase.from('post_rating').delete().eq('userid', uid);

      // Delete user's messages and chats
      final chatsResponse = await _supabase
          .from('chats')
          .select('id')
          .contains('participants', [uid]);

      if (chatsResponse.isNotEmpty) {
        final chatIds =
            chatsResponse.map((chat) => chat['id'] as String).toList();

        // Delete all messages in these chats using OR condition
        for (final chatId in chatIds) {
          await _supabase.from('messages').delete().eq('chat_id', chatId);
        }

        // Delete the chats themselves using OR condition
        for (final chatId in chatIds) {
          await _supabase.from('chats').delete().eq('id', chatId);
        }
      }

      // Delete follow requests
      await _supabase.from('user_follow_request').delete().eq('user_id', uid);
      await _supabase
          .from('user_follow_request')
          .delete()
          .eq('requester_id', uid);

      // Delete following/followers
      await _supabase.from('user_following').delete().eq('user_id', uid);
      await _supabase.from('user_followers').delete().eq('user_id', uid);
      await _supabase.from('user_followers').delete().eq('follower_id', uid);

      // Delete notifications
      await _supabase.from('notifications').delete().eq('target_user_id', uid);

      await _deleteUserActorNotifications(uid);

      await _deleteUserPostViews(uid);

      // Delete user document
      await _supabase.from('users').delete().eq('uid', uid);

      // Delete profile image
      if (profilePicUrl != null &&
          profilePicUrl.isNotEmpty &&
          profilePicUrl != 'default') {
        await StorageMethods().deleteImage(profilePicUrl);
      }

      // Delete user account (works with or without recent reauthentication)
      await currentUser.delete();
      res = "success";
    } on firebase_auth.FirebaseAuthException catch (e) {
      res = e.code == 'requires-recent-login'
          ? "Re-authentication required. Please sign in again."
          : e.message ?? "Authentication error";
    } catch (e) {
      res = e.toString();
    }
    return res;
  }
}
