import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'currency_format.dart';
import 'subscription_access_policy.dart';
import 'subscription_service.dart';

class SubscriptionGate extends StatefulWidget {
  const SubscriptionGate({super.key, required this.child});

  final Widget child;

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate>
    with WidgetsBindingObserver {
  bool _ensuringDocument = false;
  bool _isLoading = true;
  bool _clockRollback = false;
  bool _serverCheckInProgress = false;
  String? _ensureError;
  String? _ensuredUserId;
  String? _currentUid;
  String? _accessError;
  String? _cacheError;
  Map<String, dynamic>? _subscriptionData;
  DateTime? _lastKnownTime;
  DateTime? _lastServerCheck;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;
  Timer? _accessTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accessTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkAccess(),
    );
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !SubscriptionService.isAdmin(user)) {
      unawaited(_loadAndWatchUser(user));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accessTimer?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccess(forceServerCheck: _clockRollback);
    }
  }

  Future<void> _loadAndWatchUser(User user) async {
    if (_currentUid == user.uid) return;
    await _userSubscription?.cancel();
    _currentUid = user.uid;
    _subscriptionData = null;
    _lastKnownTime = null;
    _clockRollback = false;
    _accessError = null;
    _cacheError = null;
    _ensureError = null;
    _ensuredUserId = null;
    _isLoading = true;
    if (mounted) setState(() {});

    try {
      _subscriptionData = await SubscriptionService.getCachedUserAccess(
        user.uid,
      );
      _lastKnownTime = await SubscriptionService.getLastKnownUserAccessTime(
        user.uid,
      );
      final now = DateTime.now();
      _clockRollback = _lastKnownTime != null && now.isBefore(_lastKnownTime!);
      if (_subscriptionData != null && !_clockRollback) {
        await _recordObservedTime(now);
      }
    } catch (error) {
      _cacheError = 'No se pudo leer el acceso guardado: $error';
    } finally {
      _isLoading = false;
      if (mounted) setState(() {});
    }

    _userSubscription = SubscriptionService.watchUser(user.uid).listen(
      (snapshot) => unawaited(
        _handleUserSnapshot(user, snapshot).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          debugPrint('No se pudo procesar la suscripción: $error');
          _accessError = error.toString();
          _isLoading = false;
          if (mounted) setState(() {});
        }),
      ),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('No se pudo verificar la suscripción: $error');
        _accessError = error.toString();
        _isLoading = false;
        if (mounted) setState(() {});
      },
    );
    _checkAccess();
  }

  Future<void> _handleUserSnapshot(
    User user,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!mounted || _currentUid != user.uid) return;
    final data = snapshot.data();
    if (!snapshot.metadata.isFromCache) {
      if (data == null) {
        try {
          await SubscriptionService.clearCachedUserAccess(user.uid);
          _cacheError = null;
        } catch (error) {
          _cacheError = 'No se pudo actualizar la suscripción guardada: $error';
        }
        _subscriptionData = null;
        _clockRollback = false;
        _lastKnownTime = null;
        _isLoading = false;
        if (mounted) setState(() {});
        await _ensureUser(user);
        return;
      }

      final now = DateTime.now();
      _subscriptionData = data;
      _lastKnownTime = now;
      _clockRollback = false;
      _accessError = null;
      if (mounted) setState(() {});
      try {
        await SubscriptionService.cacheUserAccess(
          uid: user.uid,
          data: data,
          observedAt: now,
          serverValidated: true,
        );
        _cacheError = null;
      } catch (error) {
        _cacheError =
            'No se pudo guardar la suscripción en este dispositivo: '
            '$error';
      }
    } else if (data != null) {
      _subscriptionData = data;
      try {
        await SubscriptionService.cacheUserAccess(
          uid: user.uid,
          data: data,
          observedAt: DateTime.now(),
          serverValidated: false,
        );
        _cacheError = null;
      } catch (error) {
        _cacheError =
            'No se pudo guardar la suscripción en este dispositivo: '
            '$error';
      }
      _checkCachedClock();
    }

    _isLoading = false;
    if (mounted) setState(() {});
    _checkAccess();
  }

  Future<void> _ensureUser(User user) async {
    if (_ensuringDocument || _ensuredUserId == user.uid) return;
    _ensuringDocument = true;
    try {
      await SubscriptionService.ensureUserDocument(user);
      _ensuredUserId = user.uid;
      _ensureError = null;
    } catch (error) {
      _ensureError = error.toString();
    } finally {
      _ensuringDocument = false;
      _isLoading = false;
      if (mounted) setState(() {});
    }
  }

  void _checkCachedClock() {
    final now = DateTime.now();
    if (_lastKnownTime != null && now.isBefore(_lastKnownTime!)) {
      _clockRollback = true;
    }
  }

  Future<void> _recordObservedTime(DateTime now) async {
    final lastKnownTime = _lastKnownTime;
    if (lastKnownTime != null && now.isBefore(lastKnownTime)) {
      _clockRollback = true;
      return;
    }
    _lastKnownTime = now;
    final uid = _currentUid;
    if (uid != null) {
      try {
        await SubscriptionService.recordLastKnownUserAccessTime(uid, now);
      } catch (error) {
        _cacheError = 'No se pudo guardar la hora de validación local: $error';
      }
    }
  }

  Future<void> _checkAccess({bool forceServerCheck = false}) async {
    if (!mounted) return;
    final uid = _currentUid;
    final now = DateTime.now();
    final clockWasRolledBack = _clockRollback;
    if (!clockWasRolledBack) {
      await _recordObservedTime(now);
    }

    if (mounted) setState(() {});
    if (_clockRollback &&
        uid != null &&
        (forceServerCheck ||
            _lastServerCheck == null ||
            now.difference(_lastServerCheck!) >= const Duration(seconds: 30))) {
      await _revalidateFromServer(uid);
    }
  }

  Future<void> _revalidateFromServer(String uid) async {
    if (_serverCheckInProgress) return;
    _serverCheckInProgress = true;
    _lastServerCheck = DateTime.now();
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final user = FirebaseAuth.instance.currentUser;
      if (!mounted || user == null || user.uid != uid) return;
      await _handleUserSnapshot(user, snapshot);
    } catch (error) {
      debugPrint('No se pudo revalidar la suscripción con Firebase: $error');
      _accessError = error.toString();
      if (mounted) setState(() {});
    } finally {
      _serverCheckInProgress = false;
    }
  }

  Future<void> _retryAccessCheck() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _accessError = null;
      _ensureError = null;
      _ensuredUserId = null;
    });
    await _revalidateFromServer(user.uid);
  }

  SubscriptionAccessState get _accessState {
    if (_clockRollback) return SubscriptionAccessState.clockRollback;
    return SubscriptionAccessPolicy.evaluate(
      data: _subscriptionData,
      now: DateTime.now(),
      lastKnownTime: _lastKnownTime,
    );
  }

  Widget _offlineAccessMessage(String message) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 56, color: Colors.indigo),
              const SizedBox(height: 16),
              Text(
                'No se pudo verificar el acceso',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Conéctate a Internet e inténtalo de nuevo. La app no puede '
                'confirmar el estado de la suscripción sin conexión.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _retryAccessCheck,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return widget.child;
    if (SubscriptionService.isAdmin(user)) return widget.child;

    if (_currentUid != user.uid) unawaited(_loadAndWatchUser(user));
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_cacheError != null) return _offlineAccessMessage(_cacheError!);

    final accessState = _accessState;
    if (accessState == SubscriptionAccessState.allowed) return widget.child;
    if (_subscriptionData != null) {
      return SubscriptionScreen(
        user: user,
        data: _subscriptionData!,
        clockRollback: accessState == SubscriptionAccessState.clockRollback,
      );
    }

    final error = _ensureError ?? _accessError;
    if (error != null) return _offlineAccessMessage(error);

    return _offlineAccessMessage(
      'No hay una suscripción guardada para verificar. Conéctate a Internet.',
    );
  }
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    required this.user,
    required this.data,
    this.clockRollback = false,
  });

  final User user;
  final Map<String, dynamic> data;
  final bool clockRollback;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isSubmitting = false;
  bool _requestSubmitted = false;

  Future<void> _openWhatsapp() async {
    final message =
        'Hola, quiero activar POSMOVIL. '
        'Pagé ₡${formatMoney(SubscriptionService.monthlyPrice)} por SINPE Móvil. '
        'Mi correo es: ${widget.user.email}. '
        'Adjunto el comprobante del pago.';
    final uri = Uri.https('wa.me', '/${SubscriptionService.whatsappNumber}', {
      'text': message,
    });

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir WhatsApp.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submitPaymentConfirmation() async {
    setState(() => _isSubmitting = true);
    try {
      await SubscriptionService.submitSinpeRequest(
        uid: widget.user.uid,
        email: widget.user.email ?? '',
      );

      if (!mounted) return;
      setState(() => _requestSubmitted = true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo enviar la solicitud: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiresAt = widget.data['expiresAt'];
    String expirationText = 'Tu acceso venció.';
    if (expiresAt is Timestamp) {
      final date = expiresAt.toDate();
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();
      expirationText = 'Venció el $day/$month/$year.';
    }
    if (widget.clockRollback) {
      expirationText =
          'El reloj del dispositivo retrocedió. Conéctate a Internet para '
          'validar tu acceso antes de continuar.';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activar POSMOVIL'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                const Icon(Icons.lock_outline, size: 72, color: Colors.indigo),
                const SizedBox(height: 16),
                Text(
                  widget.clockRollback
                      ? 'Verifica tu conexión para continuar'
                      : 'Tu acceso necesita renovación',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  expirationText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text(
                          'Pago mensual por SINPE Móvil',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          SubscriptionService.sinpeNumber,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Monto: ₡${formatMoney(SubscriptionService.monthlyPrice)}',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cuenta: ${widget.user.email}',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'WhatsApp para comprobar pago: 64846604',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openWhatsapp,
                    icon: const Icon(Icons.chat),
                    label: const Text('Enviar comprobante por WhatsApp'),
                  ),
                ),
                const SizedBox(height: 8),
                if (_requestSubmitted)
                  const Card(
                    color: Color(0xFFE8F5E9),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Solicitud enviada. Verificaremos tu SINPE y activaremos tu acceso.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF2E7D32)),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : _submitPaymentConfirmation,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.payments_outlined),
                      label: Text(
                        _isSubmitting
                            ? 'Enviando solicitud...'
                            : 'Confirmar pago SINPE',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
