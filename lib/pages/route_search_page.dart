import 'package:flutter/material.dart';

import 'stop_to_stop_search_body.dart';

/// Standalone page wrapper for Stop-to-Stop Search
/// Can be navigated to separately if needed
class RouteSearchPage extends StatelessWidget {
  const RouteSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const SafeArea(
        child: StopToStopSearchBody(),
      ),
    );
  }
}
