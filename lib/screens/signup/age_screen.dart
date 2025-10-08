import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:Ratedly/screens/signup/profile_setup_screen.dart';

class AgeVerificationScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const AgeVerificationScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<AgeVerificationScreen> createState() => _AgeVerificationScreenState();
}

class _AgeVerificationScreenState extends State<AgeVerificationScreen> {
  DateTime _selectedDate = DateTime(DateTime.now().year - 20, 1, 1);

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
              const SizedBox(height: 20),
              const Text(
                'What is your date of birth?',
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
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(12),
                ),
                height: 200,
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    brightness: Brightness.dark,
                  ),
                  child: CupertinoDatePicker(
                    backgroundColor: const Color(0xFF333333),
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: _selectedDate,
                    maximumDate: DateTime.now(),
                    minimumYear: DateTime.now().year - 100,
                    maximumYear: DateTime.now().year,
                    onDateTimeChanged: (DateTime newDate) {
                      setState(() => _selectedDate = newDate);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF333333),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () {
                  widget.onComplete();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (c) =>
                          ProfileSetupScreen(dateOfBirth: _selectedDate),
                    ),
                  );
                },
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
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
