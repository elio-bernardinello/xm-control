# Architecture de XM Control

## Séparation des responsabilités

- `Sources/XM6Control` : application SwiftUI, fenêtre principale, panneau de barre des menus, mini-panneau, préférences natives, composants et ressources visuelles. `AppSettings` gère uniquement les préférences de l’application. L’identité de distribution est « XM Control » ; les noms historiques des modules (`XM6Control`, `XM6Probe`) restent internes pour limiter le churn.
- `Sources/SonyHeadphonesKit` : modèles, construction/décodage des messages Sony, réassemblage des trames, transport RFCOMM IOBluetooth, cycle de session et état observable du casque. L’interface appelle le contrôleur ; elle ne construit pas de paquets Bluetooth.
- `Sources/SonyHeadphonesKit/Models/HeadsetModel.swift` : générations prises en charge (XM4/XM5/XM6), détection depuis le nom Bluetooth, préférence de modèle.
- `Tests/SonyHeadphonesKitTests` : tests sans connexion à un casque. Un transport injectable permet de simuler les réponses, les échecs et la fin d’une session sans toucher aux appareils appairés.
- `Sources/XM6Probe` : outil historique de diagnostic matériel. Il peut envoyer de vraies commandes ; il ne fait pas partie des tests automatiques ni du paquet de l’application.
- `Scripts/build_app.sh` : compilation du seul produit d’application, génération d’icône vectorielle, assemblage et signature locale.

## Composants de session

- `HeadphonesTransport` rend le transport remplaçable par une simulation en mémoire (`isLinked` retourne faux dans les tests).
- `RFCOMMConnection` et ses sessions déléguées gardent IOBluetooth sur sa run loop, écrivent de façon asynchrone et isolent les anciennes tentatives. Un plafond de sessions OS non terminées évite des tentatives sans borne. `findLikelyXM()` couvre XM4/XM5/XM6.
- `HeadsetCommandQueue` garde explicitement la commande en vol et regroupe les valeurs non encore envoyées.
- `PersonalHeadsetPreferences` : adresse mémorisée, nom affiché personnalisé, prénom optionnel, préférence de modèle. Aucune valeur personnelle n’est pré-remplie.
- `PersonalHeadsetSelection` : adresse mémorisée > nom personnalisé exact > unique candidat XM (filtré par modèle préféré si besoin) > sinon choix explicite requis.
- `HeadsetSessionTiming` permet des délais courts contrôlés dans les tests.
- `HeadphonesController` réconcilie les événements, les valeurs demandées et les valeurs rapportées ; `FeatureAvailability` différencie lecture en cours, disponible et non communiqué (indispensable pour XM4/XM5 où certaines fonctions n’existent pas).

## Cycle d’une commande

Le contrôleur distingue le choix demandé, l’envoi sur une session active et l’état rapporté par le casque. Le mode d’écoute regroupe deux paramètres Sony indépendants (Musique de fond et Cinéma) : des réponses partielles ne doivent pas entraîner de faux passages visibles par Standard pendant la transition.

La file sérialise les échanges et associe leur attente à une session. Une déconnexion, une erreur ou un délai expiré doit terminer les opérations correspondantes et empêcher une ancienne réponse de modifier la session suivante. Les valeurs de curseurs peuvent être regroupées pour éviter l’accumulation de positions périmées ; la dernière valeur doit être conservée.

Le protocole historique utilise RFCOMM, des trames échappées et un bit de séquence alterné. La réussite d’un envoi local ou d’un accusé de réception ne prouve pas à elle seule l’application d’un réglage. Une retransmission ambiguë ne doit pas être ajoutée sans preuve matérielle de son comportement.

## Préférences et ressources

`app.xmcontrol` pour les préférences et permissions. Journal dans `XM Control` (ancien dossier `XM6 Control` conservé à part pour migration lecture seule). Diagnostic borné à trois archives plus le fichier actif (au plus environ 8 Mo). Les noms et adresses mémorisés servent à retrouver le casque, sans exposer la liste générale Bluetooth sur l’accueil ; la liste XM complète n’apparaît que dans Réglages pour un choix explicite.

Aucune photo Sony incluse : `HeadphoneIllustration` vectorielle par défaut, `headphones.png` utilisateur optionnel dans Application Support. La licence MIT et les crédits sont inclus dans `Contents/Resources`. Diagnostic et mode barre des menus dans la scène native Réglages, séparés des paramètres du casque.

## Évolution

Privilégier des changements circonscrits et des scénarios simulés reproductibles. Conserver la provenance, éviter les renommages massifs de modules et les migrations de préférences sans bénéfice utilisateur. Toute évolution de protocole doit préciser modèle (XM4/XM5/XM6), micrologiciel et observations matérielles qui la justifient.
