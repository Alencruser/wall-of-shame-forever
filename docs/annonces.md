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

## Addon v0.6.2 + Compagnon 0.7.1

- **Fenêtre des commandes plus grande** : vos commandes à gauche, leurs **composants** à droite. Cliquez le nom d'un acheteur pour ses composants, ou **Total** pour toutes vos commandes
- **Ce que vous avez déjà** : chaque composant affiche *possédés / nécessaires* (sacs et banque), en vert quand vous en avez assez, en rouge sinon, avec le nombre d'objets qui manquent. Ça se met à jour quand vous ramassez ou achetez
- Au survol d'une commande : ses composants et la réponse que vous avez laissée à l'acheteur sur le site des commandes
- **Métiers** : quelques corrections (niveaux envoyés même après avoir réactivé le partage, anciennes recettes oubliées quand un métier est désappris)
- **Mettez à jour le compagnon en 0.7.1** (menu du compagnon > **Check for updates**) : c'est lui qui apporte les composants. Addon : mettez-le à jour depuis CurseForge

## Addon v0.6.1

- **Niveaux de métiers à jour sans rien ouvrir** : Pêche, Minage, Herboristerie, Dépeçage et les autres suivent à la connexion, à la déconnexion et à chaque point gagné. Plus besoin d'ouvrir une fenêtre de métier pour mettre à jour un niveau (les recettes, elles, se relisent toujours à l'ouverture du métier)
- Addon : mettez-le à jour depuis CurseForge

## Addon v0.6.0 + Compagnon 0.7.0

- **Commandes d'artisanat** : sur la fiche d'un objet dans le salon des métiers, **🛒 Commander** : choisissez votre perso, la quantité, ajoutez une note. **📦 Mes commandes** pour suivre ou annuler, **📝 Ma note d'artisan** pour prévenir ceux qui vous commandent
- **Artisans** : vos commandes arrivent en jeu à la connexion ou au `/reload`. Cliquez l'icône de la minimap (un badge compte les commandes) ou tapez `/wos commandes`, puis **Fait** ou **Refuser** (avec une raison si vous voulez). L'acheteur reçoit un message privé quand tout est réglé
- **Mort en double corrigée** (surtout les chasseurs) : une seule carte par mort
- **Mettez à jour le compagnon en 0.7.0** (menu du compagnon > **Check for updates**) : c'est lui qui apporte les commandes à l'addon. Addon : mettez-le à jour depuis CurseForge, et laissez **Wall of Shame Forever - Commandes** coché dans la liste des addons

## Addon v0.5.0 + Compagnon 0.6.0

- **Métiers sur Discord** : l'addon note les recettes que vous connaissez (avec leur couleur : orange, jaune, vert, gris) et le niveau de tous vos métiers, récolte comprise
- **À faire une fois** : ouvrez la fenêtre de chacun de vos métiers en jeu. Ensuite ils se mettent à jour à chaque ouverture, rien ne s'affiche en jeu
- **Mettez à jour le compagnon en 0.6.0** (menu du compagnon > **Check for updates**) : c'est lui qui envoie vos métiers au bot, au `/reload` ou à la déconnexion
- Addon : mettez-le à jour depuis CurseForge
