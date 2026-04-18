import { createBrowserRouter, type RouteObject } from "react-router-dom";
import { DeviceRoute } from "../routes/DeviceRoute";
import { HashedAboutRoute } from "../routes/HashedAboutRoute";
import { HashedAccessibilityRoute } from "../routes/HashedAccessibilityRoute";
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
      },
      {
        path: "accessibility",
        element: <HashedAccessibilityRoute />
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

const resolveRouterBasename = (baseUrl: string): string | undefined => {
  const normalized = baseUrl.endsWith("/") && baseUrl.length > 1 ? baseUrl.slice(0, -1) : baseUrl;
  return normalized === "/" ? undefined : normalized;
};

export const router = createBrowserRouter(appRoutes, {
  basename: resolveRouterBasename(import.meta.env.BASE_URL)
});
