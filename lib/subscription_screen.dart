import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'currency_format.dart';
import 'subscription_service.dart';

class SubscriptionGate extends StatefulWidget {
  const SubscriptionGate({super.key, required this.child});

  final Widget child;

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate> {
  bool _ensuringDocument = false;

  Future<void> _ensureUser(User user) async {
    if (_ensuringDocument) return;
    _ensuringDocument = true;
    try {
      await SubscriptionService.ensureUserDocument(user);
    } finally {
      _ensuringDocument = false;
    }
  }

  bool _hasActiveAccess(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['status'] == 'blocked') return false;
    if (data['plan'] == 'lifetime' && data['status'] == 'active') {
      return true;
    }

    final expiresAt = data['expiresAt'];
    if (expiresAt is Timestamp && data['status'] == 'active') {
      return expiresAt.toDate().isAfter(DateTime.now());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return widget.child;
    if (SubscriptionService.isAdmin(user)) return widget.child;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: SubscriptionService.watchUser(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data?.data();
        if (!snapshot.hasData || data == null) {
          _ensureUser(user);
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_hasActiveAccess(data)) return widget.child;
        return SubscriptionScreen(user: user, data: data);
      },
    );
  }
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, required this.user, required this.data});

  final User user;
  final Map<String, dynamic> data;

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
                const Text(
                  'Tu acceso necesita renovación',
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
