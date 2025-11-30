import 'package:flutter/material.dart';
import 'package:postgrest/postgrest.dart';

import '../../config/supabase_client.dart';

class ReportIssuePage extends StatefulWidget {
  final String routeId;
  final String routeName;
  final String? busId;
  final String? busName;

  const ReportIssuePage({
    super.key,
    required this.routeId,
    required this.routeName,
    this.busId,
    this.busName,
  });

  @override
  State<ReportIssuePage> createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends State<ReportIssuePage> {
  // Form key for validation
  final _formKey = GlobalKey<FormState>();

  // Form state
  String? _selectedIssueType;
  String? _selectedBusId; // For bus dropdown if bus is not provided
  final TextEditingController _commentsController = TextEditingController();
  
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _availableBuses = []; // For dropdown when bus is not provided

  // Getter to check if bus is preselected
  bool get _isBusPreselected => widget.busId != null;

  @override
  void initState() {
    super.initState();
    // If bus is not provided, load buses for the route
    if (widget.busId == null) {
      _loadBusesForRoute();
    }
  }

  // Issue type options
  final List<String> _issueTypes = const [
    'Bus location not accurate',
    'Arrival time not accurate',
    'App not updating in real-time',
    'Wrong bus/route information',
    'Other',
  ];

  @override
  void dispose() {
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _loadBusesForRoute() async {
    try {
      // widget.routeId is the numeric route ID as a string
      final routeId = int.tryParse(widget.routeId);
      if (routeId == null) return;

      final response = await supabase
          .from('buses')
          .select('id, code, plate_no')
          .eq('route_id', routeId)
          .eq('is_active', true)
          .order('code');

      _availableBuses = (response as List)
          .map((row) => row as Map<String, dynamic>)
          .toList();

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error loading buses: $e');
    }
  }

  Future<void> _submitReport() async {
    // Validate issue type
    if (_selectedIssueType == null || _selectedIssueType!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an issue type.'),
        ),
      );
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need to be logged in to submit a report.'),
        ),
      );
      return;
    }

    try {
      setState(() {
        _isSubmitting = true;
      });

      final comments = _commentsController.text.trim();

      // Resolve bus name: if user selected from dropdown, get it from dropdown state
      // Otherwise use widget.busName (if provided)
      String? selectedBusName;
      if (_selectedBusId != null) {
        // User selected a bus from dropdown - resolve the name
        try {
          final selectedBus = _availableBuses.firstWhere(
            (b) => b['id'].toString() == _selectedBusId,
          );
          final busCode = selectedBus['code'] as String? ?? '';
          final busPlate = selectedBus['plate_no'] as String? ?? '';
          selectedBusName = 'Bus $busCode ($busPlate)';
        } catch (e) {
          // Bus not found in list, use empty string
          selectedBusName = '';
        }
      } else {
        // No bus selected from dropdown, use widget.busName if provided
        selectedBusName = widget.busName;
      }

      await supabase.from('issue_reports').insert({
        'user_id': user.id,
        'route': widget.routeName,
        'bus': _selectedBusId != null
            ? selectedBusName
            : widget.busName,
        'issue_type': _selectedIssueType,
        'description': comments.isEmpty ? '' : comments,
      });

      // If insert succeeded:
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted successfully.'),
          backgroundColor: Colors.green,
        ),
      );
      
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      // Show real Supabase error for debugging
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit report: ${e.message}'),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('Report insert error: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to submit report. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('Report insert unknown error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Issue'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  const Text(
                    'We are sorry you experienced an issue. Please tell us more.',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Route Field (always locked)
                  const Text(
                    'Route *',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade800
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 18,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.routeName,
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Bus Field (locked if provided, dropdown if not)
                  const Text(
                    'Bus',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_isBusPreselected)
                    // Locked bus display
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade800
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.busName ?? 'Selected bus',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    // Enabled bus dropdown (optional)
                    DropdownButtonFormField<String>(
                      value: _selectedBusId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: 'Choose a bus (optional)',
                        filled: true,
                        fillColor: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade800
                            : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).primaryColor,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      items: _availableBuses.map((bus) {
                        final busCode = bus['code'] as String? ?? '';
                        final busPlate = bus['plate_no'] as String? ?? '';
                        final busId = bus['id'].toString();
                        return DropdownMenuItem(
                          value: busId,
                          child: Text('Bus $busCode ($busPlate)'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedBusId = value;
                        });
                      },
                    ),
                  const SizedBox(height: 20),

                  // Issue Type Dropdown
                  const Text(
                    'Issue Type *',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedIssueType,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: 'Select issue type',
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade800
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    items: _issueTypes.map((issue) {
                      return DropdownMenuItem(
                        value: issue,
                        child: Text(issue),
                      );
                    }).toList(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select an issue type';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      setState(() {
                        _selectedIssueType = value;
                      });
                    },
                  ),
                const SizedBox(height: 20),

                  // Additional Comments
                  const Text(
                    'Additional Comments',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commentsController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Describe the issue in detail...',
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade800
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitReport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Submit Report',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (_isSubmitting)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Submitting your report...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


