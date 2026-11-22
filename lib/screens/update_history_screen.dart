import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shipped release notes, stored with the code and displayed read-only.
class UpdateHistoryScreen extends StatelessWidget {
  const UpdateHistoryScreen({super.key});

  Future<List<Map<String, dynamic>>> _load() async {
    final text = await rootBundle.loadString('assets/changelog.json');
    final json = jsonDecode(text) as Map<String, dynamic>;
    return (json['releases'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Güncelleme Geçmişi')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Sürüm notları yüklenemedi: ${snapshot.error}'),
            ));
          }
          final releases = snapshot.data;
          if (releases == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('SanalTrader geliştirme günlüğü',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'Yayınlanan sürümlerde neler değişti? Bu notlar GitHub deposundaki kodla birlikte saklanır.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 14),
              for (final release in releases) Card(
                color: const Color(0xFF19212D),
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  initiallyExpanded: release == releases.first,
                  title: Text(release['title'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('v${release['version']} • ${release['date']}',
                    style: const TextStyle(fontSize: 11, color: Colors.white60)),
                  children: [
                    for (final item in (release['details'] as List))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.check_circle_outline, size: 16,
                            color: Color(0xFF43D9A3)),
                          const SizedBox(width: 9),
                          Expanded(child: Text(item.toString(),
                            style: const TextStyle(fontSize: 12, height: 1.4))),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
