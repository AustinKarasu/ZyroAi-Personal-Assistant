import { randomUUID } from "node:crypto";

const defaultTemplates = [
  {
    id: "walk_distance",
    title: "Walk at least 1 km",
    detail: "Use a steady outdoor or indoor walk to build movement momentum.",
    category: "movement",
    target: "1 km"
  },
  {
    id: "hydration",
    title: "Drink 4 liters of water",
    detail: "Spread water intake through the day instead of drinking it all at once.",
    category: "hydration",
    target: "4 L"
  },
  {
    id: "stretch",
    title: "Stretch for 12 minutes",
    detail: "Focus on hips, shoulders, and lower back to reduce desk stiffness.",
    category: "mobility",
    target: "12 min"
  },
  {
    id: "fruit",
    title: "Eat 2 fruit servings",
    detail: "Choose fruit in separate meals to keep energy stable.",
    category: "nutrition",
    target: "2 servings"
  },
  {
    id: "mindful_breathing",
    title: "Do 8 minutes of breathing work",
    detail: "Take one focused breathing block to reduce stress and sharpen attention.",
    category: "mindset",
    target: "8 min"
  },
  {
    id: "sleep_wind_down",
    title: "Start wind-down before 11 PM",
    detail: "Reduce screen intensity and set up a cleaner sleep routine tonight.",
    category: "recovery",
    target: "before 11 PM"
  },
  {
    id: "stairs",
    title: "Climb 10 flights of stairs",
    detail: "Break it into smaller sets during the day if needed.",
    category: "fitness",
    target: "10 flights"
  },
  {
    id: "posture_breaks",
    title: "Take 5 posture breaks",
    detail: "Stand up, roll shoulders, and reset your neck and back alignment.",
    category: "mobility",
    target: "5 breaks"
  },
  {
    id: "protein_meal",
    title: "Include protein in 2 meals",
    detail: "Choose balanced meals that support stable energy and recovery.",
    category: "nutrition",
    target: "2 meals"
  },
  {
    id: "sunlight",
    title: "Get 15 minutes of sunlight",
    detail: "A short daylight break helps energy, rhythm, and mood.",
    category: "recovery",
    target: "15 min"
  }
];

const seededIndex = (seed, length, offset = 0) => {
  let total = 0;
  const text = `${seed}:${offset}`;
  for (let i = 0; i < text.length; i += 1) {
    total += text.charCodeAt(i) * (i + 3);
  }
  return total % Math.max(length, 1);
};

const uniquePush = (list, template) => {
  if (!list.some((item) => item.id === template.id)) {
    list.push(template);
  }
};

export const generateDailyQuests = ({ deviceId, workspace, dateKey }) => {
  const goal = workspace.profile?.daily_step_goal || 8000;
  const weather = workspace.weather_cache;
  const hotWeather = Number(weather?.temperatureC || 0) >= 30;
  const walkingTargetKm = goal >= 10000 ? 1.5 : 1.0;
  const stepTarget = Math.max(5000, Math.min(goal, Math.round(goal * 0.8)));

  const pool = defaultTemplates.map((template) => ({ ...template }));
  pool[0] = {
    ...pool[0],
    title: `Walk at least ${walkingTargetKm.toFixed(1)} km`,
    target: `${walkingTargetKm.toFixed(1)} km`
  };
  pool.push({
    id: "steps_goal",
    title: `Reach ${stepTarget.toLocaleString()} steps`,
    detail: "Stay active throughout the day without relying on one long session.",
    category: "movement",
    target: `${stepTarget} steps`
  });
  pool.push({
    id: "hydration_weather",
    title: hotWeather ? "Drink 4.5 liters of water" : "Drink 3.5 liters of water",
    detail: hotWeather
      ? "Today's warmer weather raises the hydration target slightly."
      : "Keep hydration steady even if the day feels cooler.",
    category: "hydration",
    target: hotWeather ? "4.5 L" : "3.5 L"
  });

  const chosen = [];
  uniquePush(chosen, pool[seededIndex(`${deviceId}-${dateKey}`, pool.length, 1)]);
  uniquePush(chosen, pool.find((item) => item.id === "hydration_weather") || pool[0]);
  uniquePush(chosen, pool.find((item) => item.id === "stretch") || pool[1]);
  uniquePush(chosen, pool.find((item) => item.id === "steps_goal") || pool[2]);
  uniquePush(chosen, pool.find((item) => item.id === "protein_meal") || pool[3]);

  for (let offset = 2; chosen.length < 7 && offset < 20; offset += 1) {
    uniquePush(chosen, pool[seededIndex(`${dateKey}-${deviceId}`, pool.length, offset)]);
  }

  return chosen.slice(0, 7).map((template, index) => ({
    id: randomUUID(),
    slug: template.id,
    title: template.title,
    detail: template.detail,
    category: template.category,
    target: template.target,
    completed: false,
    created_at: new Date().toISOString(),
    order: index
  }));
};
