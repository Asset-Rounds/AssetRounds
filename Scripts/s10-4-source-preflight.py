#!/usr/bin/env python3
"""Nonaccepting S10.4 source-lock preflight. Does not compile or execute Swift.

Evaluates a closed read-only subset of the checked-in XCTest source. Unsupported
assertions remain explicitly SKIPPED; a clean subset is not hosted acceptance.
"""
from __future__ import annotations
import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


class Unsupported(Exception):
    pass


@dataclass
class Token:
    text: str
    start: int
    end: int
    scope: int = 0


@dataclass(frozen=True)
class Span:
    lower: int
    upper: int


class SwiftSubset:
    def __init__(self, source: str, root: Path):
        self.source, self.root = source, root.resolve()
        self.literals = {}
        self.tokens = self.lex(source)
        self.parents = {0: None}
        self.scopes = {0: None}
        self.declarations = {}
        self.cache = {}
        self.read_sources = {}
        self.scope_kinds = {0: 'root'}
        self.parameterized_functions = set()
        self.loops = {}
        stack = [0]
        for i, token in enumerate(self.tokens):
            token.scope = stack[-1]
            if token.text == "{":
                self.parents[i + 1] = stack[-1]
                self.scopes[i + 1] = i
                j = i - 1
                while j >= 0 and self.tokens[j].text not in ("{", "}", ";"):
                    j -= 1
                controls = [t.text for t in self.tokens[j + 1:i] if t.text in ("class", "struct", "extension", "func", "for", "if", "else", "switch", "while", "catch")]
                self.scope_kinds[i + 1] = controls[-1] if controls else "closure"
                if self.scope_kinds[i + 1] == "func":
                    function_start = max(k for k in range(j + 1, i) if self.tokens[k].text == "func")
                    openings = [k for k in range(function_start, i) if self.tokens[k].text == "("]
                    if not openings or self.tokens[openings[0] + 1].text != ")":
                        self.parameterized_functions.add(i + 1)
                stack.append(i + 1)
            elif token.text == "}":
                if len(stack) == 1:
                    raise ValueError("Unbalanced Swift closing brace")
                stack.pop()
        if len(stack) != 1:
            raise ValueError("Unbalanced Swift opening brace")
        for i, token in enumerate(self.tokens):
            if token.text in ("let", "var") and i + 2 < len(self.tokens):
                name = self.tokens[i + 1].text
                # Every declaration shadows outer bindings, including unsupported
                # mutable/uninitialized declarations. Never fall through to an
                # outer immutable value simply because this declaration is skipped.
                expression = "@unsupported-declaration@"
                j = i + 2
                if self.tokens[j].text == ":":
                    while j < len(self.tokens) and self.tokens[j].text not in ("=", "\n", "{"):
                        if j > i + 2 and "\n" in self.source[self.tokens[j - 1].end:self.tokens[j].start]:
                            break
                        j += 1
                if token.text == "let" and j < len(self.tokens) and self.tokens[j].text == "=":
                    end = self.expression_end(j + 1)
                    expression = self.canonical(j + 1, end)
                self.declarations.setdefault((token.scope, name), []).append((token.start, expression))
            if token.text == "for" and i + 3 < len(self.tokens):
                if self.tokens[i + 2].text != "in":
                    continue
                j = self.expression_end(i + 3, stop_brace=True)
                if j < len(self.tokens) and self.tokens[j].text == "{":
                    self.loops[j + 1] = (self.tokens[i + 1].text, self.canonical(i + 3, j), token.start, token.scope)

    def lex(self, text):
        tokens = []
        i = 0
        while i < len(text):
            if text[i].isspace():
                i += 1
                continue
            if text.startswith("//", i):
                j = text.find("\n", i)
                i = len(text) if j < 0 else j
                continue
            if text.startswith("/*", i):
                depth, j = 1, i + 2
                while depth and j < len(text):
                    if text.startswith("/*", j):
                        depth, j = depth + 1, j + 2
                    elif text.startswith("*/", j):
                        depth, j = depth - 1, j + 2
                    else:
                        j += 1
                if depth:
                    raise ValueError("Unterminated Swift comment")
                i = j
                continue
            match = re.compile(r'(#+)?("""|")').match(text, i)
            if match:
                hashes, quote = match.group(1) or "", match.group(2)
                start, j = i, i + len(match.group(0))
                close = quote + hashes
                escape = "\\" + hashes
                content_start = j
                while j < len(text):
                    if text.startswith(escape, j):
                        j += len(escape) + 1
                    elif text.startswith(close, j):
                        break
                    else:
                        j += 1
                if j >= len(text):
                    raise ValueError(f"Unterminated Swift string at offset {start}")
                content = text[content_start:j]
                marker = f"@L{len(self.literals)}@"
                try:
                    self.literals[marker] = self.decode(content, hashes, quote)
                except Unsupported as exc:
                    self.literals[marker] = exc
                i = j + len(close)
                tokens.append(Token(marker, start, i))
                continue
            match = re.compile(r"[A-Za-z_]\w*|\d[\d_]*|\.\.<|\.\.\.|==|!=|&&|\|\||->").match(text, i)
            end = i + (len(match.group(0)) if match else 1)
            tokens.append(Token(text[i:end], i, end))
            i = end
        return tokens

    @staticmethod
    def decode(content, hashes, quote):
        escape = "\\" + hashes
        if escape + "(" in content:
            raise Unsupported("Swift interpolation")
        if quote == '"""':
            if not content.startswith("\n"):
                raise Unsupported("Multiline string layout")
            ending = content.rsplit("\n", 1)
            if len(ending) != 2 or ending[1].strip():
                raise Unsupported("Multiline closing indentation")
            indent = ending[1]
            lines = ending[0][1:].split("\n")
            if any(line and not line.startswith(indent) for line in lines):
                raise Unsupported("Multiline indentation")
            content = "\n".join(line[len(indent):] if line else "" for line in lines)
        pattern = re.escape(escape) + r'(u\{[0-9a-fA-F]+\}|[^\n])'
        escapes = {"0": "\0", "n": "\n", "r": "\r", "t": "\t", '"': '"', "'": "'", "\\": "\\"}
        def replace(match):
            value = match.group(1)
            if value.startswith("u{"):
                return chr(int(value[2:-1], 16))
            if value not in escapes:
                raise Unsupported("Unsupported Swift escape")
            return escapes[value]
        return re.sub(pattern, replace, content)

    def canonical(self, start, end):
        return "".join(token.text for token in self.tokens[start:end])

    def expression_end(self, start, stop_brace=False):
        depth = 0
        for j in range(start, len(self.tokens)):
            text = self.tokens[j].text
            if depth == 0:
                if text in (",", ";", "}", "else") or (stop_brace and text == "{"):
                    return j
                if j > start:
                    gap = self.source[self.tokens[j - 1].end:self.tokens[j].start]
                    if "\n" in gap and text not in (".", "+", "-", "..<") and self.tokens[j - 1].text not in ("+", "-", "..<", "="):
                        return j
            if text in ("(", "[", "{"):
                depth += 1
            elif text in (")", "]", "}"):
                if depth == 0:
                    return j
                depth -= 1
        return len(self.tokens)

    @staticmethod
    def split(expression, separator=","):
        result, start, depth = [], 0, 0
        i = 0
        while i < len(expression):
            char = expression[i]
            if char in "([{":
                depth += 1
            elif char in ")]}":
                depth -= 1
            elif depth == 0 and expression.startswith(separator, i):
                result.append(expression[start:i])
                start = i + len(separator)
                i += len(separator) - 1
            i += 1
        result.append(expression[start:])
        return result

    def lookup(self, name, position, scope, overrides, trail):
        current = scope
        while current is not None:
            options = [x for x in self.declarations.get((current, name), []) if x[0] < position]
            if options:
                start, expression = options[-1]
                key = (current, name, start)
                if key in trail:
                    raise Unsupported("Cyclic source binding")
                if key in self.cache:
                    return self.cache[key]
                try:
                    value = self.evaluate(expression, start, current, {}, trail | {key})
                    self.cache[key] = value
                    return value
                except Unsupported:
                    return self.evaluate(expression, start, current, overrides, trail | {key})
            if current in self.loops and self.loops[current][0] == name:
                if name not in overrides:
                    raise Unsupported("Loop binding requires its lexical iteration context")
                return overrides[name]
            current = self.parents[current]
        raise Unsupported(f"Unresolved binding: {name}")

    def file_bytes(self, relative):
        if not isinstance(relative, str):
            raise Unsupported("Nonliteral repository path")
        path = (self.root / relative).resolve()
        if not path.is_relative_to(self.root) or not path.is_file():
            raise Unsupported(f"Missing or outside-repository path: {relative}")
        if path not in self.read_sources:
            raw = path.read_bytes()
            self.read_sources[path] = raw
        return self.read_sources[path]

    def evaluate(self, expression, position, scope, overrides=None, trail=None):
        overrides, trail = overrides or {}, trail or set()
        ev = lambda value: self.evaluate(value, position, scope, overrides, trail)
        expression = expression.removeprefix("try")
        if expression in self.literals:
            value = self.literals[expression]
            if isinstance(value, Exception):
                raise value
            return value
        if re.fullmatch(r"\d[\d_]*", expression):
            return int(expression.replace("_", ""))
        if expression in ("true", "false"):
            return expression == "true"
        if re.fullmatch(r"[A-Za-z_]\w*", expression):
            return self.lookup(expression, position, scope, overrides, trail)
        for op in ("+", "-", "..<"):
            parts = self.split(expression, op)
            if len(parts) == 2:
                a, b = map(ev, parts)
                return a + b if op == "+" else a - b if op == "-" else Span(a, b)
        if expression.startswith("[") and expression.endswith("]"):
            return [ev(x) for x in self.split(expression[1:-1]) if x]
        match = re.fullmatch(r"(text|Data|String)\((.*)\)", expression)
        if match:
            value = ev(match[2].removesuffix(".utf8"))
            return self.file_bytes(value).decode("utf-8", errors="replace") if match[1] == "text" else value.encode("utf-8") if match[1] == "Data" else str(value)
        match = re.fullmatch(r"boundedSource\((.*)\)", expression)
        if match:
            parts = self.split(match[1])
            if len(parts) != 3 or not parts[1].startswith("from:") or not parts[2].startswith("before:"):
                raise Unsupported("boundedSource shape")
            source, start, end = ev(parts[0]), ev(parts[1][5:]), ev(parts[2][7:])
            left = source.find(start)
            right = source.find(end, left + len(start)) if left >= 0 else -1
            if left < 0 or right < 0:
                raise ValueError("Missing bounded-source marker")
            return source[left:right]
        match = re.fullmatch(r"(.+)\.(components|contains|range)\((.*)\)", expression)
        if match:
            receiver, method = ev(match[1]), match[2]
            parts = self.split(match[3])
            if method == "components" and len(parts) == 1 and parts[0].startswith("separatedBy:"):
                separator = ev(parts[0][12:])
                if not separator:
                    raise Unsupported("Empty components separator")
                return receiver.split(separator)
            if method == "contains" and len(parts) == 1:
                return ev(parts[0]) in receiver
            if method == "range" and parts[0].startswith("of:") and len(parts) <= 2:
                needle = ev(parts[0][3:])
                lower, upper = 0, len(receiver)
                if len(parts) == 2:
                    if not parts[1].startswith("range:"):
                        raise Unsupported("Range label")
                    bound = ev(parts[1][6:])
                    lower, upper = bound.lower, bound.upper
                found = receiver.find(needle, lower, upper)
                if found < 0:
                    raise ValueError("Missing source-range marker")
                return Span(found, found + len(needle))
            raise Unsupported("Source method shape")
        if expression.endswith(".utf8.count"):
            return len(ev(expression[:-11]).encode("utf-8"))
        match = re.fullmatch(r"(.+)\.(count|sha256|lowerBound|upperBound|endIndex)", expression)
        if match:
            value = ev(match[1])
            attr = match[2]
            if attr == "utf8.count":
                return len(value.encode("utf-8"))
            if attr in ("count", "endIndex"):
                return len(value)
            if attr == "sha256":
                if not isinstance(value, bytes):
                    raise Unsupported("Hash requires Data")
                return hashlib.sha256(value).hexdigest().upper()
            return value.lower if attr == "lowerBound" else value.upper
        match = re.fullmatch(r"([A-Za-z_]\w*)\[(.+)\]", expression)
        if match:
            value, index = ev(match[1]), ev(match[2])
            return value[index.lower:index.upper] if isinstance(index, Span) else value[index]
        if expression.startswith("!") and not expression.startswith("!="):
            return not ev(expression[1:])
        raise Unsupported("Expression outside closed static subset")

    def contexts(self, scope):
        chain, current = [], scope
        while current is not None:
            if current in self.parameterized_functions:
                raise Unsupported("Parameterized function body")
            if self.scope_kinds[current] not in ("root", "class", "struct", "extension", "func") and current not in self.loops:
                raise Unsupported("Dynamic control-flow or unsupported closure scope")
            if current in self.loops:
                chain.append(self.loops[current])
            current = self.parents[current]
        contexts = [{}]
        names = [row[0] for row in chain]
        if len(names) != len(set(names)):
            raise Unsupported("Repeated nested loop binding")
        for name, expression, position, loop_scope in reversed(chain):
            expanded = []
            for context in contexts:
                values = self.evaluate(expression, position, loop_scope, context)
                if not isinstance(values, list) or len(values) > 2000:
                    raise Unsupported("Nonliteral or unbounded loop")
                expanded.extend(dict(context, **{name: value}) for value in values)
            contexts = expanded
        return contexts

    def run(self):
        results = []
        for i, token in enumerate(self.tokens):
            if not (token.text.startswith("XCTAssert") or token.text == "assertFile"):
                continue
            if i + 1 >= len(self.tokens) or self.tokens[i + 1].text != "(":
                continue
            depth, end = 1, i + 2
            while end < len(self.tokens):
                if self.tokens[end].text == "(":
                    depth += 1
                elif self.tokens[end].text == ")":
                    depth -= 1
                    if depth == 0:
                        break
                end += 1
            args = self.split(self.canonical(i + 2, end))
            line = self.source.count("\n", 0, token.start) + 1
            joined = ",".join(args[:2])
            kind = "fileIdentity" if token.text == "assertFile" else "sha256" if ".sha256" in joined else "utf8Bytes" if ".utf8.count" in joined else "occurrence" if ".components(" in joined else "presence" if ".contains(" in joined else "outsideSubset"
            entry = {"line": line, "assertion": token.text, "kind": kind}
            if token.text != "assertFile" and not any(x in joined for x in (".components(", ".contains(", ".utf8.count", ".sha256")):
                results.append(dict(entry, status="SKIPPED", reason="Outside deterministic source-lock subset"))
                continue
            try:
                contexts = self.contexts(token.scope)
                if not contexts:
                    raise Unsupported("Empty loop")
                for context in contexts:
                    ev = lambda value: self.evaluate(value, token.start, token.scope, context)
                    if token.text == "assertFile":
                        if len(args) < 3 or not args[1].startswith("byteCount:") or not args[2].startswith("sha256:"):
                            raise Unsupported("assertFile declaration or call shape")
                        raw = self.file_bytes(ev(args[0]))
                        actual = [len(raw), hashlib.sha256(raw).hexdigest().upper()]
                        expected = [ev(args[1][10:]), ev(args[2][7:])]
                    elif token.text == "XCTAssertEqual":
                        actual, expected = ev(args[0]), ev(args[1])
                    elif token.text in ("XCTAssertTrue", "XCTAssertFalse"):
                        actual, expected = ev(args[0]), token.text == "XCTAssertTrue"
                    else:
                        raise Unsupported("Assertion outside equality/presence subset")
                    status = "PASS" if actual == expected else "FAIL"
                    results.append(dict(entry, status=status, actual=actual, expected=expected))
            except Unsupported as exc:
                results.append(dict(entry, status="SKIPPED", reason=str(exc)))
            except (ValueError, IndexError, KeyError, TypeError, AttributeError, OSError) as exc:
                results.append(dict(entry, status="ERROR", reason=str(exc)))
        return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--self-test", action="store_true", help="Run synthetic closed-subset tests; no repository changes")
    parser.add_argument("--json", action="store_true", help="Print complete assertion coverage JSON to stdout; writes no files")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    root = args.repository_root.resolve()
    unit_path = root / "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift"
    try:
        raw = unit_path.read_bytes()
        checker = SwiftSubset(raw.decode("utf-8"), root)
        results = checker.run()
        counts = dict(Counter(x["status"] for x in results))
        head = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
        report = {
            "kind": "nonaccepting-source-lock-subset", "hostedAcceptance": False,
            "head": head, "unitSHA256": hashlib.sha256(raw).hexdigest().upper(),
            "counts": counts, "results": results,
            "coverageByKind": dict(Counter(x["kind"] + ":" + x["status"] for x in results)),
            "skippedReasons": dict(Counter(x["reason"] for x in results if x["status"] == "SKIPPED")),
            "readSources": [{"path": path.relative_to(root).as_posix(), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest().upper()} for path, data in sorted(checker.read_sources.items())],
            "limitations": [
                "Not Swift compilation, XCTest execution, runtime/UI evidence, or acceptance.",
                "Unsupported expressions, interpolation, mutation fixtures, and dynamic assertions are explicitly skipped.",
                "Run AuthorityH separately to verify frozen 67-state/14-shard/938-cell/84-row authority.",
            ],
        }
        if args.json:
            print(json.dumps(report, indent=2))
        else:
            print(json.dumps({key: value for key, value in report.items() if key != "results"}, indent=2))
            for result in results:
                if result["status"] in ("FAIL", "ERROR"):
                    print(json.dumps(result))
        return 1 if counts.get("FAIL") or counts.get("ERROR") else 0
    except Exception as exc:
        print(json.dumps({"status": "ERROR", "hostedAcceptance": False, "reason": str(exc)}))
        return 2



