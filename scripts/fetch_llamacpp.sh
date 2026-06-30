#!/usr/bin/env bash
# fetch_llamacpp.sh — shallow-clone llama.cpp at a pinned commit for reproducible Arm64 builds.
#
# Usage: scripts/fetch_llamacpp.sh [COMMIT_SHA] [DEST_DIR]
#
# Defaults:
#   COMMIT_SHA = fabde3bf5136940eb03821aa2490e2360093965b   (release b9728, 2026-06-19)
#   DEST_DIR   = third_party/llama.cpp
#
# Source of truth for the pinned SHA: .trae/specs/bootstrap-arm-infer-bench/spec.md
# T1.6 verified on this commit:
#   GGML_CPU_REPACK  (ggml/CMakeLists.txt:120, default ON) controls ARM online repack
#                    (Q4_0 -> Q4_X_X); disable with -DGGML_CPU_REPACK=OFF.
#   GGML_CPU_AARCH64 does NOT exist as a cmake option.
#
# Network override (for restricted networks, e.g. local dev behind GFW):
#   LLAMA_REPO_URL=git@github.com:ggml-org/llama.cpp.git scripts/fetch_llamacpp.sh
# CI runners (ubuntu-24.04-arm) have direct github.com access and use HTTPS by default.

set -euo pipefail

LLAMA_COMMIT="${1:-fabde3bf5136940eb03821aa2490e2360093965b}"
LLAMA_REPO="${LLAMA_REPO_URL:-https://github.com/ggml-org/llama.cpp.git}"
DEST_DIR="${2:-third_party/llama.cpp}"

echo "::group::fetch_llamacpp: ${LLAMA_COMMIT} -> ${DEST_DIR}"
echo "fetch_llamacpp: repo=${LLAMA_REPO}"

mkdir -p "$(dirname "${DEST_DIR}")"

if [ -d "${DEST_DIR}/.git" ]; then
  ACTUAL="$(git -C "${DEST_DIR}" rev-parse HEAD 2>/dev/null || echo "")"
  if [ "${ACTUAL}" = "${LLAMA_COMMIT}" ]; then
    echo "fetch_llamacpp: already at ${LLAMA_COMMIT}, skipping fetch"
    echo "::endgroup::"
    exit 0
  fi
  echo "fetch_llamacpp: existing checkout at '${ACTUAL}', re-fetching pinned commit"
  git -C "${DEST_DIR}" fetch --depth 1 origin "${LLAMA_COMMIT}"
  git -C "${DEST_DIR}" -c advice.detachedHead=false checkout FETCH_HEAD
else
  echo "fetch_llamacpp: fresh shallow init + fetch"
  git init -q "${DEST_DIR}"
  git -C "${DEST_DIR}" remote add origin "${LLAMA_REPO}"
  git -C "${DEST_DIR}" fetch --depth 1 origin "${LLAMA_COMMIT}"
  git -C "${DEST_DIR}" -c advice.detachedHead=false checkout FETCH_HEAD
fi

# rev-parse round-trip verification (T1.1 requirement)
ACTUAL="$(git -C "${DEST_DIR}" rev-parse HEAD)"
if [ "${ACTUAL}" != "${LLAMA_COMMIT}" ]; then
  echo "fetch_llamacpp: ERROR rev-parse mismatch"
  echo "  expected: ${LLAMA_COMMIT}"
  echo "  actual:   ${ACTUAL}"
  exit 1
fi
echo "fetch_llamacpp: verified at ${ACTUAL}"
echo "::endgroup::"