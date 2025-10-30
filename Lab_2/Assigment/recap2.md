# Big Data Analytics — Assignment 02 - Recap

## Vue d'ensemble

Ce notebook implémente une analyse complète de texte utilisant **Apache Spark** et **PySpark** sur le texte de Shakespeare (chapitre 3 & 4 : From MapReduce → Spark patterns). L'objectif est d'explorer les pipelines RDD/DataFrame en comparant différentes approches d'optimisation et de résoudre des problèmes classiques d'analyse textuelle.

**Composants implémentés** :
- **Partie A** : Bigrammes avec fréquence relative (pairs vs stripes)
- **Partie B** : PMI (Pointwise Mutual Information) avec seuil de co-occurrence
- **Partie C** : Index inversé + retrieval booléen (AND/OR)
- **Partie D** : Étude de performance comparant les designs et partitions

---

## Section 0 : Bootstrap

**Objectif** : Initialiser Spark et documenter l'environnement

- Création d'une session Spark avec l'app name `BDA-AssigmentLab02`
- Configuration du timezone UTC et shuffle partitions
- UI accessible à `localhost:4046` (défini dans les paramètres Spark)

Vérifications effectuées :
- Spark version
- PySpark version
- Python version
- Configuration : `spark.sql.shuffle.partitions = 4`

Cette étape garantit la reproductibilité.

---

## Section 1 : Chargement des données

**Objectif** : Charger et préparer les données Shakespeare

```python
# Structure de répertoires
- data/shakespeare.txt          # Fichier source (~5 MiB)
- outputs/                      # Résultats CSV et index
- proof/                        # Plans d'exécution Spark
```

Le fichier de données est chargé en deux formats :
1. **RDD** : Représentation distribuée de bas niveau
   ```python
   lines_rdd = spark.sparkContext.textFile(str(TEXT_PATH)).cache()
   ```

2. **DataFrame** : Représentation structurée avec colonne 'line'
   ```python
   lines_df = spark.read.text(str(TEXT_PATH)).withColumnRenamed("value", "line").cache()
   ```

**Volume de données** : ~5 MiB, plusieurs milliers de lignes de texte de pièces théâtrales.

---

## Section 2 : Helper de tokenization

**Objectif** : Préparer les données textuelles pour les analyses

Deux fonctions définies :

1. **tokenize(text: str)** :
   - Convertit en minuscules
   - Splitte sur les caractères non-lettres `[a-z]+`
   - Retourne une liste de tokens

2. **truncate(tokens, n=40)** :
   - Garde uniquement les premiers n tokens d'une ligne
   - Utilisée pour les analyses de PMI (co-occurrence dans une fenêtre)

**RDD tokenisé** : Chaque ligne devient une liste de tokens, filtrée et tronquée à 40 tokens.

---

## Section 3 : Partie A — Bigrammes avec fréquence relative (pairs)

### Problème

Calculer la **fréquence relative** des bigrammes (paires de mots consécutifs) avec la formule :

$$f(w_i, w_{i+1}) = \frac{\text{count}(w_i, w_{i+1})}{\text{count}(w_i, *)}$$

où $\text{count}(w_i, *)$ = nombre total de fois que $w_i$ apparaît en première position.

### Approche "Pairs"

L'approche pairs émet chaque paire de mots consécutifs $(w_i, w_{i+1})$ comme une clé distincte, puis réduit par clé pour obtenir les comptages.

**Étapes principales** :
1. Émettre `((w_i, w_{i+1}), 1)` pour chaque bigram
2. Émettre `((w_i, '*'), 1)` pour chaque occurrence en première position
3. Réduire pour obtenir les comptes
4. Normaliser par les marginales

**Résultats** :
- **Fichier** : `outputs/bigram_pairs_top_10.csv`
- **Top bigrammes** : (ne, er) count=58, (ta, en) count=24, (able, to) count=10, (market, place) count=10

![Partie 3 - Bigrammes Pairs](Pïcture/Part3_1.png)

![Partie 3 - Continuité](Pïcture/Part3_2.png)

---

## Section 4 : Partie A — Bigrammes avec fréquence relative (stripes)

### Approche "Stripes"

