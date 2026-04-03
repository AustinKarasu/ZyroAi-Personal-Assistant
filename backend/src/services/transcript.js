const urgencyLexicon = {
  urgent: 90,
  asap: 85,
  blocked: 80,
  emergency: 100,
  thanks: 35,
  later: 20
};

export const analyzeTranscript = (transcript) => {
  const text = transcript.toLowerCase();
  let urgency = 30;
  Object.entries(urgencyLexicon).forEach(([token, score]) => {
    if (text.includes(token)) urgency = Math.max(urgency, score);
  });

  const sentiment = urgency > 75 ? "stressed" : urgency < 35 ? "calm" : "neutral";
  return {
    sentiment,
    urgency,
    summary: urgency > 75 ? "High urgency caller request detected." : "No immediate escalation required."
  };
};
