import { Router } from "express";
import { addDecisionRecord, clearDecisions, ensureUser, listDecisions } from "../db/index.js";
import { validateBody, schemas } from "../middleware/validation.js";

const router = Router();

router.get("/decide", async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ decisions: await listDecisions(req.deviceId) });
});

router.post("/decide", validateBody(schemas.decide), async (req, res) => {
  await ensureUser(req.deviceId);
  const { title, options } = req.validatedBody;

  const scored = options
    .map((option) => {
      const proScore = option.pros.length * 2;
      const conScore = option.cons.length * 1.5;
      const score = proScore - conScore;
      return { ...option, score };
    })
    .sort((a, b) => b.score - a.score);

  const recommendation = scored[0];
  const confidence = Math.min(95, 55 + Math.round((recommendation.score - (scored[1]?.score || 0)) * 10));

  await addDecisionRecord(req.deviceId, {
    title,
    recommendation: recommendation.name,
    confidence
  });

  res.json({
    decision: title,
    recommendation: recommendation.name,
    confidence,
    breakdown: scored
  });
});

router.delete("/decide", async (req, res) => {
  await ensureUser(req.deviceId);
  await clearDecisions(req.deviceId);
  res.json({ cleared: true });
});

export default router;