L'approche stripes regroupe les **followers par mot de départ** plutôt que d'émettre chaque paire séparément.

**Structure** : $(w_i) \to \{(w_{i+1}: \text{count}), (w_{i+2}: \text{count}), ...\}$

**Étapes principales** :
1. Pour chaque ligne, construire des stripes : $(w_i) \to \{\text{Counter}(w_{i+1})\}$
2. Réduire les stripes en fusionnant les dictionnaires de compteurs
3. Expanser et normaliser : transformer stripes en paires individuelles
4. Normaliser par la somme des comptes dans chaque stripe

**Résultats** :
- **Fichier** : `outputs/bigram_stripes_top.csv`
- **Identiques à Pairs** : Mêmes top-50 bigrammes avec mêmes valeurs

![Partie 4 - Bigrammes Stripes 1](Pïcture/Part4_1.png)

![Partie 4 - Bigrammes Stripes 2](Pïcture/Part4_2.png)

![Partie 4 - Bigrammes Stripes 3](Pïcture/Part4_3.png)

### Comparaison Pairs vs Stripes

| Métrique | Pairs | Stripes | Réduction |
|----------|-------|---------|-----------|
| **Shuffle Write** | 779.1 KiB | **Compact interne** | - |
| **Approche** | Paires séparées | Stripes fusionnées | Structure |
| **Avantage** | Simplicité | Efficacité mémoire/réseau | -31% potentiel |

**Analyse** :
- **Pairs** : Chaque bigram $(w_i, w_{i+1})$ est une clé distincte → shuffle volumineux
- **Stripes** : Chaque $w_i$ apparaît **une seule fois** avec tous ses followers regroupés → shuffle réduit

### Métrique Spark UI (Partie A - Stripes)

| Stage | Operation | Duration | Shuffle Write (B) | Note |
|-------|-----------|----------|-------------------|------|
| 18 | reduceByKey (stripes) | 1 s | 672.1 KiB | Fusion de dictionnaires |

---

## Section 5 : Partie B — PMI avec seuil de co-occurrence

### Problème

Calculer le **Pointwise Mutual Information (PMI)** pour les paires de mots qui **co-occurent dans une même ligne** :

$$PMI(x, y) = \log_{10} \left( \frac{P(x, y)}{P(x) \cdot P(y)} \right) = \log_{10} \left( \frac{c_{xy} \cdot N}{c_x \cdot c_y} \right)$$

Où :
- $c_{xy}$ = nombre de lignes contenant **à la fois** x et y
- $c_x$ = nombre de lignes contenant x
- $c_y$ = nombre de lignes contenant y
- $N$ = nombre total de lignes

**Contraintes** :
- Tokenization : lowercase, split sur [a-z]+, drop empties
- **First 40 tokens par ligne** (fenêtre temporelle simulée)
- **Seuil K=5** : Garder uniquement les paires avec co-occurrence ≥ 5

### Implémentation avec RDDs (Pairs)

Le PMI est calculé en trois étapes :
1. **Comptage univarié** : Compter combien de lignes contiennent chaque mot
2. **Comptage des paires** : Compter combien de lignes contiennent chaque paire (x, y)
3. **Calcul PMI** : Appliquer la formule $\log_{10}(\frac{c_{xy} \cdot N}{c_x \cdot c_y})$
4. **Filtrage** : Garder uniquement les paires avec co-occurrence ≥ K (K=5)

**Résultats** :
- **Fichier** : `outputs/pmi_pairs_sample.csv`
- **Colonnes** : [x, y, pmi, count]
- **Volume** : 41,903 paires (première partie du fichier)

**Top PMI pairs** (par score PMI) :
- `(rescue, rescue)` : PMI=3.60, count=6 (auto-références fortes)
- `(weapons, weapons)` : PMI=3.60, count=6
- `(scroop, stephen)` : PMI=3.55, count=7 (co-occurrence forte)
- `(shearing, sheep)` : PMI=3.34, count=5 (paire sémantique forte)

**Interprétation** :
- **PMI > 3** : Association très forte (bien plus fréquente que le hasard)
- **PMI ~ 2** : Association notable mais moins dramatique
- **PMI < 1** : L'association est moins fréquente que l'indépendance

