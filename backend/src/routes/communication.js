import { Router } from "express";
import { addCallLog, ensureUser, getSettings, listCallLogs } from "../db/index.js";
import { validateBody, schemas } from "../middleware/validation.js";
import { analyzeTranscript } from "../services/transcript.js";

const router = Router();

const dndReply = () => "The person is currently busy, drop your message for the user.";

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

export default router;
