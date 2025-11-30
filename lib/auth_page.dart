import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'commuter_home_page.dart';
import 'driver_home_page.dart';
import 'services/profile_service.dart';

final supabase = Supabase.instance.client;

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoginMode = true; // true = Login, false = Sign Up
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
    });
  }

  /// Converts Supabase auth errors to user-friendly messages
  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    // Extract message from AuthException if available
    String message = '';
    if (error is AuthException) {
      message = error.message.toLowerCase();
    }
    
    // Check for specific error codes in the error string
    if (errorStr.contains('code: invalid_credentials') || 
        errorStr.contains('invalid_credentials') ||
        (message.contains('invalid') && message.contains('credential'))) {
      return 'Invalid email or password. Please check your credentials.';
    }
    
    if (errorStr.contains('code: email_not_confirmed') || 
        errorStr.contains('email_not_confirmed')) {
      return 'Please confirm your email address before logging in.';
    }
    
    if (errorStr.contains('code: user_not_found') || 
        errorStr.contains('user_not_found')) {
      return 'No account found with this email address.';
    }
    
    if (errorStr.contains('code: email_already_registered') || 
        errorStr.contains('email_already_registered') ||
        (message.contains('email') && message.contains('already'))) {
      return 'An account with this email already exists.';
    }
    
    if (errorStr.contains('code: weak_password') || 
        errorStr.contains('weak_password') ||
        (message.contains('password') && message.contains('weak'))) {
      return 'Password is too weak. Please use a stronger password.';
    }
    
    // Check status codes
    if (errorStr.contains('statuscode: 400') || errorStr.contains('statuscode:400')) {
      if (message.contains('invalid') || message.contains('credential')) {
        return 'Invalid email or password. Please check your credentials.';
      }
      return 'Invalid input. Please check your email and password.';
    }
    
    if (errorStr.contains('statuscode: 401') || errorStr.contains('statuscode:401')) {
      return 'Invalid email or password. Please try again.';
    }
    
    if (errorStr.contains('statuscode: 422') || errorStr.contains('statuscode:422')) {
      return 'Invalid email format. Please enter a valid email address.';
    }
    
    // Handle generic error patterns
    if (errorStr.contains('invalid') && 
        (errorStr.contains('credential') || errorStr.contains('login'))) {
      return 'Invalid email or password. Please check your credentials.';
    }
    
    if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    }
    
    if (errorStr.contains('email') && errorStr.contains('already')) {
      return 'An account with this email already exists.';
    }

    // Default fallback
    return 'An error occurred. Please try again.';
  }

  Future<void> _loginAsGuest() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await supabase.auth.signInWithPassword(
        email: 'guest@smartbus.com',
        password: 'guest1234',
      );

      if (response.session == null) {
        throw Exception('Guest login failed. Please try again.');
      }

      if (!mounted) return;
      
      // Navigate to commuter home as guest
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const CommuterHomePage(isGuest: true),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      final errorMessage = _getErrorMessage(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Guest login failed: $errorMessage'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isLoginMode) {
        // LOGIN
        final response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (response.session == null) {
          throw Exception('Login failed. Please check your credentials.');
        }
      } else {
        // SIGN UP → default role = commuter
        final response = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'role': 'commuter',
          },
        );

        if (response.user == null) {
          throw Exception('Sign up failed. Please try again.');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account created! You are now logged in.'),
            ),
          );
        }
      }

      // Decide home screen based on role from profiles table
      final role = await ProfileService.getCurrentUserRole();
      if (!mounted) return;

      if (role == 'driver') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DriverHomePage()),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const CommuterHomePage(isGuest: false),
          ),
          (route) => false,
        );
      }
    } catch (error) {
      if (!mounted) return;
      final errorMessage = _getErrorMessage(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLoginMode ? 'Login' : 'Sign Up'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    
                    // Header block (icon + app name + subtitle)
                    Center(
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/icons/app_icon.png',
                            height: 90,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'SmartBus Connect',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Real-time bus tracking for commuters and drivers',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[700],
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Email
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Password
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_isLoginMode ? 'Login' : 'Sign Up'),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Toggle Login/Signup
                    Center(
                      child: TextButton(
                        onPressed: _isLoading ? null : _toggleMode,
                        child: Text(
                          _isLoginMode
                              ? "Don't have an account? Sign up"
                              : "Already have an account? Login",
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    
                    // Continue as Guest Button
                    Center(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _isLoading ? null : _loginAsGuest,
                        child: Text(
                          'Continue as Guest',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
