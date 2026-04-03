const messages = {
  en: {
    home: "Home",
    planner: "Planner",
    calls: "Calls",
    intelligence: "Intelligence",
    assistant: "Assistant",
    settings: "Settings",
    premiumAssistant: "Premium executive assistant",
    realtimeLinked: "Realtime linked",
    offlineActive: "Offline device mode",
    dndOn: "DND on",
    dndOff: "DND off"
  },
  hi: {
    home: "Home",
    planner: "Planner",
    calls: "Calls",
    intelligence: "Intelligence",
    assistant: "Assistant",
    settings: "Settings",
    premiumAssistant: "Premium executive assistant",
    realtimeLinked: "Realtime linked",
    offlineActive: "Offline device mode",
    dndOn: "DND on",
    dndOff: "DND off"
  },
  es: {
    home: "Inicio",
    planner: "Planificador",
    calls: "Llamadas",
    intelligence: "Inteligencia",
    assistant: "Asistente",
    settings: "Ajustes",
    premiumAssistant: "Asistente ejecutivo premium",
    realtimeLinked: "Tiempo real activo",
    offlineActive: "Modo sin conexion",
    dndOn: "DND activo",
    dndOff: "DND apagado"
  },
  ar: {
    home: "????????",
    planner: "??????",
    calls: "?????????",
    intelligence: "??????",
    assistant: "???????",
    settings: "?????????",
    premiumAssistant: "????? ?????? ????",
    realtimeLinked: "????? ?????",
    offlineActive: "??? ??? ?????",
    dndOn: "??? ??????? ????",
    dndOff: "??? ??????? ?????"
  }
};

export const getDirection = (language) => (language === "ar" ? "rtl" : "ltr");
export const t = (language, key) => messages[language]?.[key] || messages.en[key] || key;
