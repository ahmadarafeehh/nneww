// lib/resources/supabase_posts_methods.dart
import 'dart:typed_data';
import 'dart:io'; // Add this line for File class
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:Ratedly/resources/storage_methods.dart';
import 'package:Ratedly/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SupabasePostsMethods {
  final SupabaseClient _supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();
  final Uuid _uuid = const Uuid();

  // Helper to normalise different client return shapes
  dynamic _unwrap(dynamic res) {
    try {
      if (res == null) return null;
      // PostgrestResponse-like map
      if (res is Map && res.containsKey('data')) return res['data'];
    } catch (_) {}
    return res;
  }

// Record push notification (insert into Firestore only, not Supabase)
// ----------------------
  Future<void> _recordPushNotification({
    required String type,
    required String targetUserId,
    required String title,
    required String body,
    required Map<String, dynamic> customData,
  }) async {
    try {
      // This uses Firebase for push notifications (Firestore only)
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

  // ----------------------
  // Upload a post
  // ----------------------
  // In your SupabasePostsMethods class
  // In your SupabasePostsMethods class - FIXED VERSION
// Fixed uploadVideoPost method - remove the response error check
  Future<String> uploadVideoPost(
    String description,
    Uint8List file,
    String uid,
    String username,
    String profImage,
    String gender, {
    int boostViews = 0,
    bool isBoosted = false,
  }) async {
    String res = "Some error occurred";
    try {
      String postId = _uuid.v1();
      String fileName = 'video_$postId.mp4';

      final String videoUrl =
          await StorageMethods().uploadVideoToSupabaseSimple(
        'videos',
        file,
        fileName,
      );

      final payload = {
        'postId': postId,
        'description': description,
        'gender': gender,
        'postUrl': videoUrl,
        'profImage': profImage,
        'uid': uid,
        'username': username,
        'commentsCount': 0,
        'datePublished': DateTime.now().toUtc().toIso8601String(),
        'boost_views': boostViews,
        'is_boosted': isBoosted,
        'viewers_count': boostViews,
      };

      // FIXED: Remove the response error check that's causing the null error
      await _supabase.from('posts').insert(payload);

      res = "success";
    } catch (err) {
      res = err.toString();
    }
    return res;
  }

// Also fix the regular uploadPost method to be consistent
  Future<String> uploadPost(
    String description,
    Uint8List file,
    String uid,
    String username,
    String profImage,
    String gender, {
    int boostViews = 0,
    bool isBoosted = false,
  }) async {
    String res = "Some error occurred";
    try {
      final photoUrl =
          await StorageMethods().uploadImageToStorage('posts', file, true);
      final postId = _uuid.v1();

      final payload = {
        'postId': postId,
        'description': description,
        'gender': gender,
        'postUrl': photoUrl,
        'profImage': profImage,
        'uid': uid,
        'username': username,
        'commentsCount': 0,
        'datePublished': DateTime.now().toUtc().toIso8601String(),
        'boost_views': boostViews,
        'is_boosted': isBoosted,
        'viewers_count': boostViews,
      };

      await _supabase.from('posts').insert(payload);
      res = "success";
    } catch (err) {
      res = err.toString();
    }
    return res;
  }

// Add this method to your SupabasePostsMethods class
  Future<String> uploadVideoPostFromFile(
    String description,
    File videoFile, // Accept File instead of Uint8List
    String uid,
    String username,
    String profImage,
    String gender, {
    int boostViews = 0,
    bool isBoosted = false,
  }) async {
    String res = "Some error occurred";
    try {
      String postId = _uuid.v1();
      String fileName = 'video_$postId.mp4';

      // Use the StorageMethods to upload the File directly
      final String videoUrl = await StorageMethods().uploadVideoFileToSupabase(
        'videos',
        videoFile,
        fileName,
      );

      final payload = {
        'postId': postId,
        'description': description,
        'gender': gender,
        'postUrl': videoUrl,
        'profImage': profImage,
        'uid': uid,
        'username': username,
        'commentsCount': 0,
        'datePublished': DateTime.now().toUtc().toIso8601String(),
        'boost_views': boostViews,
        'is_boosted': isBoosted,
        'viewers_count': boostViews,
      };

      await _supabase.from('posts').insert(payload);
      res = "success";
    } catch (err) {
      res = err.toString();
    }
    return res;
  }

  // ----------------------
  // Like/unlike a comment (NOT atomic; consider server-side PG function for atomicity)
  // ----------------------
  Future<String> likeComment(
      String postId, String commentId, String uid) async {
    String res = "Some error occurred";
    try {
      // Check if user already liked this comment
      final likeCheck = await _supabase
          .from('comment_likes')
          .select()
          .eq('comment_id', commentId)
          .eq('uid', uid)
          .maybeSingle();

      final alreadyLiked = likeCheck != null;

      if (alreadyLiked) {
        // Unlike: Remove the like record
        await _supabase
            .from('comment_likes')
            .delete()
            .eq('comment_id', commentId)
            .eq('uid', uid);

        // Get current like_count and decrement it
        final commentSel = await _supabase
            .from('comments')
            .select('like_count')
            .eq('id', commentId)
            .maybeSingle();

        final commentData = _unwrap(commentSel) ?? commentSel;
        if (commentData != null) {
          int currentCount = commentData['like_count'] ?? 0;
          int newCount = currentCount - 1;
          if (newCount < 0) newCount = 0;

          await _supabase
              .from('comments')
              .update({'like_count': newCount}).eq('id', commentId);
        }

        // Delete notification
        await deleteCommentLikeNotification(postId, commentId, uid);
      } else {
        // Like: Add a like record
        await _supabase.from('comment_likes').insert({
          'comment_id': commentId,
          'uid': uid,
          'liked_at': DateTime.now().toUtc().toIso8601String()
        });

        // Get current like_count and increment it
        final commentSel = await _supabase
            .from('comments')
            .select('like_count, uid, comment_text')
            .eq('id', commentId)
            .maybeSingle();

        final commentData = _unwrap(commentSel) ?? commentSel;
        if (commentData != null) {
          int currentCount = commentData['like_count'] ?? 0;
          int newCount = currentCount + 1;

          await _supabase
              .from('comments')
              .update({'like_count': newCount}).eq('id', commentId);

          final String commentOwnerId = commentData['uid'];
          final String commentText = commentData['comment_text'] ?? '';

          if (commentOwnerId != uid) {
            // Create notification
            await createCommentLikeNotification(
              postId: postId,
              commentId: commentId,
              commentOwnerUid: commentOwnerId,
              likerUid: uid,
              commentText: commentText,
            );

            // Get liker's username for push notification
            final likerSel = await _supabase
                .from('users')
                .select('username')
                .eq('uid', uid)
                .maybeSingle();
            final likerData = _unwrap(likerSel) ?? likerSel;
            final String likerUsername = likerData?['username'] ?? 'Someone';

            // Record push notification
            await _recordPushNotification(
              type: 'comment_like',
              targetUserId: commentOwnerId,
              title: 'New Like',
              body: '$likerUsername liked your comment: $commentText',
              customData: {
                'likerId': uid,
                'postId': postId,
                'commentId': commentId
              },
            );

            // Trigger server notification
            _notificationService.triggerServerNotification(
              type: 'comment_like',
              targetUserId: commentOwnerId,
              title: 'New Like',
              body: '$likerUsername liked your comment: $commentText',
              customData: {
                'likerId': uid,
                'postId': postId,
                'commentId': commentId
              },
            );
          }
        }
      }

      res = 'success';
    } catch (err) {
      res = err.toString();
    }
    return res;
  }

  // ----------------------
  // Create comment-like notification
  // ----------------------
  Future<void> createCommentLikeNotification({
    required String postId,
    required String commentId,
    required String commentOwnerUid,
    required String likerUid,
    required String commentText,
  }) async {
    try {
      final payload = {
        'type': 'comment_like',
        'target_user_id': commentOwnerUid,
        'custom_data': {
          'likerUid': likerUid,
          'postId': postId,
          'commentId': commentId,
          'commentText': commentText,
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Insert notification row
      await _supabase.from('notifications').insert(payload);
    } catch (e) {}
  }

  // ----------------------
  // Create general notification for rating (and others)
  // ----------------------
  Future<void> createNotification({
    required String postId,
    required String postOwnerUid,
    required String raterUid,
    required double rating,
  }) async {
    try {
      if (raterUid == postOwnerUid) return;

      final payload = {
        'type': 'post_rating',
        'target_user_id': postOwnerUid,
        'custom_data': {
          'postId': postId,
          'raterUid': raterUid,
          'rating': rating,
        },
        'created_at': DateTime.now().toUtc().toIso8601String()
      };

      await _supabase.from('notifications').insert(payload);

      // Get rater's username for push notification
      final raterSel = await _supabase
          .from('users')
          .select('username')
          .eq('uid', raterUid)
          .maybeSingle();
      final raterData = _unwrap(raterSel) ?? raterSel;
      final String raterUsername = raterData?['username'] ?? 'Someone';

      // record push notification (and trigger server)
      await _recordPushNotification(
        type: 'rating',
        targetUserId: postOwnerUid,
        title: 'New Rating',
        body: '$raterUsername rated your post: ${rating.toStringAsFixed(1)}/10',
        customData: {'raterId': raterUid, 'postId': postId},
      );

      _notificationService.triggerServerNotification(
        type: 'rating',
        targetUserId: postOwnerUid,
        title: 'New Rating',
        body: '$raterUsername rated your post: ${rating.toStringAsFixed(1)}★',
        customData: {'raterId': raterUid, 'postId': postId},
      );
    } catch (e) {}
  }

  // ----------------------
  // Get viewed post ids (from post_views table)
  // ----------------------
  Future<List<String>> getViewedPostIds(String userId) async {
    try {
      final sel = await _supabase
          .from('user_post_views')
          .select('post_id, viewed_at') // Changed from 'postid'
          .eq('user_id', userId); // Changed from 'userid'

      final data = _unwrap(sel) ?? sel;
      if (data is List) {
        final rows = List<Map<String, dynamic>>.from(data);
        rows.sort((a, b) => (b['viewed_at'] ?? '')
            .toString()
            .compareTo((a['viewed_at'] ?? '').toString()));
        return rows
            .map((r) => r['post_id'].toString())
            .toList(); // Changed from 'postid'
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ----------------------
  // Delete comment + decrement count + remove related notifications
  // ----------------------
  Future<String> deleteComment(String postId, String commentId) async {
    String res = "Some error occurred";
    try {
      // Delete the comment
      await _supabase.from('comments').delete().eq('id', commentId);

      // Decrement commentsCount on the post (best effort; not atomic)
      await _changeCommentsCount(postId, -1);

      // Remove related notifications
      await _supabase
          .from('notifications')
          .delete()
          .eq('custom_data->>commentId', commentId);

      res = 'success';
    } catch (err) {
      res = err.toString();
    }
    return res;
  }

  // ----------------------
  // Delete single comment-like notification
  // ----------------------
  Future<void> deleteCommentLikeNotification(
      String postId, String commentId, String likerUid) async {
    try {
      await _supabase
          .from('notifications')
          .delete()
          .eq('type', 'comment_like')
          .eq('custom_data->>postId', postId)
          .eq('custom_data->>commentId', commentId)
          .eq('custom_data->>likerUid', likerUid);
    } catch (e) {}
  }

  // ----------------------
  // Rate a post (uses post_rating table)
  // ----------------------
  Future<String> ratePost(String postId, String uid, double rating) async {
    String res = "Some error occurred";
    String postOwnerUid = '';
    try {
      final roundedRating = double.parse(rating.toStringAsFixed(1));

      // Fetch post owner
      final postSel = await _supabase
          .from('posts')
          .select('uid')
          .eq('postId', postId)
          .maybeSingle();
      final postData = _unwrap(postSel) ?? postSel;
      if (postData == null) throw Exception('Post not found');
      postOwnerUid = postData['uid']?.toString() ?? '';

      // Upsert rating — pass onConflict as a named parameter
      final result = await _supabase.from('post_rating').upsert({
        'postid': postId,
        'userid': uid,
        'rating': roundedRating,
        'timestamp': DateTime.now().toUtc().toIso8601String()
      }, onConflict: 'postid,userid');

      // Notification for non-self rating
      if (uid != postOwnerUid) {
        await createNotification(
          postId: postId,
          postOwnerUid: postOwnerUid,
          raterUid: uid,
          rating: roundedRating,
        );
      }

      res = "success";
    } catch (err) {
      res = err.toString();
    }
    return res;
  }

  // ----------------------
  // Create comment (and notify)
  // ----------------------
  Future<String> postComment(String postId, String text, String uid,
      String name, String profilePic) async {
    String res = "Some error occurred";
    try {
      if (text.isEmpty) return "Please enter text";

      final commentId = _uuid.v1();
      final payload = {
        'id': commentId,
        'postid': postId,
        'uid': uid,
        'name': name,
        'comment_text': text,
        'date_published': DateTime.now().toUtc().toIso8601String(),
        'like_count': 0
      };

      await _supabase.from('comments').insert(payload);

      // increment commentsCount (best effort; not atomic)
      await _changeCommentsCount(postId, 1);

      // Get post owner
      final postSel = await _supabase
          .from('posts')
          .select('uid')
          .eq('postId', postId)
          .maybeSingle();
      final postData = _unwrap(postSel) ?? postSel;
      final postOwnerUid = postData?['uid']?.toString() ?? '';

      if (uid != postOwnerUid && postOwnerUid.isNotEmpty) {
        // Create the in-app notification
        await createCommentNotification(postId, uid, text, commentId);

        // Record push notification (to Firestore)
        await _recordPushNotification(
          type: 'comment',
          targetUserId: postOwnerUid,
          title: 'New Comment',
          body: '$name commented: $text',
          customData: {
            'commenterId': uid,
            'postId': postId,
            'commentId': commentId
          },
        );

        // Trigger server notification
        _notificationService.triggerServerNotification(
          type: 'comment',
          targetUserId: postOwnerUid,
          title: 'New Comment',
          body: '$name commented: $text',
          customData: {
            'commenterId': uid,
            'postId': postId,
            'commentId': commentId
          },
        );
      }

      res = 'success';
    } catch (e) {
      res = e.toString();
    }
    return res;
  }

  Future<void> createCommentNotification(
    String postId,
    String commenterUid,
    String commentText,
    String commentId,
  ) async {
    try {
      final postSel = await _supabase
          .from('posts')
          .select('uid')
          .eq('postId', postId)
          .maybeSingle();
      final postData = _unwrap(postSel) ?? postSel;
      final postOwnerUid = postData?['uid']?.toString() ?? '';
      if (postOwnerUid.isEmpty || postOwnerUid == commenterUid) return;

      final payload = {
        'type': 'comment',
        'target_user_id': postOwnerUid,
        'custom_data': {
          'commenterUid': commenterUid,
          'commentText': commentText,
          'postId': postId,
          'commentId': commentId,
        },
        'created_at': DateTime.now().toUtc().toIso8601String()
      };

      await _supabase.from('notifications').insert(payload);
    } catch (e) {}
  }

  // ----------------------
  // Share a post through chat
  // ----------------------
  // In lib/resources/supabase_posts_methods.dart

// Update the sharePostThroughChat method to use the correct table and columns
// In lib/resources/supabase_posts_methods.dart

  Future<String> sharePostThroughChat({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String postId,
    required String postImageUrl,
    required String postCaption,
    required String postOwnerId,
    String? postOwnerUsername,
    String? postOwnerPhotoUrl,
  }) async {
    try {
      final messageId = _uuid.v1();

      // Create the post_share JSON object
      final postShareData = {
        'postId': postId,
        'postImageUrl': postImageUrl,
        'postCaption': postCaption,
        'postOwnerId': postOwnerId,
        'postOwnerUsername': postOwnerUsername ?? 'Unknown User',
        'postOwnerPhotoUrl': postOwnerPhotoUrl ?? '',
        'sharedAt': DateTime.now().toUtc().toIso8601String(),
        'isDirectOwner': senderId == postOwnerId,
      };

      // Insert into messages table with post_share JSONB column
      final payload = {
        'id': messageId,
        'chat_id': chatId,
        'sender_id': senderId,
        'receiver_id': receiverId,
        'message': 'Shared a post: $postCaption', // Regular message text
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'is_read': false,
        'delivered': false,
        'post_share': postShareData, // JSONB data
      };

      await _supabase.from('messages').insert(payload);

      // Update chat metadata
      await _supabase.from('chats').update({
        'last_message': 'Shared a post',
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('id', chatId);

      return 'success';
    } catch (e) {
      return e.toString();
    }
  }

  // ----------------------
  // Record post view
  // ----------------------
  Future<void> recordPostView(String postId, String userId) async {
    try {
      await _supabase.from('user_post_views').insert({
        'post_id': postId, // Changed from 'postid'
        'user_id': userId, // Changed from 'userid'
        'viewed_at': DateTime.now().toUtc().toIso8601String()
      });
    } catch (e) {}
  }

  // ----------------------
  // Mutual block check (reads users.blockedUsers jsonb)
  // ----------------------
  Future<bool> checkMutualBlock(String userId1, String userId2) async {
    try {
      final sel1 = await _supabase
          .from('users')
          .select('blockedUsers')
          .eq('uid', userId1)
          .maybeSingle();
      final sel2 = await _supabase
          .from('users')
          .select('blockedUsers')
          .eq('uid', userId2)
          .maybeSingle();
      final data1 = _unwrap(sel1) ?? sel1;
      final data2 = _unwrap(sel2) ?? sel2;

      final List<dynamic> blocked1 =
          data1 != null ? (data1['blockedUsers'] ?? []) : [];
      final List<dynamic> blocked2 =
          data2 != null ? (data2['blockedUsers'] ?? []) : [];

      return blocked1.contains(userId2) && blocked2.contains(userId1);
    } catch (e) {
      return false;
    }
  }

  // ----------------------
  // Delete a post
  // ----------------------
  // ----------------------
// Delete a post (FIXED for videos)
// ----------------------
  // ----------------------
// Delete a post (FIXED for videos) with corrected table names
// ----------------------
  Future<String> deletePost(String postId) async {
    String res = "Some error occurred";
    try {
      final postSel = await _supabase
          .from('posts')
          .select('postUrl, uid')
          .eq('postId', postId)
          .maybeSingle();
      final postData = _unwrap(postSel) ?? postSel;

      if (postData == null) {
        throw Exception('Post does not exist');
      }

      final postUrl = postData['postUrl']?.toString() ?? '';
      final postOwnerUid = postData['uid']?.toString() ?? '';

      if (postUrl.isNotEmpty) {
        if (_isVideoUrl(postUrl)) {
          await _deleteVideoFromUrl(postUrl);
        } else {
          await StorageMethods().deleteImage(postUrl);
        }
      } else {}

      // Delete post views first (before deleting the post) - CORRECTED TABLE NAME
      final viewsResult = await _supabase
          .from('user_post_views')
          .delete()
          .eq('post_id', postId);

      // delete post ro
      final postDeleteResult =
          await _supabase.from('posts').delete().eq('postId', postId);

      // Delete related comments/replies/ratings/notifications

      final commentsResult =
          await _supabase.from('comments').delete().eq('postid', postId);

      final repliesResult =
          await _supabase.from('replies').delete().eq('postid', postId);

      final ratingsResult =
          await _supabase.from('post_rating').delete().eq('postid', postId);

      final notificationsResult = await _supabase
          .from('notifications')
          .delete()
          .eq('custom_data->>postId', postId);

      res = 'success';
    } catch (err) {
      res = err.toString();
    }
    return res;
  }

// Helper method to check if URL is from Supabase Storage (video)
  bool _isVideoUrl(String url) {
    final isSupabaseVideo =
        url.contains('supabase.co/storage/v1/object/public/videos');
    final hasVideoExtension = url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.avi') ||
        url.endsWith('.mkv');

    return isSupabaseVideo || hasVideoExtension;
  }

// Helper method to delete video from Supabase Storage using URL
  // Helper method to delete video from Supabase Storage using URL
  Future<void> _deleteVideoFromUrl(String videoUrl) async {
    try {
      // Extract the file path from the Supabase storage URL
      final uri = Uri.parse(videoUrl);
      final pathSegments = uri.pathSegments;

      // Find the index of 'videos' in the path
      final videosIndex = pathSegments.indexOf('videos');

      if (videosIndex != -1 && videosIndex < pathSegments.length - 1) {
        // The path after 'videos' is the file path (user-uid/filename.mp4)
        final filePath = pathSegments.sublist(videosIndex + 1).join('/');

        await StorageMethods().deleteVideoFromSupabase('videos', filePath);
      } else {
        throw Exception('Invalid video URL format');
      }
    } catch (e) {
      rethrow;
    }
  }

  // ----------------------
  // Report post / comment
  // ----------------------
  Future<String> reportPost(String postId, String reason) async {
    try {
      await _supabase.from('reports').insert({
        'postId': postId,
        'reason': reason,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'type': 'post'
      });
      return 'success';
    } catch (err) {
      return err.toString();
    }
  }

  Future<String> reportComment({
    required String postId,
    required String commentId,
    required String reason,
  }) async {
    try {
      await _supabase.from('reports').insert({
        'postId': postId,
        'commentId': commentId,
        'reason': reason,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'type': 'comment'
      });
      return 'success';
    } catch (err) {
      return err.toString();
    }
  }

  // ----------------------
  // Replies (create/delete/like) - similar to comments
  // ----------------------
  Future<String> postReply({
    required String postId,
    required String commentId,
    required String uid,
    required String name,
    required String profilePic,
    required String text,
    String? parentReplyId,
  }) async {
    try {
      final replyId = _uuid.v1();

      final payload = {
        'id': replyId,
        'postid': postId,
        'commentid': commentId,
        'uid': uid,
        'name': name,
        'reply_text': text,
        'date_published': DateTime.now().toUtc().toIso8601String(),
        'like_count': 0,
        'parent_reply_id': parentReplyId
      };

      await _supabase.from('replies').insert(payload);

      // Determine parent owner
      String parentOwnerUid = '';
      if (parentReplyId != null) {
        final sel = await _supabase
            .from('replies')
            .select('uid')
            .eq('id', parentReplyId)
            .maybeSingle();
        final d = _unwrap(sel) ?? sel;
        parentOwnerUid = d?['uid']?.toString() ?? '';
      } else {
        final sel = await _supabase
            .from('comments')
            .select('uid')
            .eq('id', commentId)
            .maybeSingle();
        final d = _unwrap(sel) ?? sel;
        parentOwnerUid = d?['uid']?.toString() ?? '';
      }

      if (parentOwnerUid.isNotEmpty && parentOwnerUid != uid) {
        await createReplyNotification(
          postId: postId,
          commentId: commentId,
          replyId: replyId,
          replyOwnerUid: parentOwnerUid,
          replierUid: uid,
          replyText: text,
        );
      }

      return 'success';
    } catch (e) {
      return e.toString();
    }
  }

  Future<String> deleteReply({
    required String postId,
    required String commentId,
    required String replyId,
  }) async {
    try {
      await _supabase.from('replies').delete().eq('id', replyId);

      // remove notifications
      await _supabase
          .from('notifications')
          .delete()
          .eq('custom_data->>replyId', replyId);
      return 'success';
    } catch (e) {
      return e.toString();
    }
  }

  Future<Map<String, dynamic>> likeReply({
    required String postId,
    required String commentId,
    required String replyId,
    required String uid,
  }) async {
    try {
      final likeCheck = await _supabase
          .from('reply_likes')
          .select()
          .eq('reply_id', replyId)
          .eq('uid', uid)
          .maybeSingle();

      final alreadyLiked = likeCheck != null;

      if (alreadyLiked) {
        // Unlike handling
        await _supabase
            .from('reply_likes')
            .delete()
            .eq('reply_id', replyId)
            .eq('uid', uid);

        final replySel = await _supabase
            .from('replies')
            .select('like_count')
            .eq('id', replyId)
            .maybeSingle();

        final replyData = _unwrap(replySel) ?? replySel;
        int newCount = 0;
        if (replyData != null) {
          int currentCount = replyData['like_count'] ?? 0;
          newCount = currentCount - 1;
          if (newCount < 0) newCount = 0;

          await _supabase
              .from('replies')
              .update({'like_count': newCount}).eq('id', replyId);
        }

        // Delete notification
        await deleteReplyLikeNotification(postId, commentId, replyId, uid);

        return {'action': 'unliked', 'like_count': newCount, 'is_liked': false};
      } else {
        // Like handling
        await _supabase.from('reply_likes').insert({
          'reply_id': replyId,
          'uid': uid,
          'liked_at': DateTime.now().toUtc().toIso8601String()
        });

        // Fetch reply data including owner and text
        final replySel = await _supabase
            .from('replies')
            .select('like_count, uid, reply_text')
            .eq('id', replyId)
            .maybeSingle();

        final replyData = _unwrap(replySel) ?? replySel;
        int newCount = 0;
        if (replyData != null) {
          int currentCount = replyData['like_count'] ?? 0;
          newCount = currentCount + 1;

          await _supabase
              .from('replies')
              .update({'like_count': newCount}).eq('id', replyId);

          final String replyOwnerUid = replyData['uid'];
          final String replyText = replyData['reply_text'] ?? '';

          // Create notification if not liking own reply
          if (replyOwnerUid != uid) {
            await createReplyLikeNotification(
              postId: postId,
              commentId: commentId,
              replyId: replyId,
              replyOwnerUid: replyOwnerUid,
              likerUid: uid,
              replyText: replyText,
            );
          }
        }

        return {'action': 'liked', 'like_count': newCount, 'is_liked': true};
      }
    } catch (e) {
      return {'action': 'error', 'error': e.toString()};
    }
  }

  Future<void> deleteReplyLikeNotification(
    String postId,
    String commentId,
    String replyId,
    String likerUid,
  ) async {
    try {
      await _supabase
          .from('notifications')
          .delete()
          .eq('type', 'reply_like')
          .eq('custom_data->>postId', postId)
          .eq('custom_data->>commentId', commentId)
          .eq('custom_data->>replyId', replyId)
          .eq('custom_data->>likerUid', likerUid);
    } catch (e) {}
  }

  Future<void> createReplyNotification({
    required String postId,
    required String commentId,
    required String replyId,
    required String replyOwnerUid,
    required String replierUid,
    required String replyText,
  }) async {
    try {
      if (replyOwnerUid == replierUid) return;

      final payload = {
        'type': 'reply',
        'target_user_id': replyOwnerUid,
        'custom_data': {
          'replierUid': replierUid,
          'postId': postId,
          'commentId': commentId,
          'replyId': replyId,
          'replyText': replyText,
        },
        'created_at': DateTime.now().toUtc().toIso8601String()
      };

      await _supabase.from('notifications').insert(payload);

      // Get replier's name for push notification
      final replierSel = await _supabase
          .from('users')
          .select('username')
          .eq('uid', replierUid)
          .maybeSingle();
      final replierData = _unwrap(replierSel) ?? replierSel;
      final String replierName = replierData?['username'] ?? 'Someone';

      await _recordPushNotification(
        type: 'reply',
        targetUserId: replyOwnerUid,
        title: 'New Reply',
        body: '$replierName replied: $replyText',
        customData: {
          'replierId': replierUid,
          'postId': postId,
          'commentId': commentId,
          'replyId': replyId
        },
      );

      _notificationService.triggerServerNotification(
        type: 'reply',
        targetUserId: replyOwnerUid,
        title: 'New Reply',
        body: '$replierName replied: $replyText',
        customData: {
          'replierId': replierUid,
          'postId': postId,
          'commentId': commentId,
          'replyId': replyId
        },
      );
    } catch (e) {}
  }

  Future<void> createReplyLikeNotification({
    required String postId,
    required String commentId,
    required String replyId,
    required String replyOwnerUid,
    required String likerUid,
    required String replyText,
  }) async {
    try {
      if (replyOwnerUid == likerUid) return;

      final payload = {
        'type': 'reply_like',
        'target_user_id': replyOwnerUid,
        'custom_data': {
          'likerUid': likerUid,
          'postId': postId,
          'commentId': commentId,
          'replyId': replyId,
          'replyText': replyText,
        },
        'created_at': DateTime.now().toUtc().toIso8601String()
      };

      await _supabase.from('notifications').insert(payload);

      // Get liker's name for push notification
      final likerSel = await _supabase
          .from('users')
          .select('username')
          .eq('uid', likerUid)
          .maybeSingle();
      final likerData = _unwrap(likerSel) ?? likerSel;
      final String likerName = likerData?['username'] ?? 'Someone';

      await _recordPushNotification(
        type: 'reply_like',
        targetUserId: replyOwnerUid,
        title: 'Reply Liked',
        body: '$likerName liked your reply: $replyText',
        customData: {
          'likerId': likerUid,
          'postId': postId,
          'commentId': commentId,
          'replyId': replyId,
        },
      );

      _notificationService.triggerServerNotification(
        type: 'reply_like',
        targetUserId: replyOwnerUid,
        title: 'Reply Liked',
        body: '$likerName liked your reply',
        customData: {
          'likerId': likerUid,
          'postId': postId,
          'commentId': commentId,
          'replyId': replyId,
        },
      );
    } catch (e) {}
  }

  // ----------------------
  // Helper: change commentsCount safely (not atomic)
  // If you need atomic increments under concurrency, implement a DB function (RPC) and call it instead.
  // ----------------------
  Future<void> _changeCommentsCount(String postId, int delta) async {
    try {
      final sel = await _supabase
          .from('posts')
          .select('commentsCount')
          .eq('postId', postId)
          .maybeSingle();
      final data = _unwrap(sel) ?? sel;
      int current = 0;
      if (data != null) {
        final val = data['commentsCount'];
        if (val is int)
          current = val;
        else if (val is String)
          current = int.tryParse(val) ?? current;
        else if (val is num) current = val.toInt();
      }
      int updated = current + delta;
      if (updated < 0) updated = 0;
      await _supabase
          .from('posts')
          .update({'commentsCount': updated}).eq('postId', postId);
    } catch (e) {}
  }
}
