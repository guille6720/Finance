import pg from "pg";
import { ensureLocalEnv, LOCAL } from "./env.mjs";

const { Client } = pg;

export async function withDb(fn, connectionString) {
  const env = connectionString
    ? { dbUrl: connectionString }
    : { ...LOCAL, ...ensureLocalEnv() };
  const client = new Client({ connectionString: env.dbUrl || LOCAL.dbUrl });
  await client.connect();
  try {
    return await fn(client, env);
  } finally {
    await client.end();
  }
}

export async function query(client, text, params = []) {
  return client.query(text, params);
}
