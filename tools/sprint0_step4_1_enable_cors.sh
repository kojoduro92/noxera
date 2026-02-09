set -euo pipefail

FILE="apps/api/src/main.ts"

test -f "$FILE" || { echo "❌ Missing $FILE"; exit 1; }

node - <<'NODE'
const fs = require("fs");
const p = "apps/api/src/main.ts";
let s = fs.readFileSync(p, "utf8");

if (!s.includes("enableCors(")) {
  s = s.replace(
    /const\s+app\s*=\s*await\s+NestFactory\.create\([^\)]*\);\s*/m,
    (m) =>
      m +
      `\n  // ✅ Dev CORS for Next apps\n  app.enableCors({\n    origin: [/^http:\\/\\/localhost:\\d+$/],\n    credentials: true,\n  });\n`
  );
  fs.writeFileSync(p, s);
  console.log("✅ CORS enabled in apps/api/src/main.ts");
} else {
  console.log("✅ CORS already enabled — no change.");
}
NODE
