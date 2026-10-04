/// The Helix Global server. Sign-in opens here and nowhere else unless a code,
/// a link or the hidden corner says otherwise.
///
/// In `core/` because two features need it (sign-in, and linking this device
/// by QR code) and a feature may not import another.
final kGlobalServerUrl = Uri.parse('https://helix.agiletechbd.com');
