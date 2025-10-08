import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageMethods {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  // Upload image to Firebase Storage
  Future<String> uploadImageToStorage(
      String childName, Uint8List file, bool isPost,
      {String contentType = 'image/jpeg'}) async {
    try {
      // 1. Create a reference in Firebase Storage
      Reference ref =
          _storage.ref().child(childName).child(_auth.currentUser!.uid);
      if (isPost) {
        String id = const Uuid().v1();
        ref = ref.child(id);
      }

      // 2. Set metadata dynamically based on contentType
      final metadata = SettableMetadata(contentType: contentType);

      // 3. Upload the file with metadata
      UploadTask uploadTask = ref.putData(file, metadata);

      // 4. Await the completion of the upload
      TaskSnapshot snapshot = await uploadTask;

      // 5. Poll for the thumbnail, up to a maximum number of retries
      final parentRef = snapshot.ref.parent!;
      final thumbRef = parentRef.child('${snapshot.ref.name}_1024x1024');

      String? downloadUrl;
      int retries = 0;
      const int maxRetries = 10;

      while (retries < maxRetries) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          downloadUrl = await thumbRef.getDownloadURL();
          break; // success!
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

  // Delete an image from Firebase Storage given its download URL.
  Future<void> deleteImage(String imageUrl) async {
    try {
      // Validate the URL format
      if (!imageUrl.startsWith('gs://') &&
          !imageUrl.contains('firebasestorage.googleapis.com')) {
        throw Exception('Invalid Firebase Storage URL: $imageUrl');
      }

      Reference ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      rethrow; // Propagate the error to the caller
    }
  }

  // Upload video to Supabase Storage
  Future<String> uploadVideoToSupabase(
      String bucketName, Uint8List file, String fileName,
      {bool isPublic = true}) async {
    try {
      // Generate a unique file name if needed
      final String uniqueFileName = '${const Uuid().v1()}_$fileName';

      // Upload the video to Supabase storage
      await _supabase.storage.from(bucketName).uploadBinary(
          uniqueFileName, file,
          fileOptions: FileOptions(upsert: true));

      // Get the public URL for the uploaded video
      final String publicUrl =
          _supabase.storage.from(bucketName).getPublicUrl(uniqueFileName);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload video to Supabase: $e');
    }
  }

  // Delete a video from Supabase Storage
  Future<void> deleteVideoFromSupabase(
      String bucketName, String fileName) async {
    try {
      await _supabase.storage.from(bucketName).remove([fileName]);
    } catch (e) {
      throw Exception('Failed to delete video from Supabase: $e');
    }
  }

  // Get a signed URL for private videos (if needed)
  Future<String> getSignedUrlForVideo(String bucketName, String fileName,
      {int expiresIn = 60}) async {
    try {
      final String signedUrl = await _supabase.storage
          .from(bucketName)
          .createSignedUrl(fileName, expiresIn);

      return signedUrl;
    } catch (e) {
      throw Exception('Failed to get signed URL: $e');
    }
  }
}
