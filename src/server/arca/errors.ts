export class ArcaSanitizedError extends Error {
  readonly code: string;
  readonly stage: string;

  constructor(code: string, stage: string, message: string) {
    super(message);
    this.name = "ArcaSanitizedError";
    this.code = code;
    this.stage = stage;
  }

  toJSON() {
    return {
      name: this.name,
      code: this.code,
      stage: this.stage,
      message: this.message,
    };
  }
}

/** Strip token/sign/PEM-like blobs from provider messages before logging. */
export function sanitizeArcaMessage(raw: string): string {
  return String(raw || "")
    .replace(/-----BEGIN[\s\S]*?-----END[^-]+-----/g, "[REDACTED_PEM]")
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, "[REDACTED_JWT]")
    .replace(/\b[A-Za-z0-9+/]{80,}={0,2}\b/g, "[REDACTED_B64]")
    .replace(/<(Token|Sign|token|sign)>[^<]*<\/\1>/gi, "<$1>[REDACTED]</$1>")
    .slice(0, 500);
}
