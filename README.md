# Guild Cotiz

Addon WoW (Retail — The War Within) pour suivre les **cotisations de guilde** : qui dépose au coffre, combien, semaine par semaine, et **qui n'est plus à jour**.

## Principe (modèle « solde cumulé »)

- Tu définis une **cotisation hebdomadaire attendue** (ex. 100 po/semaine).
- L'addon lit le **journal d'or du coffre de guilde** et additionne les dépôts de chaque membre.
- Un joueur peut déposer **un gros montant d'un coup** : il couvre alors plusieurs semaines d'avance.
- L'addon calcule pour chaque membre :
  - le **total déposé**,
  - le nombre de **semaines écoulées** depuis le début du suivi,
  - le **solde** (payé − dû),
  - jusqu'à quelle date il est **couvert**,
  - et s'il est **en retard** (de combien de semaines / combien d'or il manque).

## Installation

1. Copie le dossier `GuildCotiz` dans :
   `World of Warcraft\_retail_\Interface\AddOns\`
   → tu dois obtenir `...\Interface\AddOns\GuildCotiz\GuildCotiz.toc`
2. Relance WoW (ou `/reload`).
3. Sur l'écran de sélection des personnages, coche **« Afficher les extensions obsolètes »** si l'addon n'apparaît pas (le numéro d'interface du `.toc` peut être à mettre à jour selon le patch).

## Utilisation

- `/cotiz` ou `/gc` : ouvre la fenêtre.
- **Régler la cotisation** : bouton *Montant hebdo* (ou `/cotiz set 100`).
- **Régler le début du suivi** : bouton *Début de suivi* (ou `/cotiz start 2026-07-01`). Par défaut = aujourd'hui au 1er lancement.
- **Enregistrer les dépôts** : ouvre le **coffre de guilde** en jeu → l'addon scanne automatiquement le journal d'or et enregistre les nouveaux dépôts. (Bouton *Scanner le coffre* / `/cotiz scan` pour forcer, coffre ouvert.)
- **Vue Résumé** : tous les membres avec leur statut. Clique un joueur pour voir son détail.
- **Vue Détail par semaine** : semaine par semaine pour un joueur (tape son nom dans le champ *Joueur* puis Entrée). Les semaines **non payées** apparaissent en rouge, les semaines **couvertes par une avance** en bleu.
- **Filtrer** : champ *Joueur* en haut.

## Export CSV (vers Excel / Google Sheets)

- Bouton **Export résumé** : un tableau par joueur (total, solde, statut, date de couverture…).
- Bouton **Export semaine** : le détail semaine par semaine (du joueur affiché en vue Détail, sinon tous).
- Une fenêtre s'ouvre avec le texte CSV : **Ctrl+A** (tout sélectionner) puis **Ctrl+C**, et **colle** dans Excel ou Google Sheets.
- Séparateur `;` (adapté à Excel FR). Les montants sont en **or** avec 2 décimales.

> Les données sont aussi sauvegardées automatiquement par WoW dans
> `WTF\Account\<compte>\SavedVariables\GuildCotizDB.lua` (format Lua, utile en secours).

## Points de vigilance

- **Le journal d'or du coffre est limité** : WoW ne conserve qu'un nombre restreint de transactions récentes. Pour ne rien manquer, **ouvre le coffre régulièrement** (idéalement chaque semaine). L'addon dédoublonne les dépôts déjà enregistrés, donc rouvrir le coffre ne crée pas de doublons.
- Seuls les **dépôts d'or** sont comptés comme cotisation (pas les retraits ni les objets).
- Il faut **le droit de voir le journal du coffre** (permission de rang) pour que le scan fonctionne.
- Le numéro `## Interface:` du `.toc` (110200) est peut-être à ajuster selon le patch courant ; sinon coche « extensions obsolètes ».
- L'alignement des colonnes utilise la police par défaut de WoW : c'est lisible mais pas parfaitement aligné. On pourra l'affiner après un premier test en jeu.

## Fichiers

- `GuildCotiz.toc` — description de l'addon.
- `Core.lua` — lecture du coffre, dédoublonnage, calculs de cotisation.
- `Export.lua` — génération CSV + fenêtre copier-coller.
- `UI.lua` — fenêtre principale, filtres, commandes `/cotiz`.
