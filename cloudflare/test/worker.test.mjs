import test from "node:test";
import assert from "node:assert/strict";
import worker, { DISPATCH_URL, dispatchPaperBot } from "../src/worker.mjs";

test("requires a secret and never sends a request without one", async () => {
  let called = false;
  await assert.rejects(dispatchPaperBot({}, () => { called = true; }), /Missing/);
  assert.equal(called, false);
});

test("dispatches only existing paper bot in run mode", async () => {
  const calls = [];
  const result = await dispatchPaperBot(
    { GITHUB_DISPATCH_TOKEN: "fake-secret" },
    async (url, options) => {
      calls.push({ url, options });
      return { status: 204 };
    }
  );
  assert.deepEqual(result, { ok: true, status: 204 });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, DISPATCH_URL);
  assert.equal(calls[0].options.method, "POST");
  assert.equal(calls[0].options.headers.Authorization, "Bearer fake-secret");
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    ref: "main",
    inputs: { mode: "run" },
  });
});

test("API failure does not disclose tokens or create fake success", async () => {
  await assert.rejects(
    dispatchPaperBot({ GITHUB_DISPATCH_TOKEN: "do-not-print" },
      async () => ({ status: 403 })),
    (error) => error.message === "GitHub workflow_dispatch failed: HTTP 403"
      && !error.message.includes("do-not-print")
  );
});

test("GET health is read-only and cannot reveal a token", async () => {
  const response = await worker.fetch(new Request("https://example.com/health"),
    { GITHUB_DISPATCH_TOKEN: "hidden-token" });
  assert.equal(response.status, 200);
  const body = await response.text();
  assert.equal(JSON.parse(body).configured, true);
  assert.ok(!body.includes("hidden-token"));
});

test("there is no public HTTP endpoint for starting jobs", async () => {
  const response = await worker.fetch(new Request("https://example.com/trigger", {
    method: "POST",
  }), { GITHUB_DISPATCH_TOKEN: "hidden-token" });
  assert.equal(response.status, 404);
});

test("scheduled event dispatches asynchronously", async () => {
  const before = globalThis.fetch;
  const calls = [];
  const tasks = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url, options });
    return { status: 204 };
  };
  try {
    await worker.scheduled({}, { GITHUB_DISPATCH_TOKEN: "hidden-token" }, {
      waitUntil(promise) { tasks.push(promise); },
    });
    await Promise.all(tasks);
    assert.equal(tasks.length, 1);
    assert.equal(calls.length, 1);
  } finally {
    globalThis.fetch = before;
  }
});
