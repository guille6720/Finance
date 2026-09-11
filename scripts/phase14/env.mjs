import path from "node:path";
import { fileURLToPath } from "node:url";
import { PHASE13_DIR, ROOT, LOCAL } from "../phase13/env.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export { ROOT, LOCAL, PHASE13_DIR };
export const PHASE14_DIR = path.join(ROOT, "docs", "qa", "phase14");
export const RELEASE_DIR = path.join(ROOT, "docs", "release");
export const RELEASE_MANIFEST_PATH = path.join(RELEASE_DIR, "RELEASE-MANIFEST.json");
export const OPS_DIR = path.join(ROOT, "docs", "operations");
