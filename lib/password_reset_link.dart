const _firebaseAuthLinkHost = 'posmovil-app.firebaseapp.com';
const _firebaseAuthLinkPaths = {'/__/auth/links', '/__/auth/action'};

String? extractPasswordResetCode(Uri incomingLink) {
  if (!_isFirebaseAuthLink(incomingLink)) {
    return null;
  }

  var currentLink = incomingLink;
  for (var depth = 0; depth < 5; depth++) {
    if (!_isFirebaseAuthLink(currentLink)) return null;

    final mode = currentLink.queryParameters['mode'];
    final code = currentLink.queryParameters['oobCode'];
    if (mode == 'resetPassword' && code != null && code.isNotEmpty) {
      return code;
    }

    final nestedLink =
        currentLink.queryParameters['link'] ??
        currentLink.queryParameters['deep_link_id'] ??
        currentLink.queryParameters['continueUrl'];
    if (nestedLink == null) return null;

    try {
      currentLink = Uri.parse(nestedLink);
    } on FormatException {
      return null;
    }
  }
  return null;
}

bool _isFirebaseAuthLink(Uri link) =>
    link.scheme == 'https' &&
    link.host == _firebaseAuthLinkHost &&
    _firebaseAuthLinkPaths.contains(link.path);
