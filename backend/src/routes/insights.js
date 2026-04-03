import { Router } from "express";
import { ensureUser, listCallLogs, listMemories, listTasks } from "../db/index.js";
import { validateBody, schemas } from "../middleware/validation.js";
import { loadUpdateManifest } from "../services/updates.js";

const router = Router();

router.get("/insights", async (req, res) => {
  await ensureUser(req.deviceId);
  const tasks = await listTasks(req.deviceId);
  const logs = await listCallLogs(req.deviceId);
  const memories = await listMemories(req.deviceId);
  const updateCenter = await loadUpdateManifest();

  const openTasks = tasks.filter((task) => task.status !== "done").length;
  const highPriority = tasks.filter((task) => task.priority_score >= 70).length;
  const urgentCalls = logs.filter((log) => log.urgency >= 75).length;

  const recommendations = [
    highPriority > 0 ? `You have ${highPriority} high-priority tasks. Protect two focus blocks.` : "No critical tasks right now.",
    urgentCalls > 0 ? `${urgentCalls} urgent communication items should be handled first.` : "Communication stack is healthy.",
    memories.length > 0 ? "Memory vault is populated for proactive reminders." : "Capture important personal details for smarter reminders.",
    updateCenter.updateAvailable ? `Version ${updateCenter.latestVersion} is ready to roll out.` : "App is on the latest release channel."
  ];

  res.json({
    productivityScore: Math.max(40, Math.min(98, 60 + highPriority * 3 - urgentCalls * 2 + Math.min(openTasks, 8))),
    openTasks,
    highPriority,
    urgentCalls,
    memoryCount: memories.length,
    recommendations,
    updateCenter
  });
});

router.get("/updates/status", async (_req, res) => {
  res.json(await loadUpdateManifest());
});

router.post("/messages/auto-reply", validateBody(schemas.autoReply), async (req, res) => {
  const { sender = "Contact", context = "busy", until = "later today" } = req.validatedBody;
  const templates = {
    meeting: `Hi ${sender}, I am in a meeting until ${until}. I will review this right after.`,
    deep_work: `Hi ${sender}, I am in a deep work block until ${until}. I will get back with a clear response.`,
    driving: `Hi ${sender}, I am currently driving. I will reply safely after ${until}.`,
    busy: `Hi ${sender}, I am tied up until ${until}. I will check this as soon as possible.`
  };

  res.json({ message: templates[context] || templates.busy, context, generatedAt: new Date().toISOString() });
});

export default router;
