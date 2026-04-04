import { Router } from "express";
import {
  addAssistantMessagePair,
  clearAssistantMessages,
  addContact,
  addHabit,
  addMeeting,
  authorizeIntegration,
  checkInHabit,
  clearStepHistory,
  ensureUser,
  getProfile,
  getDailyQuests,
  getSettings,
  getStepSummary,
  getWeatherCache,
  getWorkspaceSnapshot,
  listAuditLogs,
  logDailySteps,
  logSmartSteps,
  saveReportSnapshot,
  setModeState,
  setWeatherCache,
  subscribeToDeviceChanges,
  triggerEmergencyOverride,
  toggleQuestCompletion,
  updateProfile,
  updateSettings,
  upsertTask
} from "../db/index.js";
import { validateBody, schemas } from "../middleware/validation.js";
import { buildAssistantReply, detectAssistantAction } from "../services/assistant.js";
import { evaluateTaskPriority } from "../services/prioritization.js";
import { buildPeriodReport } from "../services/reports.js";
import { translateText } from "../services/translate.js";
import { fetchCurrentWeather } from "../services/weather.js";
import { buildWorkspace } from "../services/workspace.js";

const router = Router();
const validReportPeriods = new Set(["weekly", "monthly", "yearly"]);
const validPlatforms = new Set(["whatsapp", "instagram", "facebook", "messenger", "x"]);
const clientAppVersion = (req) => String(req.headers["x-app-version"] || "").trim();

router.get("/workspace", async (req, res) => {
  await ensureUser(req.deviceId);
  res.json(await buildWorkspace(req.deviceId, clientAppVersion(req)));
});

router.get("/stream", async (req, res) => {
  await ensureUser(req.deviceId);
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();

  const sendWorkspace = async () => {
    const workspace = await buildWorkspace(req.deviceId, clientAppVersion(req));
    res.write(`data: ${JSON.stringify(workspace)}\n\n`);
  };

  await sendWorkspace();
  const heartbeat = setInterval(() => {
    res.write("event: heartbeat\ndata: ping\n\n");
  }, 20000);

  const unsubscribe = subscribeToDeviceChanges(req.deviceId, async () => {
    await sendWorkspace();
  });

  req.on("close", () => {
    clearInterval(heartbeat);
    unsubscribe();
    res.end();
  });
});

router.get("/profile", async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ profile: await getProfile(req.deviceId) });
});

router.patch("/profile", validateBody(schemas.updateProfile), async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ profile: await updateProfile(req.deviceId, req.validatedBody) });
});

router.get("/audit-logs", async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ logs: await listAuditLogs(req.deviceId) });
});

router.get("/steps", async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ summary: await getStepSummary(req.deviceId) });
});

router.post("/steps", validateBody(schemas.stepsLog), async (req, res) => {
  await ensureUser(req.deviceId);
  await logDailySteps(req.deviceId, req.validatedBody);
  res.status(201).json({ summary: await getStepSummary(req.deviceId, req.validatedBody.date) });
});

router.post("/steps/smart", validateBody(schemas.smartSteps), async (req, res) => {
  await ensureUser(req.deviceId);
  const summary = await logSmartSteps(req.deviceId, req.validatedBody);
  res.status(201).json({ summary });
});

router.delete("/steps", async (req, res) => {
  await ensureUser(req.deviceId);
  await clearStepHistory(req.deviceId);
  res.json({ cleared: true });
});

router.get("/reports", async (req, res) => {
  await ensureUser(req.deviceId);
  const period = String(req.query.period || "weekly").toLowerCase();
  if (!validReportPeriods.has(period)) {
    return res.status(400).json({ error: "Invalid report period" });
  }
  const snapshot = await getWorkspaceSnapshot(req.deviceId);
  const report = buildPeriodReport(snapshot, period);
  await saveReportSnapshot(req.deviceId, report);
  return res.json({ report });
});

router.get("/quests", async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ quests: await getDailyQuests(req.deviceId) });
});

router.patch("/quests/:id", validateBody(schemas.toggleQuest), async (req, res) => {
  await ensureUser(req.deviceId);
  const quests = await toggleQuestCompletion(req.deviceId, req.params.id, req.validatedBody.completed);
  if (!quests) {
    return res.status(404).json({ error: "Quest not found" });
  }
  return res.json({ quests });
});

