import { z } from "zod";

export const requireDeviceId = (req, res, next) => {
  const deviceId = req.header("x-device-id") || req.query.deviceId;
  if (!deviceId || deviceId.length < 8) {
    return res.status(400).json({ error: "Missing or invalid x-device-id header." });
  }
  req.deviceId = deviceId;
  next();
};

export const validateBody = (schema) => (req, res, next) => {
  const result = schema.safeParse(req.body);
  if (!result.success) {
    return res.status(400).json({ error: "Validation failed", details: result.error.flatten() });
  }
  req.validatedBody = result.data;
  next();
};

const integrationSchema = z.object({
  connected: z.boolean().optional(),
  mode: z.string().min(2).max(80).optional(),
  status: z.string().min(2).max(80).optional(),
  permissions: z.array(z.string().min(2).max(80)).optional(),
  last_synced_at: z.string().nullable().optional()
});

export const schemas = {
  createTask: z.object({
    title: z.string().min(2).max(120),
    dueAt: z.string().datetime().optional(),
    urgency: z.number().min(1).max(5),
    importance: z.number().min(1).max(5),
    energyCost: z.number().min(1).max(5),
    category: z.string().min(2).max(40).optional(),
    energyBand: z.enum(["low", "medium", "high", "deep"]).optional()
  }),
  updateTaskStatus: z.object({
    status: z.enum(["todo", "in_progress", "done"])
  }),
  decide: z.object({
    title: z.string().min(4),
    options: z.array(z.object({ name: z.string(), pros: z.array(z.string()), cons: z.array(z.string()) })).min(2)
  }),
  addMemory: z.object({
    hint: z.string().min(2).max(80),
    note: z.string().min(2).max(1000)
  }),
  callLog: z.object({
    caller: z.string().min(2).max(80),
    transcript: z.string().min(2).max(5000)
  }),
  setMode: z.object({
    mode: z.enum(["Executive", "Deep Work", "Available", "Travel"])
  }),
  addHabit: z.object({
    name: z.string().min(2).max(80)
  }),
  addMeeting: z.object({
    title: z.string().min(2).max(120),
    owner: z.string().min(2).max(80),
    startAt: z.string().datetime(),
    durationMinutes: z.number().min(15).max(180),
    notes: z.string().min(2).max(1000)
  }),
  addContact: z.object({
    name: z.string().min(2).max(80),
    relationship: z.string().min(2).max(60),
    tier: z.enum(["vip", "standard"]).optional(),
    phone: z.string().max(40).optional()
  }),
  emergencyOverride: z.object({
    contactId: z.string().min(4),
    reason: z.string().min(4).max(200)
  }),
  autoReply: z.object({
    sender: z.string().min(2).max(80).optional(),
    context: z.enum(["meeting", "deep_work", "driving", "busy"]).optional(),
    until: z.string().min(2).max(60).optional()
  }),
  incomingCall: z.object({
    caller: z.string().min(2).max(80),
    transcript: z.string().min(2).max(5000)
  }),
  updateSettings: z.object({
    appearance: z.object({
      theme: z.string().min(2).max(40).optional(),
      density: z.string().min(2).max(40).optional(),
      reducedMotion: z.boolean().optional()
    }).optional(),
    data: z.object({
      realtimeSync: z.boolean().optional(),
      analyticsOptIn: z.boolean().optional(),
      storageMode: z.string().min(2).max(40).optional(),
      offlineReady: z.boolean().optional(),
      autoSyncWhenOnline: z.boolean().optional()
    }).optional(),
    assistant: z.object({
      persona: z.string().min(2).max(80).optional(),
      voiceStyle: z.string().min(2).max(40).optional(),
      autoDecisionSupport: z.boolean().optional(),
      weeklyReports: z.boolean().optional(),
      monthlyReports: z.boolean().optional(),
      yearlyReports: z.boolean().optional()
    }).optional(),
    automation: z.object({
      dndMode: z.boolean().optional(),
      callAutoReply: z.boolean().optional(),
      smsAutoReply: z.boolean().optional(),
      wellbeingGuard: z.boolean().optional(),
      emergencyOverrideEnabled: z.boolean().optional(),
      autoStepTracking: z.boolean().optional()
    }).optional(),
    permissions: z.object({
      location: z.boolean().optional(),
      activity: z.boolean().optional(),
      notifications: z.boolean().optional(),
      microphone: z.boolean().optional(),
      sms: z.boolean().optional()
    }).optional(),
    integrations: z.object({
      whatsapp: integrationSchema.optional(),
      instagram: integrationSchema.optional(),
      facebook: integrationSchema.optional(),
      messenger: integrationSchema.optional(),
      x: integrationSchema.optional()
    }).optional()
  }),
  updateProfile: z.object({
    name: z.string().min(2).max(80).optional(),
    title: z.string().min(2).max(80).or(z.literal("")).optional(),
    email: z.string().email().or(z.literal("")).optional(),
    avatar_url: z.string().url().or(z.literal("")).optional(),
    avatar_color: z.string().min(4).max(20).optional(),
    language: z.enum(["en", "hi", "es", "ar"]).optional(),
    locale: z.string().min(2).max(20).optional(),
    city: z.string().max(80).optional(),
    timezone: z.string().min(2).max(60).optional(),
    daily_step_goal: z.number().min(1000).max(50000).optional()
  }),
  stepsLog: z.object({
    count: z.number().min(0).max(50000),
    mode: z.enum(["add", "set"]).optional(),
    source: z.enum(["manual", "sensor", "imported", "geo-auto", "vehicle-filtered"]).optional(),
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional()
  }),
  smartSteps: z.object({
    distance_meters: z.number().min(0).max(200000),
    duration_seconds: z.number().min(1).max(86400),
    speed_mps: z.number().min(0).max(120).optional(),
    activity_hint: z.enum(["walking", "vehicle"]).optional(),
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional()
  }),
  authorizeIntegration: z.object({
    permissions: z.array(z.enum(["read_messages", "send_messages", "read_status"])) .min(1)
  }),
  translateText: z.object({
    text: z.string().min(1).max(5000),
    sourceLang: z.string().min(2).max(20),
    targetLang: z.string().min(2).max(20)
  }),
  toggleQuest: z.object({
    completed: z.boolean()
  }),
  assistantChat: z.object({
    message: z.string().min(2).max(400)
  })
};
