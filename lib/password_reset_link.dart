const _firebaseAuthLinkHost = 'posmovil-app.firebaseapp.com';

String? extractPasswordResetCode(Uri incomingLink) {
  if (incomingLink.scheme != 'https' ||
      incomingLink.host != _firebaseAuthLinkHost ||
      incomingLink.path != '/__/auth/links') {
    return null;
  }

  var currentLink = incomingLink;
  for (var depth = 0; depth < 4; depth++) {
    if (currentLink.host != _firebaseAuthLinkHost) return null;

    final mode = currentLink.queryParameters['mode'];
    final code = currentLink.queryParameters['oobCode'];
    if (mode == 'resetPassword' && code != null && code.isNotEmpty) {
      return code;
    }

    final nestedLink =
        currentLink.queryParameters['link'] ??
        currentLink.queryParameters['deep_link_id'];
    if (nestedLink == null) return null;

    try {
      currentLink = Uri.parse(nestedLink);
    } on FormatException {
      return null;
    }
  }
  return null;
}
