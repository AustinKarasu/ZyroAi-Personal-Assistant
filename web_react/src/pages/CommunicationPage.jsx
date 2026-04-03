import { useState } from "react";

const socialScopes = ["read_messages", "send_messages", "read_status"];

export default function CommunicationPage({ workspace, actions, busyKey }) {
  const dndPreviewMessage = "The person is currently busy, drop your message for the user.";
  const [caller, setCaller] = useState("");
  const [transcript, setTranscript] = useState("");
  const [incomingCaller, setIncomingCaller] = useState("");
  const [incomingTranscript, setIncomingTranscript] = useState("");
  const [sender, setSender] = useState("Alex");
  const [context, setContext] = useState("meeting");
  const [until, setUntil] = useState("3:00 PM");
  const [reply, setReply] = useState("");
  const [callOutcome, setCallOutcome] = useState("");
  const [channelStatus, setChannelStatus] = useState("");
  const [contact, setContact] = useState({
    name: "",
    relationship: "",
    tier: "standard",
    phone: ""
  });

  if (!workspace) {
    return <section className="page-grid"><div className="panel loading-panel">Loading communications...</div></section>;
  }

  async function analyzeCall(event) {
    event.preventDefault();
    if (!caller.trim() || !transcript.trim()) return;
    await actions.analyzeCall(caller.trim(), transcript.trim());
    setCaller("");
    setTranscript("");
  }

  async function createReply(event) {
    event.preventDefault();
    const response = await actions.makeReply(sender, context, until);
    setReply(response.message);
  }

  async function handleIncoming(event) {
    event.preventDefault();
    if (!incomingCaller.trim() || !incomingTranscript.trim()) return;
    const response = await actions.handleIncomingCall(incomingCaller.trim(), incomingTranscript.trim());
    setCallOutcome(response.handledByDnd ? response.agentReply : response.summary);
    setIncomingCaller("");
    setIncomingTranscript("");
  }

  async function saveContact(event) {
    event.preventDefault();
    if (!contact.name.trim() || !contact.relationship.trim()) return;
    await actions.saveContact({
      ...contact,
      name: contact.name.trim(),
      relationship: contact.relationship.trim(),
      phone: contact.phone.trim()
    });
    setContact({ name: "", relationship: "", tier: "standard", phone: "" });
  }

  async function authorizeChannel(platform) {
    setChannelStatus(`Authorizing ${platform} inside ZyroAi...`);
    await actions.authorizeIntegration(platform, socialScopes);
    setChannelStatus(`${platform} is now authorized inside ZyroAi. Real external sending still depends on the platform's official API approval.`);
  }

  return (
    <section className="page-grid">
      <article className="panel">
        <div className="panel-head">
          <h3>Call Triage</h3>
          <span>{workspace.communications.urgentCount} urgent threads</span>
        </div>
        <form className="form-grid" onSubmit={analyzeCall}>
          <input value={caller} onChange={(event) => setCaller(event.target.value)} placeholder="Caller name" />
          <textarea
            value={transcript}
            onChange={(event) => setTranscript(event.target.value)}
            placeholder="Paste or type what the caller said"
            rows={5}
          />
          <button type="submit" disabled={busyKey === "call-analysis"}>Analyze Communication</button>
        </form>
        <div className="stack-list">
          {workspace.communications.calls.length === 0 ? (
            <div className="empty-card">No calls logged yet. Analyze one above or simulate an incoming call.</div>
          ) : null}
          {workspace.communications.calls.map((log) => (
            <div key={log.id} className="list-row">
              <div>
                <strong>{log.caller}</strong>
                <small>{new Date(log.created_at).toLocaleString()} {log.handled_by_dnd ? "- DND handled" : ""}</small>
              </div>
              <div className="right-copy">
                <span>{log.sentiment}</span>
                <strong>Urgency {log.urgency}</strong>
              </div>
            </div>
          ))}
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>DND Call Handling</h3>
          <span>{workspace.settings.automation.dndMode ? "Busy shield active" : "DND currently off"}</span>
        </div>
        <form className="form-grid" onSubmit={handleIncoming}>
          <input value={incomingCaller} onChange={(event) => setIncomingCaller(event.target.value)} placeholder="Incoming caller" />
          <textarea
            value={incomingTranscript}
            onChange={(event) => setIncomingTranscript(event.target.value)}
            rows={4}
            placeholder="What the caller said"
          />
          <button type="submit" disabled={busyKey === "incoming-call"}>Simulate Incoming Call</button>
        </form>
        <div className="reply-card">
          <strong>ZyroAi response</strong>
          <p>{callOutcome || (workspace.settings.automation.dndMode ? dndPreviewMessage : "If DND mode is on, ZyroAi will answer that you are busy and log the call automatically.")}</p>
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Auto-Reply Composer</h3>
          <span>Contextual response drafting</span>
        </div>
        <form className="form-grid" onSubmit={createReply}>
          <input value={sender} onChange={(event) => setSender(event.target.value)} placeholder="Sender name" />
          <select value={context} onChange={(event) => setContext(event.target.value)}>
            <option value="meeting">Meeting</option>
            <option value="deep_work">Deep Work</option>
            <option value="driving">Driving</option>
            <option value="busy">Busy</option>
          </select>
          <input value={until} onChange={(event) => setUntil(event.target.value)} placeholder="Until when" />
          <button type="submit" disabled={busyKey === "auto-reply"}>Generate Reply</button>
        </form>
        <div className="reply-card">
          <strong>Drafted response</strong>
          <p>{reply || "Generate a reply to preview the live message output."}</p>
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Connected Channels</h3>
          <span>Persisted authorization status</span>
        </div>
        <div className="stack-list">
          {Object.entries(workspace.settings.integrations || {}).map(([platform, meta]) => (
            <div key={platform} className="list-row">
              <div>
                <strong>{platform}</strong>
                <small>{meta.connected ? `Authorized scopes: ${(meta.permissions || []).join(", ")}` : "Awaiting official platform authorization"}</small>
              </div>
              <div className="row-actions">
                <span className={`tier-pill ${meta.connected ? "tier-vip" : "tier-standard"}`}>{meta.status || meta.mode}</span>
                <button type="button" onClick={() => authorizeChannel(platform)} disabled={busyKey === `integration-${platform}`}>
                  {meta.connected ? "Refresh Auth" : "Authorize"}
                </button>
              </div>
            </div>
          ))}
        </div>
        {channelStatus ? <div className="empty-card">{channelStatus}</div> : null}
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>VIP Contacts</h3>
          <span>{workspace.contacts.filter((entry) => entry.tier === "vip").length} priority routes</span>
        </div>
        <form className="form-grid" onSubmit={saveContact}>
          <input value={contact.name} onChange={(event) => setContact({ ...contact, name: event.target.value })} placeholder="Contact name" />
          <input value={contact.relationship} onChange={(event) => setContact({ ...contact, relationship: event.target.value })} placeholder="Relationship" />
          <select value={contact.tier} onChange={(event) => setContact({ ...contact, tier: event.target.value })}>
            <option value="standard">Standard</option>
            <option value="vip">VIP</option>
          </select>
          <input value={contact.phone} onChange={(event) => setContact({ ...contact, phone: event.target.value })} placeholder="Phone number" />
          <button type="submit" disabled={busyKey === "save-contact"}>Save Contact</button>
        </form>
        <div className="stack-list">
          {workspace.contacts.length === 0 ? (
            <div className="empty-card">No contacts added yet. Save one above to enable emergency override.</div>
          ) : null}
          {workspace.contacts.map((entry) => (
            <div key={entry.id} className="list-row">
              <div>
                <strong>{entry.name}</strong>
                <small>{entry.relationship} - {entry.phone || "No phone"}</small>
              </div>
              <div className="row-actions">
                <span className={`tier-pill tier-${entry.tier}`}>{entry.tier}</span>
                <button
                  type="button"
                  onClick={() => actions.triggerEmergency(entry.id, "Family or urgent work escalation")}
                  disabled={busyKey === "emergency"}
                >
                  Emergency Override
                </button>
              </div>
            </div>
          ))}
        </div>
      </article>
    </section>
  );
}
