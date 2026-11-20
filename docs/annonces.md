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

## Addon v0.6.5 + Compagnon 0.7.4

- **Temps de suivi** : le temps passé à suivre un guildeux (`/follow` ou clic droit > Suivre) est compté. Suivre quelqu'un hors de la guilde ne compte pas
- **Sur Discord** : le classement de **qui suit le plus** dans le salon du suivi, et `/suivi recap` pour ton temps (derrière qui, avec quels persos)
- Pendant un suivi, une petite bande de couleur apparaît quelques secondes toutes les 5 minutes : c'est normal, le compagnon la lit pour ne rien perdre si le jeu plante
- **Ton battletag doit être dans l'annuaire** pour que ton temps soit à ton nom
- **Mettez à jour le compagnon en 0.7.4** (menu du compagnon > **Check for updates**). Addon : mettez-le à jour depuis CurseForge

## Addon v0.6.4 + Compagnon 0.7.3

- **Suivi de la banque de guilde** : en ouvrant la banque de guilde, l'addon lit le journal des richesses (dépôts et retraits d'argent) et l'envoie au bot. Rien à faire, rien ne s'affiche en jeu : il suffit d'ouvrir la banque de temps en temps
- **Sur Discord** : un bilan dans le salon de la banque (objectif 100 po, soldes de chacun, records, mécène du mois, rat de banque) et `/banque recap` pour ton récap du jour ou de la semaine, tous tes persos réunis
- **Classements** avec `/banque classement` : plus gros dépôt, série de jours avec un dépôt, pièce jaune, fidèle…
- **Ton battletag doit être dans l'annuaire** pour que tes dépôts soient à ton nom
- **Mettez à jour le compagnon en 0.7.3** (menu du compagnon > **Check for updates**) : c'est lui qui envoie le journal au bot. Addon : mettez-le à jour depuis CurseForge

## Addon v0.6.3 + Compagnon 0.7.2

- **Nouvel onglet « Mes commandes »** dans la fenêtre des commandes (`/wos commandes` ou l'icône de la minimap) : les commandes que vous avez passées, rangées par artisan. En attente, **faites** (avec chez qui les récupérer) ou **refusées** (avec la raison), pendant 7 jours, et la réponse de l'artisan
- **Liste de courses** à droite : les composants de vos commandes en attente, pour un artisan ou au total, avec *possédés / nécessaires* et ce qui manque
- **À l'hôtel des ventes** : un clic sur un composant le cherche directement
- **Mettez à jour le compagnon en 0.7.2** (menu du compagnon > **Check for updates**) : c'est lui qui apporte vos commandes. Addon : mettez-le à jour depuis CurseForge

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
