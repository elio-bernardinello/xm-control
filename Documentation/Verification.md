# Vérification et livraison

## Contrôles reproductibles sans casque

```sh
swift test
./Scripts/build_app.sh release
plutil -lint ".build/XM Control.app/Contents/Info.plist"
codesign --verify --strict --verbose=1 ".build/XM Control.app"
```

Les tests utilisent des données et transports simulés : pas de recherche Bluetooth, pas d’ouverture de canal et pas de commande au casque. Scénarios couverts : choix du casque (XM4/XM5/XM6, nom personnalisé, préférence de modèle, adresse mémorisée), encodage/décodage, réponses partielles de mode, commandes absentes ou tardives et fin de session. Le succès démontre uniquement le comportement couvert par les assertions.

Contrôler dans le paquet : exécutable, icône vectorielle (aucune photo Sony incluse), `LICENSE`, `ImageCredits.txt`, version et identifiant `app.xmcontrol`. Une signature ad hoc vérifiée n’est ni une notarisation ni une garantie que Gatekeeper acceptera une archive téléchargée sur une autre machine.

Avant publication GitHub : lancer une recherche de données personnelles (identifiant mail, nom de famille, chemin absolu avec votre nom d’utilisateur, prénom privé) avec `--exclude-dir=.build --exclude-dir=.git` : elle doit être vide. Les noms de modules historiques `XM6Control` / `XM6Probe` sont conservés volontairement.

## Inspection visuelle

- Apparences claire et sombre ; fenêtre à 560 et 840 points de large, puis écran de faible hauteur.
- Accueil : nom personnalisé + modèle détecté ; connexion en cours, échec et nouvelle tentative compréhensibles ; message si plusieurs XM détectés.
- Réglages : nom affiché, prénom optionnel, modèle, liste des XM jumelés, oubli du casque mémorisé.
- Panneau : Cinéma toujours accessible ; défilement limité aux réglages secondaires ; aucun débordement.
- Musique de fond : cartes Chambre / Salon / Café, sélection par une coche et un libellé, état en attente compréhensible.
- Clavier : ordre de tabulation, focus visible, raccourcis modes et `⌘,` ; aucune commande de casque active hors connexion.
- VoiceOver : nom, valeur et état des boutons, niveaux ambiants, égaliseur et batterie. Contraste et tailles de texte lisibles dans les deux thèmes.
- Accessibilité macOS « Réduire les animations » : aucun mouvement décoratif ; état compréhensible sans mouvement.
- Mini-panneau : intitulé cohérent, absence d’allusion à un lecteur audio.

## Validation réelle à effectuer avec chaque génération

Quitter toute ancienne version avant de lancer la nouvelle application. Ne pas remplacer une copie installée pour ce contrôle. Répéter pour XM4, XM5 et XM6 quand possible.

1. Relever modèle, nom Bluetooth, nom affiché personnalisé, micrologiciel et version de macOS. Vérifier autorisation Bluetooth et reconnexion au lancement.
2. Avant la connexion, mémoriser réduction de bruit et niveau ambiant (y compris zéro). Vérifier qu’ouvrir l’application ne les modifie pas.
3. Passer Standard → Cinéma → Musique de fond ; vérifier l’état confirmé et l’effet audible. Sur XM4/XM5, noter les fonctions restées « non communiquées » : c’est attendu si le casque ne les rapporte pas.
4. Tester rapidement plusieurs choix et déplacements de curseur. Vérifier la dernière valeur après stabilisation, sans rebond visuel ni réponse ancienne. Changer le mode de bruit avec le bouton du casque : le panneau doit le suivre immédiatement, sans rester sur « Désactivé », puis l'inverse depuis l'application.
5. Éteindre le casque pendant une commande, le rallumer, reconnecter. Vérifier l’absence d’activité de l’ancienne session et un message d’échec compréhensible.
6. Vérifier le contrôle audio multipoint et les réglages secondaires effectivement utilisés.
7. Fermer et rouvrir fenêtre et mini-panneau ; activer puis désactiver le mode barre des menus. Les réglages doivent rester accessibles.
8. Personnalisation : saisir `Mon XM5`, choisir `XM5`, sélectionner le casque dans la liste, quitter/relancer : le choix doit persister sans ressaisie.

## Fluidité : mesures, pas suppositions

Utiliser Instruments (Time Profiler, Hangs, SwiftUI et allocations selon leur disponibilité) pour observer lancement, connexion, changements de mode et déplacements rapides de curseurs. Examiner l’activité au repos et les écritures Bluetooth/journal, avec diagnostic activé puis désactivé. Relever durée, machine et scénario avant toute affirmation chiffrée sur CPU, mémoire ou latence. Le cache image et le regroupement de commandes réduisent un travail identifié dans le code ; leur gain réel reste à mesurer.

## Paquet prêt à partager

Conserver les anciennes livraisons. Copier le produit vérifié vers le dossier de sortie demandé puis l’archiver en préservant le bundle macOS, par exemple :

```sh
ditto -c -k --sequesterRsrc --keepParent ".build/XM Control.app" "XM-Control-1.0.zip"
```

Ouvrir la nouvelle version demande une action distincte de la compilation. Ne pas la lancer dans les contrôles automatiques. Toute diffusion publique nécessite une revue des droits (aucune photo Sony incluse par défaut) et, selon le canal, de la signature et de la notarisation.
