const translate = (language, messages) => messages[language] || messages.en;

const currentDateKey = () => new Date().toISOString().slice(0, 10);

const summarizeWorkspace = (workspace) => {
  const tasks = [...workspace.tasks].sort((a, b) => b.priority_score - a.priority_score).slice(0, 6);
  const nextMeeting = [...workspace.meetings].sort((a, b) => a.start_at.localeCompare(b.start_at))[0] || null;
  const urgentCalls = workspace.call_logs.filter((call) => call.urgency >= 75).slice(0, 4);
  const todaySteps = workspace.step_entries.find((entry) => entry.date === currentDateKey()) || null;
  const integrations = Object.entries(workspace.settings.integrations || {})
    .filter(([, meta]) => meta?.connected)
    .map(([platform]) => platform);

  return {
    profile: {
      name: workspace.profile.name,
      title: workspace.profile.title,
      language: workspace.profile.language,
      city: workspace.profile.city,
      daily_step_goal: workspace.profile.daily_step_goal
    },
    settings: {
      dndMode: workspace.settings.automation.dndMode,
      callAutoReply: workspace.settings.automation.callAutoReply,
      autoStepTracking: workspace.settings.automation.autoStepTracking,
      theme: workspace.settings.appearance.theme,
      voiceStyle: workspace.settings.assistant.voiceStyle
    },
    tasks: tasks.map((task) => ({
      title: task.title,
      status: task.status,
      priority: task.priority_score,
      due_at: task.due_at
    })),
    nextMeeting: nextMeeting
      ? {
          title: nextMeeting.title,
          owner: nextMeeting.owner,
          start_at: nextMeeting.start_at,
          notes: nextMeeting.notes
        }
      : null,
    urgentCalls: urgentCalls.map((call) => ({
      caller: call.caller,
      urgency: call.urgency,
      sentiment: call.sentiment,
      handled_by_dnd: call.handled_by_dnd
    })),
    weather: workspace.weather_cache
      ? {
          summary: workspace.weather_cache.summary,
          temperatureC: workspace.weather_cache.temperatureC
        }
      : null,
    steps: {
      count: todaySteps?.count || 0,
      goal: todaySteps?.goal || workspace.profile.daily_step_goal || 8000,
      source: todaySteps?.source || "manual"
    },
    integrations,
    memories: workspace.memories.slice(0, 5).map((memory) => memory.hint)
  };
};

const taskSummary = (tasks, language) => {
  const top = tasks.slice(0, 3).map((task) => task.title).join(", ");
  const messages = {
    en: tasks.length === 0 ? "No tasks are in your workspace yet. Add priorities and I will rank them for you." : `Top priorities are ${top}.`,
    hi: tasks.length === 0 ? "Abhi tak koi task nahin hai. Kuch priorities add kijiye, main unhe rank kar dunga." : `Top priorities hain: ${top}.`,
    es: tasks.length === 0 ? "Aun no hay tareas. Agrega prioridades y las ordenare por ti." : `Las prioridades principales son ${top}.`,
    ar: tasks.length === 0 ? "No tasks are available yet." : `Top priorities are ${top}.`
  };
  return translate(language, messages);
};

export const detectAssistantAction = (message) => {
  const text = message.trim();
  const lower = text.toLowerCase();

  if (/(turn on|enable|activate).*(dnd|do not disturb|busy mode)/i.test(text)) {
    return { type: "settings", label: "DND enabled", patch: { automation: { dndMode: true, callAutoReply: true } } };
  }

  if (/(turn off|disable|deactivate).*(dnd|do not disturb|busy mode)/i.test(text)) {
    return { type: "settings", label: "DND disabled", patch: { automation: { dndMode: false } } };
  }

  if (/(turn on|enable|activate).*(sms|message).*(auto|reply|autopilot)/i.test(text)) {
    return { type: "settings", label: "Message autopilot enabled", patch: { automation: { smsAutoReply: true } } };
  }

  if (/(turn off|disable|deactivate).*(sms|message).*(auto|reply|autopilot)/i.test(text)) {
    return { type: "settings", label: "Message autopilot disabled", patch: { automation: { smsAutoReply: false } } };
  }

  if (/(turn on|enable|activate).*(step|walking).*(tracking|tracker)/i.test(text)) {
    return {
      type: "settings",
      label: "Smart step tracking enabled",
      patch: { automation: { autoStepTracking: true } }
    };
  }

  if (/(turn off|disable|deactivate).*(step|walking).*(tracking|tracker)/i.test(text)) {
    return {
      type: "settings",
      label: "Smart step tracking disabled",
      patch: { automation: { autoStepTracking: false } }
    };
  }

  if (/(deep work|focus mode)/i.test(lower)) {
    return { type: "mode", label: "Deep Work mode enabled", mode: "Deep Work" };
  }

  if (/(available mode|i am available)/i.test(lower)) {
    return { type: "mode", label: "Available mode enabled", mode: "Available" };
  }

  if (/(travel mode|i am traveling|i am travelling)/i.test(lower)) {
    return { type: "mode", label: "Travel mode enabled", mode: "Travel" };
  }

  const taskMatch = text.match(/(?:add|create)\s+(?:a\s+)?task[:\s]+(.+)/i);
  if (taskMatch?.[1]) {
    return {
      type: "task",
      label: `Task added: ${taskMatch[1].trim()}`,
      task: {
        title: taskMatch[1].trim(),
        urgency: 4,
        importance: 4,
        energyCost: 3
      }
    };
  }

  return null;
};

