import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/auth_provider.dart';

// Custom TextInputFormatter to handle paste events
class CodePasteFormatter extends TextInputFormatter {
  final Function(String) onPaste;

  CodePasteFormatter(this.onPaste);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If the new value is longer than 1, it's likely a paste operation
    if (newValue.text.length > 1) {
      // Extract digits only
      final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.isNotEmpty) {
        // Call the paste handler asynchronously to avoid blocking
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onPaste(digits);
        });
        // Return empty value since we'll handle it manually
        return const TextEditingValue(text: '');
      }
      // If no digits found, return old value
      return oldValue;
    }
    // For normal typing, allow single digit
    return newValue;
  }
}

class VerifyEmailPage extends StatefulWidget {
  final String email;

  const VerifyEmailPage({super.key, required this.email});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> with TickerProviderStateMixin {
  final List<TextEditingController> _codeControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final TextEditingController _pasteController = TextEditingController();
  final FocusNode _pasteFocusNode = FocusNode();
  bool _isResending = false;
  DateTime? _codeExpiresAt;
  Timer? _expirationTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // Set expiration time to 10 minutes from now
    _codeExpiresAt = DateTime.now().add(const Duration(minutes: 10));
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    // Start countdown timer
    _expirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
        if (_codeExpiresAt != null && DateTime.now().isAfter(_codeExpiresAt!)) {
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    _pulseController.dispose();
    for (var controller in _codeControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _pasteController.dispose();
    _pasteFocusNode.dispose();
    super.dispose();
  }

  String _getTimeRemaining() {
    if (_codeExpiresAt == null) return '';
    
    final now = DateTime.now();
    if (now.isAfter(_codeExpiresAt!)) {
      return 'Expired';
    }
    
    final difference = _codeExpiresAt!.difference(now);
    final minutes = difference.inMinutes;
    final seconds = difference.inSeconds % 60;
    
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  bool get _isExpired {
    return _codeExpiresAt != null && DateTime.now().isAfter(_codeExpiresAt!);
  }

  bool get _isExpiringSoon {
    if (_codeExpiresAt == null) return false;
    final difference = _codeExpiresAt!.difference(DateTime.now());
    return difference.inSeconds <= 60 && difference.inSeconds > 0;
  }

  Future<void> _checkAndPasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != null) {
        final text = clipboardData!.text!.trim();
        // Remove any non-digit characters
        final digits = text.replaceAll(RegExp(r'[^\d]'), '');
        
        if (digits.length >= 6) {
          // Fill all 6 fields with the pasted digits
          for (int i = 0; i < 6; i++) {
            _codeControllers[i].text = digits[i];
          }
          // Clear clipboard or wait a bit before submitting
          await Future.delayed(const Duration(milliseconds: 100));
          _submitCode();
        } else if (digits.isNotEmpty) {
          // Fill available fields with what we have
          for (int i = 0; i < digits.length && i < 6; i++) {
            _codeControllers[i].text = digits[i];
          }
          // Focus on the next empty field
          if (digits.length < 6) {
            _focusNodes[digits.length].requestFocus();
          }
        }
      }
    } catch (e) {
      // Ignore clipboard errors
    }
  }

  void _handlePaste(String pastedText) {
    if (!mounted) return;
    
    // Remove any non-digit characters
    final digits = pastedText.replaceAll(RegExp(r'[^\d]'), '');
    
    if (digits.isEmpty) return;
    
    // Clear all fields first
    for (int i = 0; i < 6; i++) {
      _codeControllers[i].clear();
    }
    
    // Fill fields with digits
    final length = digits.length > 6 ? 6 : digits.length;
    for (int i = 0; i < length; i++) {
      _codeControllers[i].text = digits[i];
    }
    
    // Clear the paste field
    _pasteController.clear();
    
    // If we have 6 digits, submit automatically
    if (digits.length >= 6) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          _submitCode();
        }
      });
    } else {
      // Focus on the next empty field
      _focusNodes[length].requestFocus();
    }
  }

  void _onCodeChanged(int index, String value) {
    if (value.length == 1) {
      // Move to next field
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        // Last field, submit
        _submitCode();
      }
    } else if (value.isEmpty && index > 0) {
      // Move to previous field on backspace
      _focusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _submitCode() async {
    final code = _codeControllers.map((c) => c.text).join();
    
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the complete 6-digit code'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.verifyEmail(widget.email, code);

    if (success && mounted) {
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verified successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      // Navigate back - AppShell will detect verified status
      Navigator.of(context).pop();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Verification failed'),
          backgroundColor: Colors.red,
        ),
      );
      // Clear code fields on error
      for (var controller in _codeControllers) {
        controller.clear();
      }
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isResending = true);
    
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.resendVerificationCode(widget.email);

    if (mounted) {
      setState(() => _isResending = false);
      
      if (success) {
        // Reset expiration timer
        _codeExpiresAt = DateTime.now().add(const Duration(minutes: 10));
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification code sent! Please check your email.'),
            backgroundColor: Colors.green,
          ),
        );
        // Clear code fields
        for (var controller in _codeControllers) {
          controller.clear();
        }
        _focusNodes[0].requestFocus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? 'Failed to resend code'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Verify Email'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.email_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Verify Your Email',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a 6-digit code to',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.email,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  // Expiration timer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _isExpired
                          ? Colors.red.withValues(alpha: 0.1)
                          : _isExpiringSoon
                              ? Colors.orange.withValues(alpha: 0.1)
                              : Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isExpired
                            ? Colors.red
                            : _isExpiringSoon
                                ? Colors.orange
                                : Colors.blue,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isExpired
                              ? Icons.error_outline
                              : _isExpiringSoon
                                  ? Icons.warning_amber_rounded
                                  : Icons.access_time,
                          size: 20,
                          color: _isExpired
                              ? Colors.red
                              : _isExpiringSoon
                                  ? Colors.orange
                                  : Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isExpired
                              ? 'Code expired. Please request a new one.'
                              : 'Code expires in: ${_getTimeRemaining()}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _isExpired
                                ? Colors.red
                                : _isExpiringSoon
                                    ? Colors.orange
                                    : Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Hidden field for paste functionality
                  Opacity(
                    opacity: 0,
                    child: SizedBox(
                      height: 0,
                      child: TextField(
                        controller: _pasteController,
                        focusNode: _pasteFocusNode,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: _handlePaste,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, (index) {
                      return SizedBox(
                        width: 50,
                        child: TextField(
                          controller: _codeControllers[index],
                          focusNode: _focusNodes[index],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                          inputFormatters: [
                            CodePasteFormatter((pastedText) {
                              _handlePaste(pastedText);
                            }),
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (value) {
                            // Only handle single character input
                            if (value.length <= 1) {
                              _onCodeChanged(index, value);
                            }
                          },
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      return FilledButton(
                        onPressed: (authProvider.isLoading || _isExpired) ? null : _submitCode,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: authProvider.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Verify'),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isResending ? null : _resendCode,
                    child: _isResending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.refresh, size: 18),
                              const SizedBox(width: 4),
                              Text(_isExpired ? 'Get New Code' : 'Resend Code'),
                            ],
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The verification code expires in 10 minutes',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
