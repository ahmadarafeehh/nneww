// lib/resources/auth_methods.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:Ratedly/resources/storage_methods.dart';
import 'package:Ratedly/models/user.dart';

class AuthMethods {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  final SupabaseClient _supabase = Supabase.instance.client;

  // Nonce helpers for Apple sign-in
  String _generateRawNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ----------------------
  // Generic helper to normalise various supabase returns
  // ----------------------
  static dynamic _unwrapSupabaseResponse(dynamic res) {
    // If library returns a PostgrestResponse-like object (older/newer clients vary),
    // try to get .data if present.
    try {
      if (res == null) return null;
      // If res has 'data' getter (PostgrestResponse), use it
      final data = (res is Map && res.containsKey('data')) ? res['data'] : null;
      if (data != null) return data;
    } catch (_) {}
    // Otherwise return res as-is (likely List or Map)
    return res;
  }

  // ----------------------
  // User relational queries (Supabase)
  // ----------------------
  Future<List<String>> getUserFollowers(String uid) async {
    try {
      final dynamic res = await _supabase
          .from('user_followers')
          .select('follower_id')
          .eq('user_id', uid);

      final dynamic data = _unwrapSupabaseResponse(res) ?? res;

      if (data is List) {
        return data
            .map<String>(
                (e) => (e['follower_id'] ?? e['followerId'])?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (data is Map) {
        // single row returned
        final id = (data['follower_id'] ?? data['followerId'])?.toString();
        return id != null ? [id] : [];
      } else {
        return [];
      }
    } catch (e) {
      // optionally log
      return [];
    }
  }

  Future<List<String>> getUserFollowing(String uid) async {
    try {
      final dynamic res = await _supabase
          .from('user_following')
          .select('following_id')
          .eq('user_id', uid);

      final dynamic data = _unwrapSupabaseResponse(res) ?? res;

      if (data is List) {
        return data
            .map<String>((e) =>
                (e['following_id'] ?? e['followingId'])?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (data is Map) {
        final id = (data['following_id'] ?? data['followingId'])?.toString();
        return id != null ? [id] : [];
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> getFollowRequests(String uid) async {
    try {
      final dynamic res = await _supabase
          .from('user_follow_request')
          .select('requester_id')
          .eq('user_id', uid);

      final dynamic data = _unwrapSupabaseResponse(res) ?? res;

      if (data is List) {
        return data
            .map<String>((e) =>
                (e['requester_id'] ?? e['requesterId'])?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (data is Map) {
        final id = (data['requester_id'] ?? data['requesterId'])?.toString();
        return id != null ? [id] : [];
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // ----------------------
  // Get user details (from Supabase, based on Firebase UID)
  // ----------------------
  Future<AppUser?> getUserDetails() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      // ✅ Use .select().eq() and handle single record
      final data = await _supabase
          .from('users')
          .select()
          .eq('uid', user.uid) // Match primary key
          .single(); // Throw if not exactly 1 record

      return AppUser.fromMap(data);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        // No results
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ----------------------
  // Email/password signup (Firebase Auth)
  // ----------------------
  Future<String> signUpUser({
    required String email,
    required String password,
  }) async {
    try {
      if (email.isEmpty || password.isEmpty) {
        return "Please fill all required fields";
      }

      final firebase_auth.UserCredential cred =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (cred.user == null) {
        return "Registration failed - please try again";
      }

      await cred.user!.sendEmailVerification();

      // create an initial row in Supabase users table
      try {
        await _supabase.from('users').upsert({
          'uid': cred.user!.uid,
          'email': cred.user!.email,
          'username': '',
          'bio': '',
          'photoUrl': 'default',
          'isPrivate': false,
          'onboardingComplete': false,
          'createdAt': DateTime.now().toIso8601String(),
        });
      } catch (_) {
        // ignore DB errors for now (auth succeeded)
      }

      return "success";
    } on firebase_auth.FirebaseAuthException catch (e) {
      return e.message ?? "Registration failed";
    } catch (err) {
      return err.toString();
    }
  }

  // ----------------------
  // Complete profile (replace Firestore writes with Supabase upsert)
  // ----------------------
  Future<String> completeProfile({
    required String username,
    required String bio,
    Uint8List? file,
    bool isPrivate = false,
    required DateTime dateOfBirth,
    required String gender,
  }) async {
    try {
      final firebase_auth.User? user = _auth.currentUser;
      if (user == null) return "User not authenticated";

      await user.reload();
      if (!user.emailVerified) return "Email not verified";

      final processedUsername = username.trim();

      if (processedUsername.isEmpty) return "Username cannot be empty";
      if (processedUsername.length < 3)
        return "Username must be at least 3 characters";
      if (processedUsername.length > 20)
        return "Username cannot exceed 20 characters";
      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(processedUsername)) {
        return "Username can only contain letters, numbers, and underscores";
      }

      // Check username uniqueness in Supabase
      final dynamic usernameRes = await _supabase
          .from('users')
          .select('uid')
          .eq('username', processedUsername)
          .limit(1);

      final dynamic usernameData =
          _unwrapSupabaseResponse(usernameRes) ?? usernameRes;

      if (usernameData is List && usernameData.isNotEmpty) {
        return "Username '$processedUsername' is already taken";
      }
      if (usernameData is Map && usernameData.isNotEmpty) {
        // found a matching row
        return "Username '$processedUsername' is already taken";
      }

      String photoUrl = 'default';
      if (file != null) {
        photoUrl = await StorageMethods()
            .uploadImageToStorage('profilePics', file, false);
      }

      final payload = {
        'uid': user.uid,
        'email': user.email,
        'username': processedUsername,
        'bio': bio,
        'photoUrl': photoUrl,
        'isPrivate': isPrivate,
        'onboardingComplete': true,
        'createdAt': DateTime.now().toIso8601String(),
        'dateOfBirth': dateOfBirth.toIso8601String(),
        'gender': gender,
      };

      try {
        await _supabase.from('users').upsert(payload);
      } catch (e) {
        return "Failed to save profile";
      }

      return "success";
    } on Exception catch (e) {
      return e.toString();
    }
  }

  // ----------------------
  // Login - keep using Firebase Auth, then check supabase row
  // ----------------------
  Future<String> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      final firebase_auth.UserCredential cred = await _auth
          .signInWithEmailAndPassword(email: email, password: password);

      // Check if user exists in Supabase -> if not, require onboarding
      final dynamic res = await _supabase
          .from('users')
          .select()
          .eq('uid', cred.user!.uid)
          .maybeSingle();

      final dynamic data = _unwrapSupabaseResponse(res) ?? res;

      if (data == null) return "onboarding_required";
      if (data is Map || (data is List && data.isNotEmpty)) return "success";
      return "onboarding_required";
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'invalid-email') {
        return "Please enter a valid email address";
      } else if (e.code == 'wrong-password' || e.code == 'user-not-found') {
        return "Incorrect email or password";
      } else if (e.code == 'user-disabled') {
        return "Account disabled";
      } else if (e.code == 'too-many-requests') {
        return "Too many attempts. Try again later";
      } else {
        return "Incorrect email or password";
      }
    } catch (e) {
      return "An unexpected error occurred";
    }
  }

  // ----------------------
  // Sign out
  // ----------------------
  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  // ----------------------
  // Helper to make firebase auth error messages readable
  // ----------------------
  String _handleFirebaseAuthError(firebase_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        return 'Email already linked with another method';
      case 'invalid-credential':
        return 'Invalid Google credentials';
      case 'operation-not-allowed':
        return 'Google sign-in is disabled';
      case 'user-disabled':
        return 'User account disabled';
      case 'operation-not-supported':
        return 'Apple sign-in is not enabled';
      case 'user-not-found':
        return 'User not found';
      default:
        return 'Authentication failed: ${e.message}';
    }
  }

  // ----------------------
  // Re-auth helper / current credential
  // ----------------------
  Future<firebase_auth.AuthCredential?> getCurrentUserCredential() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final providerId = user.providerData.isNotEmpty
        ? user.providerData.first.providerId
        : null;

    if (providerId == 'google.com') {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null;
      final googleAuth = await googleUser.authentication;

      return firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
    } else if (providerId == 'password') {
      throw firebase_auth.FirebaseAuthException(
        code: 'requires-email-password-re-auth',
        message: 'Re-authenticate with email and password.',
      );
    } else {
      throw firebase_auth.FirebaseAuthException(
        code: 'unsupported-provider',
        message: 'Unsupported provider: $providerId',
      );
    }
  }

  // ----------------------
  // Google sign-in (Firebase auth) + ensure Supabase user row
  // ----------------------
  Future<String> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return "cancelled";

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final firebase_auth.OAuthCredential credential =
          firebase_auth.GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      final firebase_auth.UserCredential cred =
          await _auth.signInWithCredential(credential);

      // Check or create Supabase user row
      final dynamic res = await _supabase
          .from('users')
          .select()
          .eq('uid', cred.user!.uid)
          .maybeSingle();

      final dynamic data = _unwrapSupabaseResponse(res) ?? res;

      if (data == null) {
        // create minimal row
        await _supabase.from('users').insert({
          'uid': cred.user!.uid,
          'email': cred.user!.email,
          'username': '',
          'bio': '',
          'photoUrl': cred.user!.photoURL ?? 'default',
          'isPrivate': false,
          'onboardingComplete': false,
          'createdAt': DateTime.now().toIso8601String(),
          'dateOfBirth': DateTime(2000, 1, 1).toIso8601String(),
          'gender': ''
        });
        return "onboarding_required";
      }

      return "success";
    } on firebase_auth.FirebaseAuthException catch (e) {
      return _handleFirebaseAuthError(e);
    } catch (e) {
      return "Google sign-in failed: ${e.toString()}";
    }
  }

  // ----------------------
  // Apple sign-in (Firebase auth) + Supabase row + logging
  // ----------------------
  Future<String> signInWithApple() async {
    String? rawNonce;
    String? hashedNonce;
    String? identityToken;

    try {
      rawNonce = _generateRawNonce();
      hashedNonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
        nonce: hashedNonce,
      );

      identityToken = appleCredential.identityToken;

      final oauthProvider = firebase_auth.OAuthProvider('apple.com');
      final oauthCredential = oauthProvider.credential(
        idToken: identityToken,
        accessToken: appleCredential.authorizationCode,
        rawNonce: rawNonce, // <- required for Firebase to verify nonce
      );

      final firebase_auth.UserCredential userCredential =
          await _auth.signInWithCredential(oauthCredential);

      final dynamic res = await _supabase
          .from('users')
          .select()
          .eq('uid', userCredential.user!.uid)
          .maybeSingle();

      final dynamic data = _unwrapSupabaseResponse(res) ?? res;

      if (data == null) {
        await _supabase.from('users').insert({
          'uid': userCredential.user!.uid,
          'email': appleCredential.email ?? userCredential.user!.email ?? "",
          'username': "",
          'bio': "",
          'photoUrl': 'default',
          'isPrivate': false,
          'onboardingComplete': false,
          'createdAt': DateTime.now().toIso8601String(),
          'dateOfBirth': DateTime(2000, 1, 1).toIso8601String(),
          'gender': '',
        });
        return "onboarding_required";
      }

      return "success";
    } on SignInWithAppleAuthorizationException catch (e) {
      return e.code == AuthorizationErrorCode.canceled
          ? "cancelled"
          : "Apple sign-in failed: ${e.message}";
    } on firebase_auth.FirebaseAuthException catch (e) {
      return _handleFirebaseAuthError(e);
    } catch (e, st) {
      return "Unexpected error: ${e.toString()}";
    }
  }
}
