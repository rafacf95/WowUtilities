"""Roda o harness do WowUtilities em todas as variações de ambiente.

Uso (da raiz do repositório):
    python tests\\run.py            # todas as variações
    python tests\\run.py -v         # também lista os testes que passaram
    python tests\\run.py enUS-lem   # só as variações cujo nome contém o texto

Precisa de Python 3 e da lupa (python -m pip install lupa). Usa o Lua 5.1 da lupa
(lupa.lua51), a mesma versão do WoW. Cada variação roda num Lua novo, então nada
vaza de uma para outra. Saída esperada: "FALHAS: 0" em todas (código de saída 0).
"""

import os
import sys

try:
    from lupa import lua51
except ImportError:  # pragma: no cover
    sys.exit("lupa nao encontrada: rode  python -m pip install lupa")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TOC = os.path.join(ROOT, "WowUtilities.toc")

# Cada variação liga ou desliga uma parte do ambiente simulado (ver harness.lua).
VARIANTS = [
    dict(name="ptBR-lem", locale="ptBR", editmode=True),
    dict(name="ptBR-drag", locale="ptBR", editmode=False),
    dict(name="enUS-lem", locale="enUS", editmode=True),
    dict(name="deDE-drag", locale="deDE", editmode=False, noTemplates=True),
    dict(name="legacy-db", locale="enUS", editmode=False, legacyDb=True),
    dict(name="lsm", locale="ptBR", editmode=True, lsm=True),
    dict(name="old-colorpicker", locale="enUS", editmode=False, oldPicker=True, noTemplates=True),
    dict(name="coin", locale="ptBR", editmode=False, coin=True),
]


def toc_files():
    files = []
    with open(TOC, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#"):
                files.append(line.replace("\\", "/"))
    return files


def run_variant(variant, files, verbose):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.HARNESS_ROOT = ROOT.replace("\\", "/")
    g.HARNESS_PATH = os.path.join(HERE, "harness.lua").replace("\\", "/")
    g.HARNESS_FILES = lua.table_from(files)
    g.HARNESS_VARIANT = lua.table_from(variant)
    try:
        result = lua.execute("return dofile(HARNESS_PATH)")
    except Exception as exc:  # erro fora de um teste: o próprio harness quebrou
        print("  ERRO NO HARNESS: %s" % exc)
        return 1, 0
    fails, passes = int(result["fail"]), int(result["pass"])
    lines = result["lines"]
    for i in range(1, len(lines) + 1):
        line = lines[i]
        if verbose or not line.startswith("ok "):
            print("  " + line)
    return fails, passes


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    verbose = "-v" in argv
    filters = [a for a in argv if not a.startswith("-")]
    files = toc_files()
    total = 0
    for variant in VARIANTS:
        if filters and not any(f in variant["name"] for f in filters):
            continue
        print("== %s" % variant["name"])
        fails, passes = run_variant(variant, files, verbose)
        print("  testes: %d | FALHAS: %d" % (passes + fails, fails))
        total += fails
    print("TOTAL DE FALHAS: %d" % total)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
