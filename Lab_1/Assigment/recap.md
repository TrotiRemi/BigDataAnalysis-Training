# Big Data Analytics — Assignment 01 - Recap

## Vue d'ensemble

Ce notebook implémente des analyses de texte utilisant **Apache Spark** et **PySpark** sur le texte de Shakespeare. L'objectif est d'explorer les algorithmes MapReduce et les techniques de traitement distribué de grandes données.

---

## Section 0 : Bootstrap

**Objectif** : Initialiser Spark et vérifier l'environnement

- Création d'une session Spark avec UI sur le port 4046
- Enregistrement des versions :
  - Spark version
  - PySpark version
  - Python version
  - Timezone de la session
  
Cette étape garantit la reproductibilité et permet de vérifier la configuration de l'environnement.

---

## Section 1 : Chargement des données

**Objectif** : Charger le texte de Shakespeare depuis une URL

```python
# Création des répertoires nécessaires
- data/     # pour les fichiers sources
- outputs/  # pour les résultats CSV
- proof/    # pour les plans d'exécution Spark
```

Le fichier `shakespeare.txt` est téléchargé et chargé de deux façons :
1. **RDD (Resilient Distributed Dataset)** : représentation de bas niveau distribué
2. **DataFrame** : représentation structurée plus haut niveau

Les deux formats sont cachés en mémoire pour optimiser les requêtes répétées.

---

## Section 2 : Partie A - "Perfect X" Follower Counts

### Problème (Exo 1)
Trouver les mots qui suivent le mot **"perfect"** dans le texte et compter leur fréquence.

### Approche implémentée

**Étape 1 - Tokenization** :
```
- Convertir chaque ligne en minuscules
- Splitter sur les caractères non-lettres [^a-z]+
- Éliminer les tokens vides
```

**Étape 2 - Fenêtrage** :
- Utiliser une fenêtre Window pour accéder au token suivant
- Appliquer `F.lead("token").over(window)` pour décaler les données

**Étape 3 - Filtrage et agrégation** :
- Filtrer uniquement les lignes où `token == "perfect"`
- Grouper par le token suivant et compter les occurrences
- Garder uniquement les followers qui apparaissent plus d'une fois (count > 1)
- Trier par fréquence décroissante

**Résultats** :
- Fichier de sortie : `outputs/perfect_followers.csv`
- Plan d'exécution : `proof/plan_perfect.txt`

### Métriques Spark UI (Exo 1)

| Stage | Task | Note | Input (B) | Shuffle Read (B) | Shuffle Write (B) | Timestamp |
|-------|------|------|-----------|------------------|-------------------|-----------|
| 9 | reduceByKey | stage_6 | 3,300,000 | - | 320,900 | 15:44:18 |
| 10 | collect | followers | - | 320,900 | - | 15:44:17 |

**Analyse des performances** :
- Input : 3.3 MiB (file texte tokenisée)
- Shuffle Write : 320 KiB (données filtrées, followers avec count > 1)
- Pas de Shuffle Read (première agrégation)
- Résultat compact : seulement ~320 KiB

Ce job Spark retourne :
- **Colonne 1 (next_token)** : Le mot qui suit "perfect"
- **Colonne 2 (count)** : Nombre de fois que cette occurrence apparaît
- Les résultats sont **triés par fréquence décroissante**
- Seuls les followers avec count > 1 sont conservés (filtrage des hapax)

---

## Section 3 : Partie B - PMI avec RDDs : Paires

### Problème (Exo 2)
Calculer le **Pointwise Mutual Information (PMI)** pour les paires de mots en utilisant l'approche "paires" avec des RDDs.

### Formule du PMI
$$PMI(x, y) = \log_{10} \left( \frac{c_{xy} \cdot N}{c_x \cdot c_y} \right)$$

Où :
- $c_{xy}$ = nombre de lignes contenant à la fois $x$ et $y$
- $c_x$ = nombre de lignes contenant $x$
- $c_y$ = nombre de lignes contenant $y$
- $N$ = nombre total de lignes

### Approche implémentée

**Étape 1 - Extraction des tokens** :
- Tokenizer chaque ligne avec regex `[a-z]+`
- Garder les 40 premiers tokens par ligne
- Compter $N$ = nombre de lignes avec au moins 1 token

