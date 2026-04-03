export const evaluateTaskPriority = ({ dueAt, urgency = 3, importance = 3, energyCost = 3 }) => {
  const now = Date.now();
  const duePenalty = dueAt ? Math.max(0, (new Date(dueAt).getTime() - now) / 3600000) : 72;
  const dueScore = Math.max(1, 10 - duePenalty / 8);
  const base = urgency * 1.5 + importance * 1.8 + dueScore * 1.7 - energyCost * 0.6;
  return Math.max(1, Math.min(100, Math.round(base * 4)));
};

export const suggestFocusBlocks = (tasks) => {
  const top = [...tasks].sort((a, b) => b.priority_score - a.priority_score).slice(0, 3);
  return top.map((t, i) => ({
    taskId: t.id,
    startInMinutes: i * 75,
    durationMinutes: 50,
    note: `High-focus block for ${t.title}`
  }));
};
