import { createBrowserRouter } from "react-router-dom";
import { DeviceRoute } from "../routes/DeviceRoute";
import { NotFoundRoute } from "../routes/NotFoundRoute";

export const router = createBrowserRouter([
  {
    path: "/:hashedId",
    element: <DeviceRoute />
  },
  {
    path: "*",
    element: <NotFoundRoute />
  }
]);
