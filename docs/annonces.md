<!--
Annonces Discord des nouvelles versions, écrites pour les joueurs (en français). Le bot de la
guilde publie l'entrée d'une version quand elle sort. Entrée la plus récente en premier.

Titre d'une entrée : ce qui est annoncé ensemble, dans un seul message.
  ## Addon vX.Y.Z
  ## Compagnon X.Y.Z
  ## Addon vX.Y.Z + Compagnon X.Y.Z
Corps : une courte liste à puces en markdown Discord (gras, `code`), 1500 caractères au plus.

Ordre de publication :
  1. écrire l'entrée ici ;
  2. commit et push sur main ;
  3. addon : companion\.venv\Scripts\python release.py --upload (refuse sans entrée
     "## Addon vX.Y.Z" ; --sans-annonce pour publier sans annonce) ;
  4. tag (companion-vX.Y.Z pour le compagnon : le workflow s'arrête sans entrée "Compagnon X.Y.Z").
-->

## Addon v0.5.0 + Compagnon 0.6.0

- **Métiers sur Discord** : l'addon note les recettes que vous connaissez (avec leur couleur : orange, jaune, vert, gris) et le niveau de tous vos métiers, récolte comprise
- **À faire une fois** : ouvrez la fenêtre de chacun de vos métiers en jeu. Ensuite ils se mettent à jour à chaque ouverture, rien ne s'affiche en jeu
- **Mettez à jour le compagnon en 0.6.0** (menu du compagnon > **Check for updates**) : c'est lui qui envoie vos métiers au bot, au `/reload` ou à la déconnexion
- Addon : mettez-le à jour depuis CurseForge
