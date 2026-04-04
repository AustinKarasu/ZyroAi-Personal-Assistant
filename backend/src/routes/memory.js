import { Router } from "express";
import { addMemory, clearMemories, ensureUser, listMemories, removeMemory } from "../db/index.js";
import { validateBody, schemas } from "../middleware/validation.js";
import { encrypt } from "../services/crypto.js";

const router = Router();

router.get("/memory", async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ entries: await listMemories(req.deviceId) });
});

router.post("/memory", validateBody(schemas.addMemory), async (req, res) => {
  await ensureUser(req.deviceId);
  const { note, hint } = req.validatedBody;
  const encrypted = encrypt(note);
  const id = await addMemory(req.deviceId, encrypted, hint);
  res.status(201).json({ id, hint });
});

router.delete("/memory/:id", async (req, res) => {
  await ensureUser(req.deviceId);
  const removed = await removeMemory(req.deviceId, req.params.id);
  if (!removed) return res.status(404).json({ error: "Memory not found" });
  return res.json({ removed: true });
});

router.delete("/memory", async (req, res) => {
  await ensureUser(req.deviceId);
  await clearMemories(req.deviceId);
  return res.json({ cleared: true });
});

export default router;
