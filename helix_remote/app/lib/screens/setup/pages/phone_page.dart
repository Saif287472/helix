import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/data/countries.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The phone number: a country button and the number, the way every sign-in
/// asks for it.
class PhoneFields extends StatefulWidget {
  const PhoneFields({
    super.key,
    required this.countryCode,
    required this.phoneNumber,
    required this.enabled,
    required this.onCountryCodeChanged,
    required this.onPhoneChanged,
    required this.onSubmit,
  });

  final String countryCode;
  final String phoneNumber;
  final bool enabled;
  final ValueChanged<String> onCountryCodeChanged;
  final ValueChanged<String> onPhoneChanged;
  final VoidCallback onSubmit;

  @override
  State<PhoneFields> createState() => _PhoneFieldsState();
}

class _PhoneFieldsState extends State<PhoneFields> {
  late final TextEditingController _controller;
  late Country _country;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.phoneNumber);
    _country = _countryFor(widget.countryCode);
  }

  @override
  void didUpdateWidget(PhoneFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phoneNumber != _controller.text) {
      _controller.text = widget.phoneNumber;
    }
    if (widget.countryCode != _country.normalizedDialCode) {
      _country = _countryFor(widget.countryCode);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static Country _countryFor(String dialCode) => kCountries.firstWhere(
    (c) => c.normalizedDialCode == dialCode && c.isoCode == 'BD',
    orElse: () => kCountries.firstWhere(
      (c) => c.normalizedDialCode == dialCode,
      orElse: () => kCountries.firstWhere((c) => c.isoCode == 'BD'),
    ),
  );

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CountrySheet(),
    );
    if (picked == null || !mounted) return;
    setState(() => _country = picked);
    widget.onCountryCodeChanged(picked.normalizedDialCode);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 56,
          child: OutlinedButton(
            onPressed: widget.enabled ? _pickCountry : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              side: BorderSide(color: scheme.outline),
              foregroundColor: scheme.onSurface,
            ),
            child: Semantics(
              label: 'Country: ${_country.name} ${_country.dialCode}',
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _country.flagEmoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 6),
                  Text(_country.dialCode),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: HelixSpace.xs),
        Expanded(
          child: TextField(
            key: const ValueKey('phone-field'),
            controller: _controller,
            enabled: widget.enabled,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\s-]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Phone number',
              border: OutlineInputBorder(),
            ),
            onChanged: widget.onPhoneChanged,
            onSubmitted: (_) => widget.onSubmit(),
          ),
        ),
      ],
    );
  }
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet();

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final matches = kCountries
        .where(
          (c) =>
              query.isEmpty ||
              c.name.toLowerCase().contains(query) ||
              c.dialCode.contains(query),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search countries',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: matches.length,
              itemBuilder: (context, index) {
                final country = matches[index];
                return ListTile(
                  leading: Text(
                    country.flagEmoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                  title: Text(country.name),
                  trailing: Text(country.dialCode),
                  onTap: () => Navigator.of(context).pop(country),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
