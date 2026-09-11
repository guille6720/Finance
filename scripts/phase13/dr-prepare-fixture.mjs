#!/usr/bin/env node
/**
 * Prepare deterministic synthetic DR fixtures metadata (LOCAL).
 * Does not talk to Staging. Does not provision paid resources.
 *
 * Storage object MUST use an allowed purchase-evidence MIME:
 * application/pdf, image/jpeg, image/png, image/webp
 * (text/plain is rejected by the bucket).
 */
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { PHASE13_DIR, ROOT } from "./env.mjs";

const PDF = Buffer.from(
  [
    "%PDF-1.4",
    "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj",
    "2 0 obj<</Type/Pages/Count 1/Kids[3 0 R]>>endobj",
    "3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 72 72]>>endobj",
    "trailer<</Root 1 0 R>>",
    "%%EOF",
    "",
  ].join("\n"),
  "utf8"
);
const sha256 = crypto.createHash("sha256").update(PDF).digest("hex");

const outDir = path.join(PHASE13_DIR, "dr");
const manifestPath = path.join(outDir, "DR-FIXTURE-MANIFEST.json");
const blobPath = path.join(outDir, "DR_FIXTURE_PURCHASE_EVIDENCE.pdf");

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(blobPath, PDF);

const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
manifest.storage.sha256 = sha256;
manifest.storage.bytes = PDF.length;
manifest.storage.mime_type = "application/pdf";
manifest.storage.object_name = "DR_FIXTURE_PURCHASE_EVIDENCE.pdf";
manifest.relationships.storage_path =
  "{organization_id}/{purchase_document_id}/DR_FIXTURE_PURCHASE_EVIDENCE.pdf";
manifest.created_at = new Date().toISOString();
manifest.evidence_class = "LOCAL_SYNTHETIC_FILE";
manifest.local_blob = "docs/qa/phase13/dr/DR_FIXTURE_PURCHASE_EVIDENCE.pdf";
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n");

console.log(
  JSON.stringify(
    {
      status: "PREPARED",
      sha256,
      bytes: PDF.length,
      mime: "application/pdf",
      blob: blobPath.replace(ROOT + path.sep, ""),
      upload: "deferred_until_cost_approval_or_local_storage_test",
    },
    null,
    2
  )
);
