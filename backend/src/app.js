import "dotenv/config";
import express from "express";
import cors from "cors";
import helmet from "helmet";
import morgan from "morgan";
import rateLimit from "express-rate-limit";
import compression from "compression";
import dashboardRoutes from "./routes/dashboard.js";
import decisionRoutes from "./routes/decision.js";
import memoryRoutes from "./routes/memory.js";
import communicationRoutes from "./routes/communication.js";
import integrationRoutes from "./routes/integrations.js";
import insightsRoutes from "./routes/insights.js";
import workspaceRoutes from "./routes/workspace.js";
import { requireDeviceId } from "./middleware/validation.js";

export const buildApp = () => {
  const app = express();
  const allowedOrigins = (process.env.CORS_ORIGIN || "*")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);

  app.use(helmet());
  app.use(compression());
  app.use(
    cors({
      origin(origin, callback) {
        if (!origin || allowedOrigins.includes("*") || allowedOrigins.includes(origin)) {
          return callback(null, true);
        }
        return callback(new Error("CORS origin not allowed"));
      }
    })
  );
  app.use(express.json({ limit: "500kb" }));
  app.use(morgan("dev"));
  app.use(rateLimit({ windowMs: 15 * 60 * 1000, max: 2000, standardHeaders: true, legacyHeaders: false }));

  app.get("/health", (_req, res) => res.json({ status: "ok", service: "ai-personal-chief-api" }));

  app.use("/api", requireDeviceId);
  app.use("/api", dashboardRoutes);
  app.use("/api", decisionRoutes);
  app.use("/api", memoryRoutes);
  app.use("/api", communicationRoutes);
  app.use("/api", integrationRoutes);
  app.use("/api", insightsRoutes);
  app.use("/api", workspaceRoutes);

  app.use((error, _req, res, _next) => {
    if (String(error?.message || "").includes("CORS origin not allowed")) {
      return res.status(403).json({ error: "CORS origin not allowed" });
    }
    console.error(error);
    return res.status(500).json({ error: "Unexpected server error" });
  });

  app.use((_req, res) => {
    res.status(404).json({ error: "Not found" });
  });

  return app;
};

const app = buildApp();
export default app;


