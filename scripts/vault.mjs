#!/usr/bin/env node
// vault.mjs: keep private files in a public repo as AES-256-GCM ciphertext.
//
// Plaintext lives in private/ (gitignored). Ciphertext lives in private.enc/ (committed), one
// <path>.enc file per plaintext file. Only Node's built-in crypto is used: no dependencies.
//
// Gotchas:
// - The key is never printed and never committed. It comes from the MWVAULT_KEY environment variable
//   (64 hex characters) or from the file .vault-key (gitignored, mode 600). Losing the key loses the
//   data: back it up somewhere other than this repo, such as a password manager.
// - Each file is bound to its relative path (the GCM additional data), so renaming or swapping two
//   .enc files makes decryption fail instead of returning the wrong content.
// - A fresh random IV is used per write, so encrypting twice gives different bytes. `encrypt` skips
//   files whose plaintext did not change, to keep git history free of churn.
// - `encrypt` refuses to replace an existing .enc that fails to decrypt with the current key (wrong
//   or new key). `--force` is the only override. This protects data from a silent re-key.
// - `decrypt` does not overwrite a differing plaintext file unless `--force` is given.
//
// Usage: node scripts/vault.mjs <init|encrypt|decrypt|status|check> [--force] [--prune]
//        MWVAULT_ROOT=<dir> overrides the repo root (the tests use it).

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const MAGIC = Buffer.from("MWV1");
const IV_LENGTH = 12;
const TAG_LENGTH = 16;
const HEADER = MAGIC.length + IV_LENGTH + TAG_LENGTH;

export function parseKey(text) {
  const hex = String(text ?? "").trim();
  if (!/^[0-9a-fA-F]{64}$/.test(hex)) {
    throw new Error("The key must be 64 hex characters (32 bytes).");
  }
  return Buffer.from(hex, "hex");
}

export function encryptBytes(key, relPath, plain) {
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv, { authTagLength: TAG_LENGTH });
  cipher.setAAD(Buffer.from(relPath, "utf8"));
  const body = Buffer.concat([cipher.update(plain), cipher.final()]);
  return Buffer.concat([MAGIC, iv, cipher.getAuthTag(), body]);
}

export function decryptBytes(key, relPath, blob) {
  if (blob.length < HEADER || !blob.subarray(0, MAGIC.length).equals(MAGIC)) {
    throw new Error("Not a vault file.");
  }
  const iv = blob.subarray(MAGIC.length, MAGIC.length + IV_LENGTH);
  const tag = blob.subarray(MAGIC.length + IV_LENGTH, HEADER);
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv, { authTagLength: TAG_LENGTH });
  decipher.setAAD(Buffer.from(relPath, "utf8"));
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(blob.subarray(HEADER)), decipher.final()]);
}

function walk(dir, base = dir) {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === ".DS_Store") continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full, base));
    else if (entry.isFile()) out.push(path.relative(base, full).split(path.sep).join("/"));
  }
  return out.sort();
}

function layout(root) {
  return {
    root,
    plain: path.join(root, "private"),
    enc: path.join(root, "private.enc"),
    keyFile: path.join(root, ".vault-key"),
  };
}

function loadKey(paths) {
  if (process.env.MWVAULT_KEY) return parseKey(process.env.MWVAULT_KEY);
  if (fs.existsSync(paths.keyFile)) return parseKey(fs.readFileSync(paths.keyFile, "utf8"));
  throw new Error("No key. Set MWVAULT_KEY or run `node scripts/vault.mjs init`.");
}

function writeFile(file, data, mode) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, data, { mode });
}

export function init(paths) {
  if (process.env.MWVAULT_KEY || fs.existsSync(paths.keyFile)) {
    throw new Error("A key already exists. init never replaces it.");
  }
  if (walk(paths.enc).length > 0) {
    throw new Error("private.enc already holds files. Restore their key into .vault-key instead.");
  }
  writeFile(paths.keyFile, crypto.randomBytes(32).toString("hex") + "\n", 0o600);
  fs.mkdirSync(paths.plain, { recursive: true });
  return "Created .vault-key (gitignored). Back it up outside this repo. Losing it loses the data.";
}

