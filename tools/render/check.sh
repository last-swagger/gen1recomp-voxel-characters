#!/bin/bash
# Verifica a REGUA antes de confiar em qualquer medicao feita com ela.
#
# Rode da raiz do repo:  bash mods/voxel_characters/tools/render/check.sh
#
# Existe porque numa unica sessao dez defeitos foram do harness se passando por
# defeito do mod, e cada um custou um ciclo de diagnostico apontado para o lugar
# errado. Uma medicao feita com regua torta e pior que nenhuma: ela produz
# confianca.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/love_bin.sh"
H=mods/voxel_characters/tools/render
FAIL=0

say() { printf "%-52s %s\n" "$1" "$2"; }

# Checagem que compara DUAS medicoes passa comparando vazio com vazio quando o
# render nem rodou. Foi assim que a regua ficou verde numa maquina sem o LOVE
# no caminho esperado. Toda medicao usada numa igualdade passa por aqui antes.
medido() {
  [ -n "$1" ] && return 0
  echo "  (sem medicao: o render nao produziu saida)" >&2
  return 1
}

# 1. Convencoes internas: eixos, formas de setVertex, contagem de frames.
OUT=$($LOVE $H selftest=1 2>&1 | grep "autoteste")
say "autoteste de convencoes" "$OUT"
echo "$OUT" | grep -qE "([0-9]+)/\1$" || FAIL=1

# 2. Conformidade: de frente, a pitch zero, o SLAB tem que ser identico ao card
#    original. Isto pega sinal de profundidade invertido, pivo errado, eixo Y
#    trocado e canvas espelhado de uma vez so, porque qualquer um deles quebra
#    a igualdade.
for s in red blue snorlax poke_ball nurse; do
  R=$($LOVE $H sprite=$s shapes=flat,slab frames=0 yaws=0 pitch=0 cell=256 \
      metrics=1 out=chk_$s.png 2>&1 | grep slab | grep -o "IoU [0-9.]*" | head -1)
  say "conformidade $s" "$R"
  [ "$R" = "IoU 1.000" ] || FAIL=1
done

# 2b. Conformidade nos frames de CAMINHADA, nao so no parado. O bloqueante da
#     v1.4.0 existiu porque a tabela de olhos foi validada so no frame 0, e no
#     frame 3 o rosto desce uma linha. "Amostra, nao exemplo" vale para o eixo
#     dos frames tambem, nao so para o dos personagens.
for fr in 1 2 3 4 5; do
  R=$($LOVE $H sprite=red shapes=flat,slab frames=$fr yaws=0 pitch=0 cell=256 \
      metrics=1 out=chk_f$fr.png 2>&1 | grep slab | grep -o "IoU [0-9.]*" | head -1)
  say "conformidade red frame $fr" "$R"
  [ "$R" = "IoU 1.000" ] || FAIL=1
done

# 2c. O contrato da piscada mudou na v1.4.2 e a regua tinha ficado velha: ela
#     ainda afirmava "nao pisca andando", que era o comportamento da v1.4.1.
#     Agora a pose andando pisca SE o texel do olho transferir da pose parada
#     sob o deslocamento do passo, medido folha a folha. Trocar a assercao por
#     uma mais frouxa seria racionalizar um gate vermelho, entao ela ficou mais
#     APERTADA: testa os dois lados da regra, e os dois lados vem de medicao.
#
#     red transfere nas duas poses de caminhada (frames 3 e 5). girl NAO
#     transfere de frente: a cabeca dela e redesenhada entre as poses, e nesse
#     caso a folha inteira tem que ficar de olho aberto. Se um dia a regra
#     quebrar para o lado permissivo, e a girl que pega, e ela e a folha que
#     representa o defeito que fez a v1.4.1 ser revertida: fechar o olho em
#     cima de pele.
for fr in 3 5; do
  R=$($LOVE $H sprite=red shapes=slab frames=$fr yaws=0 rungs=75 cell=140 \
      blink=on blinkscan=1 out=chk_b$fr.png 2>&1 | grep BLINKSCAN)
  say "red pisca andando, frame $fr" "$R"
  echo "$R" | grep -q "fecha em" || FAIL=1
done

R=$($LOVE $H sprite=girl shapes=slab frames=3 yaws=0 rungs=75 cell=140 \
    blink=on blinkscan=1 out=chk_bgirl.png 2>&1 | grep BLINKSCAN)
say "girl NAO pisca andando, olho nao transfere" "$R"
echo "$R" | grep -q "nao fecha" || FAIL=1