export const buildLocalAssistantReply = (message, workspace, actionNotice = "") => {
  const lower = message.toLowerCase();
  const topTasks = [...workspace.tasks].sort((a, b) => b.priority_score - a.priority_score);
  const urgentCalls = workspace.call_logs.filter((call) => call.urgency >= 75);
  const nextMeeting = [...workspace.meetings].sort((a, b) => a.start_at.localeCompare(b.start_at))[0];
  const dnd = workspace.settings.automation.dndMode;
  const language = workspace.profile.language || "en";
  const todaySteps = workspace.step_entries.find((entry) => entry.date === currentDateKey());
  const weather = workspace.weather_cache;
  const prefix = actionNotice ? `${actionNotice} ` : "";

  if (lower.includes("today") || lower.includes("plan")) {
    const meetingText = nextMeeting
      ? {
          en: `Next meeting is ${nextMeeting.title} at ${new Date(nextMeeting.start_at).toLocaleTimeString()}.`,
          hi: `Agli meeting ${nextMeeting.title} hai ${new Date(nextMeeting.start_at).toLocaleTimeString()} par.`,
          es: `La siguiente reunion es ${nextMeeting.title} a las ${new Date(nextMeeting.start_at).toLocaleTimeString()}.`,
          ar: `Next meeting is ${nextMeeting.title} at ${new Date(nextMeeting.start_at).toLocaleTimeString()}.`
        }
      : {
          en: "No meetings are scheduled yet.",
          hi: "Abhi koi meeting scheduled nahin hai.",
          es: "Aun no hay reuniones programadas.",
          ar: "No meetings are scheduled yet."
        };
    return `${prefix}${taskSummary(topTasks, language)} ${translate(language, meetingText)}`.trim();
  }

  if (lower.includes("priority") || lower.includes("focus") || lower.includes("task")) {
    return `${prefix}${taskSummary(topTasks, language)}`.trim();
  }

  if (lower.includes("meeting") || lower.includes("agenda")) {
    return nextMeeting
      ? `${prefix}${translate(language, {
          en: `Your next meeting is ${nextMeeting.title} with ${nextMeeting.owner} at ${new Date(nextMeeting.start_at).toLocaleTimeString()}.`,
          hi: `Aapki agli meeting ${nextMeeting.title} hai ${nextMeeting.owner} ke saath ${new Date(nextMeeting.start_at).toLocaleTimeString()} par.`,
          es: `Tu siguiente reunion es ${nextMeeting.title} con ${nextMeeting.owner} a las ${new Date(nextMeeting.start_at).toLocaleTimeString()}.`,
          ar: `Your next meeting is ${nextMeeting.title} with ${nextMeeting.owner} at ${new Date(nextMeeting.start_at).toLocaleTimeString()}.`
        })}`
      : `${prefix}${translate(language, {
          en: "No meetings are scheduled yet. Add one from Planner and I will help you prepare.",
          hi: "Abhi koi meeting scheduled nahin hai. Planner se ek add kijiye aur main prepare karne me help karunga.",
          es: "No hay reuniones programadas. Agrega una desde Planner y te ayudo a prepararla.",
          ar: "No meetings are scheduled yet. Add one from Planner and I will help you prepare."
        })}`;
  }

  if (lower.includes("call") || lower.includes("communication") || lower.includes("message")) {
    return urgentCalls.length > 0
      ? `${prefix}${translate(language, {
          en: `You have ${urgentCalls.length} urgent communication items. Handle ${urgentCalls[0].caller} first. DND is ${dnd ? "active" : "off"}.`,
          hi: `Aapke paas ${urgentCalls.length} urgent communication items hain. Sabse pehle ${urgentCalls[0].caller} ko handle kijiye. DND ${dnd ? "active" : "off"} hai.`,
          es: `Tienes ${urgentCalls.length} comunicaciones urgentes. Atiende primero a ${urgentCalls[0].caller}. DND esta ${dnd ? "activo" : "apagado"}.`,
          ar: `You have ${urgentCalls.length} urgent communication items. Handle ${urgentCalls[0].caller} first. DND is ${dnd ? "active" : "off"}.`
        })}`
      : `${prefix}${translate(language, {
          en: dnd
            ? "Communications are under control. DND is active and incoming calls will receive the busy message automatically."
            : "No urgent communication is waiting. Turn on DND if you want ZyroAi to answer calls while you focus.",
          hi: dnd
            ? "Communications control me hain. DND active hai aur incoming calls ko busy message milega."
            : "Abhi koi urgent communication nahin hai. Focus ke liye DND on kar sakte hain.",
          es: dnd
            ? "Las comunicaciones estan bajo control. DND esta activo y respondera automaticamente."
            : "No hay comunicaciones urgentes. Activa DND si quieres que ZyroAi responda mientras trabajas.",
          ar: dnd
            ? "Communications are under control. DND is active and incoming calls will receive the busy message automatically."
            : "No urgent communication is waiting. Turn on DND if you want ZyroAi to answer calls while you focus."
        })}`;
  }

  if (lower.includes("report") || lower.includes("weekly") || lower.includes("monthly") || lower.includes("yearly")) {
    return `${prefix}${translate(language, {
      en: "Reports are ready in the intelligence layer. Open weekly, monthly, or yearly reviews for execution, communication, and movement trends.",
      hi: "Reports intelligence layer me ready hain. Weekly, monthly ya yearly review me execution, communication aur movement trends dekhiye.",
      es: "Los reportes estan listos en la capa de inteligencia. Abre los resumentes semanales, mensuales o anuales.",
      ar: "Reports are ready in the intelligence layer. Open weekly, monthly, or yearly reviews for execution, communication, and movement trends."
    })}`;
  }

  if (lower.includes("step") || lower.includes("walk") || lower.includes("foot")) {
    const count = todaySteps?.count || 0;
    return `${prefix}${translate(language, {
      en: `You have logged ${count.toLocaleString()} steps today. Smart tracking is ${workspace.settings.automation.autoStepTracking ? "on" : "off"}.`,
      hi: `Aaj aapne ${count.toLocaleString()} steps log kiye hain. Smart tracking ${workspace.settings.automation.autoStepTracking ? "on" : "off"} hai.`,
      es: `Has registrado ${count.toLocaleString()} pasos hoy. El seguimiento inteligente esta ${workspace.settings.automation.autoStepTracking ? "activo" : "apagado"}.`,
      ar: `You have logged ${count.toLocaleString()} steps today. Smart tracking is ${workspace.settings.automation.autoStepTracking ? "on" : "off"}.`
    })}`;
  }

  if (lower.includes("weather")) {
    return weather
      ? `${prefix}${translate(language, {
          en: `Current weather is ${weather.summary} at ${weather.temperatureC} degrees Celsius.`,
          hi: `Abhi mausam ${weather.summary} hai aur temperature ${weather.temperatureC} degree Celsius hai.`,
          es: `El clima actual es ${weather.summary} con ${weather.temperatureC} grados Celsius.`,
          ar: `Current weather is ${weather.summary} at ${weather.temperatureC} degrees Celsius.`
        })}`
      : `${prefix}${translate(language, {
          en: "Weather is not cached yet. Allow location access and refresh weather from the app.",
          hi: "Weather abhi cache nahin hua. Location permission dijiye aur app se weather refresh kijiye.",
          es: "Aun no hay clima en cache. Permite la ubicacion y actualiza el clima desde la app.",
          ar: "Weather is not cached yet. Allow location access and refresh weather from the app."
        })}`;
  }

  if (lower.includes("dnd") || lower.includes("busy")) {
    return `${prefix}${translate(language, {
      en: dnd ? "DND mode is active. Incoming calls will receive the busy auto-reply and be logged for review." : "DND mode is currently off. Turn it on in Settings to let ZyroAi respond that you are busy.",
      hi: dnd ? "DND mode active hai. Incoming calls ko busy auto-reply milega aur review ke liye log kiya jayega." : "DND mode abhi off hai. Settings me ise on kijiye taaki ZyroAi busy reply bhej sake.",
      es: dnd ? "El modo DND esta activo. Las llamadas entrantes recibiran la respuesta de ocupado y quedaran registradas." : "El modo DND esta apagado. Activalo en Settings para que ZyroAi responda que estas ocupado.",
      ar: dnd ? "DND mode is active. Incoming calls will receive the busy auto-reply and be logged for review." : "DND mode is currently off. Turn it on in Settings to let ZyroAi respond that you are busy."
    })}`;
  }

  return `${prefix}${translate(language, {
    en: `ZyroAi is tracking ${workspace.tasks.length} tasks, ${workspace.meetings.length} meetings, ${workspace.call_logs.length} communication records, and ${(todaySteps?.count || 0).toLocaleString()} steps today. I can help plan your day, organize priorities, explain calls, draft replies, or manage DND and mode changes.`,
    hi: `ZyroAi ${workspace.tasks.length} tasks, ${workspace.meetings.length} meetings, ${workspace.call_logs.length} communication records aur aaj ke ${(todaySteps?.count || 0).toLocaleString()} steps track kar raha hai. Main planning, priorities, calls, drafts, DND aur mode changes me help kar sakta hun.`,
    es: `ZyroAi sigue ${workspace.tasks.length} tareas, ${workspace.meetings.length} reuniones, ${workspace.call_logs.length} comunicaciones y ${(todaySteps?.count || 0).toLocaleString()} pasos hoy. Puedo ayudarte con planificacion, prioridades, llamadas, borradores y cambios de DND o modo.`,
    ar: `ZyroAi is tracking ${workspace.tasks.length} tasks, ${workspace.meetings.length} meetings, ${workspace.call_logs.length} communication records, and ${(todaySteps?.count || 0).toLocaleString()} steps today. I can help plan your day, organize priorities, explain calls, draft replies, or manage DND and mode changes.`
  })}`;
};

