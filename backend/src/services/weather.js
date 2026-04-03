const weatherCodes = {
  0: "Clear sky",
  1: "Mainly clear",
  2: "Partly cloudy",
  3: "Overcast",
  45: "Fog",
  48: "Depositing rime fog",
  51: "Light drizzle",
  61: "Light rain",
  63: "Rain",
  65: "Heavy rain",
  71: "Snow fall",
  80: "Rain showers",
  95: "Thunderstorm"
};

export const fetchCurrentWeather = async (latitude, longitude) => {
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", String(latitude));
  url.searchParams.set("longitude", String(longitude));
  url.searchParams.set("current", "temperature_2m,apparent_temperature,weather_code,wind_speed_10m");
  url.searchParams.set("timezone", "auto");

  const response = await fetch(url, {
    headers: {
      "User-Agent": "ZyroAi/1.0"
    }
  });

  if (!response.ok) {
    throw new Error(`Weather request failed with ${response.status}`);
  }

  const data = await response.json();
  const current = data.current || {};
  return {
    latitude,
    longitude,
    temperatureC: current.temperature_2m ?? null,
    apparentTemperatureC: current.apparent_temperature ?? null,
    windSpeedKph: current.wind_speed_10m ?? null,
    weatherCode: current.weather_code ?? null,
    summary: weatherCodes[current.weather_code] || "Conditions updated",
    timezone: data.timezone || "auto"
  };
};
