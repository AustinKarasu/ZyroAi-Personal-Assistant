import { Router } from "express";
import { addDecisionRecord, clearDecisions, ensureUser, listDecisions } from "../db/index.js";
import { validateBody, schemas } from "../middleware/validation.js";

const router = Router();
const strongPositiveKeywords = ["roi", "revenue", "strategic", "health", "growth", "urgent", "retention", "automation", "scalable"];
const strongNegativeKeywords = ["risk", "delay", "cost", "burnout", "debt", "blocked", "unclear", "dependency", "expensive"];

const scoreStatement = (text, polarity = "pro") => {
  const normalized = String(text || "").trim().toLowerCase();
  if (!normalized) return 0;

  const positiveHits = strongPositiveKeywords.filter((keyword) => normalized.includes(keyword)).length;
  const negativeHits = strongNegativeKeywords.filter((keyword) => normalized.includes(keyword)).length;
  const clarityBonus = Math.min(1.5, normalized.split(/\s+/).length / 8);
  const base = 1 + clarityBonus + positiveHits * 1.2 - negativeHits * 0.8;

  return polarity === "pro" ? Math.max(0.5, base) : Math.max(0.5, base + negativeHits * 0.8 - positiveHits * 0.4);
};

router.get("/decide", async (req, res) => {
  await ensureUser(req.deviceId);
  res.json({ decisions: await listDecisions(req.deviceId) });
});

router.post("/decide", validateBody(schemas.decide), async (req, res) => {
  await ensureUser(req.deviceId);
  const { title, options } = req.validatedBody;

  const scored = options
    .map((option) => {
      const proScore = option.pros.reduce((sum, item) => sum + scoreStatement(item, "pro"), 0);
      const conScore = option.cons.reduce((sum, item) => sum + scoreStatement(item, "con"), 0);
      const balanceBonus = option.pros.length >= option.cons.length ? 1.5 : 0;
      const score = Number((proScore - conScore + balanceBonus).toFixed(1));
      return {
        ...option,
        proScore: Number(proScore.toFixed(1)),
        conScore: Number(conScore.toFixed(1)),
        score
      };
    })
    .sort((a, b) => b.score - a.score);

  const recommendation = scored[0];
  const runnerUpScore = scored[1]?.score || 0;
  const confidence = Math.min(95, Math.max(52, 58 + Math.round((recommendation.score - runnerUpScore) * 6)));

  await addDecisionRecord(req.deviceId, {
    title,
    recommendation: recommendation.name,
    confidence
  });

  res.json({
    decision: title,
    recommendation: recommendation.name,
    confidence,
    breakdown: scored,
    rationale: `${recommendation.name} leads because it has a stronger upside profile (${recommendation.proScore}) than downside drag (${recommendation.conScore}).`
  });
});

router.delete("/decide", async (req, res) => {
  await ensureUser(req.deviceId);
  await clearDecisions(req.deviceId);
  res.json({ cleared: true });
});

export default router;