**Étape 2 - Comptage univarié** :
- Pour chaque ligne, créer des paires (token, 1) pour les tokens uniques
- Réduire par clé pour obtenir $df(x)$ = nombre de lignes contenant $x$
- Broadcaster ces comptes pour un accès efficace

**Étape 3 - Création des paires** :
- Pour chaque ligne, émettre toutes les paires de tokens distincts
- Compter les cooccurrences pour chaque paire (x, y)
- Appliquer un seuil minimal $K = 5$ (cooccurrences minimales)

**Étape 4 - Calcul du PMI** :
- Pour chaque paire passant le seuil, calculer PMI avec la formule
- Convertir en DataFrame pour faciliter l'écriture CSV
- Trier par PMI décroissant

**Résultats** :
- Fichier de sortie : `outputs/pmi_pairs_sample.csv`
- Colonnes : `[x, y, count, pmi]`

### Métriques Spark UI (Exo 2)

| Stage | Task | Note | Input (B) | Shuffle Read (B) | Shuffle Write (B) | Timestamp |
|-------|------|------|-----------|------------------|-------------------|-----------|
| 11 | count | stage_11 | 3,300,000 | 3,300,000 | - | 15:44:17 |
| 12 | reduceByKey | stage_12 | 3,300,000 | - | 19,800,000 | 15:44:18 |
| 15 | csv_write | stage_15 | - | 19,800,000 | 3,100 | 15:44:25 |

**Analyse des performances** :
- Input : 3.3 MiB (tokens)
- Shuffle Write : 19.8 MiB (toutes les paires générées)
- Shuffle Read : 19.8 MiB (beaucoup de paires à traiter)
- ℹOutput : 3.1 KiB (après filtrage par seuil K=5)

**Caractéristiques de l'approche Paires** :
- Génère de nombreuses paires (x, y) intermédiaires
- Chaque paire devient une clé séparée dans le shuffle
- Volume de shuffle important pour les textes volumineux

Ce job Spark retourne les paires de mots avec leurs scores PMI :
- **Colonne 1 (x)** : Premier mot de la paire
- **Colonne 2 (y)** : Deuxième mot de la paire
- **Colonne 3 (count)** : Nombre de lignes où x et y co-occurent
- **Colonne 4 (pmi)** : Score PMI calculé selon la formule $\log_{10} \left( \frac{c_{xy} \cdot N}{c_x \cdot c_y} \right)$

