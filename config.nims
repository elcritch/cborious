import std/[os, strutils, sequtils, algorithm]

proc listTestFiles(): seq[string] =
  var files: seq[string]
  for pat in ["tests/t*.nim", "tests/test*.nim"]:
    for f in walkFiles(pat):
      files.add f
  files = files.deduplicate()
  files.sort()
  result = files

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
  if not dirExists(outDir): createDir(outDir)
  var files: seq[string]
  for f in walkDirRec("src"):
    if f.endsWith(".nim"): files.add f
  files.sort()
  if files.len == 0:
    echo "No Nim sources found under src/."
  for f in files:
    echo "[docs] Generating for ", f
    exec "nim doc --outdir:" & outDir & " " & f
