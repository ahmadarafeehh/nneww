import 'dart:typed_data';
import 'dart:io'; // for File
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class StorageMethods {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Upload image to Firebase Storage (UNCHANGED - images keep current structure)
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

  // Delete an image from Firebase Storage (UNCHANGED)
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

  // UPDATED: Create user folder for videos
  Future<String> uploadVideoToSupabase(
      String bucketName, Uint8List file, String fileName) async {
    try {
      // Get current user UID
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload video');
      }

      String extension = fileName.split('.').last;
      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      // Create path with user UID folder
      final String userFolderPath = '${user.uid}/$uniqueFileName';

      // Create a temporary file
      final tempFile = await _createTempFile(uniqueFileName, file);

      // Upload the File object with user folder path
      final response = await _supabase.storage
          .from(bucketName)
          .upload(userFolderPath, tempFile);

      // Clean up the temporary file
      await tempFile.delete();

      // Get public URL
      final String publicUrl =
          _supabase.storage.from(bucketName).getPublicUrl(userFolderPath);
      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload video to Supabase: $e');
    }
  }

  // Helper method to create a temporary file (UNCHANGED)
  Future<File> _createTempFile(String fileName, Uint8List data) async {
    try {
      // Method 1: Try to use system temp directory
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
      // Method 2: Try current directory
      final currentDir = Directory.current;
      final tempFile = File('${currentDir.path}/$fileName');
      await tempFile.writeAsBytes(data);
      return tempFile;
    } catch (e) {
      // Fall through to next method
    }

    try {
      // Method 3: Create file with just the filename (may work in some environments)
      final tempFile = File(fileName);
      await tempFile.writeAsBytes(data);
      return tempFile;
    } catch (e) {
      throw Exception('Cannot create temporary file: $e');
    }
  }

  // UPDATED: Simple method with user folder
  Future<String> uploadVideoToSupabaseSimple(
      String bucketName, Uint8List file, String fileName) async {
    try {
      // Get current user UID
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload video');
      }

      String extension = fileName.split('.').last;
      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      // Create path with user UID folder
      final String userFolderPath = '${user.uid}/$uniqueFileName';

      // Create temporary file first
      final tempFile = await _createTempFile(uniqueFileName, file);

      // Upload the File object with user folder path
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

  // Helper method to get video file from gallery (UNCHANGED)
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

  // Alternative: Get video as File instead of Uint8List (UNCHANGED)
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

  // UPDATED: Upload video from File with user folder
  Future<String> uploadVideoFileToSupabase(
      String bucketName, File videoFile, String fileName) async {
    try {
      // Get current user UID
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload video');
      }

      String extension = fileName.split('.').last;
      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      // Create path with user UID folder
      final String userFolderPath = '${user.uid}/$uniqueFileName';

      // Upload the File directly with user folder path
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

  // UPDATED: Delete video with user folder structure
  Future<void> deleteVideoFromSupabase(
      String bucketName, String fileName) async {
    try {
      // Get current user UID
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to delete video');
      }

      // Extract just the filename from the full path if needed
      String actualFileName = fileName;
      if (fileName.contains('/')) {
        actualFileName = fileName.split('/').last;
      }

      // Create the full path with user folder
      final String userFolderPath = '${user.uid}/$actualFileName';

      await _supabase.storage.from(bucketName).remove([userFolderPath]);
    } catch (e) {
      throw Exception('Failed to delete video from Supabase: $e');
    }
  }

  // UPDATED: Get signed URL with user folder structure
  Future<String> getSignedUrlForVideo(String bucketName, String fileName,
      {int expiresIn = 60}) async {
    try {
      // Get current user UID
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to get signed URL');
      }

      // Extract just the filename from the full path if needed
      String actualFileName = fileName;
      if (fileName.contains('/')) {
        actualFileName = fileName.split('/').last;
      }

      // Create the full path with user folder
      final String userFolderPath = '${user.uid}/$actualFileName';

      final String signedUrl = await _supabase.storage
          .from(bucketName)
          .createSignedUrl(userFolderPath, expiresIn);
      return signedUrl;
    } catch (e) {
      throw Exception('Failed to get signed URL: $e');
    }
  }

  // NEW: Helper method to extract filename from URL/path
  String _extractFileName(String path) {
    if (path.contains('/')) {
      return path.split('/').last;
    }
    return path;
  }

  // NEW: Method to get user's video folder path
  String getUserVideoFolderPath(String fileName) {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in');
    }
    final String uniqueFileName =
        '${const Uuid().v1()}.${fileName.split('.').last}';
    return '${user.uid}/$uniqueFileName';
  }

  // NEW: Method to list user's videos (optional - for future use)
  Future<List<String>> listUserVideos(String bucketName) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in');
      }

      final response =
          await _supabase.storage.from(bucketName).list(path: user.uid);

      // Return list of video file names
      return response
          .where((file) => _isVideoFile(file.name))
          .map((file) => file.name)
          .toList();
    } catch (e) {
      throw Exception('Failed to list user videos: $e');
    }
  }

  // NEW: Helper to check if file is a video
  bool _isVideoFile(String fileName) {
    final videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv'];
    final extension = fileName.split('.').last.toLowerCase();
    return videoExtensions.contains(extension);
  }
}
