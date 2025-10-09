import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/screens/login.dart';
import 'package:Ratedly/screens/signup/age_screen.dart';
import 'package:Ratedly/screens/signup/verify_email_screen.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';

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
  bool _isLoading = true;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final response = await _supabase
          .from('users')
          .select()
          .eq('uid', user.uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      setState(() {
        _userData = response;
        _isLoading = false;
      });

// If onboarding is complete, notify immediately
      if (_userData?['onboardingComplete'] == true) {
        widget.onComplete();
      }
    } catch (e) {
      if (e is PostgrestException && e.code == 'PGRST116') {
// No user found in Supabase
        setState(() {
          _userData = null;
          _isLoading = false;
        });
      } else {
        widget.onError(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) return const LoginScreen();

// Loading state
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

// Email not verified
    if (!user.emailVerified) {
      return VerifyEmailScreen(
        onVerified: () => _loadUserData(),
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

// Show age verification screen
    // In OnboardingFlow - FIXED
    return AgeVerificationScreen(
      onComplete: () async {
        try {
          // Only create basic user record, DON'T set onboardingComplete
          await _supabase.from('users').upsert({
            'uid': user.uid,
            'email': user.email,
            'createdAt': DateTime.now().toIso8601String(),
            // REMOVED: 'onboardingComplete': true
          });

          // REMOVED: widget.onComplete() - don't notify completion here
        } catch (e) {
          widget.onError(e);
        }
      },
    );
  }
}
