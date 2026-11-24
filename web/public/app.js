const el = id => document.getElementById(id);

const valid = {
  shipment_id: "assigned-on-send",
  partner: "Contoso Logistics",
  ship_date: "2026-11-25",
  service_level: "priority",
  ship_to: {
    name: "A. Customer",
    address_line1: "1 Main Street",
    city: "Seattle",
    state_or_province: "WA",
    postal_code: "98101",
    country_code: "US",
  },
  items: [
    { sku: "SKU-100", description: "Blue widget", quantity: 2, unit_weight_kg: 1.25 },
    { sku: "SKU-200", description: "Packing insert", quantity: 1, unit_weight_kg: 0.1 },
  ],
};

const malformed = {
  shipmentId: "assigned-on-send",
  partnerName: "Contoso Logistics",
  shipDate: "11/25/2026",
  serviceLevel: "PRIORITY",
  shipTo: {
    name: "A. Customer",
    addressLine1: "1 Main Street",
    city: "Seattle",
    stateOrProvince: "WA",
    postalCode: "98101",
    countryCode: "us",
  },
  items: [
    { sku: "SKU-100", description: "Blue widget", quantity: "2", unitWeightKg: "1.25" },
    { sku: "SKU-200", description: "Packing insert", quantity: "1", unitWeightKg: "0.10" },
  ],
};

let allowed = false;
let polling = null;
let currentId = null;

function showError(message) {
  el("error").textContent = message;
  el("error").hidden = !message;
}

function setBusy(busy) {
  for (const id of ["valid", "malformed", "message", "send"]) {
    el(id).disabled = !allowed || busy;
  }
}

async function request(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    cache: "no-store",
    signal: AbortSignal.timeout(40000),
  });
  const text = await response.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { error: text || `HTTP ${response.status}` }; }
  if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
  return data;
}

function selectTab(name) {
  const trySelected = name === "try";
  el("try-panel").hidden = !trySelected;
  el("architecture-panel").hidden = trySelected;
  el("try-tab").classList.toggle("active", trySelected);
  el("architecture-tab").classList.toggle("active", !trySelected);
  el("try-tab").setAttribute("aria-selected", String(trySelected));
  el("architecture-tab").setAttribute("aria-selected", String(!trySelected));
}

function render(run) {
  el("results").hidden = false;
  el("original").textContent = JSON.stringify(run.input, null, 2);
  el("canonical").textContent = run.canonical
    ? JSON.stringify(run.canonical, null, 2)
    : "Waiting for deterministic validation.";
  el("flow-status").textContent = run.complete ? "Complete" : "Processing";
  el("flow-status").className = `status ${run.complete ? "complete" : "working"}`;
  el("flow-detail").textContent = run.flow.label;
  el("events").replaceChildren(...run.flow.events.map(event => {
    const item = document.createElement("li");
    const time = event.observed_at ? new Date(event.observed_at).toLocaleTimeString() : "";
    item.textContent = `${time} — ${event.stage.replaceAll("_", " ")}`;
    if (event.detail) item.title = event.detail;
    return item;
  }));
  el("recovery-badge").hidden = !run.recovered_by_hosted_skill;

  if (run.html) {
    el("preview").srcdoc = run.html;
  }
  if (run.pdf_url) {
    el("open-pdf").href = run.pdf_url;
    el("open-pdf").hidden = false;
    el("pdf-detail").textContent = `${run.pdf_bytes.toLocaleString()} bytes stored in the private generated-documents container.`;
  }
}

async function poll() {
  try {
    const run = await request(`/api/demo/runs/${currentId}`);
    showError("");
    render(run);
    if (run.complete || run.expired) {
      setBusy(false);
      return;
    }
    polling = setTimeout(poll, 750);
  } catch (error) {
    showError(`${error.message}. Processing may still be continuing in Azure.`);
    polling = setTimeout(poll, 3000);
  }
}

async function submit() {
  clearTimeout(polling);
  showError("");
  let shipment;
  try {
    shipment = JSON.parse(el("message").value);
  } catch {
    showError("Enter valid JSON syntax. The repair demo fixes fields and value formats, not broken JSON.");
    return;
  }

  setBusy(true);
  currentId = crypto.randomUUID().replaceAll("-", "");
  el("results").hidden = false;
  el("original").textContent = JSON.stringify(shipment, null, 2);
  el("canonical").textContent = "Waiting for deterministic validation.";
  el("preview").srcdoc = "";
  el("open-pdf").hidden = true;
  el("recovery-badge").hidden = true;
  el("events").replaceChildren();
  el("flow-status").textContent = "Submitting";
  el("flow-status").className = "status working";
  el("flow-detail").textContent = "Sending the shipment to Service Bus.";

  try {
    await request("/api/demo/runs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ request_id: currentId, shipment }),
    });
    poll();
  } catch (error) {
    setBusy(false);
    showError(error.message);
  }
}

async function initialize() {
  el("valid").onclick = () => { el("message").value = JSON.stringify(valid, null, 2); };
  el("malformed").onclick = () => { el("message").value = JSON.stringify(malformed, null, 2); };
  el("send").onclick = submit;
  el("try-tab").onclick = () => selectTab("try");
  el("architecture-tab").onclick = () => selectTab("architecture");
  el("message").value = JSON.stringify(valid, null, 2);

  try {
    const authResponse = await fetch("/.auth/me", { cache: "no-store" });
    if (!authResponse.headers.get("content-type")?.includes("application/json")) {
      el("account").textContent = "Local UI preview";
      el("access-note").textContent = "Submission is enabled after Azure deployment and Microsoft sign-in.";
      return;
    }
    const auth = await authResponse.json();
    const principal = auth.clientPrincipal;
    if (!principal) {
      el("account").textContent = "Not signed in";
      el("sign-in").hidden = false;
      return;
    }
    el("account").textContent = principal.userDetails || "Signed in";
    el("sign-out").hidden = false;
    await request("/api/demo/access");
    allowed = true;
    el("access-note").textContent = "Ready. Choose the valid or repairable partner record.";
    setBusy(false);
  } catch (error) {
    el("access-note").textContent = error.message;
    el("sign-in").hidden = false;
  }
}

initialize();
