import { createBrowserRouter, type RouteObject } from "react-router-dom";
import { DeviceRoute } from "../routes/DeviceRoute";
import { HashedAboutRoute } from "../routes/HashedAboutRoute";
import { HashedHomeRoute } from "../routes/HashedHomeRoute";
import { HashedSiteLayout } from "../routes/HashedSiteLayout";
import { KeylessIntroRoute } from "../routes/KeylessIntroRoute";
import { LogbookRoute } from "../routes/LogbookRoute";
import { NotFoundRoute } from "../routes/NotFoundRoute";
import { ParticipantLogbookRoute } from "../routes/ParticipantLogbookRoute";

export const appRoutes: RouteObject[] = [
  {
    path: "/",
    element: <KeylessIntroRoute />
  },
  {
    path: "/about",
    element: <KeylessIntroRoute />
  },
  {
    path: "/logbook",
    element: <LogbookRoute />
  },
  {
    path: "/:hashedId",
    element: <HashedSiteLayout />,
    children: [
      {
        index: true,
        element: <HashedHomeRoute />
      },
      {
        path: "about",
        element: <HashedAboutRoute />
      }
    ]
  },
  {
    path: "/:hashedId/live",
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
];

export const router = createBrowserRouter(appRoutes);
