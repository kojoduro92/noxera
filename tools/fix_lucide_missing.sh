set -euo pipefail

INDEX="packages/ui/src/index.ts"

# 1) Re-export lucide-react from @noxera/ui (so apps can import icons from @noxera/ui)
if ! grep -q 'export \* from "lucide-react"' "$INDEX" 2>/dev/null; then
  echo '' >> "$INDEX"
  echo 'export * from "lucide-react";' >> "$INDEX"
  echo "✅ Added lucide-react re-export to $INDEX"
else
  echo "✅ lucide-react already re-exported in $INDEX"
fi

# 2) Replace all app imports:  from "lucide-react"  ->  from "@noxera/ui"
FILES="$(grep -RIl --exclude-dir=node_modules 'from ["'\''"]lucide-react["'\''"]' apps || true)"

if [ -z "$FILES" ]; then
  echo "✅ No lucide-react imports found under apps/"
  exit 0
fi

echo "🔧 Patching lucide-react imports in:"
echo "$FILES"

while IFS= read -r f; do
  perl -pi -e 's/from\s+["'\'']lucide-react["'\''];/from "@noxera\/ui";/g' "$f"
done <<< "$FILES"

echo "🎉 Done. Apps now import icons via @noxera/ui (DRY)."
