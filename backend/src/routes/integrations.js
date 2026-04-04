import { Router } from "express";
import { createHash, randomBytes } from "node:crypto";
import { completeIntegrationAuth, getSettings, setIntegrationPendingAuth } from "../db/index.js";

const router = Router();

const META_PLATFORMS = new Set(["whatsapp", "instagram", "facebook", "messenger"]);

const getMetaScope = (platform) => {
  switch (platform) {
    case "whatsapp":
      return process.env.META_SCOPE_WHATSAPP || "whatsapp_business_messaging,whatsapp_business_management";
    case "instagram":
      return process.env.META_SCOPE_INSTAGRAM || "instagram_basic,instagram_manage_messages,pages_show_list,pages_read_engagement";
    case "messenger":
      return process.env.META_SCOPE_MESSENGER || "pages_messaging,pages_read_engagement,pages_manage_metadata";
    case "facebook":
      return process.env.META_SCOPE_FACEBOOK || "pages_messaging,pages_read_engagement,pages_manage_metadata";
    default:
      return "public_profile";
  }
};

const base64Url = (buffer) => buffer.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

const buildMetaAuthUrl = (platform, deviceId) => {
  const appId = process.env.META_APP_ID;
  const redirectUrl = process.env.META_REDIRECT_URL;
  if (!appId || !redirectUrl) return null;
  const state = `${deviceId}:${randomBytes(12).toString("hex")}`;
  const scope = getMetaScope(platform);
  const authUrl = `https://www.facebook.com/v20.0/dialog/oauth?client_id=${encodeURIComponent(appId)}&redirect_uri=${encodeURIComponent(redirectUrl)}&state=${encodeURIComponent(state)}&scope=${encodeURIComponent(scope)}&response_type=code`;
  return { authUrl, state, permissions: scope.split(",").map((item) => item.trim()).filter(Boolean) };
};

const buildXAuthUrl = (deviceId) => {
  const clientId = process.env.X_CLIENT_ID;
  const redirectUrl = process.env.X_REDIRECT_URL;
  if (!clientId || !redirectUrl) return null;
  const scope = process.env.X_SCOPE || "tweet.read tweet.write users.read offline.access";
  const state = `${deviceId}:${randomBytes(12).toString("hex")}`;
  const codeVerifier = base64Url(randomBytes(32));
  const codeChallenge = base64Url(createHash("sha256").update(codeVerifier).digest());
  const authUrl = `https://twitter.com/i/oauth2/authorize?response_type=code&client_id=${encodeURIComponent(clientId)}&redirect_uri=${encodeURIComponent(redirectUrl)}&scope=${encodeURIComponent(scope)}&state=${encodeURIComponent(state)}&code_challenge=${encodeURIComponent(codeChallenge)}&code_challenge_method=S256`;
  return { authUrl, state, codeVerifier, permissions: scope.split(" ").filter(Boolean) };
};

router.get("/integrations/:platform/oauth", async (req, res) => {
  const platform = String(req.params.platform || "").toLowerCase();
  const deviceId = req.deviceId;

  if (platform === "x") {
    const payload = buildXAuthUrl(deviceId);
    if (!payload) return res.status(400).json({ configured: false, error: "X OAuth is not configured" });
    await setIntegrationPendingAuth(deviceId, platform, {
      state: payload.state,
      provider: "x",
      permissions: payload.permissions,
      codeVerifier: payload.codeVerifier
    });
    return res.json({ configured: true, authUrl: payload.authUrl });
  }

  if (META_PLATFORMS.has(platform)) {
    const payload = buildMetaAuthUrl(platform, deviceId);
    if (!payload) return res.status(400).json({ configured: false, error: "Meta OAuth is not configured" });
    await setIntegrationPendingAuth(deviceId, platform, {
      state: payload.state,
      provider: "meta",
      permissions: payload.permissions
    });
    return res.json({ configured: true, authUrl: payload.authUrl });
  }

  return res.status(400).json({ configured: false, error: "Unsupported integration" });
});

router.get("/integrations/:platform/callback", async (req, res) => {
  const platform = String(req.params.platform || "").toLowerCase();
  const code = String(req.query.code || "").trim();
  const state = String(req.query.state || "").trim();
  const deviceId = state.split(":")[0];

  if (!deviceId || !code || !state) {
    return res.status(400).json({ error: "Missing authorization payload" });
  }

  const settings = await getSettings(deviceId);
  const integration = settings?.integrations?.[platform] || {};
  if (!integration.pending_state || integration.pending_state !== state) {
    return res.status(400).json({ error: "Authorization state mismatch" });
  }

  try {
    if (platform === "x") {
      const clientId = process.env.X_CLIENT_ID;
      const clientSecret = process.env.X_CLIENT_SECRET;
      const redirectUrl = process.env.X_REDIRECT_URL;
      const codeVerifier = integration.pending_code_verifier;
      if (!clientId || !redirectUrl || !codeVerifier) {
        return res.status(400).json({ error: "X OAuth is not configured" });
      }
      const body = new URLSearchParams({
        grant_type: "authorization_code",
        code,
        client_id: clientId,
        redirect_uri: redirectUrl,
        code_verifier: codeVerifier
      });
      if (clientSecret) {
        body.append("client_secret", clientSecret);
      }
      const response = await fetch("https://api.twitter.com/2/oauth2/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body
      });
      const data = await response.json();
      if (!response.ok || !data.access_token) {
        return res.status(502).json({ error: "X token exchange failed", details: data });
      }
      await completeIntegrationAuth(deviceId, platform, {
        accessToken: data.access_token,
        refreshToken: data.refresh_token,
        expiresAt: data.expires_in ? new Date(Date.now() + data.expires_in * 1000).toISOString() : null,
        permissions: (data.scope || "").split(" ").filter(Boolean)
      });
      return res.json({ connected: true });
    }

    if (META_PLATFORMS.has(platform)) {
      const appId = process.env.META_APP_ID;
      const appSecret = process.env.META_APP_SECRET;
      const redirectUrl = process.env.META_REDIRECT_URL;
      if (!appId || !appSecret || !redirectUrl) {
        return res.status(400).json({ error: "Meta OAuth is not configured" });
      }
      const tokenUrl = `https://graph.facebook.com/v20.0/oauth/access_token?client_id=${encodeURIComponent(appId)}&redirect_uri=${encodeURIComponent(redirectUrl)}&client_secret=${encodeURIComponent(appSecret)}&code=${encodeURIComponent(code)}`;
      const tokenRes = await fetch(tokenUrl, { method: "GET" });
      const tokenData = await tokenRes.json();
      if (!tokenRes.ok || !tokenData.access_token) {
        return res.status(502).json({ error: "Meta token exchange failed", details: tokenData });
      }
      await completeIntegrationAuth(deviceId, platform, {
        accessToken: tokenData.access_token,
        refreshToken: tokenData.refresh_token,
        expiresAt: tokenData.expires_in ? new Date(Date.now() + tokenData.expires_in * 1000).toISOString() : null,
        permissions: (tokenData.scope || "").split(",").filter(Boolean)
      });
      return res.json({ connected: true });
    }

    return res.status(400).json({ error: "Unsupported integration" });
  } catch (error) {
    return res.status(502).json({ error: "Authorization failed", details: error.message });
  }
});

export default router;
