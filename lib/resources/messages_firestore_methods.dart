import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:Ratedly/services/notification_service.dart';

class SupabaseMessagesMethods {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  Future<String> sendMessage(
    String chatId,
    String senderId,
    String receiverId,
    String message,
  ) async {
    try {
      await _supabase.from('messages').insert({
        'chat_id': chatId,
        'sender_id': senderId,
        'receiver_id': receiverId,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
        'is_read': false,
        'delivered': false,
      });

      await _supabase.from('chats').update({
        'last_message': message,
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('id', chatId);

      final senderUsername = await _getUsername(senderId);
      await _notificationService.triggerServerNotification(
        type: 'message',
        targetUserId: receiverId,
        title: senderUsername,
        body: message,
        customData: {
          'senderId': senderId,
          'chatId': chatId,
        },
      );

      await _firestore.collection('Push Not').add({
        'type': 'message',
        'targetUserId': receiverId,
        'title': senderUsername,
        'body': message,
        'customData': {'senderId': senderId, 'chatId': chatId},
        'timestamp': FieldValue.serverTimestamp(),
      });

      return 'success';
    } catch (e) {
      return e.toString();
    }
  }

  Future<String> _getUsername(String userId) async {
    final response = await _supabase
        .from('users')
        .select('username')
        .eq('uid', userId)
        .single();
    return response['username'] ?? 'Unknown';
  }

  // In your messages methods file

  Stream<List<Map<String, dynamic>>> getMessages(String chatId) {
    return _supabase
        .from('messages')
        .select()
        .eq('chat_id', chatId)
        .order('timestamp')
        .asStream()
        .map((messages) => messages.map((message) {
              // Parse the post_share JSON if it exists
              dynamic postShare = message['post_share'];
              Map<String, dynamic>? postShareData;

              if (postShare != null && postShare is Map) {
                postShareData = Map<String, dynamic>.from(postShare);
              }

              return {
                'id': message['id'],
                'message': message['message'],
                'senderId': message['sender_id'],
                'receiverId': message['receiver_id'],
                'timestamp': DateTime.parse(message['timestamp']),
                'isRead': message['is_read'],
                'delivered': message['delivered'],
                'type': postShareData != null ? 'post' : 'text',
                'postShare': postShareData,
              };
            }).toList());
  }

  Future<String> getOrCreateChat(String user1, String user2) async {
    try {
      // Check if chat already exists
      final chatResponse = await _supabase
          .from('chats')
          .select('id')
          .contains('participants', [user1, user2]);

      if (chatResponse.isNotEmpty) {
        return chatResponse[0]['id'];
      }

      // Create new chat
      final newChatId = const Uuid().v1();
      await _supabase.from('chats').insert({
        'id': newChatId,
        'participants': [user1, user2],
        'last_message': '',
        'last_updated': DateTime.now().toIso8601String(),
      });
      return newChatId;
    } catch (e) {
      return e.toString();
    }
  }

  Stream<int> getTotalUnreadCount(String currentUserId) {
    return _supabase
        .from('messages')
        .select()
        .eq('receiver_id', currentUserId)
        .eq('is_read', false)
        .asStream()
        .map((messages) => messages.length);
  }

  Stream<int> getUnreadCount(String chatId, String currentUserId) {
    return _supabase
        .from('messages')
        .select()
        .eq('chat_id', chatId)
        .eq('receiver_id', currentUserId)
        .eq('is_read', false)
        .asStream()
        .map((messages) => messages.length);
  }

  Future<void> markMessagesAsRead(String chatId, String currentUserId) async {
    await _supabase
        .from('messages')
        .update({'is_read': true})
        .eq('chat_id', chatId)
        .eq('receiver_id', currentUserId)
        .eq('is_read', false);
  }

  Future<void> markMessageAsDelivered(String messageId) async {
    await _supabase
        .from('messages')
        .update({'delivered': true}).eq('id', messageId);
  }

  Future<void> markMessageAsSeen(String messageId) async {
    await _supabase
        .from('messages')
        .update({'is_read': true, 'delivered': true}).eq('id', messageId);
  }

  Future<void> deleteAllUserMessages(String uid) async {
    // Get all chats where user is a participant
    final chatsResponse = await _supabase
        .from('chats')
        .select('id')
        .contains('participants', [uid]);

    if (chatsResponse.isNotEmpty) {
      final chatIds =
          chatsResponse.map((chat) => chat['id'] as String).toList();

      // Delete all messages in these chats
      for (final chatId in chatIds) {
        await _supabase.from('messages').delete().eq('chat_id', chatId);
      }

      // Delete the chats
      for (final chatId in chatIds) {
        await _supabase.from('chats').delete().eq('id', chatId);
      }
    }
  }

  Stream<List<Map<String, dynamic>>> getUserChats(String userId) {
    return _supabase
        .from('chats')
        .select()
        .contains('participants', [userId])
        .order('last_updated', ascending: false)
        .asStream()
        .map((chats) => chats
            .map((chat) => {
                  'id': chat['id'],
                  'participants': List<String>.from(chat['participants']),
                  'lastMessage': chat['last_message'],
                  'lastUpdated': DateTime.parse(chat['last_updated']),
                })
            .toList());
  }
}
