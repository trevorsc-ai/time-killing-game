#!/usr/bin/env bash
# Offline guarantee: fail if Swift sources use networking APIs or if any SPM dependency appears.
set -u
fail=0
dirs="PuzzleGetaway PuzzleGetawayTests PuzzleGetawayUITests"

check() {
  local label="$1" pattern="$2"
  local hits
  hits=$(grep -rnE --include='*.swift' "$pattern" $dirs 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "::error::Forbidden networking API ($label) found:"
    echo "$hits"
    fail=1
  fi
}

check "URLSession" 'URLSession'
check "import Network" '^[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+Network([[:space:]]|$)'
check "import WebKit" '^[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+WebKit([[:space:]]|$)'
check "NSURLConnection" 'NSURLConnection'
check "URLRequest(" 'URLRequest\('

pkgs=$(find . -path ./node_modules -prune -o -path ./tools/forge/node_modules -prune -o \( -name 'Package.resolved' -o -name 'Package.swift' \) -print 2>/dev/null)
if [ -n "$pkgs" ]; then
  echo "::error::Swift Package Manager files found (no third-party dependencies allowed):"
  echo "$pkgs"
  fail=1
fi
if grep -nE '^[[:space:]]*packages:' project.yml; then
  echo "::error::project.yml declares SPM packages"
  fail=1
fi

if [ "$fail" -eq 0 ]; then echo "Network audit passed: no networking APIs or SPM dependencies."; fi
exit "$fail"
