const nodemailer = require('nodemailer');

// Mailpit en local (voir scripts/install-mailpit.sh) : aucune authentification,
// pas de TLS -- un vrai fournisseur en production exigerait les deux.
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || '127.0.0.1',
  port: Number(process.env.SMTP_PORT) || 1025,
  secure: false,
  ignoreTLS: true,
});

async function sendPasswordResetEmail(to, resetUrl) {
  await transporter.sendMail({
    from: 'no-reply@secure-web-lab.local',
    to,
    subject: 'Réinitialisation de votre mot de passe',
    text:
      'Une demande de réinitialisation de mot de passe a été faite pour ce compte.\n\n' +
      `Lien de réinitialisation (valable 30 minutes) : ${resetUrl}\n\n` +
      "Si vous n'êtes pas à l'origine de cette demande, ignorez cet email.",
  });
}

module.exports = { sendPasswordResetEmail };
