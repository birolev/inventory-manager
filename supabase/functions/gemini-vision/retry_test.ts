import {
  ProviderError,
  isRetryableStatus,
  runModelFallback,
  type FallbackModel,
  type FallbackOptions,
} from "./retry.ts";

Deno.test("only transient HTTP statuses are classified for retry", () => {
  for (const status of [408, 409, 425, 429, 500, 502, 503, 504]) {
    assert(isRetryableStatus(status), `${status} should be retried`);
  }
  for (const status of [400, 401, 403, 404, 422]) {
    assert(!isRetryableStatus(status), `${status} should skip retries and fail over`);
  }
});

const testModels: readonly FallbackModel[] = [
  { provider: "gemini", id: "gemini-3.1-flash-lite", envKey: "GEMINI_API_KEY" },
  { provider: "gemini", id: "gemini-3.5-flash-lite", envKey: "GEMINI_API_KEY" },
  { provider: "openai", id: "gpt-6-luna", envKey: "OPENAI_API_KEY" },
];

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

class FakeCircuitStore {
  now = 0;
  readonly failures = new Map<string, number>();
  private readonly openUntil = new Map<string, number>();
  private readonly probeUntil = new Map<string, number>();

  claim(model: string): boolean {
    const cooldownUntil = this.openUntil.get(model);
    if (cooldownUntil === undefined) return true;
    if (this.now < cooldownUntil) return false;
    if ((this.probeUntil.get(model) ?? 0) > this.now) return false;
    this.probeUntil.set(model, this.now + 90_000);
    return true;
  }

  success(model: string): void {
    this.failures.delete(model);
    this.openUntil.delete(model);
    this.probeUntil.delete(model);
  }

  failure(model: string): number {
    const count = (this.failures.get(model) ?? 0) + 1;
    this.failures.set(model, count);
    this.probeUntil.delete(model);
    const cooldownMs = Math.min(30 * 60_000, 60_000 * 2 ** (count - 1));
    this.openUntil.set(model, this.now + cooldownMs);
    return cooldownMs;
  }
}

function makeOptions(
  health: FakeCircuitStore,
  behavior: (
    model: FallbackModel,
    callNumber: number,
  ) => Record<string, unknown> | Promise<Record<string, unknown>>,
  onWait?: (ms: number) => void,
): FallbackOptions<Record<string, unknown>> & { calls: Map<string, number>; waits: number[] } {
  const calls = new Map<string, number>();
  const waits: number[] = [];
  return {
    models: testModels,
    getApiKey: () => "test-key",
    isAvailable: (model) => Promise.resolve(health.claim(model.id)),
    callModel: async (model) => {
      const callNumber = (calls.get(model.id) ?? 0) + 1;
      calls.set(model.id, callNumber);
      return behavior(model, callNumber);
    },
    recordSuccess: async (model) => health.success(model.id),
    recordFailure: async (model) => health.failure(model.id),
    wait: async (ms) => {
      waits.push(ms);
      health.now += ms;
      onWait?.(ms);
    },
    random: () => 0.5,
    calls,
    waits,
  };
}

Deno.test("429 busy response retries Gemini 3.1 with exponential backoff, then uses Gemini 3.5", async () => {
  const health = new FakeCircuitStore();
  const options = makeOptions(health, (model) => {
    if (model.id === "gemini-3.1-flash-lite") {
      throw new ProviderError("Too many requests", model.provider, model.id, 429, true);
    }
    return { selectedModel: model.id };
  });

  const result = await runModelFallback(options);

  assert(result.ok, "Fallback should succeed");
  assertEquals(result.model, "gemini-3.5-flash-lite", "Should use second Gemini model");
  assertEquals(options.calls.get("gemini-3.1-flash-lite"), 3, "429 should get three total attempts");
  assertEquals(options.calls.get("gemini-3.5-flash-lite"), 1, "Healthy fallback should be called once");
  assertEquals(options.calls.get("gpt-6-luna"), undefined, "OpenAI should not be needed");
  assertEquals(options.waits, [500, 1000], "Retry delays should grow exponentially");
  assert(!health.claim("gemini-3.1-flash-lite"), "Failed primary should enter cooldown");
});

Deno.test("503 service outage exhausts retries for Gemini 3.1 before falling back", async () => {
  const health = new FakeCircuitStore();
  const options = makeOptions(health, (model) => {
    if (model.id === "gemini-3.1-flash-lite") {
      throw new ProviderError("Service unavailable", model.provider, model.id, 503, true);
    }
    return { selectedModel: model.id };
  });

  const result = await runModelFallback(options);

  assert(result.ok, "Fallback should succeed");
  assertEquals(options.calls.get("gemini-3.1-flash-lite"), 3, "503 should get three total attempts");
  assertEquals(result.model, "gemini-3.5-flash-lite", "Should fall back to Gemini 3.5");
});

Deno.test("network timeout on Gemini 3.5 retries, then succeeds with GPT-6 Luna", async () => {
  const health = new FakeCircuitStore();
  const options = makeOptions(health, (model) => {
    if (model.id === "gemini-3.1-flash-lite") {
      throw new ProviderError("Model unavailable", model.provider, model.id, 404, false);
    }
    if (model.id === "gemini-3.5-flash-lite") throw new Error("Request timed out");
    return { selectedModel: model.id };
  });

  const result = await runModelFallback(options);

  assert(result.ok, "OpenAI fallback should succeed");
  assertEquals(options.calls.get("gemini-3.1-flash-lite"), 1, "Unavailable model should not be retried");
  assertEquals(options.calls.get("gemini-3.5-flash-lite"), 3, "Network errors should get three attempts");
  assertEquals(result.model, "gpt-6-luna", "Should reach OpenAI fallback");
});

