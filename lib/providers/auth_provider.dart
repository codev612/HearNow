import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';

class AuthProvider extends ChangeNotifier {
  String? _token;
  String? _userEmail;
  String? _userName;
  bool? _emailVerified;
  bool _isLoading = false;
  String? _errorMessage;

  String? get token => _token;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  bool? get emailVerified => _emailVerified;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? _lastVerificationCode;
  String? get lastVerificationCode => _lastVerificationCode;

  AuthProvider() {
    _loadToken();
  }

  Future<void> _loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('auth_token');
      _userEmail = prefs.getString('user_email');
      if (_token != null && _token!.isNotEmpty) {
        // Verify token is still valid by checking with server
        final isValid = await _verifyToken();
        if (!isValid) {
          await _clearAuth();
        }
      }
      notifyListeners();
    } catch (e) {
      print('Error loading auth token: $e');
    }
  }

  Future<bool> _verifyToken() async {
    if (_token == null) return false;
    
    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/me');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'];
        if (user != null) {
          _userEmail = user['email'] as String?;
          _userName = user['name'] as String?;
          _emailVerified = user['email_verified'] as bool?;
        }
        return true;
      }
      return false;
    } catch (e) {
      // Silently fail token verification if server is not available
      // This allows the app to work offline, but user will need to sign in again when server is back
      // Only log if it's not a connection error (which is expected when server is down)
      if (e.toString().contains('Connection') || e.toString().contains('refused')) {
        // Server is not running - this is expected, don't spam logs
        return false;
      }
      print('Token verification error: $e');
      return false;
    }
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/signin');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      print('[AuthProvider] Sign in response status: ${response.statusCode}');
      final responseBody = response.body;
      print('[AuthProvider] Sign in response body: $responseBody');
      
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        if (data['token'] == null) {
          print('[AuthProvider] ERROR: Token missing in successful response');
          _errorMessage = 'Sign in response missing token';
          _isLoading = false;
          notifyListeners();
          return false;
        }
        
        _token = data['token'] as String;
        final user = data['user'] as Map<String, dynamic>?;
        _userEmail = user?['email'] as String? ?? email;
        _userName = user?['name'] as String?;
        _emailVerified = user?['email_verified'] as bool?;
        
        print('[AuthProvider] Token received: ${_token?.substring(0, 20)}...');
        print('[AuthProvider] User email: $_userEmail, verified: $_emailVerified');
        
        // Save to persistent storage
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', _token!);
          if (_userEmail != null) {
            await prefs.setString('user_email', _userEmail!);
          }
          print('[AuthProvider] Token saved to SharedPreferences');
        } catch (e) {
          print('[AuthProvider] ERROR saving token: $e');
        }
        
        _errorMessage = null;
        _isLoading = false;
        print('[AuthProvider] Sign in successful, isAuthenticated will be: ${_token != null && _token!.isNotEmpty}');
        notifyListeners();
        return true;
      } else {
        // Handle different error status codes
        String errorMsg = 'Sign in failed';
        if (response.statusCode == 403) {
          errorMsg = data['error'] as String? ?? 
                    data['message'] as String? ?? 
                    'Email not verified. Please check your inbox for the verification code.';
        } else if (response.statusCode == 401) {
          errorMsg = data['error'] as String? ?? 
                    data['message'] as String? ?? 
                    'Invalid email or password';
        } else {
          errorMsg = data['error'] as String? ?? 
                    data['message'] as String? ?? 
                    'Sign in failed';
        }
        _errorMessage = errorMsg;
        _isLoading = false;
        print('[AuthProvider] Sign in failed: $_errorMessage (status: ${response.statusCode})');
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUp(String email, String name, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/signup');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'name': name,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        _userEmail = email; // Store email for verification
        // Store verification code if returned (for development when Mailgun not configured)
        _lastVerificationCode = data['verification_code'] as String?;
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = data['error'] as String? ?? 'Sign up failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyEmail(String email, String code) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/verify-email');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = data['error'] as String? ?? 'Verification failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> resendVerificationCode(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/resend-verification');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = data['error'] as String? ?? 'Failed to resend code';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await _clearAuth();
    notifyListeners();
  }

  Future<void> _clearAuth() async {
    _token = null;
    _userEmail = null;
    _userName = null;
    _emailVerified = null;
    _errorMessage = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_email');
  }

  Future<void> refreshUserInfo() async {
    if (_token == null) return;
    
    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/me');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'];
        if (user != null) {
          _userEmail = user['email'] as String?;
          _userName = user['name'] as String?;
          _emailVerified = user['email_verified'] as bool?;
          notifyListeners();
        }
      }
    } catch (e) {
      print('Error refreshing user info: $e');
    }
  }

  Future<String?> updateProfile({String? name, String? email}) async {
    if (_token == null) return 'Not authenticated';
    
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/profile');
      final response = await http.put(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          if (name != null) 'name': name,
          if (email != null) 'email': email,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final user = data['user'];
        final pendingEmail = data['pendingEmail'] as String?;
        
        if (user != null) {
          _userEmail = user['email'] as String?;
          _userName = user['name'] as String?;
          _emailVerified = user['email_verified'] as bool?;
          
          // Update stored email if changed (but not if pending)
          if (email != null && _userEmail != null && pendingEmail == null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_email', _userEmail!);
          }
        }
        
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        
        // Return pending email if exists, otherwise null for success
        return pendingEmail != null ? 'PENDING_EMAIL:$pendingEmail' : null;
      } else {
        _errorMessage = data['error'] as String? ?? 'Failed to update profile';
        _isLoading = false;
        notifyListeners();
        return _errorMessage;
      }
    } catch (e) {
      _errorMessage = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return _errorMessage;
    }
  }

  Future<String?> changePassword(String currentPassword, String newPassword) async {
    if (_token == null) return 'Not authenticated';
    
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/change-password');
      final response = await http.put(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return null; // Success
      } else {
        _errorMessage = data['error'] as String? ?? 'Failed to change password';
        _isLoading = false;
        notifyListeners();
        return _errorMessage;
      }
    } catch (e) {
      _errorMessage = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return _errorMessage;
    }
  }

  Future<String?> verifyCurrentEmailForChange(String currentEmailCode) async {
    if (_token == null) return 'Not authenticated';
    
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/verify-current-email-change');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'currentEmailCode': currentEmailCode,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return null; // Success - returns pendingEmail in data
      } else {
        _errorMessage = data['error'] as String? ?? 'Failed to verify current email';
        _isLoading = false;
        notifyListeners();
        return _errorMessage;
      }
    } catch (e) {
      _errorMessage = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return _errorMessage;
    }
  }

  Future<String?> verifyNewEmailForChange(String newEmailCode) async {
    if (_token == null) return 'Not authenticated';
    
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/verify-new-email-change');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'newEmailCode': newEmailCode,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final user = data['user'];
        if (user != null) {
          _userEmail = user['email'] as String?;
          _userName = user['name'] as String?;
          _emailVerified = user['email_verified'] as bool?;
          
          // Update stored email
          if (_userEmail != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_email', _userEmail!);
          }
        }
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return null; // Success
      } else {
        _errorMessage = data['error'] as String? ?? 'Failed to verify new email';
        _isLoading = false;
        notifyListeners();
        return _errorMessage;
      }
    } catch (e) {
      _errorMessage = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return _errorMessage;
    }
  }

  Future<String?> cancelEmailChange() async {
    if (_token == null) return 'Not authenticated';
    
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/cancel-email-change');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return null; // Success
      } else {
        _errorMessage = data['error'] as String? ?? 'Failed to cancel email change';
        _isLoading = false;
        notifyListeners();
        return _errorMessage;
      }
    } catch (e) {
      _errorMessage = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return _errorMessage;
    }
  }

  Future<bool> forgotPassword(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/forgot-password');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Success - always return true for security (don't reveal if email exists)
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = data['error'] as String? ?? 'Failed to send password reset email';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(String code, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(AppConfig.serverHttpBaseUrl).resolve('/api/auth/reset-password');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = data['error'] as String? ?? 'Failed to reset password';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
