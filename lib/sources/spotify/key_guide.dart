import '../../core/strings.dart';
import 'auth.dart';

/// Le guide « créer sa clé Spotify », ouvert dans le navigateur : une page
/// autonome, dans la langue de l'appli. Spotify limite chaque appli non
/// validée à cinq comptes, chacun déclare donc la sienne ; le guide donne
/// le lien, les valeurs à saisir et l'adresse de retour à copier.
String spotifyKeyGuide() {
  final t = _texts[Lang.current] ?? _texts[Lang.fr]!;
  const uri = SpotifyAuth.redirectUri;
  return '''<!doctype html>
<html lang="${Lang.current.name}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${t.title}</title>
<style>
  :root { color-scheme: light dark; --ink: #1c1c1e; --soft: #6b6b70; --paper: #f5f5f7; --card: #ffffff; --line: #e2e2e7; --accent: #1db954; }
  @media (prefers-color-scheme: dark) { :root { --ink: #f2f2f4; --soft: #a0a0a8; --paper: #151517; --card: #1f1f22; --line: #323236; } }
  body { margin: 0; padding: 40px 16px 64px; background: var(--paper); color: var(--ink); font: 16px/1.55 system-ui, -apple-system, "Segoe UI", sans-serif; }
  main { max-width: 640px; margin: 0 auto; }
  h1 { font-size: 28px; line-height: 1.2; margin: 0 0 12px; }
  p.lead { color: var(--soft); margin: 0 0 28px; }
  ol { list-style: none; counter-reset: step; margin: 0; padding: 0; }
  ol > li { counter-increment: step; background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 18px 20px 18px 64px; margin: 0 0 12px; position: relative; }
  ol > li::before { content: counter(step); position: absolute; left: 20px; top: 18px; width: 28px; height: 28px; border-radius: 50%; background: var(--accent); color: #fff; font-weight: 700; display: grid; place-items: center; }
  dl { display: grid; grid-template-columns: max-content 1fr; gap: 6px 16px; margin: 12px 0 0; }
  dt { color: var(--soft); }
  dd { margin: 0; overflow-wrap: anywhere; }
  code { font: 14px ui-monospace, "Cascadia Mono", Menlo, monospace; background: var(--paper); border: 1px solid var(--line); border-radius: 6px; padding: 2px 6px; }
  a.button, button { display: inline-block; margin-top: 12px; padding: 9px 16px; border-radius: 999px; border: 0; background: var(--accent); color: #fff; font: inherit; font-weight: 600; text-decoration: none; cursor: pointer; }
  button.copy { margin: 0 0 0 8px; padding: 3px 12px; font-size: 14px; }
  p.note { color: var(--soft); font-size: 14px; margin: 24px 4px 0; }
</style>
</head>
<body>
<main>
  <h1>${t.title}</h1>
  <p class="lead">${t.lead}</p>
  <ol>
    <li>${t.open}<br><a class="button" href="https://developer.spotify.com/dashboard/create" target="_blank" rel="noopener">${t.openButton}</a></li>
    <li>${t.form}
      <dl>
        <dt>App name</dt><dd>KliqPlayer</dd>
        <dt>App description</dt><dd>${t.description}</dd>
        <dt>Redirect URI</dt><dd><code id="uri">$uri</code><button class="copy" onclick="navigator.clipboard.writeText('$uri'); this.textContent = '${t.copied}'">${t.copy}</button><br><small>${t.already}</small></dd>
        <dt>APIs used</dt><dd>Web API</dd>
      </dl>
      <p>${t.save}</p>
    </li>
    <li>${t.clientId}</li>
    <li>${t.back}</li>
  </ol>
  <p class="note">${t.note}</p>
</main>
</body>
</html>
''';
}

typedef _Guide = ({
  String title,
  String lead,
  String open,
  String openButton,
  String form,
  String description,
  String copy,
  String copied,
  String already,
  String save,
  String clientId,
  String back,
  String note,
});

