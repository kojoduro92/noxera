import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { PrismaClient } from "@prisma/client";

function readSchema() {
  const candidates = [
    path.join(process.cwd(), "apps/api/prisma/schema.prisma"),
    path.join(process.cwd(), "prisma/schema.prisma"),
  ];
  const p = candidates.find((x) => fs.existsSync(x));
  if (!p) throw new Error("schema.prisma not found in apps/api/prisma or prisma/");
  return fs.readFileSync(p, "utf8");
}

function pickEnumFirst(schema, enumName) {
  const re = new RegExp(`enum\\s+${enumName}\\s*\\{([\\s\\S]*?)\\n\\}`, "m");
  const m = schema.match(re);
  if (!m) return null;
  const vals = m[1]
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("//"))
    .map((l) => l.split(/\s+/)[0]);
  return vals[0] || null;
}

function parseModel(schema, modelName) {
  const re = new RegExp(`model\\s+${modelName}\\s*\\{([\\s\\S]*?)\\n\\}`, "m");
  const m = schema.match(re);
  if (!m) return null;

  const lines = m[1]
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("//"));

  const fields = [];
  for (const line of lines) {
    if (line.startsWith("@@")) continue;

    const parts = line.split(/\s+/);
    const name = parts[0];
    const type = parts[1];

    if (!name || !type) continue;
    if (type.endsWith("[]")) continue;           // list
    if (type.endsWith("?")) continue;            // optional
    if (line.includes("@relation")) continue;    // relation
    if (line.includes("@default(")) continue;    // has default -> can omit

    fields.push({ name, type });
  }
  return fields;
}

function lowerFirst(s){ return s ? s[0].toLowerCase() + s.slice(1) : s; }

const schema = readSchema();

// Find the model referenced by Tenant.plan relation
const tenantBlock = schema.match(/model\s+Tenant\s*\{([\s\S]*?)\n\}/m);
if (!tenantBlock) throw new Error("Tenant model not found in schema.prisma");

const planLine = tenantBlock[1]
  .split("\n")
  .map((l) => l.trim())
  .find((l) => l.startsWith("plan ") && l.includes("@relation"));

if (!planLine) throw new Error("Tenant.plan relation line not found (expected: plan <Model> @relation...)");

const planModelName = planLine.split(/\s+/)[1]?.replace("?", "");
if (!planModelName) throw new Error("Could not detect plan model name from Tenant.plan line");

const fields = parseModel(schema, planModelName) || [];
const prisma = new PrismaClient();

const delegate = lowerFirst(planModelName);
if (typeof prisma[delegate] !== "object") {
  throw new Error(`Prisma delegate prisma.${delegate} not found (model ${planModelName}).`);
}

const existing = await prisma[delegate].count();
if (existing > 0) {
  console.log(`✅ ${planModelName} already has ${existing} row(s). Skipping seed.`);
  await prisma.$disconnect();
  process.exit(0);
}

const data = {};
for (const f of fields) {
  const t = f.type;

  if (t === "String") {
    if (f.name.toLowerCase().includes("name")) data[f.name] = "Default Plan";
    else if (f.name.toLowerCase().includes("slug")) data[f.name] = "default-plan";
    else if (f.name.toLowerCase().includes("id")) data[f.name] = crypto.randomUUID();
    else data[f.name] = "default";
    continue;
  }

  if (t === "Int" || t === "BigInt") { data[f.name] = 0; continue; }
  if (t === "Boolean") { data[f.name] = true; continue; }
  if (t === "DateTime") { data[f.name] = new Date(); continue; }
  if (t === "Json") { data[f.name] = {}; continue; }

  // Enum: pick first value
  const enumFirst = pickEnumFirst(schema, t);
  if (enumFirst) { data[f.name] = enumFirst; continue; }

  // Unknown scalar: skip
}

const created = await prisma[delegate].create({ data });
console.log("✅ Seeded first plan:", created);

await prisma.$disconnect();
