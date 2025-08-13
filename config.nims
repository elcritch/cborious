import std/[os, strutils, sequtils, algorithm]

proc listTestFiles(): seq[string] =
  # Use staticExec to remain NimScript-compatible
  let listing = staticExec("sh -lc 'ls -1 tests/t*.nim tests/test*.nim 2>/dev/null || true'")
  result = listing.splitLines().filterIt(it.len > 0).deduplicate()
  result.sort()

task unitTests, "Run unit tests (fast)":
  let files = listTestFiles()
  if files.len == 0:
    echo "No tests found under tests/."
  for f in files:
    echo "[unitTests] Running ", f
    exec "nim r " & f

task test, "Run full test suite":
  let files = listTestFiles()
  if files.len == 0:
    echo "No tests found under tests/."
  # In the future, add repo fixture runs here.
  for f in files:
    echo "[test] Running ", f
    exec "nim r " & f

task docs, "Generate API docs to docs/api":
  let outDir = "docs/api"
  exec "sh -lc 'mkdir -p " & outDir & "'"
  let listing2 = staticExec("sh -lc 'find src -type f -name " & "\'*.nim\'" & " -print 2>/dev/null || true'")
  var files = listing2.splitLines().filterIt(it.len > 0)
  files.sort()
  if files.len == 0:
    echo "No Nim sources found under src/."
  for f in files:
    echo "[docs] Generating for ", f
    exec "nim doc --outdir:" & outDir & " " & f
