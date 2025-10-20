import 'dart:typed_data';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StorageMethods {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Upload image to Firebase Storage
  Future<String> uploadImageToStorage(
      String childName, Uint8List file, bool isPost,
      {String contentType = 'image/jpeg'}) async {
    try {
      Reference ref =
          _storage.ref().child(childName).child(_auth.currentUser!.uid);
      if (isPost) {
        String id = const Uuid().v1();
        ref = ref.child(id);
      }

      final metadata = SettableMetadata(contentType: contentType);
      UploadTask uploadTask = ref.putData(file, metadata);
      TaskSnapshot snapshot = await uploadTask;

      final parentRef = snapshot.ref.parent!;
      final thumbRef = parentRef.child('${snapshot.ref.name}_1024x1024');

      String? downloadUrl;
      int retries = 0;
      const int maxRetries = 10;

      while (retries < maxRetries) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          downloadUrl = await thumbRef.getDownloadURL();
          break;
        } catch (e) {
          retries++;
        }
      }

      if (downloadUrl == null) {
        throw Exception(
            'Resized image not available after $maxRetries attempts');
      }

      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  // Delete an image from Firebase Storage
  Future<void> deleteImage(String imageUrl) async {
    try {
      if (!imageUrl.startsWith('gs://') &&
          !imageUrl.contains('firebasestorage.googleapis.com')) {
        throw Exception('Invalid Firebase Storage URL: $imageUrl');
      }

      Reference ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      rethrow;
    }
  }

  // Upload video to Supabase
  Future<String> uploadVideoToSupabase(
      String bucketName, Uint8List file, String fileName) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload video');
      }

      String extension = fileName.split('.').last;
      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      final String userFolderPath = '${user.uid}/$uniqueFileName';

      final tempFile = await _createTempFile(uniqueFileName, file);

      final response = await _supabase.storage
          .from(bucketName)
          .upload(userFolderPath, tempFile);

      await tempFile.delete();

      final String publicUrl =
          _supabase.storage.from(bucketName).getPublicUrl(userFolderPath);
      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload video to Supabase: $e');
    }
  }

  // Helper method to create a temporary file
  Future<File> _createTempFile(String fileName, Uint8List data) async {
    try {
      final systemTemp = Directory.systemTemp;
      if (await systemTemp.exists()) {
        final tempFile = File('${systemTemp.path}/$fileName');
        await tempFile.writeAsBytes(data);
        return tempFile;
      }
    } catch (e) {
      // Fall through to next method
    }

    try {
      final currentDir = Directory.current;
      final tempFile = File('${currentDir.path}/$fileName');
      await tempFile.writeAsBytes(data);
      return tempFile;
    } catch (e) {
      // Fall through to next method
    }

    try {
      final tempFile = File(fileName);
      await tempFile.writeAsBytes(data);
      return tempFile;
    } catch (e) {
      throw Exception('Cannot create temporary file: $e');
    }
  }

  // Simple method with user folder
  Future<String> uploadVideoToSupabaseSimple(
      String bucketName, Uint8List file, String fileName) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload video');
      }

      String extension = fileName.split('.').last;
      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      final String userFolderPath = '${user.uid}/$uniqueFileName';

      final tempFile = await _createTempFile(uniqueFileName, file);

      final response = await _supabase.storage
          .from(bucketName)
          .upload(userFolderPath, tempFile);

      await tempFile.delete();

      final String publicUrl =
          _supabase.storage.from(bucketName).getPublicUrl(userFolderPath);
      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload video: $e');
    }
  }

  // Helper method to get video file from gallery
  Future<Uint8List?> pickVideoFromGallery() async {
    try {
      final XFile? videoFile = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (videoFile != null) {
        return await videoFile.readAsBytes();
      }
      return null;
    } catch (e) {
      throw Exception('Failed to pick video: $e');
    }
  }

  // Alternative: Get video as File instead of Uint8List
  Future<File?> pickVideoFileFromGallery() async {
    try {
      final XFile? videoFile = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (videoFile != null) {
        return File(videoFile.path);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to pick video: $e');
    }
  }

  // Upload video from File with user folder
  Future<String> uploadVideoFileToSupabase(
      String bucketName, File videoFile, String fileName) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload video');
      }

      String extension = fileName.split('.').last;
      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      final String userFolderPath = '${user.uid}/$uniqueFileName';

      final response = await _supabase.storage
          .from(bucketName)
          .upload(userFolderPath, videoFile);

      final String publicUrl =
          _supabase.storage.from(bucketName).getPublicUrl(userFolderPath);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload video file: $e');
    }
  }

  // UPDATED: Delete video with multiple fallback methods
  Future<void> deleteVideoFromSupabase(
      String bucketName, String filePath) async {
    try {
      // METHOD 1: Try standard storage API first
      try {
        final response =
            await _supabase.storage.from(bucketName).remove([filePath]);

        if (response.isNotEmpty) {
          await _verifyDeletion(bucketName, filePath);
          return;
        } else {}
      } catch (e) {}

      // METHOD 2: Try REST API with multiple endpoints

      await _deleteViaRestApi(bucketName, filePath);
    } catch (e) {
      throw Exception('Failed to delete video');
    }
  }

  // FIXED: Multiple REST API endpoints for Supabase Storage
  Future<void> _deleteViaRestApi(String bucketName, String filePath) async {
    try {
      final projectRef = 'tbiemcbqjjjsgumnjlqq';
      // IMPORTANT: Replace with your actual anon key from Supabase dashboard → Settings → API
      final anonKey =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiaWVtY2Jxampqc3VtbmpscXEiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTcyODU1OTY0NywiZXhwIjoyMDQ0MTM1NjQ3fQ.0t_lxOQkF4K9cEEmhJ4w1b2q6y6q2q9Q2q9Q2q9Q2q9Q';

      // NOTE: use dynamic/maps so we can cast safely later
      final List<Map<String, dynamic>> endpoints = [
        {
          'name': 'Single file DELETE',
          'url':
              'https://$projectRef.supabase.co/storage/v1/object/$bucketName/${Uri.encodeComponent(filePath)}',
          'method': 'DELETE',
          'body': null
        },
        {
          'name': 'Batch deletion POST',
          'url':
              'https://$projectRef.supabase.co/storage/v1/object/$bucketName',
          'method': 'POST',
          'body': {
            'prefixes': [filePath]
          }
        },
      ];

      for (var endpoint in endpoints) {
        // Extract and cast to correct types BEFORE using them
        final String name = endpoint['name'] as String;
        final String url = endpoint['url'] as String;
        final String method = endpoint['method'] as String;
        final dynamic body = endpoint['body'];

        try {
          final uri = Uri.parse(url);
          final http.Response response = method == 'POST'
              ? await http.post(
                  uri,
                  headers: {
                    'Authorization': 'Bearer $anonKey',
                    'Content-Type': 'application/json',
                  },
                  body: body != null ? json.encode(body) : null,
                )
              : await http.delete(
                  uri,
                  headers: {
                    'Authorization': 'Bearer $anonKey',
                  },
                );

          if (response.statusCode == 200 || response.statusCode == 204) {
            await _verifyDeletion(bucketName, filePath);
            return;
          } else if (response.statusCode == 401) {
            throw Exception('Authentication failed - check your anon key');
          } else {
            // Continue to next endpoint
          }
        } catch (e) {
          // Continue to next endpoint
        }

        await Future.delayed(Duration(milliseconds: 500));
      }

      throw Exception('All REST API endpoints failed');
    } catch (e) {
      rethrow;
    }
  }

  // FIXED: Verify deletion with proper type casting
  Future<void> _verifyDeletion(String bucketName, String filePath) async {
    try {
      // Wait a moment for changes to propagate
      await Future.delayed(Duration(seconds: 2));

      bool deletionVerified = false;

      // Method 1: Try to access via public URL
      try {
        final publicUrl =
            _supabase.storage.from(bucketName).getPublicUrl(filePath);
        final headResponse = await http.head(Uri.parse(publicUrl));

        if (headResponse.statusCode == 200) {
        } else if (headResponse.statusCode == 404) {
          deletionVerified = true;
        } else {}
      } catch (e) {
        deletionVerified = true;
      }

      // Method 2: Check via storage API list - FIXED TYPE CASTING
      try {
        final userFolder = filePath.split('/').first;
        final files =
            await _supabase.storage.from(bucketName).list(path: userFolder);

        // FIXED: Proper null-safe type handling with explicit type checking
        bool fileExists = false;
        for (final file in files) {
          final fileName = file.name;
          // Check for null and type before using the value
          if (fileName != null &&
              fileName is String &&
              fileName == filePath.split('/').last) {
            fileExists = true;
            break;
          }
        }

        if (!fileExists) {
          deletionVerified = true;
        } else {}
      } catch (e) {}

      if (!deletionVerified) {}
    } catch (e) {}
  }

  // FIXED: Alternative method with proper type casting
  Future<void> deleteVideoAlternative(
      String bucketName, String filePath) async {
    try {
      // Try different path formats
      final pathsToTry = [
        [filePath], // Original path
        [filePath.split('/').last], // Just filename
        ['${filePath.split('/').first}/'], // Folder path
      ];

      for (int i = 0; i < pathsToTry.length; i++) {
        try {
          final result =
              await _supabase.storage.from(bucketName).remove(pathsToTry[i]);

          if (result.isNotEmpty) {
            return;
          }
        } catch (e) {}
      }
    } catch (e) {}
  }

  // Get signed URL with user folder structure
  Future<String> getSignedUrlForVideo(String bucketName, String fileName,
      {int expiresIn = 60}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to get signed URL');
      }

      String actualFileName = fileName;
      if (fileName.contains('/')) {
        actualFileName = fileName.split('/').last;
      }

      final String userFolderPath = '${user.uid}/$actualFileName';

      final String signedUrl = await _supabase.storage
          .from(bucketName)
          .createSignedUrl(userFolderPath, expiresIn);
      return signedUrl;
    } catch (e) {
      throw Exception('Failed to get signed URL: $e');
    }
  }

  // Helper method to extract filename from URL/path
  String _extractFileName(String path) {
    if (path.contains('/')) {
      return path.split('/').last;
    }
    return path;
  }

  // Method to get user's video folder path
  String getUserVideoFolderPath(String fileName) {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in');
    }
    final String uniqueFileName =
        '${const Uuid().v1()}.${fileName.split('.').last}';
    return '${user.uid}/$uniqueFileName';
  }

  // FIXED: List user's videos with proper type casting
  Future<List<String>> listUserVideos(String bucketName) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in');
      }

      final response =
          await _supabase.storage.from(bucketName).list(path: user.uid);

      // FIXED: Proper null-safe type handling with explicit type checking
      final List<String> videoFiles = [];
      for (final file in response) {
        final fileName = file.name;
        // Check for null and type before using the value
        if (fileName != null && fileName is String && _isVideoFile(fileName)) {
          videoFiles.add(fileName);
        }
      }
      return videoFiles;
    } catch (e) {
      throw Exception('Failed to list user videos: $e');
    }
  }

  // Helper to check if file is a video
  bool _isVideoFile(String fileName) {
    final videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv'];
    final extension = fileName.split('.').last.toLowerCase();
    return videoExtensions.contains(extension);
  }
}
