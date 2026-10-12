#!/bin/bash
# Executa um alvo de verificacao sem iniciar a bateria completa.

set -u

PASTA_FERRAMENTAS="$(dirname "$0")"
MOD="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$PASTA_FERRAMENTAS/..")"
RAIZ="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${VC_ENGINE_ROOT:-$MOD/../..}")"
LUAJIT="$(command -v luajit || echo /usr/local/bin/luajit)"

uso() {
  echo "Usage: bash mods/voxel_characters/tools/foco.sh unit|host-manifest|probe <name>|host <id>"
  echo "Probes: probe_life menu probe_hd probe_walk probe_draw probe_fp probe_grid"
  echo "Hosts: potato_voxel BATTLE_ART_VOXEL_FORK DRAMALESS_SHAPE DRAMATIC_SHAPE TERRARIUM"
}

MODO="${1:-}"
case "$MODO" in
  unit)
    LOG="$(mktemp)"
    env -C "$RAIZ" "$LUAJIT" "$MOD/tests/voxel_chars_test.lua" >"$LOG" 2>&1
    RESULTADO=$?
    tail -n 12 "$LOG"
    rm -f "$LOG"
    exit "$RESULTADO"
    ;;
  host-manifest)
    env -C "$RAIZ" python3 "$MOD/tools/host_manifest_gate.py"
    exit $?
    ;;
  probe)
    NOME="${2:-}"
    case "$NOME" in
      probe_life|menu|probe_hd|probe_walk|probe_draw|probe_fp|probe_grid) ;;
      *) uso; exit 2 ;;
    esac
    LOG="$(mktemp)"
    env -C "$RAIZ" POKEPORT_VERSION=blue \
      POKEPORT_DRIVER="$MOD/tools/ingame/$NOME.lua" \
      bash "$MOD/tools/love.sh" . >"$LOG" 2>&1
    RESULTADO=$?
    APROVADOS="$(grep -c 'PASSED' "$LOG" || true)"
    FALHAS="$(grep -c 'FAILED' "$LOG" || true)"
    tail -n 16 "$LOG"
    rm -f "$LOG"
    if [ "$APROVADOS" -eq 0 ] || [ "$FALHAS" -ne 0 ]; then exit 1; fi
    exit "$RESULTADO"
    ;;
  host)
    ID="${2:-}"
    case "$ID" in
      potato_voxel|BATTLE_ART_VOXEL_FORK|DRAMALESS_SHAPE|DRAMATIC_SHAPE|TERRARIUM) ;;
      *) uso; exit 2 ;;
    esac
    env -C "$RAIZ" bash "$MOD/tools/ingame/hosts.sh" "$ID"
    exit $?
    ;;
  *)
    uso
    exit 2
    ;;
esac
