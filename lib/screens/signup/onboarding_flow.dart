import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/screens/login.dart';
import 'package:Ratedly/screens/signup/age_screen.dart';
import 'package:Ratedly/screens/signup/verify_email_screen.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';

class OnboardingFlow extends StatefulWidget {
  final VoidCallback onComplete;
  final Function(dynamic) onError;

  const OnboardingFlow({
    Key? key,
    required this.onComplete,
    required this.onError,
  }) : super(key: key);

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _supabase = Supabase.instance.client;
  final _auth = FirebaseAuth.instance;

  // Remove loading state and use immediate decisions
  Map<String, dynamic>? _userData;
  bool _emailVerified = true; // Assume verified until proven otherwise
  bool _hasCheckedUser = false;

  // Simple cache for user data to avoid repeated queries
  static Map<String, Map<String, dynamic>> _userCache = {};

  @override
  void initState() {
    super.initState();
    _startImmediateChecks();
  }

  void _startImmediateChecks() {
    final user = _auth.currentUser;
    if (user == null) return;

    // Check email verification immediately (synchronous)
    _emailVerified = user.emailVerified;

    // Try cache first for instant response
    final cachedUser = _userCache[user.uid];
    if (cachedUser != null) {
      if (mounted) {
        setState(() {
          _userData = cachedUser;
          _hasCheckedUser = true;
        });

        // Immediately complete if onboarding is done
        if (cachedUser['onboardingComplete'] == true) {
          widget.onComplete();
        }
      }
      return;
    }

    // If no cache, start async check but don't wait for it
    _loadUserDataInBackground();
  }

  Future<void> _loadUserDataInBackground() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final response = await _supabase
          .from('users')
          .select()
          .eq('uid', user.uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 5)); // Reduced timeout

      if (mounted) {
        setState(() {
          _userData = response;
          _hasCheckedUser = true;
        });

        // Cache the result for future use
        _userCache[user.uid] = response ?? {};

        // If onboarding is complete, notify immediately
        if (response != null && response['onboardingComplete'] == true) {
          widget.onComplete();
        }
      }
    } catch (e) {
      if (e is PostgrestException && e.code == 'PGRST116') {
        // No user found - cache empty result
        final user = _auth.currentUser;
        if (user != null) {
          _userCache[user.uid] = {};
        }

        if (mounted) {
          setState(() {
            _userData = null;
            _hasCheckedUser = true;
          });
        }
      } else {
        // For other errors, still mark as checked to avoid infinite loading
        if (mounted) {
          setState(() {
            _hasCheckedUser = true;
          });
        }
        widget.onError(e);
      }
    }
  }

  // Fast skeleton that shows immediately
  Widget _buildOnboardingSkeleton(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    final skeletonColor = isDarkMode
        ? const Color(0xFF333333).withOpacity(0.6)
        : Colors.grey[300]!.withOpacity(0.6);
    final backgroundColor =
        isDarkMode ? const Color(0xFF121212) : Colors.grey[100]!;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: skeletonColor,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) return const LoginScreen();

    // Show skeleton only briefly while we check user data
    if (!_hasCheckedUser) {
      return _buildOnboardingSkeleton(context);
    }

    // Email not verified - show immediately
    if (!_emailVerified) {
      return VerifyEmailScreen(
        onVerified: () {
          // Update email verification status and reload
          if (mounted) {
            setState(() {
              _emailVerified = true;
            });
          }
          _loadUserDataInBackground();
        },
      );
    }

    // User exists in Supabase and onboarding is complete
    if (_userData != null && _userData!['onboardingComplete'] == true) {
      // Ensure we notify about completion
      widget.onComplete();
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    // Show age verification immediately - don't wait for anything
    return AgeVerificationScreen(
      onComplete: () async {
        try {
          final user = _auth.currentUser;
          if (user == null) return;

          // Create user record without waiting
          _supabase.from('users').upsert({
            'uid': user.uid,
            'email': user.email,
            'createdAt': DateTime.now().toIso8601String(),
            'onboardingComplete': true, // Mark as complete immediately
          }).then((_) {
            // Cache the result
            _userCache[user.uid] = {
              'uid': user.uid,
              'email': user.email,
              'onboardingComplete': true,
            };

            // Notify completion
            widget.onComplete();
          }).catchError((e) {
            // Even if Supabase fails, still proceed to avoid blocking user
            widget.onComplete();
          });
        } catch (e) {
          // If anything fails, still complete onboarding to avoid blocking user
          widget.onComplete();
        }
      },
    );
  }
}
