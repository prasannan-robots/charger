import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../google_api.dart';

class SelectedPlace {
  const SelectedPlace(this.label, this.position);
  final String label;
  final LatLng position;
}

/// A text field that suggests places as you type and reports the coordinates
/// of the suggestion the user picks.
class PlaceField extends StatefulWidget {
  const PlaceField({
    super.key,
    required this.api,
    required this.label,
    required this.icon,
    required this.onChanged,
    this.hint,
    this.near,
  });

  final GoogleMapsApi api;
  final String label;
  final String? hint;
  final IconData icon;

  /// Biases suggestions towards this point (usually the user's location).
  final LatLng? near;

  /// Called with the chosen place, or `null` once the text is edited again.
  final ValueChanged<SelectedPlace?> onChanged;

  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String? _sessionToken;
  int _latestRequest = 0;
  List<PlaceSuggestion> _suggestions = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _suggestions.isNotEmpty) {
        setState(() => _suggestions = const []);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    widget.onChanged(null);
    _debounce?.cancel();
    _latestRequest++;
    if (text.trim().length < 3) {
      setState(() {
        _suggestions = const [];
        _busy = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(text.trim()),
    );
  }

  Future<void> _search(String text) async {
    final request = ++_latestRequest;
    final token = _sessionToken ??= GoogleMapsApi.newSessionToken();
    setState(() => _busy = true);
    try {
      final results = await widget.api
          .autocomplete(text, sessionToken: token, near: widget.near);
      if (!mounted || request != _latestRequest) return;
      setState(() => _suggestions = results.take(5).toList());
    } on Exception catch (e) {
      if (!mounted || request != _latestRequest) return;
      setState(() => _suggestions = const []);
      _showError('Search failed: $e');
    } finally {
      if (mounted && request == _latestRequest) setState(() => _busy = false);
    }
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    _debounce?.cancel();
    final request = ++_latestRequest;
    // The details lookup closes the billing session started by autocomplete.
    final token = _sessionToken;
    _sessionToken = null;
    _controller.text = suggestion.fullText;
    _focus.unfocus();
    setState(() {
      _suggestions = const [];
      _busy = true;
    });
    try {
      final position = await widget.api
          .placeLocation(suggestion.placeId, sessionToken: token);
      if (!mounted || request != _latestRequest) return;
      widget.onChanged(SelectedPlace(suggestion.primaryText, position));
    } on Exception catch (e) {
      if (mounted) _showError('Could not load that place: $e');
    } finally {
      if (mounted && request == _latestRequest) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          onChanged: _onTextChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            floatingLabelBehavior: widget.hint == null
                ? FloatingLabelBehavior.auto
                : FloatingLabelBehavior.always,
            prefixIcon: Icon(widget.icon),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: _busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : ValueListenableBuilder(
                    valueListenable: _controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _controller.clear();
                              _onTextChanged('');
                            },
                          ),
                  ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          // Taps inside this region count as "inside" the text field, so the
          // field keeps focus (and the list stays) until a tile is tapped.
          TextFieldTapRegion(
            child: Card(
              margin: const EdgeInsets.only(top: 4),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final s in _suggestions)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(
                        s.primaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: s.secondaryText.isEmpty
                          ? null
                          : Text(
                              s.secondaryText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => _select(s),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
