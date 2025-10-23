#!/usr/bin/env bash
set -euo pipefail
echo "=============================="
echo "🔍 Big Data Analytics - Env Check"
echo "=============================="

echo "== Conda =="
if command -v conda >/dev/null 2>&1; then
  conda --version
  conda info --envs | grep '*' || echo "⚠️  Aucun environnement conda actif"
else
  echo "❌ conda non trouvé (installe Miniconda)"
fi
echo

echo "== Java =="
if command -v java >/dev/null 2>&1; then
  java -version
else
  echo "❌ Java non trouvé (installe OpenJDK 21 : sudo apt install -y openjdk-21-jdk)"
fi
echo

echo "== Python =="
if command -v python >/dev/null 2>&1; then
  python -V
else
  echo "❌ Python non trouvé (conda create -n bda-env python=3.10)"
fi
echo

echo "== PySpark =="
if python -c "import pyspark" >/dev/null 2>&1; then
  python -c "import pyspark; print('PySpark', pyspark.__version__)"
else
  echo "❌ PySpark non trouvé (pip install pyspark findspark)"
fi
echo

echo "== Spark =="
if command -v spark-submit >/dev/null 2>&1; then
  spark-submit --version
else
  echo "⚠️ spark-submit non trouvé (tu utilises peut-être l’installation pip-only ?)"
fi
echo

echo "== JupyterLab =="
if command -v jupyter >/dev/null 2>&1; then
  jupyter --version
else
  echo "❌ JupyterLab non trouvé (pip install jupyterlab)"
fi
echo

echo "== Spark smoke test =="
python - <<'EOF'
try:
    from pyspark.sql import SparkSession
    spark = SparkSession.builder.appName("bda-env-check").getOrCreate()
    print(f"Spark Version: {spark.version}")
    print("Count:", spark.range(0, 10).count())
    spark.stop()
except Exception as e:
    print("❌ Spark test échoué :", e)
EOF

echo
echo "✅ Vérification terminée."
echo "Si tout est vert, ton environnement est prêt ! 🎉"