R=$($LOVE $H sprite=red shapes=slab frames=1 yaws=0 rungs=75 cell=140 \
    blink=on blinkscan=1 out=chk_b1.png 2>&1 | grep BLINKSCAN)
say "frame 1 de costas NAO pisca" "$R"
echo "$R" | grep -q "nao fecha" || FAIL=1

# 3. A piscada acontece. A janela e de 0,12 s num periodo de segundos, entao
#    amostrar o tempo de longe nao prova nada: ja concluí que nao funcionava
#    quando funcionava.
R=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=75 cell=140 \
    blink=on blinkscan=1 out=chk_blink.png 2>&1 | grep BLINKSCAN)
say "piscada dispara" "$R"
echo "$R" | grep -q "fecha em" || FAIL=1

# 4. O compositor aceita legenda com sinal de igual. Este bug apareceu duas
#    vezes identico, e o sintoma e "arquivo nao encontrado", que manda quem
#    lê procurar no lugar errado.
R=$($LOVE $H/compose out=chk_compose.png \
    "t=0.4 uma legenda com igual=$HOME/Library/Application Support/LOVE/render/chk_red.png" \
    2>&1 | grep -cE "WROTE")
say "compositor aceita '=' na legenda" "$([ "$R" = "1" ] && echo ok || echo FALHOU)"
[ "$R" = "1" ] || FAIL=1

# 5. A REGUA MEDE A SI MESMA.
#
#    Uma revisao adversarial apontou que as tres mudancas mais recentes do
#    harness nao tinham cobertura nenhuma, e que o gate oficial
#    (voxel_chars_test.lua) estruturalmente NAO PODE cobri-las: ele nunca
#    carrega este arquivo. Verde la nao diz nada sobre a regua. Entao os
#    casos abaixo cobrem o instrumento, nao o mod.

# 5a. Vazamento entre celulas. Uma forma funda transbordava a propria celula e
#     contaminava a vizinha, e so no tamanho de celula PADRAO: em celula menor
#     nao vazava, o que fazia o defeito sumir quando alguem tentava reproduzir.
A=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=220 \
    metrics=1 out=chk_iso.png 2>&1 | grep "^  slab" | grep -o "art *[0-9.]*")
B=$($LOVE $H sprite=red shapes=flat,slab,carved frames=0 yaws=0 rungs=35 cell=220 \
    metrics=1 out=chk_juntos.png 2>&1 | grep "^  slab" | grep -o "art *[0-9.]*")
say "medicao nao vaza entre celulas" "sozinho $A / ao lado do carved $B"
medido "$A" && medido "$B" && [ "$A" = "$B" ] || FAIL=1

# 5b. A passagem generica de opcao chega no mod. Sem isto, uma opcao nova
#     mediria com o padrao e ninguem notaria.
A=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=140 \
    metrics=1 out=chk_o0.png 2>&1 | grep "front  niveis" | grep -o "niveis *[0-9]*")
B=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=140 \
    opt="front_shape:0.12" metrics=1 out=chk_o1.png 2>&1 | grep "front  niveis" | grep -o "niveis *[0-9]*")
say "opcao generica chega no mod" "sem opcao $A / com opcao $B"
[ "$A" != "$B" ] || FAIL=1

# 5c. Chave desconhecida nao pode passar calada: um erro de digitacao vira
#     "medi com a opcao desligada e nao percebi".
R=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=120 \
    opt="chave_que_nao_existe:1" metrics=1 out=chk_o2.png 2>&1 | grep -c "OPCAO DESCONHECIDA")
say "chave de opcao desconhecida grita" "$([ "$R" -ge 1 ] && echo ok || echo FALHOU)"
[ "$R" -ge 1 ] || FAIL=1

# 5d. A estrutura tonal precisa DISTINGUIR FORCA. A primeira versao contava
#     tons distintos e dava o mesmo numero para 0.12 e 0.22, com 2382 de 43600
#     pixels realmente diferentes: dizia "igual" com 5% da tela mudada.
A=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=140 \
    opt="front_shape:0.12" metrics=1 out=chk_d1.png 2>&1 | grep "front  niveis" | grep -o "desvio [0-9.]*")
B=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=140 \
    opt="front_shape:0.22" metrics=1 out=chk_d2.png 2>&1 | grep "front  niveis" | grep -o "desvio [0-9.]*")
say "estrutura tonal distingue forca" "0.12 -> $A / 0.22 -> $B"
[ "$A" != "$B" ] || FAIL=1

echo
[ $FAIL -eq 0 ] && echo "REGUA OK" || echo "REGUA TORTA: nao confie em medicao ate consertar"
exit $FAIL
