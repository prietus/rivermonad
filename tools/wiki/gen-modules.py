#!/usr/bin/env python3
"""Generate wiki/docs/modules/ from the Haddock header of every contrib
module in src/Rivermonad/{Actions,Hooks,Layout,Util}/, like the
xmonad-contrib documentation: one page per module (its description,
examples and exports) and an index table.

Run from the repository root: tools/wiki/gen-modules.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "src", "Rivermonad")
OUT = os.path.join(ROOT, "wiki", "docs", "modules")
CATEGORIES = [
    ("Actions", "Actions", "Commands to bind to keys: moving the focus, menus, windows on several workspaces..."),
    ("Hooks", "Hooks", "Things that happen on their own: when a window opens or closes, after every change..."),
    ("Layout", "Layouts", "Ways to arrange windows, and modifiers that change any layout."),
    ("Util", "Utilities", "Key bindings, menus, scratchpads, state and other helpers for your configuration."),
]
# Modules that are internals of a category, not for configurations.
SKIP = {"Rivermonad.Util.Process"}


def inline(text):
    """Haddock inline markup to Markdown."""
    # "Module.Name" -> link to its page
    def mod_link(m):
        name = m.group(1)
        parts = name.split(".")
        if len(parts) == 3 and parts[0] == "Rivermonad":
            return f"[`{name}`](../{parts[1].lower()}/{parts[2]}.md)"
        return f"`{name}`"
    text = re.sub(r'"(Rivermonad(?:\.[A-Z][A-Za-z0-9]*)+)"', mod_link, text)
    text = re.sub(r"@([^@]+)@", r"`\1`", text)                       # @code@
    text = re.sub(r"'([A-Za-z_][A-Za-z0-9_.']*)'", r"`\1`", text)    # 'identifier'
    return text


def parse(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    header, i = [], 0
    while i < len(lines) and not lines[i].startswith("module "):
        line = lines[i]
        if line.startswith("--"):
            header.append(line[2:])
        i += 1
    # export list: from "module X" to "where"
    exports_src = []
    while i < len(lines):
        exports_src.append(lines[i])
        if re.search(r"\bwhere\s*$", lines[i]):
            break
        i += 1
    src = "\n".join(exports_src)
    m = re.search(r"\((.*)\)\s*where", src, re.S)
    exports = []
    if m:
        body = re.sub(r"--[^\n]*", "", m.group(1))
        for item in body.split(","):
            item = " ".join(item.split())
            if item:
                exports.append(item)
    return header, exports


def to_markdown(header):
    """The header comment, with '-- >' example lines as code blocks and
    '-- *' items as lists."""
    out, code = [], []
    text = [h[1:] if h.startswith(" ") else h for h in header]
    # drop a leading "| "
    if text and text[0].startswith("| "):
        text[0] = text[0][2:]
    for line in text:
        if line.startswith(">"):
            code.append(line[2:] if line.startswith("> ") else line[1:])
            continue
        if code:
            out.append("```haskell")
            out.extend(code)
            out.append("```")
            code = []
        out.append(inline(line))
    if code:
        out.extend(["```haskell"] + code + ["```"])
    md = "\n".join(out).strip() + "\n"
    return md


def first_sentence(md):
    """The first sentence of the first paragraph, without the "as in
    XMonad..." reference."""
    para = []
    for line in md.split("\n"):
        if not line.strip():
            if para:
                break
            continue
        para.append(line.strip())
    text = " ".join(para)
    text = re.split(r"(?<=[a-z0-9)`])\. ", text)[0].rstrip(".")
    text = re.sub(r",? (as|after|like) in `XMonad[^`]*`(,| with the [^,:.]*)?", "", text)
    text = re.sub(r",? after `XMonad[^`]*`", "", text)
    text = text.split(": ")[0] if len(text) > 110 else text
    return text.rstrip(".;, ")


def main():
    index = ["# Modules", "",
             "rivermonad ships ports of the most used "
             "[xmonad-contrib](https://hackage.haskell.org/package/xmonad-contrib) "
             "modules in the same package, with the `XMonad.` prefix replaced by "
             "`Rivermonad.`. Import the ones you use in your `rivermonad.hs`:", "",
             "```haskell", "import Rivermonad.Actions.WindowGo", "```", "",
             "These pages are generated from the documentation in each module's "
             "source, so they always match the version in the repository.", ""]
    nav = []
    for folder, title, blurb in CATEGORIES:
        d = os.path.join(SRC, folder)
        mods = sorted(f[:-3] for f in os.listdir(d) if f.endswith(".hs"))
        mods = [m for m in mods if f"Rivermonad.{folder}.{m}" not in SKIP]
        if not mods:
            continue
        outdir = os.path.join(OUT, folder.lower())
        os.makedirs(outdir, exist_ok=True)
        index += [f"## {title}", "", blurb, "", "| Module | |", "|---|---|"]
        pages = []
        nav.append((title, pages))
        for m in mods:
            name = f"Rivermonad.{folder}.{m}"
            header, exports = parse(os.path.join(d, m + ".hs"))
            md = to_markdown(header)
            summary = first_sentence(md)
            page = [f"# {name}", "", md]
            if exports:
                page += ["## Exports", ""] + [f"- `{e}`" for e in exports] + [""]
            page += [f"Source: [`src/Rivermonad/{folder}/{m}.hs`]"
                     f"(https://github.com/prietus/rivermonad/blob/main/src/Rivermonad/{folder}/{m}.hs)", ""]
            with open(os.path.join(outdir, m + ".md"), "w", encoding="utf-8") as f:
                f.write("\n".join(page))
            index.append(f"| [{m}]({folder.lower()}/{m}.md) | {summary} |")
            pages.append((m, f"modules/{folder.lower()}/{m}.md"))
        index.append("")
    with open(os.path.join(OUT, "index.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(index))
    write_config(nav)


def write_config(nav):
    """wiki/mkdocs.yml with the module pages in the navigation, as
    wiki/mkdocs.gen.yml (MkDocs cannot list a directory by itself)."""
    src = os.path.join(ROOT, "wiki", "mkdocs.yml")
    with open(src, encoding="utf-8") as f:
        lines = f.read().split("\n")
    out = []
    for line in lines:
        if line.strip().startswith("- Modules: modules/"):
            indent = line[:len(line) - len(line.lstrip())]
            out.append(f"{indent}- Modules:")
            out.append(f"{indent}    - modules/index.md")
            for title, pages in nav:
                out.append(f"{indent}    - {title}:")
                for name, path in pages:
                    out.append(f"{indent}        - {name}: {path}")
        else:
            out.append(line)
    with open(os.path.join(ROOT, "wiki", "mkdocs.gen.yml"), "w", encoding="utf-8") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    sys.exit(main())