export function encryptAll(paths, { force = false, prune = false } = {}) {
  const key = loadKey(paths);
  const report = { written: [], unchanged: [], refused: [], pruned: [] };
  const plainFiles = walk(paths.plain);
  for (const rel of plainFiles) {
    const plain = fs.readFileSync(path.join(paths.plain, rel));
    const target = path.join(paths.enc, rel + ".enc");
    if (fs.existsSync(target)) {
      try {
        const current = decryptBytes(key, rel, fs.readFileSync(target));
        if (current.equals(plain)) {
          report.unchanged.push(rel);
          continue;
        }
      } catch {
        if (!force) {
          report.refused.push(rel);
          continue;
        }
      }
    }
    writeFile(target, encryptBytes(key, rel, plain), 0o644);
    report.written.push(rel);
  }
  if (prune) {
    const wanted = new Set(plainFiles);
    for (const encRel of walk(paths.enc)) {
      const rel = encRel.replace(/\.enc$/, "");
      if (!wanted.has(rel)) {
        fs.rmSync(path.join(paths.enc, encRel));
        report.pruned.push(rel);
      }
    }
  }
  return report;
}

export function decryptAll(paths, { force = false } = {}) {
  const key = loadKey(paths);
  const report = { written: [], unchanged: [], skipped: [], failed: [] };
  for (const encRel of walk(paths.enc)) {
    if (!encRel.endsWith(".enc")) continue;
    const rel = encRel.slice(0, -4);
    let plain;
    try {
      plain = decryptBytes(key, rel, fs.readFileSync(path.join(paths.enc, encRel)));
    } catch {
      report.failed.push(rel);
      continue;
    }
    const target = path.join(paths.plain, rel);
    if (fs.existsSync(target)) {
      if (fs.readFileSync(target).equals(plain)) {
        report.unchanged.push(rel);
        continue;
      }
      if (!force) {
        report.skipped.push(rel);
        continue;
      }
    }
    writeFile(target, plain, 0o600);
    report.written.push(rel);
  }
  return report;
}

/** Fails when plaintext or the key could end up in a commit. Used as a pre-commit check. */
export function check(paths) {
  const problems = [];
  let tracked = [];
  try {
    tracked = execFileSync("git", ["-C", paths.root, "ls-files"], { encoding: "utf8" })
      .split("\n")
      .filter(Boolean);
  } catch {
    return problems;
  }
  for (const file of tracked) {
    if (file.startsWith("private/")) problems.push(`${file} is tracked but must stay local`);
    if (file === ".vault-key") problems.push(".vault-key is tracked");
  }
  return problems;
}

function main() {
  const [command, ...flags] = process.argv.slice(2);
  const options = { force: flags.includes("--force"), prune: flags.includes("--prune") };
  const root = process.env.MWVAULT_ROOT ?? path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const paths = layout(root);
  try {
    if (command === "init") {
      console.log(init(paths));
    } else if (command === "encrypt") {
      const r = encryptAll(paths, options);
      console.log(`encrypted ${r.written.length}, unchanged ${r.unchanged.length}, pruned ${r.pruned.length}`);
      if (r.refused.length) {
        console.error(`refused (existing ciphertext does not open with this key, use --force): ${r.refused.join(", ")}`);
        process.exitCode = 1;
      }
    } else if (command === "decrypt") {
      const r = decryptAll(paths, options);
      console.log(`decrypted ${r.written.length}, unchanged ${r.unchanged.length}`);
      if (r.skipped.length) console.error(`kept your newer plaintext (use --force to overwrite): ${r.skipped.join(", ")}`);
      if (r.failed.length) {
        console.error(`failed to decrypt: ${r.failed.join(", ")}`);
        process.exitCode = 1;
      }
    } else if (command === "status") {
      const plain = walk(paths.plain);
      const enc = walk(paths.enc).map((f) => f.replace(/\.enc$/, ""));
      console.log(`plaintext files: ${plain.length}, ciphertext files: ${enc.length}`);
      for (const f of plain.filter((f) => !enc.includes(f))) console.log(`  not encrypted yet: ${f}`);
      for (const f of enc.filter((f) => !plain.includes(f))) console.log(`  only encrypted (run decrypt): ${f}`);
    } else if (command === "check") {
      const problems = check(paths);
      for (const p of problems) console.error(p);
      process.exitCode = problems.length ? 1 : 0;
      if (!problems.length) console.log("ok: no plaintext or key is tracked");
    } else {
      console.error("Usage: node scripts/vault.mjs <init|encrypt|decrypt|status|check> [--force] [--prune]");
      process.exitCode = 2;
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) main();
