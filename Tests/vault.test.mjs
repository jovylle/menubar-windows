import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { decryptAll, decryptBytes, encryptAll, encryptBytes, init, parseKey } from "../scripts/vault.mjs";

function tempPaths() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "mwvault-"));
  return { root, plain: path.join(root, "private"), enc: path.join(root, "private.enc"), keyFile: path.join(root, ".vault-key") };
}

test("round trip, and the ciphertext is not the plaintext", () => {
  const key = crypto.randomBytes(32);
  const blob = encryptBytes(key, "notes/a.md", Buffer.from("secret text"));
  assert.ok(!blob.includes(Buffer.from("secret text")));
  assert.equal(decryptBytes(key, "notes/a.md", blob).toString(), "secret text");
});

test("a changed byte, a wrong key and a different path all fail", () => {
  const key = crypto.randomBytes(32);
  const blob = encryptBytes(key, "a.md", Buffer.from("hello"));
  const tampered = Buffer.from(blob);
  tampered[tampered.length - 1] ^= 1;
  assert.throws(() => decryptBytes(key, "a.md", tampered));
  assert.throws(() => decryptBytes(crypto.randomBytes(32), "a.md", blob));
  assert.throws(() => decryptBytes(key, "b.md", blob));
});

test("keys must be 64 hex characters", () => {
  assert.throws(() => parseKey("abc"));
  assert.equal(parseKey("0".repeat(64)).length, 32);
});

test("init, encrypt, decrypt on another checkout", () => {
  delete process.env.MWVAULT_KEY;
  const a = tempPaths();
  init(a);
  fs.mkdirSync(path.join(a.plain, "deep"), { recursive: true });
  fs.writeFileSync(path.join(a.plain, "deep", "plan.md"), "launch plan");
  const first = encryptAll(a);
  assert.deepEqual(first.written, ["deep/plan.md"]);
  assert.deepEqual(encryptAll(a).unchanged, ["deep/plan.md"]);

  const b = tempPaths();
  fs.cpSync(a.enc, b.enc, { recursive: true });
  fs.copyFileSync(a.keyFile, b.keyFile);
  const out = decryptAll(b);
  assert.deepEqual(out.written, ["deep/plan.md"]);
  assert.equal(fs.readFileSync(path.join(b.plain, "deep", "plan.md"), "utf8"), "launch plan");
});

test("init never replaces a key, and encrypt refuses a wrong key without --force", () => {
  delete process.env.MWVAULT_KEY;
  const a = tempPaths();
  init(a);
  assert.throws(() => init(a));
  fs.mkdirSync(a.plain, { recursive: true });
  fs.writeFileSync(path.join(a.plain, "x.txt"), "one");
  encryptAll(a);

  fs.writeFileSync(a.keyFile, crypto.randomBytes(32).toString("hex"));
  fs.writeFileSync(path.join(a.plain, "x.txt"), "two");
  const report = encryptAll(a);
  assert.deepEqual(report.refused, ["x.txt"]);
  assert.deepEqual(encryptAll(a, { force: true }).written, ["x.txt"]);
});

test("decrypt keeps a differing local file unless forced", () => {
  delete process.env.MWVAULT_KEY;
  const a = tempPaths();
  init(a);
  fs.mkdirSync(a.plain, { recursive: true });
  fs.writeFileSync(path.join(a.plain, "x.txt"), "saved");
  encryptAll(a);
  fs.writeFileSync(path.join(a.plain, "x.txt"), "newer local edit");
  assert.deepEqual(decryptAll(a).skipped, ["x.txt"]);
  assert.equal(fs.readFileSync(path.join(a.plain, "x.txt"), "utf8"), "newer local edit");
  assert.deepEqual(decryptAll(a, { force: true }).written, ["x.txt"]);
});
