import 'package:flutter/material.dart';

import 'pages/stop_to_stop_search_body.dart';

class CommuterRoutesPage extends StatelessWidget {
  const CommuterRoutesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Plan Your Trip',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
      ),
      body: const SafeArea(
        child: StopToStopSearchBody(),
      ),
    );
  }
}

