"""Verificador de traduções do WowUtilities.

Uso (da raiz do repositório):  python tests\\verify_l10n.py

Confere, em todos os .lua do addon (fora de tests/):
  1. toda chave L["..."] usada tem tradução em Locales/ptBR.lua;
  2. o ptBR.lua não tem chaves duplicadas;
  2b. os rótulos curtos do Edit Mode (ns.RegisterEditModeLabels) só usam chaves que já têm
      tradução normal e não se repetem;
  3. não há letras acentuadas em literais de texto fora de L[...] e de comentários
     (texto visível ao jogador deve passar por L; o ptBR.lua é a exceção).
Também lista, só como aviso, as traduções que nenhum arquivo usa.
Saída esperada: "PROBLEMAS: 0" (código de saída 0); senão, código 1.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PTBR = os.path.join("Locales", "ptBR.lua")

# Letras acentuadas (Latin-1 Supplement e Latin Extended-A). Traços e aspas tipográficas não contam.
ACCENTED = re.compile("[À-ÿĀ-ſ]")

ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n",
           "a": "\a", "b": "\b", "f": "\f", "v": "\v"}


def lua_files():
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d != "tests"]
        for name in files:
            if name.endswith(".lua"):
                full = os.path.join(base, name)
                yield os.path.relpath(full, ROOT), full


def long_bracket(src, i):
    """Se src[i:] abre um colchete longo ([[ ou [==[), devolve (nível, índice após a abertura)."""
    m = re.match(r"\[(=*)\[", src[i:])
    if not m:
        return None
    return len(m.group(1)), i + m.end()


def tokens(src):
    """Gera (tipo, valor, linha, prefixo) para literais de texto; pula comentários.
    `prefixo` é o código imediatamente antes do literal (para reconhecer L[...])."""
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif src.startswith("--", i):
            lb = long_bracket(src, i + 2)
            if lb:
                level, start = lb
                end = src.find("]" + "=" * level + "]", start)
                end = n if end < 0 else end + level + 2
            else:
                end = src.find("\n", i)
                end = n if end < 0 else end
            line += src.count("\n", i, end)
            i = end
        elif c in "\"'":
            start_line, j, out = line, i + 1, []
            while j < n and src[j] != c:
                if src[j] == "\\" and j + 1 < n:
                    nxt = src[j + 1]
                    if nxt.isdigit():
                        m = re.match(r"\d{1,3}", src[j + 1:])
                        out.append(chr(int(m.group(0))))
                        j += 1 + m.end()
                        continue
                    out.append(ESCAPES.get(nxt, nxt))
                    if nxt == "\n":
                        line += 1
                    j += 2
                    continue
                if src[j] == "\n":
                    line += 1
                out.append(src[j])
                j += 1
            yield "string", "".join(out), start_line, src[max(0, i - 20):i]
            i = j + 1
        elif c == "[" and long_bracket(src, i):
            level, start = long_bracket(src, i)
            end = src.find("]" + "=" * level + "]", start)
            end = n if end < 0 else end
            text = src[start:end]
            yield "string", text, line, src[max(0, i - 20):i]
            line += text.count("\n")
            i = end + level + 2
        else:
            i += 1


KEY_PREFIX = re.compile(r"(?<![\w.:])L\s*\[\s*$")
PTBR_ENTRY = re.compile(r"\[\s*$")
EDIT_LABELS = "ns.RegisterEditModeLabels("


def main():
    problems, used = [], {}
    ptbr_keys, ptbr_dupes = {}, []
    edit_keys, edit_dupes = {}, []

    for rel, full in sorted(lua_files()):
        with open(full, encoding="utf-8") as fh:
            src = fh.read()
        is_ptbr = os.path.normcase(rel) == os.path.normcase(PTBR)
        edit_start = src.count("\n", 0, src.find(EDIT_LABELS)) + 1 if EDIT_LABELS in src else None
        for _, text, line, prefix in tokens(src):
            if is_ptbr:
                # Entradas da tabela: ["chave"] = "valor"
                if PTBR_ENTRY.search(prefix) and edit_start and line > edit_start:
                    if text in edit_keys:
                        edit_dupes.append((text, edit_keys[text], line))
                    else:
                        edit_keys[text] = line
                elif PTBR_ENTRY.search(prefix):
                    if text in ptbr_keys:
                        ptbr_dupes.append((text, ptbr_keys[text], line))
                    else:
                        ptbr_keys[text] = line
                continue
            if KEY_PREFIX.search(prefix):
                used.setdefault(text, "%s:%d" % (rel, line))
            elif ACCENTED.search(text):
                problems.append("%s:%d: literal acentuado fora de L[...]: %r" % (rel, line, text))

    for key, where in sorted(used.items(), key=lambda kv: kv[1]):
        if key not in ptbr_keys:
            problems.append("%s: chave sem traducao no ptBR.lua: %r" % (where, key))
    for key, first, again in ptbr_dupes:
        problems.append("%s:%d: chave duplicada (primeira na linha %d): %r" % (PTBR, again, first, key))
    for key, first, again in edit_dupes:
        problems.append("%s:%d: rotulo curto duplicado (primeiro na linha %d): %r" % (PTBR, again, first, key))
    for key, line in sorted(edit_keys.items(), key=lambda kv: kv[1]):
        if key not in ptbr_keys:
            problems.append("%s:%d: rotulo curto sem traducao normal: %r" % (PTBR, line, key))

    unused = sorted(k for k in ptbr_keys if k not in used)

    for p in problems:
        print(p)
    if unused:
        print("AVISO: %d traducao(oes) sem uso:" % len(unused))
        for k in unused:
            print("  %s:%d: %r" % (PTBR, ptbr_keys[k], k))
    print("Chaves usadas: %d | traducoes: %d | rotulos curtos: %d" % (len(used), len(ptbr_keys), len(edit_keys)))
    print("PROBLEMAS: %d" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