export const buildAssistantReply = async (message, workspace, actionNotice = "") => {
  const apiKey = process.env.OPENROUTER_API_KEY?.trim();
  if (!apiKey) {
    return buildLocalAssistantReply(message, workspace, actionNotice);
  }

  const model = process.env.OPENROUTER_MODEL || "openai/gpt-4o-mini";
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25000);

  try {
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": process.env.OPENROUTER_SITE_URL || "http://127.0.0.1",
        "X-Title": process.env.OPENROUTER_APP_NAME || "ZyroAi"
      },
      body: JSON.stringify({
        model,
        temperature: 0.35,
        messages: [
          {
            role: "system",
            content: [
              "You are ZyroAi, a premium AI personal chief for personal productivity and communication triage.",
              "Be concise, practical, and proactive.",
              "You can help plan tasks, explain call urgency, suggest replies, summarize meetings, manage DND and mode changes, and recommend next actions.",
              "Do not claim to have sent messages or modified external platforms unless the provided workspace context shows the integration is connected and the user explicitly asked for that action.",
              "If a request involves WhatsApp, Instagram, Facebook, Messenger, or X, be honest that official platform APIs and authorization are required for real external sending.",
              actionNotice ? `A workspace action was already completed before this reply: ${actionNotice}` : "",
              `Live workspace context: ${JSON.stringify(summarizeWorkspace(workspace))}`
            ].filter(Boolean).join(" ")
          },
          {
            role: "user",
            content: message
          }
        ]
      })
    });

    if (!response.ok) {
      throw new Error(`OpenRouter failed with ${response.status}`);
    }

    const payload = await response.json();
    const content = payload?.choices?.[0]?.message?.content;
    if (typeof content === "string" && content.trim()) {
      return content.trim();
    }

    return buildLocalAssistantReply(message, workspace, actionNotice);
  } catch {
    return buildLocalAssistantReply(message, workspace, actionNotice);
  } finally {
    clearTimeout(timeout);
  }
};
