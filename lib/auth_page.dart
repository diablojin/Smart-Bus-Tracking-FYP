import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'commuter_home_page.dart';
import 'driver_home_page.dart';

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

  Future<String> _getUserRole() async {
    final user = supabase.auth.currentUser;
    if (user == null) return 'commuter';

    final metadata = user.userMetadata ?? {};
    final rawRole = metadata['role'];

    if (rawRole is String && (rawRole == 'driver' || rawRole == 'commuter')) {
      return rawRole;
    }
    return 'commuter';
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

      // Decide home screen based on role
      final role = await _getUserRole();
      if (!mounted) return;

      final Widget target =
          (role == 'driver') ? const DriverHomePage() : const CommuterHomePage();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => target),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const SizedBox(height: 16),

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
                const SizedBox(height: 24),

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
                const SizedBox(height: 8),

                // Toggle Login/Signup
                TextButton(
                  onPressed: _isLoading ? null : _toggleMode,
                  child: Text(
                    _isLoginMode
                        ? "Don't have an account? Sign up"
                        : "Already have an account? Login",
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