Deno.test("GPT outage returns a controlled failure after every available model is exhausted", async () => {
  const health = new FakeCircuitStore();
  const options = makeOptions(health, (model) => {
    throw new ProviderError("Service unavailable", model.provider, model.id, 503, true);
  });

  const result = await runModelFallback(options);

  assert(!result.ok, "All provider failures should return a failure outcome");
  assertEquals(options.calls.get("gemini-3.1-flash-lite"), 3, "First Gemini should retry three times");
  assertEquals(options.calls.get("gemini-3.5-flash-lite"), 3, "Second Gemini should retry three times");
  assertEquals(options.calls.get("gpt-6-luna"), 3, "OpenAI should retry three times");
  assertEquals(result.attempted, testModels.map((model) => model.id), "All configured models should be attempted");
});

Deno.test("non-retryable authentication errors skip straight to the next model", async () => {
  const health = new FakeCircuitStore();
  const options = makeOptions(health, (model) => {
    if (model.id === "gemini-3.1-flash-lite") {
      throw new ProviderError("Invalid API key", model.provider, model.id, 401, false);
    }
    return { selectedModel: model.id };
  });

  const result = await runModelFallback(options);

  assert(result.ok, "Second model should handle the request");
  assertEquals(options.calls.get("gemini-3.1-flash-lite"), 1, "401 should not retry the same model");
  assertEquals(result.model, "gemini-3.5-flash-lite", "Should proceed to next model");
});

Deno.test("a failed model is skipped throughout a 100-item batch", async () => {
  const health = new FakeCircuitStore();
  const options = makeOptions(health, (model) => {
    if (model.id === "gemini-3.1-flash-lite") {
      throw new ProviderError("Service unavailable", model.provider, model.id, 503, true);
    }
    return { selectedModel: model.id };
  });

  for (let item = 0; item < 100; item++) {
    const result = await runModelFallback(options);
    assert(result.ok, `Item ${item + 1} should succeed through fallback`);
    assertEquals(result.model, "gemini-3.5-flash-lite", `Item ${item + 1} should use Gemini 3.5`);
  }

  assertEquals(options.calls.get("gemini-3.1-flash-lite"), 3, "Open primary should only be tried on first item");
  assertEquals(options.calls.get("gemini-3.5-flash-lite"), 100, "Fallback should handle the batch");
  assertEquals(options.calls.get("gpt-6-luna"), undefined, "OpenAI should remain unused while Gemini 3.5 works");
});

Deno.test("after cooldown, one successful probe restores the preferred model", async () => {
  const health = new FakeCircuitStore();
  const options = makeOptions(health, (model, callNumber) => {
    if (model.id === "gemini-3.1-flash-lite" && callNumber <= 3) {
      throw new ProviderError("Service unavailable", model.provider, model.id, 503, true);
    }
    return { selectedModel: model.id };
  });

  const first = await runModelFallback(options);
  assert(first.ok, "Initial fallback should succeed");
  assertEquals(first.model, "gemini-3.5-flash-lite", "Initial outage should use fallback");

  health.now += 60_001;
  const recovered = await runModelFallback(options);
  assert(recovered.ok, "Probe should succeed after cooldown");
  assertEquals(recovered.model, "gemini-3.1-flash-lite", "Recovered preferred model should be used");

  const next = await runModelFallback(options);
  assert(next.ok, "Subsequent request should succeed");
  assertEquals(next.model, "gemini-3.1-flash-lite", "Preferred model should stay active after recovery");
  assertEquals(options.calls.get("gemini-3.5-flash-lite"), 1, "Fallback should only serve the first request");
  assertEquals(health.failures.has("gemini-3.1-flash-lite"), false, "Successful probe should reset failure history");
});

Deno.test("only one request probes a recovered model while concurrent batch requests use fallback", async () => {
  const health = new FakeCircuitStore();
  let markProbeStarted!: () => void;
  let releaseProbe!: () => void;
  const probeStarted = new Promise<void>((resolve) => {
    markProbeStarted = resolve;
  });
  const probeResult = new Promise<Record<string, unknown>>((resolve) => {
    releaseProbe = () => resolve({ selectedModel: "gemini-3.1-flash-lite" });
  });
  const options = makeOptions(health, (model, callNumber) => {
    if (model.id === "gemini-3.1-flash-lite" && callNumber <= 3) {
      throw new ProviderError("Service unavailable", model.provider, model.id, 503, true);
    }
    if (model.id === "gemini-3.1-flash-lite" && callNumber === 4) {
      markProbeStarted();
      return probeResult;
    }
    return { selectedModel: model.id };
  });

  const initial = await runModelFallback(options);
  assert(initial.ok, "Initial request should fall back");
  health.now += 60_001;

  const probeRequest = runModelFallback(options);
  await probeStarted;
  const concurrentRequest = await runModelFallback(options);
  assert(concurrentRequest.ok, "Concurrent request should complete on fallback");
  assertEquals(concurrentRequest.model, "gemini-3.5-flash-lite", "Concurrent request should skip leased probe");

  releaseProbe();
  const recovered = await probeRequest;
  assert(recovered.ok, "Probe request should recover successfully");
  assertEquals(recovered.model, "gemini-3.1-flash-lite", "Probe should return the preferred model");
  assertEquals(options.calls.get("gemini-3.1-flash-lite"), 4, "Only one recovery probe should run");
  assertEquals(options.calls.get("gemini-3.5-flash-lite"), 2, "Fallback serves initial and concurrent request");
});
