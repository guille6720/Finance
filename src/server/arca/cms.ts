import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { ArcaSanitizedError } from "./errors";

/**
 * Create PKCS#7 / CMS SignedData (attached) for WSAA LoginCms.
 * Prefers node-forge in-memory; falls back to openssl with wiped temp files.
 * Never logs key/cert/CMS.
 */
export function signTraCms(
  traXml: string,
  privateKeyPem: string,
  certificatePem: string
): string {
  try {
    return signWithForge(traXml, privateKeyPem, certificatePem);
  } catch {
    try {
      return signWithOpenSsl(traXml, privateKeyPem, certificatePem, "cms");
    } catch {
      return signWithOpenSsl(traXml, privateKeyPem, certificatePem, "smime");
    }
  }
}

function signWithForge(
  traXml: string,
  privateKeyPem: string,
  certificatePem: string
): string {
  // Dynamic require so unit env without install can fall back.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const forge = require("node-forge") as typeof import("node-forge");
  const cert = forge.pki.certificateFromPem(certificatePem);
  const key = forge.pki.privateKeyFromPem(privateKeyPem);
  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(traXml, "utf8");
  p7.addCertificate(cert);
  p7.addSigner({
    key,
    certificate: cert,
    digestAlgorithm: forge.pki.oids.sha256,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      // node-forge accepts Date at runtime; typings expect string
      { type: forge.pki.oids.signingTime, value: new Date() as unknown as string },
    ],
  });
  p7.sign({ detached: false });
  const der = forge.asn1.toDer(p7.toAsn1()).getBytes();
  return forge.util.encode64(der);
}

function signWithOpenSsl(
  traXml: string,
  privateKeyPem: string,
  certificatePem: string,
  mode: "cms" | "smime"
): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "arca-cms-"));
  const keyPath = path.join(dir, "k.pem");
  const certPath = path.join(dir, "c.pem");
  const traPath = path.join(dir, "tra.xml");
  const outPath = path.join(dir, "out.der");
  try {
    fs.writeFileSync(keyPath, privateKeyPem, { mode: 0o600 });
    fs.writeFileSync(certPath, certificatePem, { mode: 0o600 });
    fs.writeFileSync(traPath, traXml, { mode: 0o600 });
    const args =
      mode === "cms"
        ? [
            "cms",
            "-sign",
            "-in",
            traPath,
            "-signer",
            certPath,
            "-inkey",
            keyPath,
            "-outform",
            "DER",
            "-nodetach",
            "-out",
            outPath,
          ]
        : [
            "smime",
            "-sign",
            "-in",
            traPath,
            "-signer",
            certPath,
            "-inkey",
            keyPath,
            "-outform",
            "DER",
            "-nodetach",
            "-out",
            outPath,
          ];
    execFileSync("openssl", args, {
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
    });
    const der = fs.readFileSync(outPath);
    return der.toString("base64");
  } catch {
    throw new ArcaSanitizedError(
      "CMS_SIGN_FAILED",
      "cms",
      "Unable to sign TRA CMS"
    );
  } finally {
    for (const p of [keyPath, certPath, traPath, outPath]) {
      try {
        if (fs.existsSync(p)) {
          const len = fs.statSync(p).size;
          fs.writeFileSync(p, crypto.randomBytes(Math.max(len, 32)));
          fs.unlinkSync(p);
        }
      } catch {
        /* ignore */
      }
    }
    try {
      fs.rmdirSync(dir);
    } catch {
      /* ignore */
    }
  }
}
