import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { MemoryRouter } from "react-router-dom";
import { LogbookRoute } from "../src/routes/LogbookRoute";

describe("LogbookRoute", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("renders entry text safely without injecting scripts", async () => {
    const alertSpy = vi.spyOn(window, "alert").mockImplementation(() => undefined);
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => ({
          entries: [
            {
              participantTag: "abc123-9999",
              signer: "Ari",
              message: "<script>alert('xss')</script>",
              createdAt: 1,
              updatedAt: 1
            }
          ],
          nextCursor: null
        })
      })
    );

    render(
      <MemoryRouter>
        <LogbookRoute />
      </MemoryRouter>
    );

    await screen.findByText("Ari");
    expect(screen.getByText("<script>alert('xss')</script>")).toBeTruthy();
    await waitFor(() => expect(alertSpy).not.toHaveBeenCalled());
  });
});
