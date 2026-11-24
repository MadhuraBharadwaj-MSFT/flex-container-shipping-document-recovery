function createShipmentFlow() {
  const stage = document.getElementById("flow-stage");
  const svg = document.getElementById("flow-svg");
  const token = document.getElementById("message-token");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const nodeIds = ["ui", "queue", "worker", "blob", "dlq", "skill"];
  const animations = [];
  const playedStages = new Set();
  let playing = false;
  let runId = null;
  let repairable = false;

  const stagePaths = {
    submitted: [{ path: "flow-submit", tone: "main", duration: 650 }],
    received: [{ path: "flow-queue-worker", tone: "main", duration: 850 }],
    rejected: [{ path: "flow-worker-dlq", tone: "rejected", duration: 1150 }],
    requeue_rejected: [{ path: "flow-worker-dlq", tone: "rejected", duration: 1150 }],
    requeued: [
      { path: "flow-dlq-skill", tone: "recovered", duration: 800 },
      { path: "flow-skill-queue", tone: "recovered", duration: 1300 },
      { path: "flow-queue-worker", tone: "recovered", duration: 850 },
    ],
    output_saved: [{ path: "flow-worker-blob", tone: "main", duration: 850 }],
  };

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

  function stageState(stageName) {
    clearNodeStates();
    markNode("ui", "complete");
    if (stageName === "submitted") {
      markNode("queue", "active");
    }
    if (stageName !== "submitted") {
      markNode("queue", "complete");
    }
    if (stageName === "received") {
      markNode("worker", "active");
    }
    if (stageName === "rejected" || stageName === "requeue_rejected") {
      markNode("worker", "complete");
      markNode("dlq", "active");
    }
    if (stageName === "requeued") {
      markNode("dlq", "complete");
      markNode("skill", "complete");
      markNode("worker", "active");
    }
    if (stageName === "output_saved") {
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
    playedStages.clear();
    playing = false;
    runId = null;
    hideToken();
    token.className.baseVal = "message-token";
    token.removeAttribute("transform");
    delete token.dataset.path;
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
    token.dataset.path = animation.path;
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

  function queueStage(stageName) {
    if (playedStages.has(stageName)) return;
    playedStages.add(stageName);
    for (const animation of stagePaths[stageName] || []) animations.push(animation);
    stageState(stageName);
    playNext();
  }

  function start(showRecovery) {
    reset(showRecovery);
    queueStage("submitted");
  }

  function update(run) {
    if (runId !== run.id) {
      reset(run.repair_expected);
      runId = run.id;
      queueStage("submitted");
    } else {
      setMode(run.repair_expected);
    }
    for (const event of run.flow.events) {
      queueStage(event.stage);
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