![Partie 5 - PMI Computation 1](Pïcture/Part5_1.png)

![Partie 5 - PMI Computation 2](Pïcture/Part5_2.png)

![Partie 5 - PMI Computation 3](Pïcture/Part5_3.png)

---

## Section 6 : Partie C — Index inversé + Requêtes booléennes

### Problème

Construire un **index inversé** à partir du texte de Shakespeare en groupant les lignes en "documents" (10 lignes consécutives = 1 document).

**Schema Parquet** :
```
- term: STRING           # Mot unique
- df: INT                # Document frequency (nombre de docs contenant le terme)
- postings: ARRAY<STRUCT<doc_id INT, tf INT>>
  # Liste des documents contenant le terme avec term frequency
```

### Implémentation

Construire un **index inversé** à partir du texte de Shakespeare en groupant les lignes en "documents" (10 lignes consécutives = 1 document).

**Étapes principales** :
1. Grouper les lignes en documents (10 lignes = 1 doc)
2. Tokeniser et indexer : pour chaque terme, stocker les doc_ids et term frequencies
3. Sérialiser au format Parquet avec le schéma complet

**Schema Parquet** :
- `term`: STRING (mot unique)
- `df`: INT (document frequency)
- `postings`: ARRAY<STRUCT<doc_id INT, tf INT>>

**Résultats** :
- **Fichier** : `outputs/index_parquet/` (avec `_SUCCESS` marker)
- Index complet avec tous les termes et leurs postings

![Partie 6 - Index Inversé 1](Pïcture/Part6_1.png)

![Partie 6 - Index Inversé 2](Pïcture/Part6_2.png)

### Requêtes booléennes et résultats

Implémentées pour les opérateurs **AND** et **OR** :

**AND** : Intersection des doc_ids
- Retourne les documents contenant **tous** les termes de la requête
- Score = somme des term frequencies

**OR** : Union des doc_ids
- Retourne les documents contenant **au moins un** terme
- Score = somme des term frequencies

**Requêtes exécutées et résultats** (voir `outputs/queries_and_results.md`) :

Les 5 requêtes principales :
1. **"romeo juliet"** - Documents contenant ces personnages shakespeariens
2. **"you me"** - Dialogue personnel
3. **"man woman"** - Relations de genre
4. **"love hate"** - Opposés émotionnels
5. **"the"** - Terme très fréquent (unigramme)

Pour chaque requête, les résultats incluent les top documents triés par score.

![Partie 7 - Requêtes Booléennes 1](Pïcture/Part7_1.png)

![Partie 7 - Requêtes Booléennes 2](Pïcture/Part7_2.png)

![Partie 7 - Requêtes Booléennes 3](Pïcture/Part7_3.png)

### Métrique Spark UI (Partie A - Index)

![Partie 8 - Performance Study 1](Pïcture/Part8_1.png)

![Partie 8 - Performance Study 2](Pïcture/Part8_2.png)

---

## Section 7 : Partie D — Étude de performances et Physical Plans

### Comparaison des designs et Shuffle patterns

La comparaison complète entre Pairs et Stripes est visualisée par les stages Spark :

![Stage 1 - Physical Plan](Pïcture/Stage1.png)

![Stage 2 - Physical Plan Details](Pïcture/Stage2.png)

### Analyse comparative

**Pairs vs Stripes (Partie A - Bigrammes)** :

**Explication Shuffle** :
- **Pairs** : Chaque bigram $(w_i, w_{i+1})$ devient une clé → beaucoup de clés à shuffler
- **Stripes** : Chaque mot $w_i$ → clé unique avec tous les followers dans un dict → moins de clés
- **Réduction** : Environ -13% de shuffle write avec l'approche stripes

---

## Section 8 : Spark UI Metrics

### Récapitulatif des Jobs et stages

Les jobs exécutés lors du notebook :

![Job List 1 - Bootstrap et Bigrammes](Pïcture/Job1.png)

![Job List 2 - PMI et Index](Pïcture/Job2.png)

![Job List 3 - Queries et Results](Pïcture/Job3.png)

### LocalHost UI

L'interface Spark UI est accessible pour la monitoring en temps réel :

![Spark UI - LocalHost Dashboard](Pïcture/LocalHost.png)

---