import express, { Request, Response } from 'express';
import {
  createUser,
  getUserByEmail,
  getUserById,
  getUserByVerificationToken,
  getUserByResetToken,
  markEmailVerified,
  setVerificationToken,
  setResetToken,
  updatePassword,
  generateToken as generateDbToken,
} from '../database.js';
import { hashPassword, verifyPassword, generateToken } from '../auth.js';
import { sendVerificationEmail, sendPasswordResetEmail } from '../emailService.js';
import { authenticate, AuthRequest } from '../auth.js';

const router = express.Router();

interface SignupBody {
  email?: string;
  password?: string;
}

interface SigninBody {
  email?: string;
  password?: string;
}

interface ResendVerificationBody {
  email?: string;
}

interface ForgotPasswordBody {
  email?: string;
}

interface ResetPasswordBody {
  token?: string;
  password?: string;
}

// Signup
router.post('/signup', async (req: Request<{}, {}, SignupBody>, res: Response) => {
  try {
    const { email, password } = req.body;

    // Validation
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    // Email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ error: 'Invalid email format' });
    }

    // Password validation (minimum 8 characters)
    if (password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters long' });
    }

    // Check if user already exists
    const existingUser = await getUserByEmail(email);
    if (existingUser) {
      return res.status(409).json({ error: 'Email already registered' });
    }

    // Hash password
    const passwordHash = await hashPassword(password);

    // Create user
    const user = await createUser(email, passwordHash);

    // Send verification email
    const emailSent = await sendVerificationEmail(email, user.verification_token);
    if (!emailSent) {
      console.warn(`Failed to send verification email to ${email}, but user was created`);
    }

    return res.status(201).json({
      message: 'User created successfully. Please check your email to verify your account.',
      user: {
        id: user.id,
        email: user.email,
        email_verified: false,
      },
    });
  } catch (error) {
    console.error('Signup error:', error);
    res.status(500).json({ error: 'Internal server error' });
    return;
  }
});

// Signin
router.post('/signin', async (req: Request<{}, {}, SigninBody>, res: Response) => {
  try {
    const { email, password } = req.body;

    // Validation
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    // Get user
    const user = await getUserByEmail(email);
    if (!user || !user.id) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }

    // Verify password
    const isValidPassword = await verifyPassword(password, user.password_hash);
    if (!isValidPassword) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }

    // Check if email is verified
    if (!user.email_verified) {
      return res.status(403).json({
        error: 'Email not verified',
        email_verified: false,
        message: 'Please verify your email before signing in. Check your inbox for the verification link.',
      });
    }

    // Generate JWT token
    const token = generateToken(user.id, user.email);

    return res.json({
      message: 'Sign in successful',
      token,
      user: {
        id: user.id,
        email: user.email,
        email_verified: user.email_verified,
      },
    });
  } catch (error) {
    console.error('Signin error:', error);
    res.status(500).json({ error: 'Internal server error' });
    return;
  }
});

// Verify email
router.get('/verify-email', async (req: Request, res: Response) => {
  try {
    const { token } = req.query;

    if (!token || typeof token !== 'string') {
      return res.status(400).json({ error: 'Verification token is required' });
    }

    const user = await getUserByVerificationToken(token);
    if (!user || !user.id) {
      return res.status(400).json({ error: 'Invalid or expired verification token' });
    }

    // Mark email as verified
    await markEmailVerified(user.id);

    return res.json({
      message: 'Email verified successfully',
      user: {
        id: user.id,
        email: user.email,
        email_verified: true,
      },
    });
  } catch (error) {
    console.error('Verify email error:', error);
    res.status(500).json({ error: 'Internal server error' });
    return;
  }
});

// Resend verification email
router.post('/resend-verification', async (req: Request<{}, {}, ResendVerificationBody>, res: Response) => {
  try {
    const { email } = req.body;

    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }

    const user = await getUserByEmail(email);
    if (!user) {
      // Don't reveal if email exists or not for security
      return res.json({
        message: 'If the email exists and is not verified, a verification email has been sent.',
      });
    }

    if (user.email_verified) {
      return res.json({ message: 'Email is already verified' });
    }

    if (!user.id) {
      return res.status(500).json({ error: 'Invalid user data' });
    }

    // Generate new verification token
    const newToken = generateDbToken();
    await setVerificationToken(user.id, newToken);

    // Send verification email
    const emailSent = await sendVerificationEmail(email, newToken);
    if (!emailSent) {
      return res.status(500).json({ error: 'Failed to send verification email' });
    }

    return res.json({
      message: 'Verification email sent. Please check your inbox.',
    });
  } catch (error) {
    console.error('Resend verification error:', error);
    res.status(500).json({ error: 'Internal server error' });
    return;
  }
});

// Request password reset
router.post('/forgot-password', async (req: Request<{}, {}, ForgotPasswordBody>, res: Response) => {
  try {
    const { email } = req.body;

    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }

    const user = await getUserByEmail(email);
    if (!user) {
      // Don't reveal if email exists or not for security
      return res.json({
        message: 'If the email exists, a password reset link has been sent.',
      });
    }

    if (!user.id) {
      return res.status(500).json({ error: 'Invalid user data' });
    }

    // Generate reset token
    const resetToken = generateDbToken();
    await setResetToken(user.id, resetToken);

    // Send password reset email
    const emailSent = await sendPasswordResetEmail(email, resetToken);
    if (!emailSent) {
      return res.status(500).json({ error: 'Failed to send password reset email' });
    }

    return res.json({
      message: 'If the email exists, a password reset link has been sent.',
    });
  } catch (error) {
    console.error('Forgot password error:', error);
    res.status(500).json({ error: 'Internal server error' });
    return;
  }
});

// Reset password
router.post('/reset-password', async (req: Request<{}, {}, ResetPasswordBody>, res: Response) => {
  try {
    const { token, password } = req.body;

    if (!token || !password) {
      return res.status(400).json({ error: 'Token and password are required' });
    }

    if (password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters long' });
    }

    const user = await getUserByResetToken(token);
    if (!user || !user.id) {
      return res.status(400).json({ error: 'Invalid or expired reset token' });
    }

    // Update password
    const passwordHash = await hashPassword(password);
    await updatePassword(user.id, passwordHash);

    return res.json({
      message: 'Password reset successfully',
    });
  } catch (error) {
    console.error('Reset password error:', error);
    res.status(500).json({ error: 'Internal server error' });
    return;
  }
});

// Get current user (protected route)
router.get('/me', authenticate, async (req: AuthRequest, res: Response) => {
  try {
    if (!req.user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await getUserById(String(req.user.userId));
    
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    return res.json({
      user: {
        id: user.id,
        email: user.email,
        email_verified: user.email_verified,
        created_at: user.created_at,
      },
    });
  } catch (error) {
    console.error('Get user error:', error);
    res.status(500).json({ error: 'Internal server error' });
    return;
  }
});

export default router;
