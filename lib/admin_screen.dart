import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'subscription_service.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administración'),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Solicitudes'),
              Tab(text: 'Usuarios'),
              Tab(text: 'Ventas'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PendingRequestsTab(),
            _UsersTab(),
            _SalesHistoryTab(),
          ],
        ),
      ),
    );
  }
}

class _PendingRequestsTab extends StatelessWidget {
  const _PendingRequestsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: SubscriptionService.watchPendingRequests(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('No se pudieron cargar las solicitudes.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data!.docs;
        if (requests.isEmpty) {
          return const Center(child: Text('No hay solicitudes pendientes.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            final data = request.data();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['email'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Monto reportado: ₡${data['amount'] ?? 400}'),
                    const SizedBox(height: 12),
                    const Text(
                      'Verificación manual SINPE en la cuenta bancaria.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () =>
                              SubscriptionService.approveMonthly(
                            requestId: request.id,
                            uid: data['uid'],
                          ),
                          child: const Text('Activar mes'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              SubscriptionService.approveLifetime(
                            requestId: request.id,
                            uid: data['uid'],
                          ),
                          child: const Text('Vitalicio'),
                        ),
                        TextButton(
                          onPressed: () =>
                              SubscriptionService.rejectRequest(request.id),
                          child: const Text('Rechazar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SalesHistoryTab extends StatelessWidget {
  const _SalesHistoryTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: SubscriptionService.watchSales(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('No se pudo cargar el historial de ventas.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final sales = snapshot.data!.docs;
        if (sales.isEmpty) {
          return const Center(child: Text('No hay ventas registradas.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sales.length,
          itemBuilder: (context, index) {
            final sale = sales[index].data();
            final dateValue = sale['date'];
            var dateText = '';
            if (dateValue is Timestamp) {
              final date = dateValue.toDate();
              dateText =
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
            }
            final price = sale['price'];

            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.point_of_sale),
                ),
                title: Text(sale['productName'] ?? 'Producto'),
                subtitle: Text('${sale['email'] ?? ''}\n$dateText'),
                isThreeLine: true,
                trailing: Text(
                  '₡$price',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: SubscriptionService.watchUsers(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('No se pudieron cargar los usuarios.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data!.docs;
        if (users.isEmpty) {
          return const Center(child: Text('No hay usuarios registrados.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final data = user.data();
            final plan = data['plan'] ?? 'trial';
            final status = data['status'] ?? 'active';
            final expiresAt = data['expiresAt'];
            String expiration = 'Sin vencimiento';
            if (expiresAt is Timestamp) {
              final date = expiresAt.toDate();
              expiration =
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
            }

            return Card(
              child: ListTile(
                title: Text(data['email'] ?? user.id),
                subtitle: Text('$plan · $status · vence: $expiration'),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'month') {
                      await SubscriptionService.extendMonth(user.id);
                    } else if (value == 'lifetime') {
                      await SubscriptionService.setLifetime(user.id);
                    } else if (value == 'block') {
                      await SubscriptionService.blockUser(user.id);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'month',
                      child: Text('Extender mes'),
                    ),
                    PopupMenuItem(
                      value: 'lifetime',
                      child: Text('Dar vitalicio'),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Text('Bloquear'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
