#!/bin/bash
# Confere se uma release publicada e ACEITAVEL PELO JOGO, usando o parser do
# proprio jogo em vez da nossa opiniao sobre o que ele aceita.
#
# POR QUE ISTO EXISTE. A v1.6.0 saiu com o pacote chamado
# `voxel_characters-1.6.0.modpkg`. O `modkit pack` gera esse nome, e o arquivo E
# um zip por dentro, entao tudo parecia certo: o pacote validava, baixava e
# instalava a mao. Mas o gerenciador de mods dentro do jogo nunca viu a release.
#
# `ModUpdate.pickZipAsset` (src/mods/ModUpdate.lua:17-45) so olha anexo cujo
# NOME termina em `.zip`, e `parseReleases` (:155) DESCARTA a release inteira
# quando nao acha um. Um `.modpkg` e invisivel para ele.
#
# Isso vale para todas as nossas releases desde a 1.0.0: nenhuma delas jamais
# apareceu no atualizador interno. Quem quis atualizar teve que baixar do
# GitHub e importar na mao, e "como eu instalo" e a pergunta mais repetida da
# thread. Quem apontou foi o absol, que tinha batido no mesmo no fork dele.
#
# Uso:
#   tools/release_check.sh [tag]        default: a release marcada como latest
set -u

REPO_MOD="${VC_REPO:-last-swagger/gen1recomp-voxel-characters}"
RAIZ="$(cd "$(dirname "$0")/../../.." && pwd)"
TAG="${1:-}"

command -v gh >/dev/null || { echo "gh nao encontrado"; exit 1; }
command -v luajit >/dev/null || { echo "luajit nao encontrado"; exit 1; }

TMP="$(mktemp -t vcrel)" || exit 1
trap 'rm -f "$TMP"' EXIT

if [ -n "$TAG" ]; then
  gh api "repos/$REPO_MOD/releases/tags/$TAG" > "$TMP" 2>/dev/null \
    || { echo "nao consegui ler a release $TAG"; exit 1; }
else
  gh api "repos/$REPO_MOD/releases/latest" > "$TMP" 2>/dev/null \
    || { echo "nao consegui ler a release mais recente"; exit 1; }
fi

# O ID do mod vem do manifesto, nao de uma constante aqui: `pickZipAsset`
# prefere exatamente `<id>-<versao>.zip`, entao errar o id aqui esconderia um
# nome de anexo errado la.
MOD_ID=$(python3 -c "import json,sys;print(json.load(open('$RAIZ/mods/voxel_characters/manifest.json'))['id'])")

cd "$RAIZ" || exit 1
VC_REL_JSON="$TMP" VC_MOD_ID="$MOD_ID" luajit -e '
package.path = "./?.lua;" .. package.path
local ModUpdate = require("src.mods.ModUpdate")
local f = assert(io.open(os.getenv("VC_REL_JSON")))
local txt = f:read("*a"); f:close()

local lista, err = ModUpdate.parseReleases(txt, os.getenv("VC_MOD_ID"))
if not lista or not lista[1] then
  print("RELEASE REPROVADA: o jogo diz \"" .. tostring(err) .. "\"")
  print("")
  print("O gerenciador de mods dentro do jogo NAO vai enxergar esta release.")
  print("Quase sempre e o nome do anexo: precisa terminar em .zip, e o nome")
  print("preferido e " .. tostring(os.getenv("VC_MOD_ID")) .. "-<versao>.zip")
  os.exit(1)
end
local r = lista[1]
print(string.format("tag         %s", tostring(r.tag)))
print(string.format("versao      %s", tostring(r.version)))
print(string.format("anexo       %s", tostring(r.zip and r.zip.name)))
print(string.format("tamanho     %s bytes", tostring(r.zip and r.zip.size)))
print(string.format("prerelease  %s", tostring(r.prerelease)))
if r.prerelease then
  print("")
  print("AVISO: marcada como prerelease; o atualizador pode ignorar.")
end
print("")
print("RELEASE OK: o proprio parser do jogo aceita esta release.")
' 2>&1 || exit 1

echo ""
echo "conferido com src/mods/ModUpdate.lua, o codigo que o jogo roda de verdade,"
echo "nao com a nossa suposicao sobre o que ele aceita."

# ------------------------------------------------------------------
# QUEM ASSINA A RELEASE.
#
# O autor de uma release e a conta cujo token a criou, e o GitHub NAO deixa
# troca-lo depois: PATCH em releases aceita tag, nome, corpo, draft,
# prerelease e make_latest, e nada mais. As nove releases publicadas ate agora
# aparecem assinadas por kimsfigueredo, que e a conta pessoal do Kim, porque o
# `gh` desta maquina esta logado nela. Os COMMITS estao certos: os 32 do
# origin/main sao todos last-swagger.
#
# Entao isto nao conserta o passado, impede o proximo. Publicar com a conta
# errada e o tipo de erro que so aparece depois de publicado, que e tarde.
# ------------------------------------------------------------------
# O TEXTO DA RELEASE.
#
# Regra do Kim, 2026-08-09: direto ao ponto, com imagem ou video, sem lenga
# lenga. O corpo da v1.6.0 tinha 125 linhas e nenhuma midia. Isto nao reprova,
# avisa: julgar prosa por contagem de linha seria fingir precisao que nao
# existe, mas 40 linhas e o dobro do que qualquer uma das nossas releases
# precisou para dizer o que mudou, e midia ausente e binario.
LINHAS=$(python3 -c "import json;print(len(json.load(open('$TMP')).get('body','').splitlines()))" 2>/dev/null || echo 0)
TEM_MIDIA=$(python3 -c "
import json,re
b=json.load(open('$TMP')).get('body','')
print('sim' if re.search(r'!\[|<img|<video|\.png|\.gif|\.mp4', b) else 'nao')
" 2>/dev/null || echo "?")
echo ""
echo "corpo       $LINHAS linhas, midia: $TEM_MIDIA"
[ "${LINHAS:-0}" -gt 40 ] && echo "  AVISO: passou de 40 linhas; o formato acordado e titulo, 3 a 5 bullets, midia, instalacao, creditos"
[ "$TEM_MIDIA" = "nao" ] && echo "  AVISO: sem imagem nem video; use o GIF do clip.sh ou do trailer.sh"

ESPERADO="${VC_RELEASE_AUTHOR:-last-swagger}"
AUTOR=$(python3 -c "import json,sys; print(json.load(open('$TMP')).get('author',{}).get('login',''))" 2>/dev/null)
echo ""
if [ "$AUTOR" = "$ESPERADO" ]; then
  echo "AUTOR OK: assinada por $AUTOR"
else
  echo "AUTOR ERRADO: esta release esta assinada por '$AUTOR', esperado '$ESPERADO'."
  echo ""
  echo "  O autor e definido na CRIACAO e o GitHub nao deixa editar depois."
  echo "  Para as proximas: exporte um token da conta $ESPERADO antes de publicar"
  echo "    GH_TOKEN=<token de $ESPERADO> gh release create ..."
  echo "  Para esta: so apagando e recriando com o token certo, o que zera a"
  echo "  contagem de downloads e derruba o link por alguns segundos."
  exit 1
fi
