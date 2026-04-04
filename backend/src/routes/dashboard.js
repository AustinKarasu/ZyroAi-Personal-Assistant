import { Router } from "express";
import { clearTasks, ensureUser, getModeState, listTasks, updateTaskStatus, upsertTask } from "../db/index.js";
import { validateBody, schemas } from "../middleware/validation.js";
import { evaluateTaskPriority, suggestFocusBlocks } from "../services/prioritization.js";

const router = Router();

router.get("/dashboard", async (req, res) => {
  await ensureUser(req.deviceId);
  const tasks = await listTasks(req.deviceId);
  const focusPlan = suggestFocusBlocks(tasks);
  const modeState = await getModeState(req.deviceId);

  res.json({
    date: new Date().toISOString(),
    activeMode: modeState.mode,
    topPriorities: tasks.slice(0, 5),
    focusPlan,
    wellbeing: {
      hydrateReminderInMin: 35,
      stretchReminderInMin: 80
    }
  });
});

router.post("/tasks", validateBody(schemas.createTask), async (req, res) => {
  await ensureUser(req.deviceId);
  const input = req.validatedBody;
  const priorityScore = evaluateTaskPriority(input);
  const id = await upsertTask(req.deviceId, {
    title: input.title,
    dueAt: input.dueAt,
    priorityScore,
    status: "todo",
    category: input.category,
    energyBand: input.energyBand
  });

  res.status(201).json({ id, priorityScore });
});

router.patch("/tasks/:id/status", validateBody(schemas.updateTaskStatus), async (req, res) => {
  await ensureUser(req.deviceId);
  const updated = await updateTaskStatus(req.deviceId, req.params.id, req.validatedBody.status);
  if (!updated) {
    return res.status(404).json({ error: "Task not found" });
  }
  return res.json({ task: updated });
});

router.delete("/tasks", async (req, res) => {
  await ensureUser(req.deviceId);
  await clearTasks(req.deviceId);
  return res.json({ cleared: true });
});

export default router;