**Interprétation** :
- PMI élevé (> 1) = association forte entre x et y (ils apparaissent ensemble plus que par hasard)
- PMI faible (< 1) = association faible ou aléatoire
- Les résultats sont **triés par PMI décroissant** (paires les plus fortement associées d'abord)

---

## Section 4 : Partie B - PMI avec RDDs : Stripes

### Problème (Exo 3)
Implémenter la même analyse PMI en utilisant l'approche **"stripes"** (plus efficace en mémoire).

### Approche "Stripes" vs "Paires"

| Aspect | Paires | Stripes |
|--------|--------|---------|
| Structure | (x, y) → count | (x, {y: count, z: count, ...}) |
| Mémoire | Une entrée par paire | Regroupement par clé x |
| Shuffle | Potentiellement lourd | Plus compacte |
| Combineurs | Moins efficaces | Fusion de dictionnaires efficace |

### Implémentation

**Étape 1 - Création des stripes** :
```python
def stripes_from_line(tokens):
    return [(x, {y: 1 for y in set if y != x})]
```

**Étape 2 - Combiner les maps** :
- Réduire les stripes par clé x avec une fusion de dictionnaires
- Compiler les comptes pour tous les y associés à x

**Étape 3 - Extraction et PMI** :
- Transformer les stripes en paires ((x, y), count)
- Appliquer le même calcul PMI qu'en Section 3
- Seuil K = 5

**Résultats** :
- Fichier de sortie : `outputs/pmi_stripes_sample.csv`
- Plan d'exécution : `proof/plan_pmi_stripes.txt`

### Métriques Spark UI (Exo 3)

| Stage | Task | Note | Input (B) | Shuffle Read (B) | Shuffle Write (B) | Timestamp |
|-------|------|------|-----------|------------------|-------------------|-----------|
| 18 | reduceByKey | stage_18 | 3,300,000 | - | 320,900 | 15:44:28 |
| 19 | collect | stage_19 | - | 320,900 | - | 15:44:28 |
| 20 | reduceByKey | stage_20 | 3,300,000 | - | 13,600,000 | 15:44:29 |
| 21 | runJob | stage_21 | - | 6,700,000 | - | 15:44:30 |
| 23-24 | csv_write | stage_23-24 | - | 13,600,000 | 3,600 | 15:44:31 |

**Analyse des performances** :
- Input : 3.3 MiB (tokens)
- Shuffle Write : 13.6 MiB (**31% moins que Paires** 19.8 MiB)
- Shuffle Read : 13.6 MiB (données fusionnées par clé)
- ℹOutput : 3.6 KiB (résultats finaux)

**Caractéristiques de l'approche Stripes** :
- Regroupe les paires par première clé x
- Chaque x apparaît **une seule fois** dans le shuffle
- Les y co-occurrants sont fusionnés dans un dictionnaire
- Volume de shuffle significativement réduit

Ce job Spark retourne les mêmes résultats que l'approche "Paires" mais avec une **stratégie d'optimisation différente** :

**Données retournées** (identiques à Exo 2) :
- **Colonne 1 (x)** : Premier mot de la paire
- **Colonne 2 (y)** : Deuxième mot de la paire
- **Colonne 3 (count)** : Nombre de co-occurrences
- **Colonne 4 (pmi)** : Score PMI

**Comparaison Paires (Exo 2) vs Stripes (Exo 3)** :

| Métrique | Paires | Stripes | Gain |
|----------|--------|---------|------|
| **Shuffle Write** | 19.8 MiB | 13.6 MiB | -31% |
| **Shuffle Read** | 19.8 MiB | 13.6 MiB | -31% |
| **Approche** | Paires (x,y) séparées | Stripes {x:{y:c}} | Structure |
| **Efficacité réseau** | Plus volumineux | Plus compacte | Bande passante |

**Visualisation interne** :

Approche Paires (Exo 2) :
```
Line "the lord" → [(the, lord, 1), (lord, the, 1)]
All pairs mixed → [(the, lord), (lord, the), (the, lord), ...]
Shuffle → Group by (x, y) → Reduce count
```

Approche Stripes (Exo 3) :
```
Line "the lord" → [(the, {lord:1}), (lord, {the:1})]
Stripes grouped → [(the, {lord:1, ...}), (lord, {the:1, ...})]
Shuffle → Group by x → Merge maps → Reduce
```

Le résultat final est **identique**, mais le processus utilise **31% moins de bande passante** pour les données volumineuses !

---

## Section 5 : Evidence Spark UI

**Objectif** : Documenter les performances

Pendant l'exécution, le Spark UI (http://localhost:4046) affiche :
- **Files Read** : nombre de fichiers lus
- **Input Size** : taille totale des entrées
- **Shuffle Read/Write** : données échangées entre les nœuds
- **Task Duration** : temps d'exécution des tâches

Ces métriques permettent d'évaluer l'efficacité de chaque approche (paires vs stripes).

### Données d'Evidence

Toutes les métriques capturées lors de l'exécution sont enregistrées dans le fichier : **[`log.csv`](log.csv)**

Ce fichier contient pour chaque job :
- `run_id` : Identifiant du run (r1, r2, r3, r4)
- `task` : Nom de la tâche (perfect_followers, pmi_pairs, pmi_stripes)
- `note` : Description de la stage
- `files_read` : Nombre de fichiers lus
- `input_size_bytes` : Taille totale des entrées en octets
- `shuffle_read_bytes` : Données lues depuis le shuffle
- `shuffle_write_bytes` : Données écrites dans le shuffle
- `timestamp` : Horodatage de l'exécution

---

## Section 6 : Environment et Reproducibilité

**Objectif** : Garantir la reproductibilité

Données à capturer et sauvegarder dans `ENV.md` :
```
- Java version
- Spark version et configurations
- OS et architecture
- Python version
- Versions des librairies (PySpark, etc.)
- Timezone et locale
```
