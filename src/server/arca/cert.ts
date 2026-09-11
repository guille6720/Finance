import crypto from "node:crypto";
import { ArcaSanitizedError } from "./errors";

export type CertKeyMatchResult = {
  key_match: boolean;
  fingerprint_sha256: string;
  not_before: string;
  not_after: string;
  subject_cn_sanitized: string | null;
};

function tryForgeValidate(
  privateKeyPem: string,
  certificatePem: string
): CertKeyMatchResult | null {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const forge = require("node-forge") as typeof import("node-forge");
    const cert = forge.pki.certificateFromPem(certificatePem);
    const key = forge.pki.privateKeyFromPem(privateKeyPem);
    const certPublic = forge.pki.publicKeyToPem(cert.publicKey);
    const keyPublic = forge.pki.publicKeyToPem(
      forge.pki.setRsaPublicKey(key.n, key.e)
    );
    const key_match =
      certPublic.replace(/\s+/g, "") === keyPublic.replace(/\s+/g, "");
    if (!key_match) {
      throw new ArcaSanitizedError(
        "KEY_CERT_MISMATCH",
        "cert",
        "Certificate public key does not match private key"
      );
    }
    const now = new Date();
    if (now < cert.validity.notBefore || now > cert.validity.notAfter) {
      throw new ArcaSanitizedError(
        "CERT_NOT_VALID_NOW",
        "cert",
        "Certificate is outside its validity window"
      );
    }
    const der = forge.asn1.toDer(forge.pki.certificateToAsn1(cert)).getBytes();
    const fingerprint_sha256 = crypto
      .createHash("sha256")
      .update(Buffer.from(der, "binary"))
      .digest("hex");
    const cnAttr = cert.subject.getField("CN");
    return {
      key_match: true,
      fingerprint_sha256,
      not_before: cert.validity.notBefore.toISOString(),
      not_after: cert.validity.notAfter.toISOString(),
      subject_cn_sanitized: cnAttr?.value ? String(cnAttr.value).slice(0, 64) : null,
    };
  } catch (e) {
    if (e instanceof ArcaSanitizedError) throw e;
    return null;
  }
}

function validateWithNodeCrypto(
  privateKeyPem: string,
  certificatePem: string
): CertKeyMatchResult {
  try {
    const x509 = new crypto.X509Certificate(certificatePem);
    const keyObject = crypto.createPrivateKey(privateKeyPem);
    const pubFromCert = crypto.createPublicKey(x509.publicKey);
    const pubFromKey = crypto.createPublicKey(keyObject);
    const key_match =
      pubFromCert.export({ type: "spki", format: "der" }).compare(
        pubFromKey.export({ type: "spki", format: "der" })
      ) === 0;
    if (!key_match) {
      throw new ArcaSanitizedError(
        "KEY_CERT_MISMATCH",
        "cert",
        "Certificate public key does not match private key"
      );
    }
    const notBefore = new Date(x509.validFrom);
    const notAfter = new Date(x509.validTo);
    const now = new Date();
    if (now < notBefore || now > notAfter) {
      throw new ArcaSanitizedError(
        "CERT_NOT_VALID_NOW",
        "cert",
        "Certificate is outside its validity window"
      );
    }
    const fingerprint_sha256 = crypto
      .createHash("sha256")
      .update(x509.raw)
      .digest("hex");
    return {
      key_match: true,
      fingerprint_sha256,
      not_before: notBefore.toISOString(),
      not_after: notAfter.toISOString(),
      subject_cn_sanitized: x509.subject.slice(0, 64),
    };
  } catch (e) {
    if (e instanceof ArcaSanitizedError) throw e;
    throw new ArcaSanitizedError(
      "CERT_PARSE_FAILED",
      "cert",
      "Unable to parse certificate or private key"
    );
  }
}

export function validateCertKeyMatch(
  privateKeyPem: string,
  certificatePem: string
): CertKeyMatchResult {
  const viaForge = tryForgeValidate(privateKeyPem, certificatePem);
  if (viaForge) return viaForge;
  return validateWithNodeCrypto(privateKeyPem, certificatePem);
}
