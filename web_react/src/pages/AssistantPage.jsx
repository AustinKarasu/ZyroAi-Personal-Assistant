import { useEffect, useMemo, useRef, useState } from "react";

const speechLanguages = [
  { label: "English", value: "en-US" },
  { label: "Hindi", value: "hi-IN" },
  { label: "Spanish", value: "es-ES" },
  { label: "Arabic", value: "ar-SA" },
  { label: "French", value: "fr-FR" },
  { label: "German", value: "de-DE" },
  { label: "Japanese", value: "ja-JP" },
  { label: "Korean", value: "ko-KR" },
  { label: "Portuguese", value: "pt-BR" },
  { label: "Chinese", value: "zh-CN" }
];

const translationLanguages = [
  { label: "English", value: "en" },
  { label: "Hindi", value: "hi" },
  { label: "Spanish", value: "es" },
  { label: "Arabic", value: "ar" },
  { label: "French", value: "fr" },
  { label: "German", value: "de" },
  { label: "Japanese", value: "ja" },
  { label: "Korean", value: "ko" },
  { label: "Portuguese", value: "pt" },
  { label: "Chinese", value: "zh" }
];

const getSpeechConstructor = () => window.SpeechRecognition || window.webkitSpeechRecognition || null;

export default function AssistantPage({ workspace, actions, busyKey }) {
  const [message, setMessage] = useState("");
  const [sourceSpeechLang, setSourceSpeechLang] = useState("en-US");
  const [sourceLang, setSourceLang] = useState("en");
  const [targetLang, setTargetLang] = useState("hi");
  const [transcript, setTranscript] = useState("");
  const [translated, setTranslated] = useState("");
  const [translatorError, setTranslatorError] = useState("");
  const [assistantError, setAssistantError] = useState("");
  const [assistantStatus, setAssistantStatus] = useState("Ready");
  const [isListening, setIsListening] = useState(false);
  const recognitionRef = useRef(null);
  const translateTimerRef = useRef(null);

  const tools = useMemo(() => [
    "Plan my day around priorities and meetings",
    "What should I handle first right now?",
    "Summarize communication urgency",
    "Check whether DND mode is protecting me",
    "Generate my weekly report",
    "How is the weather and step progress?",
    "Switch me into deep work mode",
    "Review my step progress and suggest a break"
  ], []);

  useEffect(() => () => {
    recognitionRef.current?.stop?.();
    if (translateTimerRef.current) {
      clearTimeout(translateTimerRef.current);
    }
  }, []);

  useEffect(() => {
    if (!transcript.trim()) {
      setTranslated("");
      setTranslatorError("");
      return;
    }
    if (translateTimerRef.current) {
      clearTimeout(translateTimerRef.current);
    }
    translateTimerRef.current = setTimeout(async () => {
      try {
        const response = await actions.translateText({
          text: transcript,
          sourceLang,
          targetLang
        });
        setTranslated(response.translatedText);
        setTranslatorError("");
      } catch (error) {
        setTranslatorError(error.message || "Translation failed");
      }
    }, 350);
  }, [actions, sourceLang, targetLang, transcript]);

  if (!workspace) {
    return <section className="page-grid"><div className="panel loading-panel">Loading assistant...</div></section>;
  }

  async function submitAssistantMessage(nextMessage) {
    const trimmed = nextMessage.trim();
    if (!trimmed) return;
    setAssistantError("");
    setAssistantStatus("Working on your request...");
    try {
      await actions.chat(trimmed);
      setAssistantStatus("ZyroAi responded from your live workspace.");
    } catch (error) {
      setAssistantError(error.message || "Assistant request failed.");
      setAssistantStatus("Retry needed");
    }
  }

  async function onSubmit(event) {
    event.preventDefault();
    const outgoing = message;
    setMessage("");
    await submitAssistantMessage(outgoing);
  }

  async function handleQuickPrompt(prompt) {
    setMessage(prompt);
    await submitAssistantMessage(prompt);
  }

  function toggleListening() {
    const SpeechRecognitionCtor = getSpeechConstructor();
    if (!SpeechRecognitionCtor) {
      setTranslatorError("This browser does not support live speech recognition.");
      return;
    }

    if (isListening) {
      recognitionRef.current?.stop?.();
      setIsListening(false);
      return;
    }

    const recognition = new SpeechRecognitionCtor();
    recognition.lang = sourceSpeechLang;
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.onstart = () => {
      setTranslatorError("");
      setIsListening(true);
    };
    recognition.onerror = (event) => {
      setTranslatorError(event.error || "Speech recognition failed.");
      setIsListening(false);
    };
    recognition.onend = () => {
      setIsListening(false);
    };
    recognition.onresult = (event) => {
      const nextTranscript = Array.from(event.results)
        .map((result) => result[0]?.transcript || "")
        .join(" ")
        .trim();
      setTranscript(nextTranscript);
    };
    recognitionRef.current = recognition;
    recognition.start();
  }

  return (
    <section className="page-grid">
      <article className="hero-panel compact">
        <div>
          <p className="eyebrow">AI Assistant</p>
          <h3>{workspace.settings.assistant.persona}</h3>
          <p className="hero-copy">
            The assistant now runs as a stronger personal operator using your live task list, meetings, DND status, communication urgency, reports, and movement data.
          </p>
        </div>
        <div className="status-cluster">
          <span className="status-pill">{workspace.settings.assistant.voiceStyle}</span>
          <span className="status-pill accent">{workspace.settings.automation.dndMode ? "DND armed" : "DND off"}</span>
          <span className="status-pill">{assistantStatus}</span>
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Speech Translator</h3>
          <span>{isListening ? "Listening live" : "Ready"}</span>
        </div>
        <div className="settings-grid">
          <label className="setting-field">
            <span>Speech input language</span>
            <select
              value={sourceSpeechLang}
              onChange={(event) => {
                setSourceSpeechLang(event.target.value);
                setSourceLang(event.target.value.split("-")[0]);
              }}
            >
              {speechLanguages.map((item) => (
                <option key={item.value} value={item.value}>{item.label}</option>
              ))}
            </select>
          </label>
          <label className="setting-field">
            <span>Translate to</span>
            <select value={targetLang} onChange={(event) => setTargetLang(event.target.value)}>
              {translationLanguages.map((item) => (
                <option key={item.value} value={item.value}>{item.label}</option>
              ))}
            </select>
          </label>
        </div>
        <div className="row-actions">
          <button type="button" onClick={toggleListening}>{isListening ? "Stop Listening" : "Start Listening"}</button>
          <button type="button" onClick={() => { setTranscript(""); setTranslated(""); setTranslatorError(""); }}>Clear</button>
          {transcript.trim() ? <button type="button" onClick={() => setMessage(transcript)}>Use in Assistant</button> : null}
        </div>
        <label className="setting-field">
          <span>Detected speech</span>
          <textarea rows={5} value={transcript} onChange={(event) => setTranscript(event.target.value)} placeholder="Speech will appear here in real time." />
        </label>
        <div className="reply-card">
          <strong>Translated text</strong>
          <p>{translated || "Live translation will appear here as speech is captured."}</p>
        </div>
        {translatorError ? <div className="empty-card">{translatorError}</div> : null}
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Chief Conversation</h3>
          <span>{workspace.assistant.messages.length} messages</span>
        </div>
        <div className="chat-thread">
          {workspace.assistant.messages.length === 0 ? (
            <div className="empty-card">No assistant history yet. Ask ZyroAi to plan your day, summarize calls, or organize priorities.</div>
          ) : null}
          {workspace.assistant.messages.map((entry) => (
            <div key={entry.id} className={`chat-bubble role-${entry.role}`}>
              <strong>{entry.role === "assistant" ? "Chief" : "You"}</strong>
              <p>{entry.content}</p>
            </div>
          ))}
        </div>
        <form className="inline-form" onSubmit={onSubmit}>
          <input value={message} onChange={(event) => setMessage(event.target.value)} placeholder="Ask ZyroAi to plan, prioritize, draft, summarize, or switch modes" />
          <button type="submit" disabled={busyKey === "assistant-chat"}>Send</button>
        </form>
        {assistantError ? <div className="empty-card">{assistantError}</div> : null}
        <div className="suggestion-row">
          {workspace.assistant.suggestions.map((suggestion) => (
            <button key={suggestion} type="button" onClick={() => handleQuickPrompt(suggestion)} disabled={busyKey === "assistant-chat"}>
              {suggestion}
            </button>
          ))}
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>AI Tools</h3>
          <span>One-tap management tools</span>
        </div>
        <div className="feature-grid">
          {tools.map((tool) => (
            <button key={tool} type="button" className="feature-card" onClick={() => handleQuickPrompt(tool)} disabled={busyKey === "assistant-chat"}>
              {tool}
            </button>
          ))}
        </div>
      </article>
    </section>
  );
}
