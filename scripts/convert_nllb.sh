#!/bin/bash
# Lager Core ML-versjonen av NLLB-200 for Oversetter-appen.
# Kjøres én gang på Macen fra prosjektmappen:   ./scripts/convert_nllb.sh
#
# Tar 10–20 minutter og laster ned ca. 2,5 GB (PyTorch + NLLB-modellen).
set -euo pipefail

cd "$(dirname "$0")/.."

# PyTorch fungerer best med Python 3.10–3.12.
PYTHON=""
for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
        PYTHON="$candidate"
        break
    fi
done
if [ -z "$PYTHON" ]; then
    echo "Fant ikke Python 3. Installer Xcode Command Line Tools:  xcode-select --install"
    exit 1
fi
echo "Bruker $($PYTHON --version)"

if [ ! -d .venv ]; then
    echo "Lager Python-miljø i .venv …"
    "$PYTHON" -m venv .venv
fi
source .venv/bin/activate

python -m pip install --quiet --upgrade pip
python -m pip install --quiet -r scripts/requirements.txt

python scripts/convert_nllb.py "$@"
