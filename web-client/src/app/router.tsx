import { createBrowserRouter } from "react-router-dom";
import { DeviceRoute } from "../routes/DeviceRoute";
import { HomeRoute } from "../routes/HomeRoute";
import { LogbookRoute } from "../routes/LogbookRoute";
import { NotFoundRoute } from "../routes/NotFoundRoute";
import { ParticipantLogbookRoute } from "../routes/ParticipantLogbookRoute";

export const router = createBrowserRouter([
  {
    path: "/",
    element: <HomeRoute />
  },
  {
    path: "/logbook",
    element: <LogbookRoute />
  },
  {
    path: "/:hashedId",
    element: <DeviceRoute />
  },
  {
    path: "/:hashedId/logbook",
    element: <ParticipantLogbookRoute />
  },
  {
    path: "*",
    element: <NotFoundRoute />
  }
]);
