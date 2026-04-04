import express, { Router } from "express";
import { addCallLog, clearCallLogs, ensureUser, getProfile, getSettings, getModeState, listCallLogs, removeCallLog } from "../db/index.js";
import { validateBody, schemas } from "../middleware/validation.js";
import { analyzeTranscript } from "../services/transcript.js";

const router = Router();
router.use(express.urlencoded({ extended: false }));

const dndReply = () => "The person is currently busy, drop your message for the user.";
const escapeXml = (value = "") =>
  String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&apos;");

const buildCallReply = ({ profile, modeState, settings }) => {
  const name = profile?.name || "the user";
  const mode = modeState?.mode || "Executive";
  if (settings?.automation?.dndMode) {
    return `${name} is currently busy in ${mode} mode. Please leave a message after the beep.`;
  }
  return `${name} is unavailable right now. Please leave a message after the beep.`;
};

router.get("/communications", async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ logs: await listCallLogs(req.deviceId) });
});

router.post("/communications/call-log", validateBody(schemas.callLog), async (req, res) => {
  await ensureUser(req.deviceId);
  const settings = await getSettings(req.deviceId);
  const { caller, transcript } = req.validatedBody;
  const analysis = analyzeTranscript(transcript);
  const agentReply = settings.automation.dndMode && settings.automation.callAutoReply ? dndReply() : "";
  const id = await addCallLog(req.deviceId, {
    caller,
    transcript,
    sentiment: analysis.sentiment,
    urgency: analysis.urgency,
    agentReply,
    handledByDnd: Boolean(agentReply)
  });

  res.status(201).json({ id, ...analysis, agentReply, handledByDnd: Boolean(agentReply) });
});

router.post("/communications/incoming-call", validateBody(schemas.incomingCall), async (req, res) => {
  await ensureUser(req.deviceId);
  const settings = await getSettings(req.deviceId);
  const { caller, transcript } = req.validatedBody;
  const analysis = analyzeTranscript(transcript);
  const handledByDnd = settings.automation.dndMode && settings.automation.callAutoReply;
  const agentReply = handledByDnd ? dndReply() : "";

  const id = await addCallLog(req.deviceId, {
    caller,
    transcript,
    sentiment: analysis.sentiment,
    urgency: analysis.urgency,
    agentReply,
    handledByDnd
  });

  res.status(201).json({
    id,
    handledByDnd,
    agentReply,
    sentiment: analysis.sentiment,
    urgency: analysis.urgency,
    summary: handledByDnd ? "Chief answered the caller because DND is active." : analysis.summary
  });
});

router.post("/voice/twilio", async (req, res) => {
  const deviceId = req.query.deviceId || req.body.deviceId;
  if (!deviceId) {
    return res.status(400).type("text/plain").send("Missing deviceId");
  }
  await ensureUser(deviceId);
  const settings = await getSettings(deviceId);
  const profile = await getProfile(deviceId);
  const modeState = await getModeState(deviceId);
  const caller = req.body.From || req.body.Caller || "Unknown";
  const reply = buildCallReply({ profile, modeState, settings });

  const baseUrl = process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get("host")}`;
  const actionUrl = `${baseUrl}/api/voice/twilio/recording?deviceId=${encodeURIComponent(deviceId)}&caller=${encodeURIComponent(caller)}`;

  const twiml = [
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    "<Response>",
    `<Say>${escapeXml(reply)}</Say>`,
    `<Record maxLength=\"180\" playBeep=\"true\" action=\"${escapeXml(actionUrl)}\" />`,
    "</Response>"
  ].join("");

  res.type("text/xml").send(twiml);
});

router.post("/voice/twilio/recording", async (req, res) => {
  const deviceId = req.query.deviceId || req.body.deviceId;
  if (!deviceId) {
    return res.status(400).type("text/plain").send("Missing deviceId");
  }
  await ensureUser(deviceId);
  const settings = await getSettings(deviceId);
  const caller = req.body.From || req.query.caller || req.body.Caller || "Unknown";
  const recordingUrl = req.body.RecordingUrl ? `${req.body.RecordingUrl}.mp3` : null;
  const recordingDuration = req.body.RecordingDuration ? Number(req.body.RecordingDuration) : null;
  const transcriptText = req.body.TranscriptionText?.trim();
  const transcript = transcriptText || (recordingUrl ? `Recording captured: ${recordingUrl}` : "Recording captured.");
  const analysis = analyzeTranscript(transcript);
  const handledByDnd = settings.automation.dndMode && settings.automation.callAutoReply;
  const agentReply = handledByDnd ? dndReply() : "";

  await addCallLog(deviceId, {
    caller,
    transcript,
    sentiment: analysis.sentiment,
    urgency: analysis.urgency,
    agentReply,
    handledByDnd,
    recordingUrl,
    recordingDuration,
    callSid: req.body.CallSid
  });

  const twiml = [
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    "<Response>",
    "<Say>Thank you. Your message has been recorded.</Say>",
    "</Response>"
  ].join("");

  res.type("text/xml").send(twiml);
});

router.delete("/communications/:id", async (req, res) => {
  await ensureUser(req.deviceId);
  const removed = await removeCallLog(req.deviceId, req.params.id);
  if (!removed) return res.status(404).json({ error: "Call log not found" });
  return res.json({ removed: true });
});

router.delete("/communications", async (req, res) => {
  await ensureUser(req.deviceId);
  await clearCallLogs(req.deviceId);
  return res.json({ cleared: true });
});

export default router;
