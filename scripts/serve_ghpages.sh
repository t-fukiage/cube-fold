#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-8000}"
BASE_HREF="${2:-/cube-fold/}"
ROOT_DIR="${3:-/tmp/ghpages}"

if [[ "${BASE_HREF}" != /* ]]; then
  BASE_HREF="/${BASE_HREF}"
fi
if [[ "${BASE_HREF}" != */ ]]; then
  BASE_HREF="${BASE_HREF}/"
fi

OUT_DIR="${ROOT_DIR}${BASE_HREF}"

echo "Building web with base href: ${BASE_HREF}"
flutter build web --base-href "${BASE_HREF}"

rm -rf "${ROOT_DIR}"
mkdir -p "${OUT_DIR}"
cp -R build/web/* "${OUT_DIR}"

echo "Serving at http://localhost:${PORT}${BASE_HREF}"
python3 -m http.server "${PORT}" --directory "${ROOT_DIR}"