def self_test():
    def run(source):
        return SwiftSubset(source, Path.cwd()).run()
    good = r'''
class Audit {
    let source = "start\nalpha\nalpha\nend"
    func testA() {
        let bounded = try boundedSource(source, from: "start\n", before: "\nend")
        XCTAssertEqual(bounded.utf8.count, 17)
        XCTAssertEqual(source.components(separatedBy: "alpha").count - 1, 2)
        let locks = ["start", "alpha", "end"]
        for lock in locks {
            XCTAssertTrue(source.contains(lock))
        }
        guard let startRange = source.range(of: "alpha"),
              let endRange = source.range(of: "\nend", range: startRange.upperBound..<source.endIndex)
        else { return }
        let slice = String(source[startRange.lowerBound..<endRange.lowerBound])
        XCTAssertEqual(slice.utf8.count, 11)
        let raw = #"Text("raw")"#
        XCTAssertTrue(raw.contains(#""raw""#))
        let unicode = "é"
        XCTAssertEqual(unicode.utf8.count, 2)
    }
    func testB() {
        let source = "elsewhere"
        XCTAssertEqual(source.components(separatedBy: "alpha").count - 1, 0)
    }
}'''
    outcomes = run(good)
    if len(outcomes) != 9 or any(x["status"] != "PASS" for x in outcomes):
        raise ValueError(f"Self-test supported subset: {outcomes}")
    fail = run('let source = "alpha"\nXCTAssertEqual(source.components(separatedBy: "alpha").count - 1, 2)')
    if len(fail) != 1 or fail[0]["status"] != "FAIL":
        raise ValueError("Self-test mismatch was not rejected")
    skip = run(r'let source = "\(dynamic)"' + '\nXCTAssertTrue(source.contains("value"))')
    if len(skip) != 1 or skip[0]["status"] != "SKIPPED":
        raise ValueError("Self-test interpolation was not skipped")
    hostile_shadows = [
        ('let source = "alpha"\nfunc testA() {\n var source = "beta"\n XCTAssertTrue(source.contains("alpha"))\n}', "SKIPPED"),
        ('let source = "alpha"\nfor lock in ["alpha"] {\n let lock = "beta"\n XCTAssertTrue(source.contains(lock))\n}', "FAIL"),
        ('let source = "alpha"\nfunc testA(source: String) {\n XCTAssertTrue(source.contains("alpha"))\n}', "SKIPPED"),
        ('let source = "alpha"\nfunc testA() {\n let source: String\n XCTAssertTrue(source.contains("alpha"))\n}', "SKIPPED"),
    ]
    for source, expected_status in hostile_shadows:
        shadow = run(source)
        if len(shadow) != 1 or shadow[0]["status"] != expected_status:
            raise ValueError(f"Self-test lexical shadow was guessed: {shadow}")
    missing = run('let source = "alpha"\nlet slice = try boundedSource(source, from: "missing", before: "alpha")\nXCTAssertEqual(slice.utf8.count, 0)')
    if len(missing) != 1 or missing[0]["status"] != "ERROR":
        raise ValueError("Self-test missing marker was not rejected")
    try:
        SwiftSubset('let bad = "unterminated', Path.cwd())
    except ValueError:
        pass
    else:
        raise ValueError("Self-test lexical error was not rejected")
    print("PASS: nonaccepting source-preflight synthetic self-tests")


if __name__ == "__main__":
    sys.exit(main())
