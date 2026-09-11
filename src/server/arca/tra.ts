import { TRA_VALIDITY_SECONDS } from "./constants";

function pad(n: number) {
  return String(n).padStart(2, "0");
}

/** AFIP-style local datetime with offset, e.g. 2026-09-10T13:00:00.000-03:00 */
export function formatAfipDateTime(d: Date, offsetMinutes = -180): string {
  const utc = d.getTime() + d.getTimezoneOffset() * 60_000;
  const local = new Date(utc + offsetMinutes * 60_000);
  const sign = offsetMinutes <= 0 ? "-" : "+";
  const abs = Math.abs(offsetMinutes);
  const oh = pad(Math.floor(abs / 60));
  const om = pad(abs % 60);
  return (
    `${local.getFullYear()}-${pad(local.getMonth() + 1)}-${pad(local.getDate())}` +
    `T${pad(local.getHours())}:${pad(local.getMinutes())}:${pad(local.getSeconds())}.000` +
    `${sign}${oh}:${om}`
  );
}

export type TraDocument = {
  xml: string;
  uniqueId: number;
  generationTime: string;
  expirationTime: string;
  service: "wsfe";
};

export function buildLoginTicketRequest(
  service: "wsfe" = "wsfe",
  now = new Date(),
  validitySeconds = TRA_VALIDITY_SECONDS
): TraDocument {
  const uniqueId = Math.floor(now.getTime() / 1000);
  const generationDate = new Date(now.getTime() - 10 * 60_000);
  const generationTime = formatAfipDateTime(generationDate);
  const expirationTime = formatAfipDateTime(
    new Date(now.getTime() + validitySeconds * 1000)
  );

  const xml =
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<loginTicketRequest version="1.0">` +
    `<header>` +
    `<uniqueId>${uniqueId}</uniqueId>` +
    `<generationTime>${generationTime}</generationTime>` +
    `<expirationTime>${expirationTime}</expirationTime>` +
    `</header>` +
    `<service>${service}</service>` +
    `</loginTicketRequest>`;

  return { xml, uniqueId, generationTime, expirationTime, service };
}
