# Mots de passe : hachage, coût, et pourquoi pas de règles de complexité

## Jamais stocké, jamais chiffré : haché

Un mot de passe ne doit jamais être stocké en clair, ni même **chiffré**
(le chiffrement se déchiffre avec une clé — si cette clé fuit, tous les
mots de passe redeviennent lisibles d'un coup). Il doit être **haché** :
une fonction à sens unique, impossible à inverser mathématiquement.
Vérifier un mot de passe ne consiste donc jamais à le "déchiffrer" pour
comparer, mais à hacher la valeur soumise et comparer les deux empreintes.

## Pourquoi pas un hachage générique (SHA-256, MD5...)

Un hachage générique (SHA-256, conçu pour l'intégrité de fichiers, pas
pour des mots de passe) est **trop rapide** — des milliards de tentatives
par seconde sur du matériel dédié (GPU), rendant une attaque par
force brute ou par dictionnaire réaliste dès qu'une base de hachages
fuit. Les fonctions dédiées aux mots de passe (bcrypt, scrypt, Argon2)
sont délibérément **lentes et coûteuses en mémoire**, réglables, pour
rendre ce même calcul irréalisable à grande échelle même avec du matériel
puissant.

## Le "coût" bcrypt

bcrypt prend un paramètre de coût (`12` dans ce lab) : chaque incrément
**double** le temps de calcul nécessaire pour hacher (et donc pour
vérifier) un mot de passe. Choisir ce nombre est un compromis :

- trop bas → hachage rapide à casser par force brute hors ligne (si la
  base fuit) ;
- trop haut → chaque connexion légitime devient lente, et le serveur peut
  saturer sous une charge de connexions normale.

Un repère courant : viser un temps de hachage de l'ordre de 100-300ms sur
le matériel de production réel — `12` correspond à cet ordre de grandeur
sur du matériel serveur courant en 2026, à réévaluer si le matériel
change significativement (une bonne pratique est de mesurer, pas de
recopier un chiffre trouvé en ligne sans le vérifier sur sa propre
machine).

## Pourquoi pas de règles de composition imposées

Longtemps la norme ("au moins une majuscule, un chiffre, un symbole"),
ces règles sont aujourd'hui déconseillées par les référentiels
sécurité les plus cités (NIST SP 800-63B, § 5.1.1) : elles poussent les
utilisateurs vers des motifs prévisibles pour un humain qui doit s'en
souvenir (`Password1!`, `Azerty123!`) — plus faciles à deviner pour un
outil de craquage qui connaît ces motifs qu'un mot de passe long mais
sans contrainte de forme. La recommandation actuelle privilégie :

- une **longueur minimale** généreuse (ce lab : 10 caractères — NIST
  recommande d'autoriser au moins 64 caractères, sans l'imposer) ;
- la vérification contre une liste de mots de passe déjà compromis
  connus (non implémenté ici — nécessiterait une base externe type "Have
  I Been Pwned" API, hors périmètre de ce lab) plutôt que des règles de
  forme arbitraires ;
- encourager les phrases de passe (plus longues, plus mémorisables,
  souvent plus fortes qu'un mot de passe court "complexe").
