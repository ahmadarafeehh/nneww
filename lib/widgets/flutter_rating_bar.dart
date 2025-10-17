// RatingBar widget with improved responsive design
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart'; // Add this import

class RatingBar extends StatefulWidget {
  final double initialRating;
  final ValueChanged<double>? onRatingUpdate;
  final ValueChanged<double> onRatingEnd;
  final bool hasRated;
  final double userRating;
  final bool isRating;
  final bool showSlider;
  final VoidCallback onEditRating;

  const RatingBar({
    Key? key,
    this.initialRating = 5.0,
    this.onRatingUpdate,
    required this.onRatingEnd,
    required this.hasRated,
    required this.userRating,
    required this.isRating,
    required this.showSlider,
    required this.onEditRating,
  }) : super(key: key);

  @override
  State<RatingBar> createState() => _RatingBarState();
}

class _RatingBarState extends State<RatingBar>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;
  late Animation<double> scale;
  late double _currentRating;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.initialRating;
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    scale = Tween<double>(begin: 1, end: 1.1).animate(controller);
  }

  @override
  void didUpdateWidget(covariant RatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasRated && widget.userRating != _currentRating) {
      setState(() {
        _currentRating = widget.userRating;
      });
    }
  }

  void _onRatingChanged(double newRating) {
    setState(() => _currentRating = newRating);
    widget.onRatingUpdate?.call(newRating);
    controller.forward().then((_) => controller.reverse());
  }

  void _onRatingEnd(double rating) {
    widget.onRatingEnd(rating);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  // Helper method to get the appropriate color scheme
  Color _getTextColor(ThemeProvider themeProvider) {
    return themeProvider.themeMode == ThemeMode.dark
        ? const Color(0xFFd9d9d9)
        : Colors.black;
  }

  Color _getBackgroundColor(ThemeProvider themeProvider) {
    return themeProvider.themeMode == ThemeMode.dark
        ? const Color(0xFF333333)
        : Colors.grey[300]!;
  }

  Color _getSliderActiveColor(ThemeProvider themeProvider) {
    return themeProvider.themeMode == ThemeMode.dark
        ? const Color(0xFFd9d9d9)
        : Colors.black;
  }

  Color _getSliderInactiveColor(ThemeProvider themeProvider) {
    return themeProvider.themeMode == ThemeMode.dark
        ? const Color(0xFF333333)
        : Colors.grey[400]!;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final textColor = _getTextColor(themeProvider);
    final backgroundColor = _getBackgroundColor(themeProvider);
    final sliderActiveColor = _getSliderActiveColor(themeProvider);
    final sliderInactiveColor = _getSliderInactiveColor(themeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.showSlider && widget.hasRated)
          Center(
            child: widget.isRating
                ? CircularProgressIndicator(color: textColor)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Calculate responsive button width
                      double buttonWidth = constraints.maxWidth * 0.7;
                      buttonWidth = buttonWidth.clamp(250.0, 300.0);

                      return Container(
                        width: buttonWidth,
                        height: 50.0, // Fixed height
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        // In the RatingBar widget, find the ElevatedButton and update its style:
                        child: ElevatedButton(
                          onPressed: widget.onEditRating,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.black54, // Change this to transparent
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            minimumSize: const Size(100, 40),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'You rated: ${widget.userRating.toStringAsFixed(1)}, change it?',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        if (widget.showSlider)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Slider(
              value: _currentRating,
              min: 1,
              max: 10,
              divisions: 100,
              label: _currentRating.toStringAsFixed(1),
              activeColor: sliderActiveColor,
              inactiveColor: sliderInactiveColor,
              onChanged: _onRatingChanged,
              onChangeEnd: _onRatingEnd,
            ),
          ),
      ],
    );
  }
}
