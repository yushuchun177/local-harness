# Local-Harness. Manuel d'utilisation

> **Ce programme ne contient aucun poids de modèle GGUF.** Vous devez télécharger et importer un modèle vous-même.

Local-Harness est une surcouche graphique (harness) pour llama.cpp : chargement du modèle, réglage des paramètres et conversation multi-tours dans une seule fenêtre, sans ligne de commande.

---

## 1. Installation et lancement

1. Téléchargez la version publiée (zip portable ou exe unique) et décompressez-la dans un dossier quelconque (les chemins accentués sont acceptés).
2. Lancez `local-harness.exe`.
3. Au premier démarrage, le modèle se charge ; un indicateur s'affiche au centre pendant quelques secondes.
4. Une fois prêt, saisissez votre question en bas et appuyez sur Entrée.

Contenu du dossier :

```
local-harness.exe      programme principal
_internal\             bibliothèques d'exécution (ne pas supprimer ni renommer)
llama\                 binaires de llama.cpp (llama-cli.exe et ses DLL)
model\                 vos modèles .gguf
chats\                 historique des conversations (créé au premier lancement)
config.json            réglages d'interface et de paramètres (créé au premier lancement)
```

## 2. Préparer un modèle

Aucun modèle n'est fourni. Téléchargez un fichier GGUF (extension `.gguf`), par exemple une version quantifiée depuis Hugging Face ou ModelScope.

Deux façons de l'importer :

