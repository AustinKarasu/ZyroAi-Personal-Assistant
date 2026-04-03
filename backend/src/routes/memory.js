import { Router } from "express";
import { addMemory, ensureUser, listMemories } from "../db/index.js";
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

export default router;