const _texts = <Lang, _Guide>{
  Lang.fr: (
    title: 'Votre clé Spotify pour KliqPlayer',
    lead: 'Spotify demande à chacun sa propre clé d’appli. C’est gratuit, ça prend cinq minutes et ce n’est à faire qu’une fois. Il faut un compte Spotify Premium.',
    open: 'Ouvrez le tableau de bord de Spotify et connectez-vous avec votre compte.',
    openButton: 'Ouvrir le tableau de bord',
    form: 'Remplissez le formulaire « Create app » avec ces valeurs :',
    description: 'Lecteur personnel',
    copy: 'Copier',
    copied: 'Copié',
    already: 'Elle est déjà dans votre presse-papiers : il suffit de la coller, puis de cliquer sur « Add ».',
    save: 'Acceptez les conditions, puis cliquez sur « Save ».',
    clientId: 'Sur la page de votre appli, copiez le <strong>Client ID</strong>.',
    back: 'Revenez dans KliqPlayer : <strong>Réglages › Bibliothèque › Spotify › Coller la clé</strong>, puis <strong>Se connecter</strong>.',
    note: 'Le Client ID n’est pas un mot de passe : seul, il ne donne accès à rien. KliqPlayer le garde sur cet ordinateur.',
  ),
  Lang.en: (
    title: 'Your Spotify key for KliqPlayer',
    lead: 'Spotify asks every user for their own app key. It is free, takes five minutes and only has to be done once. You need a Spotify Premium account.',
    open: 'Open the Spotify dashboard and sign in with your account.',
    openButton: 'Open the dashboard',
    form: 'Fill in the “Create app” form with these values:',
    description: 'Personal player',
    copy: 'Copy',
    copied: 'Copied',
    already: 'It is already in your clipboard: paste it, then click “Add”.',
    save: 'Accept the terms, then click “Save”.',
    clientId: 'On your app’s page, copy the <strong>Client ID</strong>.',
    back: 'Back in KliqPlayer: <strong>Settings › Library › Spotify › Paste Key</strong>, then <strong>Sign In</strong>.',
    note: 'The Client ID is not a password: on its own it gives access to nothing. KliqPlayer keeps it on this computer.',
  ),
  Lang.es: (
    title: 'Tu clave de Spotify para KliqPlayer',
    lead: 'Spotify pide a cada usuario su propia clave de aplicación. Es gratis, lleva cinco minutos y solo se hace una vez. Necesitas una cuenta Spotify Premium.',
    open: 'Abre el panel de Spotify e inicia sesión con tu cuenta.',
    openButton: 'Abrir el panel',
    form: 'Rellena el formulario «Create app» con estos valores:',
    description: 'Reproductor personal',
    copy: 'Copiar',
    copied: 'Copiado',
    already: 'Ya está en tu portapapeles: pégala y haz clic en «Add».',
    save: 'Acepta las condiciones y haz clic en «Save».',
    clientId: 'En la página de tu aplicación, copia el <strong>Client ID</strong>.',
    back: 'Vuelve a KliqPlayer: <strong>Ajustes › Biblioteca › Spotify › Pegar clave</strong> y después <strong>Iniciar sesión</strong>.',
    note: 'El Client ID no es una contraseña: por sí solo no da acceso a nada. KliqPlayer lo guarda en este ordenador.',
  ),
  Lang.de: (
    title: 'Dein Spotify-Schlüssel für KliqPlayer',
    lead: 'Spotify verlangt von jedem Nutzer einen eigenen App-Schlüssel. Das ist kostenlos, dauert fünf Minuten und ist nur einmal nötig. Du brauchst ein Spotify-Premium-Konto.',
    open: 'Öffne das Spotify-Dashboard und melde dich mit deinem Konto an.',
    openButton: 'Dashboard öffnen',
    form: 'Fülle das Formular „Create app“ mit diesen Werten aus:',
    description: 'Persönlicher Player',
    copy: 'Kopieren',
    copied: 'Kopiert',
    already: 'Sie liegt schon in deiner Zwischenablage: einfügen und auf „Add“ klicken.',
    save: 'Akzeptiere die Bedingungen und klicke auf „Save“.',
    clientId: 'Kopiere auf der Seite deiner App die <strong>Client ID</strong>.',
    back: 'Zurück in KliqPlayer: <strong>Einstellungen › Mediathek › Spotify › Schlüssel einfügen</strong>, dann <strong>Anmelden</strong>.',
    note: 'Die Client ID ist kein Passwort: Allein gibt sie auf nichts Zugriff. KliqPlayer speichert sie auf diesem Computer.',
  ),
};
