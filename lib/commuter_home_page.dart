import 'package:flutter/material.dart';
import 'commuter_map_page.dart';

class CommuterHomePage extends StatelessWidget {
  const CommuterHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commuter Home'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map, size: 80, color: Colors.green),
            const SizedBox(height: 20),
            const Text(
              'Track Your Bus',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const CommuterMapPage()),
                );
              },
              icon: const Icon(Icons.location_on),
              label: const Text('View Bus Locations'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
