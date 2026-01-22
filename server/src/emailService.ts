import formData from 'form-data';
import Mailgun from 'mailgun.js';

const MAILGUN_API_KEY = process.env.MAILGUN_API_KEY || '';
const DOMAIN = process.env.MAILGUN_DOMAIN || '';
const FROM_EMAIL = process.env.MAILGUN_FROM_EMAIL || `noreply@${DOMAIN}`;
const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

// Initialize Mailgun client only if API key is provided
let mg: ReturnType<typeof Mailgun.prototype.client> | null = null;

if (MAILGUN_API_KEY && DOMAIN) {
  try {
    const mailgun = new Mailgun(formData);
    mg = mailgun.client({
      username: 'api',
      key: MAILGUN_API_KEY,
    });
  } catch (error) {
    console.warn('Failed to initialize Mailgun client:', error);
  }
}

// Send verification email
export const sendVerificationEmail = async (email: string, token: string): Promise<boolean> => {
  if (!mg || !MAILGUN_API_KEY || !DOMAIN) {
    console.warn('Mailgun not configured. Skipping email send.');
    return false;
  }

  const verificationUrl = `${BASE_URL}/api/auth/verify-email?token=${token}`;

  const messageData = {
    from: FROM_EMAIL,
    to: email,
    subject: 'Verify your HearNow account',
    html: `
      <!DOCTYPE html>
      <html>
        <head>
          <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .button { display: inline-block; padding: 12px 24px; background-color: #007bff; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
            .button:hover { background-color: #0056b3; }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>Welcome to HearNow!</h1>
            <p>Thank you for signing up. Please verify your email address by clicking the button below:</p>
            <a href="${verificationUrl}" class="button">Verify Email</a>
            <p>Or copy and paste this link into your browser:</p>
            <p><a href="${verificationUrl}">${verificationUrl}</a></p>
            <p>This link will expire in 24 hours.</p>
            <p>If you didn't create an account, please ignore this email.</p>
          </div>
        </body>
      </html>
    `,
    text: `
      Welcome to HearNow!
      
      Thank you for signing up. Please verify your email address by visiting this link:
      ${verificationUrl}
      
      This link will expire in 24 hours.
      
      If you didn't create an account, please ignore this email.
    `,
  };

  try {
    await mg.messages.create(DOMAIN, messageData);
    console.log(`Verification email sent to ${email}`);
    return true;
  } catch (error) {
    console.error('Error sending verification email:', error);
    return false;
  }
};

// Send password reset email
export const sendPasswordResetEmail = async (email: string, token: string): Promise<boolean> => {
  if (!mg || !MAILGUN_API_KEY || !DOMAIN) {
    console.warn('Mailgun not configured. Skipping email send.');
    return false;
  }

  const resetUrl = `${BASE_URL}/api/auth/reset-password?token=${token}`;

  const messageData = {
    from: FROM_EMAIL,
    to: email,
    subject: 'Reset your HearNow password',
    html: `
      <!DOCTYPE html>
      <html>
        <head>
          <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .button { display: inline-block; padding: 12px 24px; background-color: #dc3545; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
            .button:hover { background-color: #c82333; }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>Password Reset Request</h1>
            <p>You requested to reset your password. Click the button below to reset it:</p>
            <a href="${resetUrl}" class="button">Reset Password</a>
            <p>Or copy and paste this link into your browser:</p>
            <p><a href="${resetUrl}">${resetUrl}</a></p>
            <p>This link will expire in 1 hour.</p>
            <p>If you didn't request a password reset, please ignore this email.</p>
          </div>
        </body>
      </html>
    `,
    text: `
      Password Reset Request
      
      You requested to reset your password. Visit this link to reset it:
      ${resetUrl}
      
      This link will expire in 1 hour.
      
      If you didn't request a password reset, please ignore this email.
    `,
  };

  try {
    await mg.messages.create(DOMAIN, messageData);
    console.log(`Password reset email sent to ${email}`);
    return true;
  } catch (error) {
    console.error('Error sending password reset email:', error);
    return false;
  }
};
