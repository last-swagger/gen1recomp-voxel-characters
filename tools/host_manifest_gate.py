#!/usr/bin/env python3
"""Confere a ordem de carregamento entre os hosts e o manifesto do mod."""

import json
import re
import sys
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]


def falha(mensagem: str) -> None:
    print(f"HOST MANIFEST FAILED: {mensagem}", file=sys.stderr)
    raise SystemExit(1)


try:
    manifesto = json.loads((MOD / "manifest.json").read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as erro:
    falha(f"manifest.json invalido: {erro}")

fonte = (MOD / "main.lua").read_text(encoding="utf-8")
tabela = re.search(r"local HOSTS = \{(.*?)\n\}", fonte, flags=re.S)
if not tabela:
    falha("nao encontrei a tabela HOSTS em main.lua")

jogos = set(manifesto.get("games", []))
dependencias = {
    item for item in manifesto.get("optional_dependencies", [])
    if isinstance(item, str)
}


def cobre_geracao(geracao: str) -> bool:
    if "all" in jogos or geracao in jogos:
        return True
    versoes = {"red", "blue", "yellow"} if geracao == "gen1" else {
        "gold", "silver", "crystal"
    }
    return bool(jogos & versoes)


entradas = re.findall(r"\n  \{(.*?)\n  \},", tabela.group(1), flags=re.S)
vistos: set[str] = set()
contagem = 0
for entrada in entradas:
    id_host = re.search(r'id\s*=\s*"([^"]+)"', entrada)
    geracao = re.search(r'game\s*=\s*"(gen[12])"', entrada)
    if not id_host or not geracao:
        falha("cada entrada de HOSTS precisa de id e game gen1/gen2")
    host = id_host.group(1)
    if host in vistos:
        falha(f"id repetido em HOSTS: {host}")
    vistos.add(host)
    if cobre_geracao(geracao.group(1)):
        contagem += 1
        if host not in dependencias:
            falha(f"{host} pode ser carregado, mas falta em optional_dependencies")

if contagem == 0:
    falha("nenhum host corresponde aos jogos do manifesto")
print(f"HOST MANIFEST OK: {contagem} host(s) coberto(s) por optional_dependencies")
