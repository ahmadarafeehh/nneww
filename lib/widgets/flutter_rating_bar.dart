// RatingBar widget with improved responsive design and performance optimizations
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';

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
  late AnimationController _controller;
  late Animation<double> _scale;
  late double _currentRating;

  // Cache theme colors to avoid recalculating every build
  Color? _cachedTextColor;
  Color? _cachedBackgroundColor;
  Color? _cachedSliderActiveColor;
  Color? _cachedSliderInactiveColor;
  ThemeProvider? _lastThemeProvider;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.initialRating;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1, end: 1.1).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant RatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if slider just became visible (user pressed "change it?")
    final bool sliderJustAppeared = widget.showSlider && !oldWidget.showSlider;

    // FIXED: Only update _currentRating when slider appears AND we don't already have a current rating
    // OR when the initial rating changes significantly
    if (sliderJustAppeared) {
      // Only update if the current rating is significantly different from the new user rating
      // or if we're resetting from a completed rating
      if ((_currentRating - widget.userRating).abs() > 0.1 ||
          _currentRating == oldWidget.initialRating) {
        _currentRating = widget.userRating;
      } else {}
    }

    // Also update when userRating changes while slider is visible and we want to sync
    if (widget.hasRated &&
        widget.userRating != _currentRating &&
        widget.showSlider &&
        !sliderJustAppeared) {
      _currentRating = widget.userRating;
    }
  }

  void _onRatingChanged(double newRating) {
    setState(() => _currentRating = newRating);
    widget.onRatingUpdate?.call(newRating);
    _controller.forward().then((_) => _controller.reverse());
  }

  void _onRatingEnd(double rating) {
    widget.onRatingEnd(rating);
  }

  // Cache theme colors to avoid recalculating every build
  void _updateCachedColors(ThemeProvider themeProvider) {
    if (_lastThemeProvider != themeProvider) {
      _lastThemeProvider = themeProvider;
      final isDarkMode = themeProvider.themeMode == ThemeMode.dark;

      _cachedTextColor = isDarkMode ? const Color(0xFFd9d9d9) : Colors.black;
      _cachedBackgroundColor =
          isDarkMode ? const Color(0xFF333333) : Colors.grey[300]!;
      _cachedSliderActiveColor =
          isDarkMode ? const Color(0xFFd9d9d9) : Colors.black;
      _cachedSliderInactiveColor =
          isDarkMode ? const Color(0xFF333333) : Colors.grey[400]!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildRatingButton(ThemeProvider themeProvider) {
    return widget.isRating
        ? const CircularProgressIndicator()
        : LayoutBuilder(
            builder: (context, constraints) {
              // Calculate responsive button width with constraints
              final double buttonWidth =
                  (constraints.maxWidth * 0.7).clamp(250.0, 300.0);

              return Container(
                width: buttonWidth,
                height: 50.0,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: ElevatedButton(
                  onPressed: () {
                    widget.onEditRating();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black54,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: const Size(100, 40),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'You rated: ${widget.userRating.toStringAsFixed(1)}, change it?',
                      style: const TextStyle(
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
          );
  }

  Widget _buildRatingSlider(ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Slider(
        value: _currentRating,
        min: 1,
        max: 10,
        divisions: 100,
        label: _currentRating.toStringAsFixed(1),
        activeColor: _cachedSliderActiveColor,
        inactiveColor: _cachedSliderInactiveColor,
        onChanged: _onRatingChanged,
        onChangeEnd: _onRatingEnd,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    // Update cached colors if theme changed
    _updateCachedColors(themeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.showSlider && widget.hasRated)
          Center(
            child: _buildRatingButton(themeProvider),
          ),
        if (widget.showSlider) _buildRatingSlider(themeProvider),
      ],
    );
  }
}
