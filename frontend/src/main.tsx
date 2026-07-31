import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
// Carbon first so the Tailwind layer that still styles unmigrated pages wins
// where the two resets overlap. globals.css goes away once the last route is
// on Carbon.
import "../app/carbon.scss";
import "../app/globals.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
