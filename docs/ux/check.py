"""Check the UX prototypes: links resolve, assets exist, tags balance.

    python docs/ux/check.py

Static HTML rots quietly: a renamed page leaves a dead nav link, a moved asset
leaves an unstyled screen. This is the smallest thing that fails when that
happens.
"""

import re
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "source", "track", "wbr"}


class Balance(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.errors = []

    def handle_starttag(self, tag, attrs):
        if tag not in VOID:
            self.stack.append((tag, self.getpos()))

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if not self.stack:
            self.errors.append(f"{self.getpos()}: stray </{tag}>")
            return
        open_tag, pos = self.stack.pop()
        if open_tag != tag:
            self.errors.append(
                f"{self.getpos()}: </{tag}> closes <{open_tag}> opened at {pos}")


def main():
    pages = sorted(ROOT.glob("*.html"))
    if not pages:
        print("no pages found")
        return 1
    failures = []
    for page in pages:
        text = page.read_text(encoding="utf-8")
        # Balanced tags.
        parser = Balance()
        parser.feed(text)
        for leftover in parser.stack:
            parser.errors.append(f"unclosed <{leftover[0]}> at {leftover[1]}")
        for error in parser.errors:
            failures.append(f"{page.name}: {error}")
        # Local references exist.
        for ref in re.findall(r'(?:href|src)="([^"#:]+)"', text):
            if ref.startswith(("http", "//", "mailto")):
                continue
            target = (page.parent / ref).resolve()
            if not target.exists():
                failures.append(f"{page.name}: missing {ref}")
        print(f"  {page.name:<22} {len(text.splitlines()):>4} 行  "
              f"{len(re.findall(r'class=', text)):>3} 处样式引用")

    if failures:
        print("\n失败:")
        for failure in failures:
            print("  " + failure)
        return 1
    print(f"\n{len(pages)} 个页面全部通过：标签平衡、引用完整")
    return 0


if __name__ == "__main__":
    sys.exit(main())
