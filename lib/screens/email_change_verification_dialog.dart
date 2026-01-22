import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'verify_email_page.dart'; // Import CodePasteFormatter

class EmailChangeVerificationDialog extends StatefulWidget {
  final String currentEmail;
  final String newEmail;
  final AuthProvider authProvider;

  const EmailChangeVerificationDialog({
    super.key,
    required this.currentEmail,
    required this.newEmail,
    required this.authProvider,
  });

  @override
  State<EmailChangeVerificationDialog> createState() => _EmailChangeVerificationDialogState();
}

class _EmailChangeVerificationDialogState extends State<EmailChangeVerificationDialog> {
  final List<TextEditingController> _currentEmailControllers = List.generate(6, (_) => TextEditingController());
  final List<TextEditingController> _newEmailControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _currentEmailFocusNodes = List.generate(6, (_) => FocusNode());
  final List<FocusNode> _newEmailFocusNodes = List.generate(6, (_) => FocusNode());
  bool _isVerifying = false;
  String? _errorMessage;
  int _currentStep = 1; // 1 = verify current email, 2 = verify new email

  @override
  void dispose() {
    for (var controller in _currentEmailControllers) {
      controller.dispose();
    }
    for (var controller in _newEmailControllers) {
      controller.dispose();
    }
    for (var node in _currentEmailFocusNodes) {
      node.dispose();
    }
    for (var node in _newEmailFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _handlePaste(String pastedText, bool isCurrentEmail) {
    if (!mounted) return;
    
    // Remove any non-digit characters
    final digits = pastedText.replaceAll(RegExp(r'[^\d]'), '');
    
    if (digits.isEmpty) return;
    
    final controllers = isCurrentEmail ? _currentEmailControllers : _newEmailControllers;
    final focusNodes = isCurrentEmail ? _currentEmailFocusNodes : _newEmailFocusNodes;
    
    // Clear all fields first
    for (int i = 0; i < 6; i++) {
      controllers[i].clear();
    }
    
    // Fill fields with digits
    final length = digits.length > 6 ? 6 : digits.length;
    for (int i = 0; i < length; i++) {
      controllers[i].text = digits[i];
    }
    
    // If we have 6 digits, submit
    if (digits.length >= 6) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          if (isCurrentEmail) {
            _verifyCurrentEmail();
          } else {
            _verifyNewEmail();
          }
        }
      });
    } else {
      // Focus on the next empty field
      focusNodes[length].requestFocus();
    }
  }

  void _onCurrentEmailChanged(int index, String value) {
    if (value.length == 1) {
      // Move to next field
      if (index < 5) {
        _currentEmailFocusNodes[index + 1].requestFocus();
      } else {
        // Last field, submit current email code
        _verifyCurrentEmail();
      }
    } else if (value.isEmpty && index > 0) {
      // Move to previous field on backspace
      _currentEmailFocusNodes[index - 1].requestFocus();
    }
  }

  void _onNewEmailChanged(int index, String value) {
    if (value.length == 1) {
      // Move to next field
      if (index < 5) {
        _newEmailFocusNodes[index + 1].requestFocus();
      } else {
        // Last field, submit new email code
        _verifyNewEmail();
      }
    } else if (value.isEmpty && index > 0) {
      // Move to previous field on backspace
      _newEmailFocusNodes[index - 1].requestFocus();
    }
  }

  void _checkAndSubmit() {
    if (_currentStep == 1) {
      final currentCode = _currentEmailControllers.map((c) => c.text).join();
      if (currentCode.length == 6) {
        _verifyCurrentEmail();
      }
    } else {
      final newCode = _newEmailControllers.map((c) => c.text).join();
      if (newCode.length == 6) {
        _verifyNewEmail();
      }
    }
  }

  Future<void> _verifyCurrentEmail() async {
    if (_isVerifying) return;

    final currentCode = _currentEmailControllers.map((c) => c.text).join();

    if (currentCode.length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final error = await widget.authProvider.verifyCurrentEmailForChange(currentCode);
    
    if (mounted) {
      setState(() => _isVerifying = false);
      if (error == null) {
        // Step 1 complete, move to step 2
        setState(() {
          _currentStep = 2;
          _errorMessage = null;
          // Clear current email fields
          for (var controller in _currentEmailControllers) {
            controller.clear();
          }
        });
        // Focus on first new email field
        _newEmailFocusNodes[0].requestFocus();
      } else {
        setState(() => _errorMessage = error);
        // Clear code fields on error
        for (var controller in _currentEmailControllers) {
          controller.clear();
        }
        _currentEmailFocusNodes[0].requestFocus();
      }
    }
  }

  Future<void> _verifyNewEmail() async {
    if (_isVerifying) return;

    final newCode = _newEmailControllers.map((c) => c.text).join();

    if (newCode.length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final error = await widget.authProvider.verifyNewEmailForChange(newCode);
    
    if (mounted) {
      setState(() => _isVerifying = false);
      if (error == null) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _errorMessage = error);
        // Clear code fields on error
        for (var controller in _newEmailControllers) {
          controller.clear();
        }
        _newEmailFocusNodes[0].requestFocus();
      }
    }
  }

  Future<void> _cancel() async {
    await widget.authProvider.cancelEmailChange();
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_currentStep == 1 ? 'Step 1: Verify Current Email' : 'Step 2: Verify New Email'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_currentStep == 1) ...[
              Text(
                'A verification code has been sent to your current email address.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Current Email: ${widget.currentEmail}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 50,
                    child: TextField(
                      controller: _currentEmailControllers[index],
                      focusNode: _currentEmailFocusNodes[index],
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
                          _handlePaste(pastedText, true);
                        }),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (value) {
                        // Only handle single character input
                        if (value.length <= 1) {
                          _onCurrentEmailChanged(index, value);
                        }
                      },
                    ),
                  );
                }),
              ),
            ] else ...[
              Text(
                'A verification code has been sent to your new email address.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'New Email: ${widget.newEmail}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 50,
                    child: TextField(
                      controller: _newEmailControllers[index],
                      focusNode: _newEmailFocusNodes[index],
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
                          _handlePaste(pastedText, false);
                        }),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (value) {
                        // Only handle single character input
                        if (value.length <= 1) {
                          _onNewEmailChanged(index, value);
                        }
                      },
                    ),
                  );
                }),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            return TextButton(
              onPressed: (_isVerifying || authProvider.isLoading) ? null : _cancel,
              child: const Text('Cancel'),
            );
          },
        ),
        Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            final isLoading = _isVerifying || authProvider.isLoading;
            return FilledButton(
              onPressed: isLoading
                  ? null
                  : (_currentStep == 1 ? _verifyCurrentEmail : _verifyNewEmail),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_currentStep == 1 ? 'Verify' : 'Complete'),
            );
          },
        ),
      ],
    );
  }
}
