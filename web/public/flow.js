function createShipmentFlow() {
  const stage = document.getElementById("flow-stage");
  const svg = document.getElementById("flow-svg");
  const token = document.getElementById("message-token");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const nodeIds = ["ui", "queue", "worker", "blob", "dlq", "skill"];
  const animations = [];
  let playing = false;
  let currentStage = -1;
  let runId = null;
  let repairable = false;

  const stagePaths = [
    [{ path: "flow-submit", tone: "main", duration: 650 }],
    [{ path: "flow-queue-worker", tone: "main", duration: 850 }],
    [{ path: "flow-worker-dlq", tone: "rejected", duration: 1150 }],
    [
      { path: "flow-dlq-skill", tone: "recovered", duration: 800 },
      { path: "flow-skill-queue", tone: "recovered", duration: 1300 },
      { path: "flow-queue-worker", tone: "recovered", duration: 850 },
    ],
    [{ path: "flow-worker-blob", tone: "main", duration: 850 }],
  ];

  function setMode(showRecovery) {
    repairable = showRecovery;
    stage.classList.toggle("show-recovery", showRecovery);
    for (const element of stage.querySelectorAll(".recovery-only")) {
      element.setAttribute("aria-hidden", String(!showRecovery));
    }
    svg.setAttribute("viewBox", showRecovery ? "0 0 1160 430" : "0 0 1160 240");
    svg.setAttribute(
      "aria-label",
      showRecovery
        ? "Repairable shipment flow with the dead-letter queue shown inside Azure Service Bus."
        : "Valid shipment flow through the primary Service Bus queue.",
    );
  }

  function clearNodeStates() {
    for (const id of nodeIds) {
      document.getElementById(`flow-node-${id}`)?.classList.remove("active", "complete");
    }
  }

  function markNode(id, stateName) {
    const node = document.getElementById(`flow-node-${id}`);
    if (!node) return;
    node.classList.remove("active", "complete");
    node.classList.add(stateName);
  }

  function stageState(index) {
    clearNodeStates();
    if (index >= 0) markNode("ui", "complete");
    if (index === 0) markNode("queue", "active");
    if (index >= 1) markNode("queue", "complete");
    if (index === 1) markNode("worker", "active");
    if (index === 2) {
      markNode("worker", "complete");
      markNode("dlq", "active");
    }
    if (index === 3) {
      markNode("dlq", "complete");
      markNode("skill", "complete");
      markNode("worker", "active");
    }
    if (index >= 4) {
      markNode("worker", "complete");
      markNode("blob", "complete");
      if (repairable) {
        markNode("dlq", "complete");
        markNode("skill", "complete");
      }
    }
  }

  function hideToken() {
    token.setAttribute("hidden", "");
  }

  function showToken() {
    token.removeAttribute("hidden");
  }

  function reset(showRecovery = false) {
    animations.length = 0;
    playing = false;
    currentStage = -1;
    runId = null;
    hideToken();
    token.className.baseVal = "message-token";
    token.removeAttribute("transform");
    clearNodeStates();
    setMode(showRecovery);
  }

  function positionToken(path, progress) {
    const length = path.getTotalLength();
    const point = path.getPointAtLength(length * progress);
    token.setAttribute("transform", `translate(${point.x} ${point.y})`);
  }

  function playNext() {
    if (playing || animations.length === 0) {
      if (!playing && animations.length === 0) hideToken();
      return;
    }
    playing = true;
    const animation = animations.shift();
    const path = document.getElementById(animation.path);
    showToken();
    token.className.baseVal = `message-token ${animation.tone}`;
    if (reducedMotion.matches) {
      positionToken(path, 1);
      playing = false;
      playNext();
      return;
    }
    const started = performance.now();
    function frame(now) {
      const progress = Math.min(1, (now - started) / animation.duration);
      positionToken(path, progress);
      if (progress < 1) {
        requestAnimationFrame(frame);
        return;
      }
      playing = false;
      window.setTimeout(playNext, 90);
    }
    requestAnimationFrame(frame);
  }

  function queueStage(index) {
    for (const animation of stagePaths[index] || []) animations.push(animation);
    stageState(index);
    playNext();
  }

  function targetStage(run) {
    const observed = new Set(run.flow.events.map(event => event.stage));
    if (observed.has("output_saved")) return 4;
    if (observed.has("requeued")) return 3;
    if (observed.has("rejected") || observed.has("requeue_rejected")) return 2;
    if (observed.has("received")) return 1;
    return 0;
  }

  function start(showRecovery) {
    reset(showRecovery);
    queueStage(0);
  }

  function update(run) {
    if (runId !== run.id) {
      reset(run.repair_expected);
      runId = run.id;
      queueStage(0);
    } else {
      setMode(run.repair_expected);
    }
    const target = targetStage(run);
    while (currentStage < target) {
      currentStage++;
      if (currentStage > 0) queueStage(currentStage);
    }
  }

  reducedMotion.addEventListener("change", () => {
    if (reducedMotion.matches) {
      animations.length = 0;
      playing = false;
      hideToken();
    }
  });

  reset(false);
  return { reset, setMode, start, update };
}