- **Copier dans le dossier** : placez le `.gguf` dans `model\`, redémarrez le programme, il apparaît dans la liste des modèles.
- **Importer depuis l'interface** : cliquez sur « Importer » et choisissez un dossier contenant des modèles ; le chemin est mémorisé.

Remarques :

- Pour les modèles découpés, seule la première partie (`xxx-00001-of-00002.gguf`) est nécessaire ; laissez les autres dans le même dossier.
- Les fichiers mmproj, les projecteurs visuels, les modèles d'embedding ou de reranking et les fichiers de moins de 20 Mo sont ignorés automatiquement.
- Les poids sont sous licence de leurs éditeurs (Qwen, par exemple, est en Apache-2.0). Respectez la licence correspondante.

Repères de mémoire :

| Taille du modèle | Taille de fichier (indicative) | Mémoire conseillée |
| --- | --- | --- |
| 0.4B – 1B | 300 Mo – 900 Mo | 4 Go et plus |
| 1.5B – 2B | 1 Go – 2 Go | 8 Go |
| 3B – 4B | 2 Go – 3 Go | 16 Go |

## 3. Interface

- **Barre supérieure** : choix du modèle, « Importer », paramètres (température / contexte / limite de réponse), mode réflexion, « À propos », « Réglages », bascule de thème.
- **Panneau gauche** : liste des conversations. Survolez pour supprimer, clic droit pour renommer ou supprimer.
- **Centre** : zone de messages, la réponse s'affiche en flux.
- **Bas** : zone de saisie et bouton « Envoyer », qui devient « Arrêter » pendant la génération.
- **Barre d'état** : à gauche le modèle, l'occupation du contexte et la limite native du modèle ; à droite la part de tokens de la conversation.

## 4. Paramètres

| Paramètre | Plage | Description |
| --- | --- | --- |
| Température | 0 – 2 | Plus bas = plus stable, plus haut = plus créatif. Code 0,2–0,6 ; questions 0,7 ; rédaction 0,9–1,2 |
| Contexte | 512 – limite native du modèle | Tokens conservés pour une conversation. Le maximum du curseur vient du modèle ; la barre d'état affiche « native xxxx » |
| Limite de réponse | 64 – 8192 | Nombre maximal de tokens par réponse. Augmentez-la si les réponses sont coupées |
| Mode réflexion | on / off | Pour les modèles capables de raisonner (Qwen3 par exemple) : réflexion puis réponse ; la réflexion n'apparaît pas dans le texte |

Les valeurs peuvent être saisies directement ou modifiées au curseur ; elles s'appliquent immédiatement et sont enregistrées dans `config.json`.

## 5. Compression du contexte

Les longues conversations finissent par dépasser la fenêtre de contexte. Avec la compression automatique activée, dès que la conversation atteint le seuil, l'historique ancien est résumé en un seul message avant la question suivante, les derniers tours restant intacts.

- Où : **Réglages → Compression du contexte**.
- Le seuil se règle par paliers de 1024 tokens : **1024 / 2048 / 3072 / 4096**, valeur par défaut **2048**.
- Vous pouvez choisir le nombre de tours récents conservés tels quels (4 par défaut).
- La compression lance un processus de modèle temporaire et prend quelques secondes ; l'envoi est bloqué pendant ce temps.
- Désactivez-la si vous préférez démarrer une nouvelle conversation quand le contexte est plein.

## 6. Raccourcis clavier

| Touche | Action |
| --- | --- |
| Entrée | Envoyer |
| Maj + Entrée | Retour à la ligne |
| Ctrl + Entrée | Envoyer |
| Échap | Arrêter la génération |
| Ctrl + L | Vider la zone de saisie |

## 7. Données et sauvegarde

- Les conversations sont stockées dans `chats\`, un `.json` par conversation ; supprimer le fichier supprime la conversation.
- L'interface, les paramètres et les dossiers de modèles importés sont dans `config.json` ; le supprimer rétablit les valeurs par défaut.
- Le programme n'accède pas au réseau et ne demande aucun compte ; rien n'est envoyé.
- Pour changer d'ordinateur, copiez tout le dossier du programme, `model\` compris.

## 8. Questions fréquentes

**Il se lance puis se ferme aussitôt**
`_internal\` ou `llama\` a été déplacé ou mis en quarantaine par l'antivirus. Décompressez à nouveau la version publiée.

**Il indique qu'aucun modèle n'est présent**
`model\` est vide. Copiez un `.gguf` ou utilisez « Importer », puis redémarrez.

**Mon modèle n'apparaît pas**
Vérifiez qu'il s'agit d'un `.gguf` de plus de 20 Mo, et non d'un mmproj ou d'un modèle d'embedding. Pour les modèles découpés, seulement la première partie.

**Les réponses sont lentes**
Utilisez un modèle plus petit ; dans « Réglages », réglez le nombre de threads sur le nombre de cœurs du processeur ; branchez le portable et désactivez l'économie d'énergie.

**Les réponses sont coupées**
Augmentez la « Limite de réponse » (par exemple 2048).

**Ralentissement après une longue conversation ou alerte de contexte**
La compression automatique est active par défaut ; vérifiez le seuil dans « Réglages » ou démarrez une nouvelle conversation.

**Le nom du modèle s'affiche comme « Qwen3 0.6B · Q8_0 »**
C'est normal : le nom et la quantification proviennent des métadonnées GGUF.

## 9. Environnement de test

Vérifié sur : Windows 11 (64 bits), Intel Core i5-4590 (4 cœurs / 4 threads, AVX2), 16 Go de RAM, inférence uniquement sur CPU, sans carte graphique dédiée.

Vitesse de génération mesurée (4 threads, contexte 2048) : SmolLM2-360M environ 42 t/s, Llama-3.2-1B 21 t/s, Qwen3-0.6B 15 t/s, Qwen2.5-1.5B / Qwen3-1.7B environ 7 t/s, Qwen2.5-3B 6 t/s. Le tableau complet figure dans le README.

## 10. Licence

Ce projet est publié sous GPLv3. La distribution de binaires empaquetés est autorisée, mais toute distribution du programme (source ou binaire) doit être accompagnée du code source complet correspondant ; les versions modifiées doivent rester open source.

Les poids des modèles ne font pas partie du projet et suivent les licences de leurs éditeurs.
