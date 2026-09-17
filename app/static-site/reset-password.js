// Externe, pas inline -- même raison que forgot-password.js (CSP).
const token = new URLSearchParams(window.location.search).get('token');

document.getElementById('reset-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const password = document.getElementById('password').value;
  const res = await fetch('/api/auth/reset-password', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token, password }),
  });
  document.getElementById('result').textContent = res.ok
    ? 'Mot de passe mis à jour, vous pouvez vous reconnecter.'
    : 'Lien invalide ou expiré.';
});
