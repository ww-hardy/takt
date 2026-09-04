#!/usr/bin/env bash
set -euo pipefail

# Start the local Qwen3-VL server used by TAKT's llama.cpp provider.
# The server exposes an OpenAI-compatible API on localhost:8080.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

MODEL_DIR=${LLAMA_CPP_MODEL_DIR:-"$HOME/Library/Application Support/wertwandler-takt/llama.cpp"}
MODEL_FILE=${LLAMA_CPP_MODEL_FILE:-"Qwen3VL-4B-Instruct-Q4_K_M.gguf"}
MMPROJ_FILE=${LLAMA_CPP_MMPROJ_FILE:-"mmproj-Qwen3VL-4B-Instruct-F16.gguf"}
HOST=${LLAMA_CPP_HOST:-127.0.0.1}
PORT=${LLAMA_CPP_PORT:-8080}
ALIAS=${LLAMA_CPP_MODEL_ALIAS:-qwen3-vl-4b}
CTX_SIZE=${LLAMA_CPP_CTX_SIZE:-8192}
PARALLEL=${LLAMA_CPP_PARALLEL:-1}
BATCH_SIZE=${LLAMA_CPP_BATCH_SIZE:-512}
UBATCH_SIZE=${LLAMA_CPP_UBATCH_SIZE:-256}
IMAGE_MIN_TOKENS=${LLAMA_CPP_IMAGE_MIN_TOKENS:-1024}

MODEL_URL="https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/resolve/main/$MODEL_FILE"
MMPROJ_URL="https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/resolve/main/$MMPROJ_FILE"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--download] [--print-config]

Starts llama-server for TAKT's local llama.cpp provider.

Environment overrides:
  LLAMA_CPP_MODEL_DIR    Model directory (default: $MODEL_DIR)
  LLAMA_CPP_MODEL_FILE   Main GGUF filename
  LLAMA_CPP_MMPROJ_FILE  Vision projector GGUF filename
  LLAMA_CPP_HOST         Bind host (default: $HOST)
  LLAMA_CPP_PORT         Bind port (default: $PORT)
  LLAMA_CPP_MODEL_ALIAS  API model ID (default: $ALIAS)
  LLAMA_CPP_CTX_SIZE     Context size (default: $CTX_SIZE)
  LLAMA_CPP_PARALLEL     Server slots (default: $PARALLEL)
  LLAMA_CPP_BATCH_SIZE   Logical batch size (default: $BATCH_SIZE)
  LLAMA_CPP_UBATCH_SIZE  Physical batch size (default: $UBATCH_SIZE)
  LLAMA_CPP_IMAGE_MIN_TOKENS  Minimum image tokens (default: $IMAGE_MIN_TOKENS)

The model files are several GB and are never downloaded implicitly.
EOF
}

DOWNLOAD=0
PRINT_CONFIG=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --download) DOWNLOAD=1; shift ;;
    --print-config) PRINT_CONFIG=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ "$PRINT_CONFIG" -eq 1 ]]; then
  printf 'server=%s\n' "${LLAMA_CPP_SERVER:-auto-detect}"
  printf 'model_dir=%s\n' "$MODEL_DIR"
  printf 'model_file=%s\n' "$MODEL_FILE"
  printf 'mmproj_file=%s\n' "$MMPROJ_FILE"
  printf 'host=%s\n' "$HOST"
  printf 'port=%s\n' "$PORT"
  printf 'alias=%s\n' "$ALIAS"
  printf 'ctx_size=%s\n' "$CTX_SIZE"
  printf 'parallel=%s\n' "$PARALLEL"
  printf 'batch_size=%s\n' "$BATCH_SIZE"
  printf 'ubatch_size=%s\n' "$UBATCH_SIZE"
  printf 'image_min_tokens=%s\n' "$IMAGE_MIN_TOKENS"
  printf 'model_url=%s\n' "$MODEL_URL"
  printf 'mmproj_url=%s\n' "$MMPROJ_URL"
  exit 0
fi

if [[ "$DOWNLOAD" -eq 1 ]]; then
  command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl is required for model downloads." >&2
    exit 1
  }
  mkdir -p "$MODEL_DIR"
  if [[ ! -f "$MODEL_DIR/$MODEL_FILE" ]]; then
    echo "Downloading ${MODEL_FILE}…"
    curl --fail --location --progress-bar "$MODEL_URL" -o "$MODEL_DIR/$MODEL_FILE.part"
    mv "$MODEL_DIR/$MODEL_FILE.part" "$MODEL_DIR/$MODEL_FILE"
  else
    echo "Already present: $MODEL_DIR/$MODEL_FILE"
  fi
  if [[ ! -f "$MODEL_DIR/$MMPROJ_FILE" ]]; then
    echo "Downloading ${MMPROJ_FILE}…"
    curl --fail --location --progress-bar "$MMPROJ_URL" -o "$MODEL_DIR/$MMPROJ_FILE.part"
    mv "$MODEL_DIR/$MMPROJ_FILE.part" "$MODEL_DIR/$MMPROJ_FILE"
  else
    echo "Already present: $MODEL_DIR/$MMPROJ_FILE"
  fi
fi

if [[ -n "${LLAMA_CPP_SERVER:-}" ]]; then
  SERVER="$LLAMA_CPP_SERVER"
elif command -v llama-server >/dev/null 2>&1; then
  SERVER=$(command -v llama-server)
elif [[ -x /opt/homebrew/opt/llama.cpp/bin/llama-server ]]; then
  SERVER=/opt/homebrew/opt/llama.cpp/bin/llama-server
elif [[ -x /usr/local/opt/llama.cpp/bin/llama-server ]]; then
  SERVER=/usr/local/opt/llama.cpp/bin/llama-server
else
  echo "ERROR: llama-server not found. Install it with: brew install llama.cpp" >&2
  exit 1
fi

if [[ ! -f "$MODEL_DIR/$MODEL_FILE" ]]; then
  echo "ERROR: missing main model: $MODEL_DIR/$MODEL_FILE" >&2
  echo "Run with --download or place the Qwen3-VL GGUF there." >&2
  exit 1
fi
if [[ ! -f "$MODEL_DIR/$MMPROJ_FILE" ]]; then
  echo "ERROR: missing vision projector: $MODEL_DIR/$MMPROJ_FILE" >&2
  echo "Run with --download or place the matching mmproj GGUF there." >&2
  exit 1
fi

exec "$SERVER" \
  --model "$MODEL_DIR/$MODEL_FILE" \
  --mmproj "$MODEL_DIR/$MMPROJ_FILE" \
  --alias "$ALIAS" \
  --ctx-size "$CTX_SIZE" \
  --parallel "$PARALLEL" \
  --batch-size "$BATCH_SIZE" \
  --ubatch-size "$UBATCH_SIZE" \
  --image-min-tokens "$IMAGE_MIN_TOKENS" \
  --host "$HOST" \
  --port "$PORT"
