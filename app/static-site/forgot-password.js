// Script externe, pas inline : la Content-Security-Policy de ce lab
// (default-src 'self', voir nginx/snippets/security-headers.conf) bloque
// tout <script> en ligne sans 'unsafe-inline' -- jamais ajouté
// volontairement, un fichier externe même-origine (autorisé par 'self')
// est la solution correcte plutôt qu'affaiblir la CSP.
document.getElementById('forgot-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const email = document.getElementById('email').value;
  const res = await fetch('/api/auth/forgot-password', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email }),
  });
  document.getElementById('result').textContent = res.ok
    ? 'Si ce compte existe, un email a été envoyé.'
    : 'Une erreur est survenue.';
});
