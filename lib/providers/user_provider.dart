// lib/providers/user_provider.dart
import 'package:flutter/widgets.dart';
import 'package:Ratedly/models/user.dart';
import 'package:Ratedly/resources/auth_methods.dart';

class UserProvider with ChangeNotifier {
  AppUser? _user;
  final AuthMethods _authMethods = AuthMethods();

  AppUser? get user => _user;

  Future<void> refreshUser() async {
    try {
      final AppUser? fetchedUser = await _authMethods.getUserDetails();

      if (fetchedUser == null) {
        // No logged-in user or no DB row found
        _user = null;
        notifyListeners();
        return;
      }

      // Run follower/following/request queries in parallel for speed
      final results = await Future.wait([
        _authMethods.getUserFollowers(fetchedUser.uid),
        _authMethods.getUserFollowing(fetchedUser.uid),
        _authMethods.getFollowRequests(fetchedUser.uid),
      ]);

      final List<String> followers = results[0] as List<String>;
      final List<String> following = results[1] as List<String>;
      final List<String> requests = results[2] as List<String>;

      _user = fetchedUser.withRelationships(
        followers: followers,
        following: following,
        followRequests: requests,
      );
    } catch (e) {
      // On error, clear user (you can also log the error)
      _user = null;
    }

    notifyListeners();
  }

  String? get safeUID => _user?.uid;
}
