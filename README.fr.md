# XM Control

Une application macOS native pour piloter les casques **Sony WH-1000XM4 / XM5 / XM6**, avec un accès direct à **Standard / Musique de fond / Cinéma** depuis la barre des menus.

Dérivée de [XM6 Control, par Rui Martins](https://github.com/ruimartins23/xm6-control). Les noms de modules Swift historiques (`SonyHeadphonesKit`, `XM6Control`) sont conservés pour limiter les changements ; seul le produit visible est générique : **XM Control**.

## Personnalisation

Dans **XM Control → Réglages…** (`⌘,`) :

- **Nom affiché du casque** : texte libre, par ex. `Casque de Marie`, `Mon XM6`, `XM4`. Affiché dans la fenêtre, le menu et les annonces. Vide par défaut (`Mon casque`).
- **Votre prénom (optionnel)** : stocké localement uniquement, jamais envoyé.
- **Modèle** : `Automatique`, `XM4`, `XM5`, `XM6`. Aide à choisir quand plusieurs casques XM sont jumelés.
- **Casque suivi** : liste des appareils XM jumelés + `Automatique`. L’adresse mémorisée reste prioritaire même après un renommage. `Oublier le casque mémorisé` relance la détection.

La détection automatique reconnaît :
`WH-1000XM4`, `WH-1000XM5`, `WH-1000XM6` et tout nom personnalisé contenant `XM4` / `XM5` / `XM6` (ex. `Mon XM6`). S’il ne reste qu’un seul candidat, il est choisi. S’il y en a plusieurs, l’app demande un choix explicite au lieu d’en inventer un.

## Utilisation

- Jumeler le casque dans **Réglages Système → Bluetooth**, l’allumer et autoriser le Bluetooth au premier lancement.
- L’app tente de rejoindre le casque mémorisé ou le seul candidat XM. Si le casque est déjà connecté en audio, la session Sony est rejointe automatiquement (sans clic) en quelques secondes et au retour au premier plan.
- Si le casque est jumelé mais non connecté, **Se connecter** demande d’abord à macOS d’établir la liaison Bluetooth, puis ouvre la session Sony.
- Les réglages s’ouvrent une fois la session établie. La barre des menus donne accès aux modes d’écoute, à la batterie et à la réduction de bruit ; la fenêtre principale regroupe les réglages détaillés.
- **XM Control → Réglages…** contient le mode « Barre des menus uniquement » et le diagnostic. Le mini-panneau est un petit contrôle du casque, sans commande de lecture audio.
- Raccourcis `⌘⌥1`, `⌘⌥2`, `⌘⌥3` : Standard, Musique de fond, Cinéma (app active et connectée).

La connexion de commande Bluetooth est distincte de la sortie audio macOS : une musique audible ne garantit pas que le casque accepte déjà une session de contrôle. Une sélection envoyée doit être confirmée par les réponses du casque ; en cas d’échec, vérifier la connexion avant de réessayer.

## Guide de fonctionnement en 2 minutes

1. **Connexion sans clic.** Allumez le casque déjà jumelé : s’il est connecté en audio macOS, l’app le rejoint seule en quelques secondes (pareil au retour premier plan). Sinon, **Se connecter** demande d’abord à macOS d’établir le Bluetooth, puis ouvre la session Sony.
2. **Mode Cinéma pour un film sur Mac.** Barre des menus → **Cinéma** (ou `⌘⌥3`). L’affichage distingue `demandé` / `confirmé par le casque` / `non confirmé` : seul le confirmé compte pour le son. Si ça ne confirme pas, revérifiez la liaison avant de réessayer.
3. **Le téléphone a volé la connexion ?** Carte **Source audio** : la lecture en cours est marquée `Actif`. Mettez l’autre appareil en pause, touchez **Utiliser** sur le Mac. Si l’iPhone rejoue aussitôt, remettez-le en pause puis recommencez — l’app vous le dit.
4. **Égaliseurs à portée de main.** Presets Sony + curseurs 10 bandes + 2 raccourcis :
   - **Film** : basses présentes, dialogues maintenus — pour films/séries.
   - **Voix** : ronron coupé, 500 Hz–2 kHz poussés — pour dialogues, podcasts, appels.
   Un clic applique la courbe (le casque bascule en `Personnalisé`). Les curseurs restent éditables après.
5. **Perso.** Réglages : nom affiché (`Casque de Marie`), modèle, casque suivi. Rien n’est envoyé nulle part.

FAQ : `Chargement…` puis `non communiqué` = le casque ne l’a pas rapporté (normal sur XM4/XM5 pour certaines fonctions). `Le casque ne répond pas` = lien perdu : rallumez, reconnectez en audio macOS, puis **Se connecter**. Journal désactivé par défaut.

## Construire

macOS 13 minimum et outils Apple compatibles avec **Swift 6** (`swift --version`).

```sh
swift test
./Scripts/build_app.sh
open ".build/XM Control.app"
```

Le script produit une application autonome dans `.build/XM Control.app`. Il assemble les fichiers dans un dossier temporaire, vérifie la signature, puis remplace uniquement son produit de compilation. Il ne lance rien et ne remplace aucune application installée. Identifiant : `app.xmcontrol`.

La signature utilise votre certificat `Apple Development` s’il existe, sinon `XMDev`, sinon ad hoc (`XM_SIGN_IDENTITY` pour forcer). Une nouvelle compilation peut redemander l’autorisation Bluetooth. Ce paquet local n’est pas signé ni notarié pour distribution Apple.

[Architecture](Documentation/Architecture.md) · [Livraison et vérification](Documentation/Verification.md)

## Capacités et limites (XM4 / XM5 / XM6)

Réduction de bruit, son ambiant et niveau, modes d’écoute et distance des enceintes, égaliseur, batterie, multipoint, Speak-to-Chat, détection du port, extinction automatique : chaque fonction n’est affichée que si le casque la rapporte vraiment. `Chargement…` puis `non communiqué` signifie que le modèle ou le firmware ne l’a pas confirmée, pas un bug d’affichage.

- Le protocole partagé (transport Sony « v2 », utilisé par XM5/XM6) est implémenté ; XM4 fonctionne en sous-ensemble compatible.
- BGM / Cinéma et certains réglages fins sont d’abord validés XM6 : sur XM4/XM5, ils peuvent rester indisponibles selon les réponses du casque.
- Les tests automatisés simulent protocole et sessions ; ils ne prouvent ni l’effet acoustique ni la fiabilité d’un lien Bluetooth réel. Valider chaque génération avec son casque via la grille de vérification. Aucune valeur CPU / conso / latence garantie sans mesure.

## Diagnostic

Si le casque ne répond pas, vérifier sa connexion dans Réglages Système, puis retenter depuis sa carte. Déconnecter puis reconnecter dans macOS si besoin. L’oubli et le nouvel appairage restent un dernier recours.

Le journal est optionnel et désactivé par défaut : `~/Library/Application Support/XM Control/protocol.log`. Il peut contenir noms et adresses : le relire avant tout partage. Le menu Réglages permet d’ouvrir son dossier. Une connexion ne doit jamais changer silencieusement vos réglages du casque.

## Origine, images et licence

Code : [licence MIT et attribution originale à Rui Martins](LICENSE). Références protocole : [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge), [SonyHeadphonesClient](https://github.com/Plutoberth/SonyHeadphonesClient) et [son fork mos9527](https://github.com/mos9527/SonyHeadphonesClient). Sans garantie sur chaque commande.

**Aucune image Sony incluse.** L’interface utilise une illustration vectorielle. Voir [ImageCredits.txt](Sources/XM6Control/Resources/ImageCredits.txt) pour ajouter votre propre `headphones.png` locale (non redistribuée). Ne publiez jamais de visuel Sony sans droit.

XM Control est indépendant de Sony et d’Apple, sans affiliation ni approbation. Marques et visuels appartiennent à leurs titulaires.
