export const enableHtmlInCanvasExperiment = (
  canvas: HTMLCanvasElement,
  text: string,
  intensity: number
): void => {
  const context = canvas.getContext("2d");
  if (!context) {
    return;
  }

  const width = canvas.width;
  const height = canvas.height;

  context.clearRect(0, 0, width, height);
  const gradient = context.createLinearGradient(0, 0, width, height);
  gradient.addColorStop(0, `rgba(217,95,53,${0.2 + intensity * 0.4})`);
  gradient.addColorStop(1, `rgba(46,143,88,${0.2 + intensity * 0.4})`);

  context.fillStyle = gradient;
  context.fillRect(0, 0, width, height);

  context.fillStyle = "rgba(242, 237, 230, 0.9)";
  context.font = "700 24px 'Space Grotesk'";
  context.fillText(text.slice(0, 80), 20, height / 2);
};
