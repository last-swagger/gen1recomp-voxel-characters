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
LOVE=/opt/homebrew/bin/love
H=mods/voxel_characters/tools/render
FAIL=0

say() { printf "%-52s %s\n" "$1" "$2"; }

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

echo
[ $FAIL -eq 0 ] && echo "REGUA OK" || echo "REGUA TORTA: nao confie em medicao ate consertar"
exit $FAIL