router.get("/weather", async (req, res) => {
  await ensureUser(req.deviceId);
  const { lat, lon } = req.query;

  if (lat && lon) {
    try {
      const weather = await fetchCurrentWeather(Number(lat), Number(lon));
      await setWeatherCache(req.deviceId, weather);
      return res.json({ weather, source: "live" });
    } catch (error) {
      const cached = await getWeatherCache(req.deviceId);
      if (cached) {
        return res.json({ weather: cached, source: "cache", warning: error.message });
      }
      return res.status(502).json({ error: "Unable to refresh weather", details: error.message });
    }
  }

  const cached = await getWeatherCache(req.deviceId);
  return res.json({ weather: cached, source: cached ? "cache" : "empty" });
});

router.post("/translate", validateBody(schemas.translateText), async (req, res) => {
  await ensureUser(req.deviceId);
  try {
    const translation = await translateText(req.validatedBody);
    return res.json(translation);
  } catch (error) {
    return res.status(502).json({
      error: "Translation unavailable",
      details: error.message
    });
  }
});

router.post("/mode", validateBody(schemas.setMode), async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ mode: await setModeState(req.deviceId, req.validatedBody.mode) });
});

router.post("/habits", validateBody(schemas.addHabit), async (req, res) => {
  await ensureUser(req.deviceId);
  res.status(201).json({ habit: await addHabit(req.deviceId, req.validatedBody.name) });
});

router.post("/habits/:id/check-in", async (req, res) => {
  await ensureUser(req.deviceId);
  const habit = await checkInHabit(req.deviceId, req.params.id);
  if (!habit) {
    return res.status(404).json({ error: "Habit not found" });
  }
  return res.json({ habit });
});

router.post("/meetings", validateBody(schemas.addMeeting), async (req, res) => {
  await ensureUser(req.deviceId);
  res.status(201).json({ meeting: await addMeeting(req.deviceId, req.validatedBody) });
});

router.post("/contacts", validateBody(schemas.addContact), async (req, res) => {
  await ensureUser(req.deviceId);
  res.status(201).json({ contact: await addContact(req.deviceId, req.validatedBody) });
});

router.post("/emergency/override", validateBody(schemas.emergencyOverride), async (req, res) => {
  await ensureUser(req.deviceId);
  const notification = await triggerEmergencyOverride(req.deviceId, req.validatedBody);
  if (!notification) {
    return res.status(404).json({ error: "Contact not found" });
  }
  return res.json({ notification });
});

router.get("/settings", async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ settings: await getSettings(req.deviceId) });
});

router.patch("/settings", validateBody(schemas.updateSettings), async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ settings: await updateSettings(req.deviceId, req.validatedBody) });
});

router.post("/integrations/:platform/authorize", validateBody(schemas.authorizeIntegration), async (req, res) => {
  await ensureUser(req.deviceId);
  const platform = String(req.params.platform || "").toLowerCase();
  if (!validPlatforms.has(platform)) {
    return res.status(400).json({ error: "Unsupported integration" });
  }
  const integration = await authorizeIntegration(req.deviceId, platform, req.validatedBody.permissions);
  res.status(201).json({ platform, integration });
});

router.post("/assistant/chat", validateBody(schemas.assistantChat), async (req, res) => {
  await ensureUser(req.deviceId);
  const userMessage = req.validatedBody.message;
  const detectedAction = detectAssistantAction(userMessage);
  let actionNotice = "";

  if (detectedAction?.type === "settings") {
    await updateSettings(req.deviceId, detectedAction.patch);
    actionNotice = detectedAction.label;
  }

  if (detectedAction?.type === "mode") {
    await setModeState(req.deviceId, detectedAction.mode);
    actionNotice = detectedAction.label;
  }

  if (detectedAction?.type === "task") {
    const priorityScore = evaluateTaskPriority(detectedAction.task);
    await upsertTask(req.deviceId, {
      title: detectedAction.task.title,
      priorityScore,
      status: "todo",
      category: "Execution",
      energyBand: "medium"
    });
    actionNotice = detectedAction.label;
  }

  const snapshot = await getWorkspaceSnapshot(req.deviceId);
  const reply = await buildAssistantReply(userMessage, snapshot, actionNotice);
  const saved = await addAssistantMessagePair(req.deviceId, userMessage, reply);
  res.json({ message: saved, action: actionNotice || null });
});

router.delete('/assistant/chat', async (req, res) => {
  await ensureUser(req.deviceId);
  await clearAssistantMessages(req.deviceId);
  res.json({ cleared: true });
});

export default router;




