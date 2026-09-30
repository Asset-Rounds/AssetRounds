from pathlib import Path
import hashlib, json, re

q = Path('.codex-temp/cold-ledger-continuation-successor-v1')
p = q / 'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift'
s = p.read_text()
before = hashlib.sha256(p.read_bytes()).hexdigest()
assert before == 'b4bc9f51389341f7599a5b34a6dd254d6585ec0f7889a345590217dbcf991dd2', before
start = s.index('    private final class PublicationSessionV1 {')
end = s.index('\n    private func publishDurably(', start + 1)
body = s[start:end]
calls = list(re.finditer(r'Darwin\.(?:fstat|fstatat|fsync)\(', body))
replacements = []
for hit in calls:
    j = hit.end()
    depth = 1
    while depth:
        if body[j] == '(': depth += 1
        elif body[j] == ')': depth -= 1
        j += 1
    text = body[hit.start():j]
    replacements.append((hit.start(), j, 'try store.originalEraseBorrowedObservationIO { ' + text + ' }'))
for left, right, replacement in reversed(replacements):
    body = body[:left] + replacement + body[right:]
needle = '                let opened = Darwin.openat(parent, temporaryName,\n'
assert body.count(needle) == 1
body = body.replace(needle, '                try store.requireScratchDescriptorAccess()\n' + needle)
s = s[:start] + body + s[end:]
needle = '        // dup shares the directory offset with the retained descriptor.\n        Darwin.rewinddir(directory)\n'
assert s.count(needle) == 1
s = s.replace(needle, '        // dup shares the directory offset with the retained descriptor.\n        try self.originalEraseBorrowedObservationIO { Darwin.rewinddir(directory) }\n')
p.write_text(s)
record = {
    'model': 'gpt-6.1-sol', 'reasoningEffort': 'xhigh',
    'beforeSHA256': before, 'afterSHA256': hashlib.sha256(p.read_bytes()).hexdigest(),
    'nestedPublicationMetadataAndSyncCalls': len(calls),
    'change': 'Fresh borrowed binding before/after each nested publication metadata/sync call and rewinddir; explicit pre-open memory/fresh fence, retained owner still installed before any post-open callback.',
    'unchanged': ['No open/close wrapped across owner installation or close receipt', 'No predicate, publication stage or producer payload change', 'Ordinary path uses the same wrapper with ordinary no-op fence'],
    'runtime': 'due', 'semanticCompilation': 'due'
}
(q / 'NESTED_PUBLICATION_IO_V22.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record, indent=2))
