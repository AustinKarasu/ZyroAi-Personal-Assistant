export const normalizeLanguageCode = (language) => (language || 'en').split('-')[0].toLowerCase();

export const translateText = async ({ text, sourceLang, targetLang }) => {
  const trimmed = String(text || '').trim();
  if (!trimmed) {
    return {
      translatedText: '',
      sourceLang,
      targetLang,
      provider: 'none'
    };
  }

  const normalizedSource = normalizeLanguageCode(sourceLang);
  const normalizedTarget = normalizeLanguageCode(targetLang);

  if (normalizedSource === normalizedTarget) {
    return {
      translatedText: trimmed,
      sourceLang: normalizedSource,
      targetLang: normalizedTarget,
      provider: 'identity'
    };
  }

  const url = new URL('https://api.mymemory.translated.net/get');
  url.searchParams.set('q', trimmed);
  url.searchParams.set('langpair', `${normalizedSource}|${normalizedTarget}`);

  const response = await fetch(url, {
    headers: {
      'User-Agent': 'ZyroAi/1.0'
    }
  });

  if (!response.ok) {
    throw new Error(`Translation request failed with ${response.status}`);
  }

  const data = await response.json();
  const translatedText = data?.responseData?.translatedText;

  if (!translatedText) {
    throw new Error('Translation provider returned an empty result');
  }

  return {
    translatedText,
    sourceLang: normalizedSource,
    targetLang: normalizedTarget,
    provider: 'mymemory'
  };
};
