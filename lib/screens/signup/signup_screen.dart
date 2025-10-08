import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:Ratedly/resources/auth_methods.dart';
import 'package:Ratedly/screens/login.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/widgets/text_filed_input.dart';
import 'package:Ratedly/screens/signup/auth_wrapper.dart';
import 'package:Ratedly/screens/terms_of_service_screen.dart';
import 'package:Ratedly/screens/privacy_policy_screen.dart';
import 'dart:io';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    super.dispose();
    _emailController.dispose();
  }

  void signUpWithGoogle() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    String res = await AuthMethods().signInWithGoogle();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (res == "success") {
      if (mounted) {
        // replace entire stack with AuthWrapper
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    } else if (res == "onboarding_required") {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
        );
      }
    } else if (res == "cancelled") {
      if (mounted) showSnackBar(context, 'Google sign-in cancelled');
    } else {
      if (mounted) showSnackBar(context, res);
    }
  }

  // Add this Apple sign-in method
  void signUpWithApple() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    String res = await AuthMethods().signInWithApple();
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res == "success" || res == "onboarding_required") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
      );
    } else if (res == "cancelled") {
      showSnackBar(context, 'Apple sign-in cancelled');
    } else {
      showSnackBar(context, res);
    }
  }

  void navigateToPasswordScreen() {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      showSnackBar(context, "Please enter your email");
      return;
    }

    if (!email.contains("@") || !email.contains(".")) {
      showSnackBar(context, "Please enter a valid email address");
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PasswordSignupScreen(email: email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset(
                'assets/logo/22.png',
                width: 100,
                height: 100,
              ),
              const SizedBox(height: 8),
              const Text(
                'Create your account',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Montserrat',
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),
              TextFieldInput(
                hintText: 'Enter your email',
                textInputType: TextInputType.emailAddress,
                textEditingController: _emailController,
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontFamily: 'Inter',
                ),
                fillColor: const Color(0xFF333333),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: navigateToPasswordScreen,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF333333),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Inter',
                  ),
                ),
              ),

              const SizedBox(height: 24),
              // Separator with OR
              Row(
                children: [
                  const Expanded(
                    child: Divider(
                      color: Colors.grey,
                      thickness: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Divider(
                      color: Colors.grey,
                      thickness: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Google Signup Button
              ElevatedButton.icon(
                onPressed: signUpWithGoogle,
                icon: Container(
                  width: 29,
                  height: 29,
                  alignment: Alignment.center,
                  child: Image.asset(
                    'assets/logo/google-logo.png',
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                  ),
                ),
                label: const Text(
                  'Sign up with Google',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF333333),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Conditionally show Apple Signup Button only on non-Android platforms
              if (!Platform.isAndroid)
                ElevatedButton.icon(
                  onPressed: signUpWithApple,
                  icon: Container(
                    width: 29,
                    height: 29,
                    alignment: Alignment.center,
                    child: Image.asset(
                      'assets/logo/apple-logo.png',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      color: Colors.white,
                    ),
                  ),
                  label: const Text(
                    'Sign up with Apple',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF333333),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              if (!Platform.isAndroid) const SizedBox(height: 16),

              // Terms and Privacy Policy
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontFamily: 'Inter',
                      fontSize: 14,
                    ),
                    children: [
                      const TextSpan(text: 'By signing in, you agree to our '),
                      TextSpan(
                        text: 'Terms',
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const TermsOfServiceScreen(),
                              ),
                            );
                          },
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const PrivacyPolicyScreen(),
                              ),
                            );
                          },
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
              // Login prompt
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                ),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontFamily: 'Inter',
                      fontSize: 14,
                    ),
                    children: [
                      const TextSpan(text: 'Already have an account? '),
                      TextSpan(
                        text: 'Log in',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const LoginScreen()),
                            );
                          },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PasswordSignupScreen extends StatefulWidget {
  final String email;

  const PasswordSignupScreen({Key? key, required this.email}) : super(key: key);

  @override
  State<PasswordSignupScreen> createState() => _PasswordSignupScreenState();
}

class _PasswordSignupScreenState extends State<PasswordSignupScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmationController =
      TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    super.dispose();
    _passwordController.dispose();
    _passwordConfirmationController.dispose();
  }

  void signUpUser() async {
    if (_passwordController.text != _passwordConfirmationController.text) {
      showSnackBar(context, "Passwords don't match");
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    String res = await AuthMethods().signUpUser(
      email: widget.email,
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res == "success") {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
        );
      }
    } else {
      if (mounted) showSnackBar(context, "Signup failed. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create your account',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFamily: 'Montserrat',
            height: 1.3,
          ),
          textAlign: TextAlign.center,
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset(
                'assets/logo/22.png',
                width: 100,
                height: 100,
              ),
              const SizedBox(height: 8),
              const Text(
                'Create your account',
                style: TextStyle(
                  color: Color(0xFFd9d9d9),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Montserrat',
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Password
              TextFieldInput(
                hintText: 'Enter your password',
                textInputType: TextInputType.text,
                textEditingController: _passwordController,
                isPass: true,
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontFamily: 'Inter',
                ),
                fillColor: const Color(0xFF333333),
              ),
              const SizedBox(height: 24),

              // Confirm Password
              TextFieldInput(
                hintText: 'Confirm your password',
                textInputType: TextInputType.text,
                textEditingController: _passwordConfirmationController,
                isPass: true,
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontFamily: 'Inter',
                ),
                fillColor: const Color(0xFF333333),
              ),

              const SizedBox(height: 24),

              // Sign Up Button
              ElevatedButton(
                onPressed: signUpUser,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF333333),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      )
                    : const Text(
                        'Sign Up',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Inter',
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
