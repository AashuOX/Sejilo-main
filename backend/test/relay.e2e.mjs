import assert from "node:assert/strict";
import { generateKeyPairSync, randomBytes, randomUUID, sign } from "node:crypto";
import { WebSocket } from "ws";

const baseUrl = process.env.SEJILO_E2E_URL ?? "http://127.0.0.1:8080";

const request = async (path, { method = "GET", token, body } = {}) => {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      accept: "application/json",
      ...(body ? { "content-type": "application/json" } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const responseText = await response.text();
  const value = responseText ? JSON.parse(responseText) : {};
  if (!response.ok) {
    throw new Error(`${method} ${path} failed (${response.status}): ${JSON.stringify(value)}`);
  }
  return { status: response.status, value };
};

const registerDevice = async () => {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const challenge = await request("/v1/auth/challenges", {
    method: "POST",
    body: { purpose: "register" },
  });
  const publicDer = publicKey.export({ type: "spki", format: "der" });
  const publicRaw = publicDer.subarray(publicDer.length - 32);
  const signature = sign(null, Buffer.from(challenge.value.payload), privateKey);
  const session = await request("/v1/devices/register", {
    method: "POST",
    body: {
      challengeId: challenge.value.challengeId,
      publicKey: publicRaw.toString("base64url"),
      signature: signature.toString("base64url"),
      platform: "windows",
      protocolVersions: [1],
      capabilities: ["encrypted-relay-v1"],
    },
  });
  return session.value;
};

const waitForSocketMessage = (socket, type) => new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error(`Timed out waiting for ${type}`)), 5000);
  const listener = (raw) => {
    const message = JSON.parse(raw.toString());
    if (message.type !== type) return;
    clearTimeout(timeout);
    socket.off("message", listener);
    resolve(message);
  };
  socket.on("message", listener);
});

const sender = await registerDevice();
const recipient = await registerDevice();
const intruder = await registerDevice();
const wsUrl = baseUrl.replace(/^http/, "ws") + "/v1/ws";
const unauthorizedSocket = new WebSocket(wsUrl);
await new Promise((resolve, reject) => {
  unauthorizedSocket.once("close", (code) => {
    try {
      assert.equal(code, 1008);
      resolve();
    } catch (error) {
      reject(error);
    }
  });
  unauthorizedSocket.once("unexpected-response", (_request, response) => {
    try {
      assert.equal(response.statusCode, 401);
      resolve();
    } catch (error) {
      reject(error);
    }
  });
  unauthorizedSocket.once("error", () => {});
});
const socket = new WebSocket(wsUrl, {
  headers: { authorization: `Bearer ${recipient.token}` },
});
const readyPromise = waitForSocketMessage(socket, "ready");
await new Promise((resolve, reject) => {
  socket.once("open", resolve);
  socket.once("error", reject);
});
const ready = await readyPromise;
assert.equal(ready.deviceId, recipient.deviceId);
const liveHint = waitForSocketMessage(socket, "messages");

const now = Date.now();
const envelope = {
  protocolVersion: 1,
  packetType: "message",
  packetId: randomUUID(),
  messageId: randomUUID(),
  senderDeviceId: sender.deviceId,
  recipientDeviceId: recipient.deviceId,
  createdAt: new Date(now).toISOString(),
  expiresAt: new Date(now + 60 * 60 * 1000).toISOString(),
  ttl: 4,
  hopCount: 0,
  payloadType: "ciphertext",
  encryptedPayload: randomBytes(96).toString("base64url"),
  contentEncoding: "identity",
};

const accepted = await request("/v1/messages", {
  method: "POST",
  token: sender.token,
  body: envelope,
});
assert.equal(accepted.status, 202);
assert.equal(accepted.value.duplicate, false);
await liveHint;

const duplicate = await request("/v1/messages", {
  method: "POST",
  token: sender.token,
  body: envelope,
});
assert.equal(duplicate.status, 200);
assert.equal(duplicate.value.duplicate, true);

const pending = await request("/v1/messages/pending?limit=100", {
  token: recipient.token,
});
assert.equal(pending.value.envelopes.length, 1);
assert.deepEqual(pending.value.envelopes[0], envelope);

await assert.rejects(
  request(`/v1/messages/${envelope.messageId}/acknowledgements`, {
    method: "POST",
    token: intruder.token,
    body: { state: "delivered_to_device" },
  }),
  /failed \(400\)/,
);

const acknowledgement = await request(
  `/v1/messages/${envelope.messageId}/acknowledgements`,
  {
    method: "POST",
    token: recipient.token,
    body: { state: "delivered_to_device" },
  },
);
assert.equal(acknowledgement.value.state, "delivered_to_device");

const empty = await request("/v1/messages/pending", { token: recipient.token });
assert.equal(empty.value.envelopes.length, 0);

const refreshed = await request("/v1/sessions/refresh", {
  method: "POST",
  body: { refreshToken: recipient.refreshToken },
});
assert.notEqual(refreshed.value.token, recipient.token);
await assert.rejects(
  request("/v1/sessions/refresh", {
    method: "POST",
    body: { refreshToken: recipient.refreshToken },
  }),
  /failed \(401\)/,
);
await request("/v1/sessions/current", {
  method: "DELETE",
  token: refreshed.value.token,
});
await assert.rejects(
  request("/v1/messages/pending", { token: refreshed.value.token }),
  /failed \(401\)/,
);
socket.close();
console.log("relay e2e passed: auth rotation/revocation, WS auth, IDOR, queue, idempotency, ack");
